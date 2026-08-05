#!/bin/bash

# ==========================================
# Usage:
# ./setup-nginx.sh                 (IP + HTTP)
# ./setup-nginx.sh example.com     (Domain + HTTPS)
# ==========================================

DOMAIN="$1"

BACKEND_URL="http://localhost:8000"

NGINX_CONF="/etc/nginx/sites-available/default"
NGINX_ENABLED="/etc/nginx/sites-enabled/default"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"

echo "=================================="

# ------------------------------
# CASE 1: DOMAIN PROVIDED → HTTPS
# ------------------------------
if [ -n "$DOMAIN" ]; then
    echo "Mode: DOMAIN detected → HTTPS setup"
    echo "Domain: $DOMAIN"

    sudo tee "$NGINX_CONF" > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate $CERT_PATH/fullchain.pem;
    ssl_certificate_key $CERT_PATH/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass $BACKEND_URL;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF

# ------------------------------
# CASE 2: NO DOMAIN → HTTP ONLY
# ------------------------------
else
    echo "Mode: NO DOMAIN → HTTP IP setup"

    sudo tee "$NGINX_CONF" > /dev/null <<EOF
server {
    listen 80 default_server;
    server_name _;

    location / {
        proxy_pass $BACKEND_URL;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto http;
    }
}
EOF

fi

echo "Config written to $NGINX_CONF"

# Enable site
if [ ! -L "$NGINX_ENABLED" ]; then
    sudo ln -s "$NGINX_CONF" "$NGINX_ENABLED"
fi

# Remove default if needed (safe cleanup)
if [ -L "/etc/nginx/sites-enabled/default" ]; then
    sudo rm /etc/nginx/sites-enabled/default
fi

# Test nginx
echo "Testing nginx config..."
if ! sudo nginx -t; then
    echo "ERROR: nginx config failed"
    exit 1
fi

# Reload nginx
sudo systemctl reload nginx

echo "=================================="

if [ -n "$DOMAIN" ]; then
    echo "Access: https://$DOMAIN"
else
    echo "Access: http://YOUR_SERVER_IP"
fi