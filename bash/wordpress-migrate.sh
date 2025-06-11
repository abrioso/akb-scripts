#!/bin/bash

# CONFIGURATION
SRC_SSH="user@old_server"
DST_SSH="user@new_server"
SRC_DIR="/var/www/html"
DST_DIR="/var/www/html"
LOCAL_TMP_DIR="/tmp/wordpress_site"
SRC_DB_NAME="wordpress_multisite"
SRC_DB_USER="wp_user_src"
SRC_DB_PASS="wp_pass_src"
DST_DB_NAME="wordpress_multisite"
DST_DB_USER="wp_user_dst"
DST_DB_PASS="wp_pass_dst"
DB_HOST="localhost"
DUMP_FILE="/tmp/wordpress_multisite.sql"
DST_FILES_OWNER="www-data"
OLD_URL="https://oldsite.example.com"
NEW_URL="https://newsite.example.com"
OLD_PATH="/var/www/html"
NEW_PATH="/var/www/html"

# 1. EXPORT DATABASE FROM SOURCE SERVER
echo "[1/8] Exporting database from source server..."
ssh $SRC_SSH "mysqldump -u$SRC_DB_USER -p$SRC_DB_PASS $SRC_DB_NAME > $DUMP_FILE"

# 2. TRANSFER DATABASE DUMP TO LOCAL AND THEN TO DESTINATION SERVER
echo "[2/8] Transferring database dump to local and destination server..."
scp $SRC_SSH:$DUMP_FILE $DUMP_FILE
scp $DUMP_FILE $DST_SSH:$DUMP_FILE

# 3. IMPORT DATABASE ON DESTINATION SERVER
echo "[3/8] Importing database on destination server..."
ssh $DST_SSH "mysql -u$DST_DB_USER -p$DST_DB_PASS $DST_DB_NAME < $DUMP_FILE"

# 4. SYNC WORDPRESS FILES USING LOCAL INTERMEDIATE HOP
echo "[4/8] Syncing WordPress files via local temporary directory..."
rm -rf $LOCAL_TMP_DIR
mkdir -p $LOCAL_TMP_DIR
rsync -avz --progress -e ssh $SRC_SSH:$SRC_DIR/ $LOCAL_TMP_DIR/
rsync -avz --progress -e ssh $LOCAL_TMP_DIR/ $DST_SSH:$DST_DIR/

# 5. SET PERMISSIONS ON DESTINATION SERVER (optional)
echo "[5/8] Setting file permissions..."
ssh $DST_SSH "chown -R $DST_FILES_OWNER:$DST_FILES_OWNER $DST_DIR"

# 6. REPLACE URL AND PATH REFERENCES IN DATABASE
echo "[6/8] Replacing old URLs and paths in the database..."
ssh $DST_SSH \
	  "wp search-replace '$OLD_URL' '$NEW_URL' --url='$NEW_URL' --allow-root --network && \
	     wp search-replace '$OLD_PATH' '$NEW_PATH' --url='$NEW_URL' --allow-root --network"

# 7. CLEANUP TEMPORARY FILES
echo "[7/8] Cleaning up temporary files..."
rm -f $DUMP_FILE
rm -rf $LOCAL_TMP_DIR
ssh $SRC_SSH "rm -f $DUMP_FILE"
ssh $DST_SSH "rm -f $DUMP_FILE"

# 8. DONE
echo "[8/8] Migration and post-migration steps completed successfully."
