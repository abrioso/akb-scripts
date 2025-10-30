#!/bin/bash

# Parse optional config file argument (default: ./wordpress_migration_config.env)
CONFIG_FILE="./wordpress_migration_config.env"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config)
      shift
      if [ -z "$1" ]; then
        echo "ERROR: --config requires a file path" >&2
        exit 1
      fi
      CONFIG_FILE="$1"
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--config CONFIG_FILE] [CONFIG_FILE]"
      exit 0
      ;;
    *)
      CONFIG_FILE="$1"
      shift
      ;;
  esac
done

# LOAD CONFIGURATION FROM EXTERNAL FILE
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Configuration file $CONFIG_FILE not found. Aborting."
  exit 1
fi
source "$CONFIG_FILE"

# --- Validate required environment variables ---
required_vars=(SRC_SSH DST_SSH SRC_DIR DST_DIR LOCAL_TMP_DIR \
               SRC_DB_NAME SRC_DB_USER SRC_DB_PASS \
               DST_DB_NAME DST_DB_USER DST_DB_PASS DST_DB_HOST \
               DUMP_FILE DST_FILES_OWNER OLD_URL NEW_URL OLD_PATH NEW_PATH)

missing=()
for v in "${required_vars[@]}"; do
  if [ -z "${!v}" ]; then
    missing+=("$v")
  fi
done

