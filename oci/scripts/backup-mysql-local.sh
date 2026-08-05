#!/bin/bash
set -euo pipefail

echo "---------------- MYSQL DOCKER BACKUP START ----------------"

USERNAME=$(whoami)

# ================= CONFIG =================
DB_HOST="127.0.0.1"
DB_USER="appuser"
DB_PASS="apppassword"
DB_NAME="expense-tracker"

OCI_CLI_PATH="/home/$USERNAME/bin/oci"
OCI_BUCKET_NAME="bucket-spring-projects"
OCI_CONFIG_FILE="/home/$USERNAME/.oci/config"
# =========================================

BACKUP_DIR="/home/$USERNAME/oci-deploy/data"
DATE=$(date +%F-%H%M%S)
BACKUP_FILE="mysql-backup-$DATE.sql.gz"
LOCAL_PATH="$BACKUP_DIR/$BACKUP_FILE"

mkdir -p "$BACKUP_DIR"

echo "Creating Docker MySQL backup..."

# 🔥 IMPORTANT: run mysqldump INSIDE container OR via network
mysqldump \
  -h "$DB_HOST" \
  -u "$DB_USER" \
  -p"$DB_PASS" \
  --single-transaction \
  --quick \
  --set-gtid-purged=OFF \
  --no-tablespaces \
  "$DB_NAME" \
| gzip > "$LOCAL_PATH"

echo "Backup created: $LOCAL_PATH"

# verify
if [ ! -f "$LOCAL_PATH" ]; then
  echo "ERROR: backup failed"
  exit 1
fi

echo "Uploading to OCI Object Storage..."

OCI_NAMESPACE=$($OCI_CLI_PATH os ns get --query 'data' --raw-output)

$OCI_CLI_PATH os object put \
  --bucket-name "$OCI_BUCKET_NAME" \
  --file "$LOCAL_PATH" \
  --name "$BACKUP_FILE" \
  --config-file "$OCI_CONFIG_FILE"

echo "Upload successful"

rm -f "$LOCAL_PATH"

echo "Local cleanup done"

echo "---------------- MYSQL DOCKER BACKUP END ----------------"
