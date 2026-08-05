#!/bin/bash
set -e

echo "☁️ Fetching latest MySQL backup from OCI..."

# OCI config path
OCI_CONFIG=./oci_config

# Bucket name
BUCKET_NAME="bucket-spring-projects"

# Temp directory
mkdir -p ./data

# Get latest file
LATEST_FILE=$(oci os object list \
  -bn "$BUCKET_NAME" \
  --config-file "$OCI_CONFIG" \
  --query 'reverse(sort_by(data, &"time-created"))[0].name' \
  --raw-output)

if [ -z "$LATEST_FILE" ] || [ "$LATEST_FILE" = "null" ]; then
  echo "❌ No backup file found in bucket"
  exit 1
fi

echo "📦 Found latest backup: $LATEST_FILE"

# Get storage tier
STORAGE_TIER=$(oci os object list \
  -bn "$BUCKET_NAME" \
  --config-file "$OCI_CONFIG" \
  --query 'reverse(sort_by(data, &"time-created"))[0]."storage-tier"' \
  --raw-output)

echo "🗂 Storage tier: $STORAGE_TIER"

# Handle archive restore
if [[ "$STORAGE_TIER" == "Archive" ]]; then
  echo "⚠️ Object is archived"

  oci os object restore \
    -bn "$BUCKET_NAME" \
    --name "$LATEST_FILE" \
    --config-file "$OCI_CONFIG"

  echo "🕒 Restore requested."
  echo "⏳ Wait around 15–60 minutes, then run script again."

  exit 0
fi

# Download backup
echo "⬇️ Downloading backup..."

oci os object get \
  -bn "$BUCKET_NAME" \
  --name "$LATEST_FILE" \
  --file ./data/latest-backup.sql.gz \
  --config-file "$OCI_CONFIG"

# Decompress
echo "📂 Extracting backup..."

gunzip -f ./data/latest-backup.sql.gz

echo "✅ Backup ready:"
echo "./data/latest-backup.sql"