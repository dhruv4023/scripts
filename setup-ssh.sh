#!/usr/bin/env bash

# Exit immediately if any command fails.
# This prevents the script from continuing with a broken setup.
set -e


# ============================================================
# 1. INSTALL REQUIRED PACKAGES
# ============================================================

# openssh-server
#   Provides the SSH server (sshd), allowing other computers
#   to connect to this laptop using:
#       ssh username@IP
#
# avahi-daemon
#   Provides mDNS (Multicast DNS), which allows this laptop
#   to be discovered using a hostname such as:
#       <hostname>.local
#
# avahi-utils
#   Provides useful commands for testing mDNS/Avahi.
#
# apt update refreshes the package index before installation.
echo "==> Installing SSH and Avahi..."

sudo apt update
sudo apt install -y openssh-server avahi-daemon avahi-utils


# ============================================================
# 2. ENABLE AND START SSH SERVER
# ============================================================

# 'systemctl enable' makes SSH start automatically when
# the laptop boots.
#
# '--now' also starts the SSH service immediately.
#
# After this, other devices on the same network can connect
# to this laptop using port 22.
echo "==> Enabling and starting SSH..."

sudo systemctl enable --now ssh


# ============================================================
# 3. ENABLE AND START AVAHI / mDNS
# ============================================================

# Avahi advertises this laptop's hostname on the local network.
#
# For example, if:
#     hostname = ramramsa
#
# other devices may be able to access it using:
#     ramramsa.local
#
# Note:
# Android hotspots can sometimes block mDNS traffic.
# In that case, the IP address will still work even though
# ramramsa.local does not.
echo "==> Enabling and starting Avahi..."

sudo systemctl enable --now avahi-daemon


# ============================================================
# 4. CONFIGURE FIREWALL
# ============================================================

# If UFW is installed and currently active, allow incoming
# TCP connections on port 22.
#
# Port 22 is the standard port used by SSH.
#
# We only modify the firewall when UFW is actually active,
# so the script does not unnecessarily enable/change UFW.
echo "==> Checking firewall..."

if command -v ufw >/dev/null 2>&1; then

    if sudo ufw status | grep -q "Status: active"; then

        sudo ufw allow 22/tcp

        echo "    Port 22/tcp allowed through UFW."

    else

        echo "    UFW is installed but currently inactive."

    fi

else

    echo "    UFW is not installed."

fi


# ============================================================
# 5. DISPLAY CONNECTION INFORMATION
# ============================================================

# Display the laptop's hostname.
#
# Example:
#     ramramsa
#
# The hostname is used by Avahi to advertise:
#     ramramsa.local
echo
echo "========================================"
echo " SSH SERVER SETUP COMPLETE"
echo "========================================"
echo

echo "Hostname:"
hostname

echo
echo "IP addresses:"
hostname -I

echo
echo "Try connecting from another laptop:"
echo

# Show an SSH command using the first detected IP address.
echo "    ssh $USER@$(hostname -I | awk '{print $1}')"

echo
echo "Or, if mDNS works:"
echo

# Show the .local hostname.
echo "    ssh $USER@$(hostname).local"


# ============================================================
# 6. SHOW SERVICE STATUS
# ============================================================

# Display the SSH service status so we can confirm that
# sshd is running.
echo
echo "SSH service:"
systemctl --no-pager --full status ssh | head -15


# Display the Avahi service status so we can confirm that
# mDNS is running.
echo
echo "Avahi service:"
systemctl --no-pager --full status avahi-daemon | head -15


# ============================================================
# 7. TEST mDNS LOCALLY
# ============================================================

# avahi-resolve asks the local Avahi service to resolve
# this laptop's .local hostname.
#
# Expected result:
#
#     ramramsa.local    10.x.x.x
#
# If this works on the server but does not work from the
# other laptop, the network/hotspot is likely blocking mDNS.
echo
echo "Testing mDNS..."

avahi-resolve -n "$(hostname).local" || true

echo
echo "Done."
