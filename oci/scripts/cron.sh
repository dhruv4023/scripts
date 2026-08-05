#!/bin/bash

# Usage:
# ./create-cron.sh /path/to/script.sh "0 * * * *"

SCRIPT_PATH="$1"
CRON_FREQ="$2"

if [ -z "$SCRIPT_PATH" ] || [ -z "$CRON_FREQ" ]; then
  echo "Usage: $0 <script_path> <cron_frequency>"
  echo "example: ./create-cron.sh /path/to/script.sh '0 * * * *'"
  exit 1
fi

if [ ! -f "$SCRIPT_PATH" ]; then
  echo "Error: Script not found at $SCRIPT_PATH"
  exit 1
fi

USERNAME=$(whoami)

BASE_NAME=$(basename "$SCRIPT_PATH" .sh)

LOG_DIR="/home/$USERNAME/oci-deploy/logs"
LOG_FILE="$LOG_DIR/${BASE_NAME}.log"

mkdir -p "$LOG_DIR"

CRON_JOB="$CRON_FREQ /bin/bash $SCRIPT_PATH >> $LOG_FILE 2>&1"

# Remove existing entry for same script and add new one
(crontab -l 2>/dev/null | grep -Fv "$SCRIPT_PATH"; echo "$CRON_JOB") | crontab -

echo "Cron job created:"
echo "$CRON_JOB"
echo "Logs: $LOG_FILE"
