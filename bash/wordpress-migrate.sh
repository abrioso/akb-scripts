#!/bin/bash

# CONFIGURATION
SRC_SSH="user@old_server"
DST_SSH="user@new_server"
SRC_DIR="/var/www/html"
DST_DIR="/var/www/html"
SRC_DB_NAME="wordpress_multisite"
SRC_DB_USER="wp_user_src"
SRC_DB_PASS="wp_pass_src"
DST_DB_NAME="wordpress_multisite"
DST_DB_USER="wp_user_dst"
DST_DB_PASS="wp_pass_dst"
DB_HOST="localhost"
DUMP_FILE="/tmp/wordpress_multisite.sql"

# 1. EXPORT DATABASE FROM SOURCE SERVER
echo "[1/6] Exporting database from source server..."
ssh $SRC_SSH "mysqldump -u$SRC_DB_USER -p$SRC_DB_PASS $SRC_DB_NAME > $DUMP_FILE"

# 2. TRANSFER DATABASE DUMP TO LOCAL AND THEN TO DESTINATION SERVER
echo "[2/6] Transferring database dump to local and destination server..."
scp $SRC_SSH:$DUMP_FILE $DUMP_FILE
scp $DUMP_FILE $DST_SSH:$DUMP_FILE

# 3. IMPORT DATABASE ON DESTINATION SERVER
echo "[3/6] Importing database on destination server..."
ssh $DST_SSH "mysql -u$DST_DB_USER -p$DST_DB_PASS $DST_DB_NAME < $DUMP_FILE"

# 4. SYNC WORDPRESS FILES
echo "[4/6] Syncing WordPress files..."
rsync -avz --progress -e ssh $SRC_SSH:$SRC_DIR/ $DST_SSH:$DST_DIR/

# 5. SET PERMISSIONS ON DESTINATION SERVER (optional)
echo "[5/6] Setting file permissions..."
ssh $DST_SSH "chown -R www-data:www-data $DST_DIR"

# 6. CLEANUP TEMP FILES (optional)
echo "[6/6] Cleaning up temporary files..."
rm -f $DUMP_FILE
ssh $SRC_SSH "rm -f $DUMP_FILE"
ssh $DST_SSH "rm -f $DUMP_FILE"

echo "Migration completed successfully."

