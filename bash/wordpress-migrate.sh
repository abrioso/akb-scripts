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
ssh $SRC_SSH "mysqldump -u$SRC_DB_USER -p$SRC_DB_PASS $SRC_DB_NAME > $DUMP_FILE"

# 2. TRANSFER DATABASE DUMP TO LOCAL AND THEN TO DESTINATION SERVER
echo "[2/10] Transferring database dump to local and destination server..."
scp $SRC_SSH:$DUMP_FILE $DUMP_FILE
scp $DUMP_FILE $DST_SSH:$DUMP_FILE

# 3. IMPORT DATABASE ON DESTINATION SERVER
echo "[3/10] Importing database on destination server..."
ssh $DST_SSH "mysql -u$DST_DB_USER -p$DST_DB_PASS $DST_DB_NAME < $DUMP_FILE"

# 4. SYNC WORDPRESS FILES USING LOCAL INTERMEDIATE HOP
echo "[4/10] Syncing WordPress files via local temporary directory..."

if [ ! -d "$LOCAL_TMP_DIR" ]; then
  mkdir -p $LOCAL_TMP_DIR
fi

rsync -avz --delete --progress -e ssh \
  --filter='P **/.git/**' --filter='P **/.gitignore' \
  "$SRC_SSH:$SRC_DIR/" "$LOCAL_TMP_DIR/"

rsync -avz --delete --progress -e ssh \
  --filter='P **/.git/**' --filter='P **/.gitignore' \
  "$LOCAL_TMP_DIR/" "$DST_SSH:$DST_DIR/"

# 5. SET PERMISSIONS ON DESTINATION SERVER (optional)
echo "[5/10] Setting file permissions..."
ssh $DST_SSH "chown -R $DST_FILES_OWNER:$DST_FILES_OWNER $DST_DIR"

# 6. CORRECT WP-CONFIG.PHP IF NECESSARY
# 6.1 CORRECT DB_NAME, DB_USER, DB_PASSWORD, DB_HOST
echo "[6/10] Updating wp-config.php with new database credentials..."

# Derive DOMAIN_CURRENT_SITE as the host portion of NEW_URL (e.g. example.com)
DOMAIN_CURRENT_SITE_VAL=$(echo "$NEW_URL" | awk -F/ '{print $3}')

# Prefer using wp-cli remotely to safely update wp-config.php and avoid nested-quote issues.
# If wp-cli is not available on the destination host, fail fast with a message.
ssh "$DST_SSH" "if ! command -v wp >/dev/null 2>&1; then echo 'ERROR: wp-cli not found on destination ($DST_SSH). Install wp-cli or update the script to use sed fallback.' >&2; exit 3; fi; \
  wp --path='$DST_DIR' config set DB_NAME '$DST_DB_NAME' --allow-root && \
  wp --path='$DST_DIR' config set DB_USER '$DST_DB_USER' --allow-root && \
  wp --path='$DST_DIR' config set DB_PASSWORD '$DST_DB_PASS' --allow-root --raw && \
  wp --path='$DST_DIR' config set DB_HOST '$DST_DB_HOST' --allow-root"



# 6.2 CORRECT DOMAIN_CURRENT_SITE IF NECESSARY
echo "[6/10] Updating wp-config.php with new domain..."
ssh "$DST_SSH" "wp --path='$DST_DIR' config set DOMAIN_CURRENT_SITE '$DOMAIN_CURRENT_SITE_VAL' --allow-root"

# 6.3. List site IDs and update each to the new domain
ssh "$DST_SSH" "wp --path='$DST_DIR' site list --fields=blog_id --format=csv \
  | tail -n +2 \
  | while read id; do
      wp --path='$DST_DIR' site update $id --domain='$DOMAIN_CURRENT_SITE_VAL' --allow-root;
    done"

ssh "$DST_SSH" "mysql -u$DST_DB_USER -p$DST_DB_PASS $DST_DB_NAME -e \"UPDATE wp_site SET domain='www-qua.iseg.ulisboa.pt' WHERE domain='www.iseg.ulisboa.pt'; UPDATE wp_blogs SET domain='www-qua.iseg.ulisboa.pt' WHERE domain='www.iseg.ulisboa.pt';\""

