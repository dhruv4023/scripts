#!/bin/bash

set -e

ETH="eno1"
REMOTE_IP="192.168.0.11/24"
GATEWAY="192.168.0.10"

echo "Configuring remote Ethernet: $ETH"

# Remove existing IP configuration
sudo ip addr flush dev "$ETH"

# Assign fixed IP
sudo ip addr add "$REMOTE_IP" dev "$ETH"

# Bring interface up
sudo ip link set "$ETH" up

# Remove existing default route through this interface if present
sudo ip route del default dev "$ETH" 2>/dev/null || true

# Add host laptop as Internet gateway
sudo ip route add default via "$GATEWAY" dev "$ETH" 2>/dev/null || \
sudo ip route replace default via "$GATEWAY" dev "$ETH"

# Configure DNS
sudo resolvectl dns "$ETH" 8.8.8.8 1.1.1.1

echo
echo "Remote configuration complete."
echo
echo "Ethernet IP:"
ip addr show "$ETH" | grep 'inet '

echo
echo "Routing:"
ip route

echo
echo "Testing host:"
ping -c 2 "$GATEWAY"

echo
echo "Testing Internet:"
ping -c 2 8.8.8.8

echo
echo "Testing DNS:"
ping -c 2 google.com
