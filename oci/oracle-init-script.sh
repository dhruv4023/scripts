#!/bin/bash
set -e

# =========================================================
# OCI VM INITIAL SERVER SETUP
# Installs:
# - OCI CLI
# - Docker
# - Docker Compose
# - Nginx
# - MySQL Client
# - Nano
# - jq
# - UFW
# =========================================================

echo "=================================================="
echo "🚀 Starting OCI VM setup..."
echo "=================================================="

USERNAME=$(whoami)

OCI_KEY_PATH="/home/$USERNAME/.oci/oci_api_key.pem"
OCI_CONFIG_PATH="/home/$USERNAME/.oci/config"

# =========================================================
# VALIDATE OCI CONFIGURATION
# =========================================================

echo ""
echo "🔍 Checking OCI configuration..."

if [ ! -f "$OCI_KEY_PATH" ]; then
    echo "❌ ERROR: OCI API key not found"
    echo "Expected location:"
    echo "$OCI_KEY_PATH"
    echo ""
    echo "Please create:"
    echo "1. ~/.oci/oci_api_key.pem"
    echo "2. ~/.oci/config"
    exit 1
fi

echo "✅ OCI API key found"

# =========================================================
# SYSTEM UPDATE
# =========================================================

echo ""
echo "📦 Updating system packages..."

sudo apt update -y

echo "✅ System update completed"

# =========================================================
# INSTALL CURL
# =========================================================

echo ""
echo "🔧 Installing curl..."

sudo apt install -y curl

echo "✅ curl installed"

# =========================================================
# INSTALL OCI CLI
# =========================================================

echo ""
echo "☁️ Checking OCI CLI..."

if ! command -v oci &>/dev/null; then
    echo "📥 OCI CLI not found. Installing..."

    curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh \
    | bash -s -- --accept-all-defaults

    echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
    export PATH=$HOME/bin:$PATH

    echo "✅ OCI CLI installed"

else
    echo "✅ OCI CLI already installed"
fi

# Repair OCI permissions
if command -v oci &>/dev/null; then
    echo ""
    echo "🔐 Fixing OCI file permissions..."

    oci setup repair-file-permissions --file "$OCI_CONFIG_PATH"

    echo "✅ OCI permissions repaired"
else
    echo "❌ OCI CLI installation failed"
fi

# =========================================================
# INSTALL DOCKER
# =========================================================

echo ""
echo "🐳 Checking Docker..."

if ! command -v docker &>/dev/null; then
    echo "📥 Installing Docker..."

    curl -fsSL https://get.docker.com | sudo bash

    sudo usermod -aG docker "$USER"

    echo "✅ Docker installed"

else
    echo "✅ Docker already installed"
fi

# =========================================================
# INSTALL DOCKER COMPOSE
# =========================================================

echo ""
echo "🐳 Checking Docker Compose..."

if ! command -v docker-compose &>/dev/null; then
    echo "📥 Installing Docker Compose..."

    sudo apt install -y docker-compose

    echo "✅ Docker Compose installed"

else
    echo "✅ Docker Compose already installed"
fi

# =========================================================
# INSTALL NANO
# =========================================================

echo ""
echo "📝 Checking Nano..."

if ! command -v nano &>/dev/null; then
    echo "📥 Installing Nano..."

    sudo apt install -y nano

    echo "✅ Nano installed"

else
    echo "✅ Nano already installed"
fi

# =========================================================
# INSTALL JQ
# =========================================================

echo ""
echo "🧩 Checking jq..."

if ! command -v jq &>/dev/null; then
    echo "📥 Installing jq..."

    sudo apt install -y jq

    echo "✅ jq installed"

else
    echo "✅ jq already installed"
fi

# =========================================================
# INSTALL MYSQL CLIENT
# =========================================================

echo ""
echo "🛢️ Checking MySQL client..."

if ! command -v mysql &>/dev/null; then
    echo "📥 Installing MySQL client..."

    sudo apt install -y mysql-client

    echo "✅ MySQL client installed"

else
    echo "✅ MySQL client already installed"
fi

# =========================================================
# INSTALL NGINX
# =========================================================

echo ""
echo "🌐 Checking Nginx..."

if ! command -v nginx &>/dev/null; then
    echo "📥 Installing Nginx..."

    sudo apt install -y nginx

    echo "✅ Nginx installed"

else
    echo "✅ Nginx already installed"
fi

# =========================================================
# START NGINX
# =========================================================

echo ""
echo "🚀 Starting Nginx service..."

sudo systemctl enable nginx
sudo systemctl restart nginx

echo "✅ Nginx started"

# =========================================================
# INSTALL & CONFIGURE UFW
# =========================================================

echo ""
echo "🔥 Checking UFW firewall..."

if ! command -v ufw &>/dev/null; then
    echo "📥 Installing UFW..."

    sudo apt install -y ufw
fi

echo "🔓 Allowing ports..."

sudo ufw allow OpenSSH
sudo ufw allow 80
sudo ufw allow 443

echo "🛡️ Enabling firewall..."

sudo ufw --force enable

echo "✅ Firewall configured"

# =========================================================
# VERIFY NGINX
# =========================================================

echo ""
echo "🧪 Testing Nginx..."

curl -I http://localhost || echo "⚠️ Warning: Nginx test failed"

# =========================================================
# MAKE PROJECT SCRIPTS EXECUTABLE
# =========================================================

echo ""
echo "📜 Setting executable permissions for scripts..."

chmod +x ./scripts/backup-mysql-local.sh || true
chmod +x ./scripts/fetch-latest-backup.sh || true

echo "✅ Script permissions updated"

# =========================================================
# FINAL STATUS
# =========================================================

echo ""
echo "=================================================="
echo "✅ OCI VM setup completed successfully"
echo "=================================================="

echo ""
echo "📌 Installed Services:"
echo "   ✅ OCI CLI"
echo "   ✅ Docker"
echo "   ✅ Docker Compose"
echo "   ✅ Nginx"
echo "   ✅ MySQL Client"
echo "   ✅ Nano"
echo "   ✅ jq"
echo "   ✅ UFW"

echo ""
echo "🌐 Access your server:"
echo "   http://YOUR_PUBLIC_IP"

echo ""
echo "⚠️ IMPORTANT:"
echo "You may need to log out and back in"
echo "for Docker group permissions to apply."

echo ""
echo "=================================================="