if [ ${#missing[@]} -ne 0 ]; then
  echo "ERROR: Missing required configuration variables in $CONFIG_FILE:" 1>&2
  for m in "${missing[@]}"; do
    echo "  - $m" 1>&2
  done
  echo "Please set the above variables in $CONFIG_FILE and re-run the script." 1>&2
  exit 2
fi


# 1. EXPORT DATABASE FROM SOURCE SERVER
echo "[1/10] Exporting database from source server..."
# Detect preferred dump binary on the source host (prefer mariadb-dump, fallback to mysqldump)
echo "Detecting database dump binary on source host ($SRC_SSH)..."
SRC_DUMP_BIN=$(ssh "$SRC_SSH" "command -v mariadb-dump || command -v mysqldump || true")
if [ -z "$SRC_DUMP_BIN" ]; then
  echo "ERROR: neither 'mariadb-dump' nor 'mysqldump' found on source host ($SRC_SSH). Aborting." >&2
  exit 4
fi
echo "Using dump binary on source: $SRC_DUMP_BIN"
ssh "$SRC_SSH" "$SRC_DUMP_BIN -u$SRC_DB_USER -p$SRC_DB_PASS $SRC_DB_NAME > $DUMP_FILE"

# 2. TRANSFER DATABASE DUMP TO LOCAL AND THEN TO DESTINATION SERVER
echo "[2/10] Transferring database dump to local and destination server..."
scp $SRC_SSH:$DUMP_FILE $DUMP_FILE
scp $DUMP_FILE $DST_SSH:$DUMP_FILE

# 3. IMPORT DATABASE ON DESTINATION SERVER
echo "[3/10] Importing database on destination server..."
# Detect preferred SQL client on destination host (prefer mariadb, fallback to mysql)
echo "Detecting SQL client binary on destination host ($DST_SSH)..."
DST_SQL_BIN=$(ssh "$DST_SSH" "command -v mariadb || command -v mysql || true")
if [ -z "$DST_SQL_BIN" ]; then
  echo "ERROR: neither 'mariadb' nor 'mysql' found on destination host ($DST_SSH). Aborting." >&2
  exit 5
fi
echo "Using SQL client on destination: $DST_SQL_BIN"
ssh "$DST_SSH" "$DST_SQL_BIN -u$DST_DB_USER -p$DST_DB_PASS $DST_DB_NAME < $DUMP_FILE"

# 4. SYNC WORDPRESS FILES USING LOCAL INTERMEDIATE HOP
echo "[4/10] Syncing WordPress files via local temporary directory..."

if [ ! -d "$LOCAL_TMP_DIR" ]; then
  mkdir -p $LOCAL_TMP_DIR
fi

# Sync from source -> local. Exclude VCS artefacts and .gitignore files.
rsync -avz --delete --progress -e ssh \
  --exclude='.git' --exclude='.git/**' --exclude='.gitignore' \
  "$SRC_SSH:$SRC_DIR/" "$LOCAL_TMP_DIR/"

# Sync from local -> destination. Do NOT remove excluded files on destination so
# existing .git and .gitignore on the destination remain untouched.
# (Removed --delete-excluded so excluded items like .git and .gitignore are preserved.)
rsync -avz --delete --force --progress -e ssh \
  --exclude='.git' --exclude='.git/**' --exclude='.gitignore' \
  "$LOCAL_TMP_DIR/" "$DST_SSH:$DST_DIR/"

# 5. SET PERMISSIONS ON DESTINATION SERVER (optional)
echo "[5/10] Setting file permissions..."
ssh $DST_SSH "chown -R $DST_FILES_OWNER:$DST_FILES_OWNER $DST_DIR"

# Pre-check: verify wp-cli exists on the destination and that --path points to a WP install.
# This runs a lightweight 'wp --info' to assert the environment before we run wp-cli commands.
echo "[5.1] Verifying wp-cli presence and WordPress path on destination..."
# Run a robust check (expand local variables here). If this fails, exit with a helpful message.
ssh "$DST_SSH" "if ! command -v wp >/dev/null 2>&1; then echo 'ERROR: wp-cli not found on destination ($DST_SSH). Aborting.' >&2; exit 3; fi; wp --path=\"$DST_DIR\" --info" || {
  echo "ERROR: wp-cli check failed on destination ($DST_SSH). Ensure wp-cli is installed and --path ($DST_DIR) is a WordPress install." >&2
  exit 6
}

# 6. CORRECT WP-CONFIG.PHP IF NECESSARY
# 6.1 CORRECT DB_NAME, DB_USER, DB_PASSWORD, DB_HOST
echo "[6/10] Updating wp-config.php with new database credentials..."

# Derive DOMAIN_NEW_SITE as the host portion of NEW_URL
DOMAIN_NEW_SITE_VAL=$(echo "$NEW_URL" | awk -F/ '{print $3}')

# Derive DOMAIN_OLD_SITE as the host portion of OLD_URL (e.g. example.com)
DOMAIN_OLD_SITE_VAL=$(echo "$OLD_URL" | awk -F/ '{print $3}')

# Print the current DOMAIN_CURRENT_SITE constant from the remote wp-config.php so the user
# can confirm it matches the new domain (helps diagnose 'site not found' WP-CLI errors).
echo "[5.2] Inspecting remote wp-config.php for DOMAIN_CURRENT_SITE..."
ssh "$DST_SSH" "wp --path=\"$DST_DIR\" --url=\"$NEW_URL\" config get DOMAIN_CURRENT_SITE --allow-root 2>/dev/null || echo 'DOMAIN_CURRENT_SITE not set'"
echo "Derived NEW_URL host: $DOMAIN_NEW_SITE_VAL (from NEW_URL: $NEW_URL)"
echo "Derived OLD_URL host: $DOMAIN_OLD_SITE_VAL (from OLD_URL: $OLD_URL)"

# Prefer using wp-cli remotely to safely update wp-config.php and avoid nested-quote issues.
# If wp-cli is not available on the destination host, fail fast with a message. Expand local
# variables before sending the command so wp receives real paths/values.
ssh "$DST_SSH" "if ! command -v wp >/dev/null 2>&1; then echo 'ERROR: wp-cli not found on destination ($DST_SSH). Install wp-cli or update the script to use sed fallback.' >&2; exit 3; fi; \
  wp --path=\"$DST_DIR\" --url=\"$NEW_URL\" config set DB_NAME \"$DST_DB_NAME\" --allow-root && \
  wp --path=\"$DST_DIR\" --url=\"$NEW_URL\" config set DB_USER \"$DST_DB_USER\" --allow-root && \
  wp --path=\"$DST_DIR\" --url=\"$NEW_URL\" config set DB_PASSWORD \"$DST_DB_PASS\" --allow-root && \
  wp --path=\"$DST_DIR\" --url=\"$NEW_URL\" config set DB_HOST \"$DST_DB_HOST\" --allow-root"

# 6.2 CORRECT DOMAIN_NEW_SITE IF NECESSARY
echo "[6/10] Updating wp-config.php with new domain..."
ssh "$DST_SSH" "wp --path=\"$DST_DIR\" --url=\"$NEW_URL\" config set DOMAIN_NEW_SITE \"$DOMAIN_NEW_SITE_VAL\" --allow-root"

# 6.3. Update site domains.
# The wp-cli 'site update' invocation previously used quoting that prevented local variables
# from being expanded and caused errors. We already update wp_site and wp_blogs directly via SQL
# below, which is reliable, so skip the wp site update loop to avoid WP-CLI subcommand problems.
ssh "$DST_SSH" "$DST_SQL_BIN -u$DST_DB_USER -p$DST_DB_PASS $DST_DB_NAME -e \"UPDATE wp_site SET domain='$DOMAIN_NEW_SITE_VAL' WHERE domain='$DOMAIN_OLD_SITE_VAL'; UPDATE wp_blogs SET domain='$DOMAIN_NEW_SITE_VAL' WHERE domain='$DOMAIN_OLD_SITE_VAL';\""

# Force flush cache if any caching plugin is active
ssh "$DST_SSH" "wp --path=\"$DST_DIR\" --url=\"$NEW_URL\" cache flush --allow-root"

# List all sites to verify (use expanded --path and --url where applicable)
ssh "$DST_SSH" "wp --path=\"$DST_DIR\" --url=\"$NEW_URL\" site list"
ssh "$DST_SSH" "wp --path=\"$DST_DIR\" --url=\"$NEW_URL\" db query \"SELECT blog_id, domain, path FROM wp_blogs WHERE domain='$DOMAIN_NEW_SITE_VAL';\""
ssh "$DST_SSH" "wp --path=\"$DST_DIR\" --url=\"$NEW_URL\" db query \"SELECT option_name, option_value FROM wp_options WHERE option_name IN ('siteurl','home');\""
ssh "$DST_SSH" "wp --path=\"$DST_DIR\" --url=\"$NEW_URL\" option get siteurl"
ssh "$DST_SSH" "wp --path=\"$DST_DIR\" --url=\"$NEW_URL\" option get home"


# 6.3 Disable Wordfence temporarily if installed and fix WAF path issues
echo "[6/10] Disabling Wordfence plugin temporarily and fixing WAF path issues..."
ssh "$DST_SSH" "if wp --path=\"$DST_DIR\" --url=\"$NEW_URL\" plugin is-installed wordfence --allow-root >/dev/null 2>&1; then wp --path=\"$DST_DIR\" --url=\"$NEW_URL\" plugin deactivate wordfence --allow-root; fi"

# Fix Wordfence WAF path issues
echo "[6.3.1] Fixing Wordfence WAF path references..."
ssh "$DST_SSH" "
  # Check if wordfence-waf.php exists in the WordPress root
  if [ -f \"$DST_DIR/wordfence-waf.php\" ]; then
    echo 'Found wordfence-waf.php in WordPress root, updating path references...'
    
    # Update auto_prepend_file in .user.ini if it exists
    if [ -f \"$DST_DIR/.user.ini\" ]; then
      sed -i \"s|auto_prepend_file = .*/wordfence-waf.php|auto_prepend_file = $DST_DIR/wordfence-waf.php|g\" \"$DST_DIR/.user.ini\"
      echo 'Updated .user.ini auto_prepend_file path'
    fi
    
    # Update wordfence-waf.php itself if it contains old path references
    sed -i \"s|$OLD_PATH|$NEW_PATH|g\" \"$DST_DIR/wordfence-waf.php\"
    
    # Update Wordfence database options with correct WAF path
    wp --path=\"$DST_DIR\" --url=\"$NEW_URL\" option update wordfence_waf_auto_prepend \"$DST_DIR/wordfence-waf.php\" --allow-root 2>/dev/null || true
    
    echo 'Wordfence WAF path references updated'
  else
    echo 'wordfence-waf.php not found, may have been cleaned up already'
  fi
  
  # Remove old WAF references from php.ini or .htaccess that might point to old paths
  if [ -f \"$DST_DIR/.htaccess\" ]; then
    sed -i \"/auto_prepend_file.*wordfence-waf.php/d\" \"$DST_DIR/.htaccess\"
    echo 'Removed old WAF references from .htaccess'
  fi
"

# 6.4 Flush CacheS if wpo-cache is installed
echo "[6/10] Flushing wpo-cache..."
ssh "$DST_SSH" "if wp --path=\"$DST_DIR\" --url=\"$NEW_URL\" plugin is-installed wpo-cache --allow-root >/dev/null 2>&1; then wp --path=\"$DST_DIR\" --url=\"$NEW_URL\" wpo-cache flush --allow-root; fi"

# 7. REPLACE URL AND PATH REFERENCES IN DATABASE (Comprehensive)
echo "[7/10] Replacing old URLs and paths in the database..."
ssh $DST_SSH \
  "wp search-replace '$OLD_URL' '$NEW_URL' --path=\"$DST_DIR\" --url=\"$NEW_URL\" --allow-root --all-tables --precise --recurse-objects && \
   wp search-replace '$OLD_PATH' '$NEW_PATH' --path=\"$DST_DIR\" --url=\"$NEW_URL\" --allow-root --all-tables --precise --recurse-objects && \
   wp search-replace '$OLD_URL' '$NEW_URL' --path=\"$DST_DIR\" --url=\"$NEW_URL\" --all-tables --skip-columns=guid"

# 7.1 Fix Wordfence-specific database entries
echo "[7.1] Fixing Wordfence-specific database configurations..."
ssh $DST_SSH \
  "# Update Wordfence WAF configuration in database
   $DST_SQL_BIN -u'$DST_DB_USER' -p'$DST_DB_PASS' $DST_DB_NAME -e \"
     UPDATE wp_options 
     SET option_value = REPLACE(option_value, '$OLD_PATH', '$NEW_PATH') 
     WHERE option_name LIKE 'wordfence_%' AND option_value LIKE '%$OLD_PATH%';
     
     UPDATE wp_options 
     SET option_value = REPLACE(option_value, '$OLD_URL', '$NEW_URL') 
     WHERE option_name LIKE 'wordfence_%' AND option_value LIKE '%$OLD_URL%';
   \" && echo 'Updated Wordfence database configurations'"

# 8. REPLACE URL AND PATH REFERENCES IN CONFIG FILES (e.g., plugins)
echo "[8/10] Replacing URL and path references in configuration files..."
ssh $DST_SSH \
  "find $DST_DIR -type f \( -name '*.php' -o -name '*.ini' -o -name '*.conf' \) -print0 | \
   tee >(xargs -0 grep -l '$OLD_PATH' | tee /tmp/files_with_path.txt | xargs -0 -I{} sed -i 's|$OLD_PATH|$NEW_PATH|g') \
        >(xargs -0 grep -l '$OLD_URL' | tee /tmp/files_with_url.txt | xargs -0 -I{} sed -i 's|$OLD_URL|$NEW_URL|g')
   echo 'Replaced paths in the following files:' && cat /tmp/files_with_path.txt
   echo 'Replaced URLs in the following files:' && cat /tmp/files_with_url.txt"

# 9. DIAGNOSE POSSIBLE REDIRECTIONS TO OLD_URL
echo "[9/10] Diagnosing possible redirections to OLD_URL..."
echo "[wp_options with OLD_URL]"
ssh "$DST_SSH" "$DST_SQL_BIN -u'$DST_DB_USER' -p'$DST_DB_PASS' $DST_DB_NAME -e \"SELECT option_name, option_value FROM wp_options WHERE option_value LIKE '%$OLD_URL%';\""
echo "[wp_postmeta with OLD_URL]"
ssh "$DST_SSH" "$DST_SQL_BIN -u'$DST_DB_USER' -p'$DST_DB_PASS' $DST_DB_NAME -e \"SELECT meta_key, meta_value FROM wp_postmeta WHERE meta_value LIKE '%$OLD_URL%';\""
echo "[wp_usermeta with OLD_URL]"
ssh "$DST_SSH" "$DST_SQL_BIN -u'$DST_DB_USER' -p'$DST_DB_PASS' $DST_DB_NAME -e \"SELECT meta_key, meta_value FROM wp_usermeta WHERE meta_value LIKE '%$OLD_URL%';\""
echo "[wp_site with OLD_URL domain]"
ssh "$DST_SSH" "$DST_SQL_BIN -u'$DST_DB_USER' -p'$DST_DB_PASS' $DST_DB_NAME -e \"SELECT * FROM wp_site WHERE domain LIKE '%$(echo $OLD_URL | awk -F/ '{print $3}')%';\""
echo "[wp_sitemeta with OLD_URL]"
ssh "$DST_SSH" "$DST_SQL_BIN -u'$DST_DB_USER' -p'$DST_DB_PASS' $DST_DB_NAME -e \"SELECT * FROM wp_sitemeta WHERE meta_value LIKE '%$OLD_URL%';\""
echo "[wp_blogs with OLD_URL domain]"
ssh "$DST_SSH" "$DST_SQL_BIN -u'$DST_DB_USER' -p'$DST_DB_PASS' $DST_DB_NAME -e \"SELECT blog_id, domain, path FROM wp_blogs WHERE domain LIKE '%$(echo $OLD_URL | awk -F/ '{print $3}')%';\""
echo "[wp-config.php check]"
ssh "$DST_SSH" "grep -E 'WP_HOME|WP_SITEURL' \"$DST_DIR/wp-config.php\" || true"
echo "[.htaccess check]"
ssh "$DST_SSH" "grep -i 'Redirect' \"$DST_DIR/.htaccess\" || echo 'No redirects found in .htaccess'"
echo "[File search for OLD_URL]"
ssh "$DST_SSH" "grep -RIn --exclude-dir='.git' --exclude-dir='.git*' --exclude-dir='.vscode' --binary-files=without-match '$OLD_URL' \"$DST_DIR\" || echo 'No hardcoded OLD_URL found in files.'"

# 10. CLEANUP TEMPORARY FILES
echo "[10/10] Cleaning up temporary files..."
rm -f $DUMP_FILE
#rm -rf $LOCAL_TMP_DIR
ssh $SRC_SSH "rm -f $DUMP_FILE"
ssh $DST_SSH "rm -f $DUMP_FILE"

# DONE
echo "Migration and post-migration steps completed successfully."