# 6.3 Disable Wordfence temporarily if installed
echo "[6/10] Disabling Wordfence plugin temporarily if installed..."
ssh "$DST_SSH" "if wp --path='$DST_DIR' plugin is-installed wordfence --allow-root; then wp --path='$DST_DIR' plugin deactivate wordfence --allow-root; fi"

# 6.4 Flush CacheS if wpo-cache is installed
echo "[6/10] Flushing wpo-cache..."
ssh "$DST_SSH" "if wp --path='$DST_DIR' plugin is-installed wpo-cache --allow-root; then wp --path='$DST_DIR' wpo-cache flush --allow-root; fi"

# 7. REPLACE URL AND PATH REFERENCES IN DATABASE (Comprehensive)
echo "[7/10] Replacing old URLs and paths in the database..."
ssh $DST_SSH \
  "wp search-replace '$OLD_URL' '$NEW_URL' --path='$DST_DIR' --allow-root --all-tables --precise --recurse-objects && \
   wp search-replace '$OLD_PATH' '$NEW_PATH' --path='$DST_DIR' --allow-root --all-tables --precise --recurse-objects && \
   wp search-replace '$OLD_URL' '$NEW_URL' --path='$DST_DIR' --all-tables --skip-columns=guid"

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
ssh $DST_SSH "
  echo '[wp_options with OLD_URL]';
  mysql -u$DST_DB_USER -p$DST_DB_PASS $DST_DB_NAME -e \"SELECT option_name, option_value FROM wp_options WHERE option_value LIKE '%$OLD_URL%';\"
  echo '[wp_postmeta with OLD_URL]';
  mysql -u$DST_DB_USER -p$DST_DB_PASS $DST_DB_NAME -e \"SELECT meta_key, meta_value FROM wp_postmeta WHERE meta_value LIKE '%$OLD_URL%';\"
  echo '[wp_usermeta with OLD_URL]';
  mysql -u$DST_DB_USER -p$DST_DB_PASS $DST_DB_NAME -e \"SELECT meta_key, meta_value FROM wp_usermeta WHERE meta_value LIKE '%$OLD_URL%';\"
  echo '[wp_site with OLD_URL domain]';
  mysql -u$DST_DB_USER -p$DST_DB_PASS $DST_DB_NAME -e \"SELECT * FROM wp_site WHERE domain LIKE '%$(echo $OLD_URL | awk -F/ '{print $3}')%';\"
  echo '[wp_sitemeta with OLD_URL]';
  mysql -u$DST_DB_USER -p$DST_DB_PASS $DST_DB_NAME -e \"SELECT * FROM wp_sitemeta WHERE meta_value LIKE '%$OLD_URL%';\"
  echo '[wp_blogs with OLD_URL domain]';
  mysql -u$DST_DB_USER -p$DST_DB_PASS $DST_DB_NAME -e \"SELECT blog_id, domain, path FROM wp_blogs WHERE domain LIKE '%$(echo $OLD_URL | awk -F/ '{print $3}')%';\"
  echo '[wp-config.php check]'; grep -E 'WP_HOME|WP_SITEURL' $DST_DIR/wp-config.php;
  echo '[.htaccess check]'; grep -i 'Redirect' $DST_DIR/.htaccess || echo 'No redirects found in .htaccess';
  echo '[File search for OLD_URL]'; grep -r '$OLD_URL' $DST_DIR || echo 'No hardcoded OLD_URL found in files.'
"

# 10. CLEANUP TEMPORARY FILES
echo "[10/10] Cleaning up temporary files..."
rm -f $DUMP_FILE
#rm -rf $LOCAL_TMP_DIR
ssh $SRC_SSH "rm -f $DUMP_FILE"
ssh $DST_SSH "rm -f $DUMP_FILE"

# DONE
echo "Migration and post-migration steps completed successfully."