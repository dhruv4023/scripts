#!/bin/bash

HOST="10.0.0.47"
PORT="3306"
USER="oci-dhruv-4023"

if [ -n "$1" ]; then
  if [ ! -f "$1" ]; then
    echo "File not found: $1"
    exit 1
  fi
  echo "Importing $1 into expense-tracker..."
  mysql -h $HOST -P $PORT -u $USER -p expense-tracker < "$1"
else
  mysql -h $HOST -P $PORT -u $USER -p
fi

DB_HOST="127.0.0.1"
DB_USER="appuser"
DB_PASS="apppassword"
DB_NAME="expense-tracker"

mysql -h 127.0.0.1 -P 3306 -u appuser -p apppassword