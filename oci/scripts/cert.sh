#!/bin/bash

echo "---------------------start certificate cron---------------------"

# Check params
if [ "$#" -ne 2 ]; then
    echo "❌ Usage: $0 <domain> <email>"
    echo "👉 Example: $0 oraclemanage.duckdns.org you@example.com"
    exit 1
fi

DOMAIN=$1
EMAIL=$2

DATE=$(date +%F-%H%M%S)

echo "Timestamp: $DATE"

# Add cron job (every 85 days)
SCRIPT_PATH=$(realpath "$0")
USERNAME=$(whoami)
BASE_NAME=$(basename "$SCRIPT_PATH" .sh)
LOG_DIR="/home/$USERNAME/oci-deploy/logs"
LOG_FILE="$LOG_DIR/${BASE_NAME}.log"

CRON_JOB="30 1 * * * /bin/bash $SCRIPT_PATH $DOMAIN $EMAIL >> $LOG_FILE 2>&1"

(crontab -l 2>/dev/null | grep -F "$SCRIPT_PATH $DOMAIN") >/dev/null
if [ $? -eq 0 ]; then
    echo "🕒 Cron job already exists"
else
    echo "🕒 Adding cron job..."
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "✅ Cron job added"
fi

if sudo certbot certificates 2>/dev/null | grep -q "INVALID"; then
    echo "❌ Expired"
else
    echo "✅ Valid"
    exit 0
fi

echo "🔐 Setting up SSL for $DOMAIN"

# Install certbot if not installed
if ! command -v certbot &> /dev/null
then
    echo "📦 Installing Certbot..."
    sudo apt update
    sudo apt install -y certbot
else
    echo "✅ Certbot already installed"
fi

# Stop nginx if running
if systemctl is-active --quiet nginx; then
    echo "⛔ Stopping nginx..."
    sudo systemctl stop nginx
fi

# Create / renew certificate
echo "📜 Creating/Renewing certificate..."
sudo certbot certonly --standalone \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    -d "$DOMAIN" \
    --force-renewal

echo "▶️ Starting nginx..."
sudo systemctl start nginx


echo "✅ Done!"
echo "📁 Certs at: /etc/letsencrypt/live/$DOMAIN/"
echo "---------------------end certificate cron---------------------"
echo ""
echo ""
