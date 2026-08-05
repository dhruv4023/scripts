#!/bin/bash
set -e

# Usage:
# ./import.sh ./data/latest-backup.sql

CONTAINER_NAME="expense-mysql"

MYSQL_USER="appuser"
MYSQL_PASSWORD="apppassword"
MYSQL_DATABASE="expense-tracker"

SQL_FILE="$1"

# Validate argument
if [ -z "$SQL_FILE" ]; then
  echo "❌ Please provide SQL file path"
  echo "Usage: ./import.sh <sql-file>"
  echo "example: ./import.sh ./data/latest-backup.sql"
  exit 1
fi

# Check container running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "❌ Container '$CONTAINER_NAME' is not running"
  exit 1
fi

# Check file exists
if [ ! -f "$SQL_FILE" ]; then
  echo "❌ SQL file not found: $SQL_FILE"
  exit 1
fi

echo "📦 Importing: $SQL_FILE"
echo "🚀 Import started..."

docker exec -i "$CONTAINER_NAME" \
  mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < "$SQL_FILE"

echo "✅ Import completed successfully"
