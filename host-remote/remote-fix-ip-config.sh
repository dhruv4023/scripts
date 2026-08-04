#!/bin/bash

set -e

INTERFACE="eno1"
IP="192.168.0.11/24"
GATEWAY="192.168.0.10"
NETPLAN_FILE="/etc/netplan/50-cloud-init.yaml"

echo "=== Configuring Ubuntu remote network ==="

# Make sure Netplan directory exists
sudo mkdir -p /etc/netplan

# Create Netplan configuration
sudo tee "$NETPLAN_FILE" > /dev/null <<EOF
network:
  version: 2
  ethernets:
    $INTERFACE:
      dhcp4: false
      addresses:
        - $IP
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses:
          - 8.8.8.8
          - 1.1.1.1
      optional: true
EOF

# Fix Netplan permissions
sudo chown root:root "$NETPLAN_FILE"
sudo chmod 600 "$NETPLAN_FILE"

echo
echo "=== Netplan configuration ==="
sudo cat "$NETPLAN_FILE"

echo
echo "=== Applying network configuration ==="

# Generate and apply
sudo netplan generate
sudo netplan apply

echo
echo "=== Current IP ==="
ip addr show "$INTERFACE"

echo
echo "=== Current routes ==="
ip route

echo
echo "=== Testing gateway ==="
if ping -c 2 -W 2 "$GATEWAY" > /dev/null; then
    echo "✓ Gateway $GATEWAY reachable"
else
    echo "⚠ Gateway $GATEWAY not reachable"
    echo "Make sure the Ethernet cable is connected."
fi

echo
echo "=== Testing Internet ==="
if ping -c 2 -W 3 8.8.8.8 > /dev/null; then
    echo "✓ Internet reachable"
else
    echo "⚠ Internet not reachable"
fi

echo
echo "=== Testing DNS ==="
if getent hosts google.com > /dev/null; then
    echo "✓ DNS working"
else
    echo "⚠ DNS not working"
fi

echo
echo "=== Setup complete ==="
echo "Interface : $INTERFACE"
echo "IP        : $IP"
echo "Gateway   : $GATEWAY"
echo "DNS       : 8.8.8.8, 1.1.1.1"
