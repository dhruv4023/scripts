#!/bin/bash
echo "---------------------start delete old backup cron---------------------"

set -euo pipefail

#################################
# CONFIG
#################################
FILE_PREFIX="mysql-backup-"
KEEP_DAYS=2
OCI_BUCKET="bucket-spring-projects"

USERNAME=$(whoami)
OCI_CLI="/home/$USERNAME/bin/oci"
OCI_CONFIG="/home/$USERNAME/.oci/config"


#################################
# CALCULATE CUTOFF (UTC)
#################################
CUTOFF_DATE=$(date -u -d "$KEEP_DAYS days ago" +"%Y-%m-%dT%H:%M:%S")

echo "Keeping last $KEEP_DAYS days of backups"
echo "Deleting objects older than: $CUTOFF_DATE (UTC)"
echo "Prefix filter: $FILE_PREFIX"

#################################
# LIST & DELETE OLD OBJECTS
#################################

# List objects in JSON
OBJECTS=$($OCI_CLI os object list \
  --bucket-name "$OCI_BUCKET" \
  --query "data[?starts_with(name, '$FILE_PREFIX') && \"time-created\" < '$CUTOFF_DATE']" \
  --output json)

# Check if OBJECTS is empty
if [ "$OBJECTS" = "[]" ] || [ -z "$OBJECTS" ]; then
    echo "No objects to delete."
    exit 0
fi

# Delete objects
echo "$OBJECTS" | jq -r '.[] | "\(.name) \(.time)"' | while read -r OBJECT_NAME OBJECT_TIME; do
    if [ -n "$OBJECT_NAME" ]; then
        echo "Deleting OCI object: $OBJECT_NAME (created at $OBJECT_TIME)"
        $OCI_CLI os object delete \
          --bucket-name "$OCI_BUCKET" \
          --name "$OBJECT_NAME" \
          --force
    fi
done


echo "OCI cleanup completed successfully."

echo "---------------------end delete old backup cron---------------------"
echo ""
echo ""
