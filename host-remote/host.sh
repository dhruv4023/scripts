#!/bin/bash

set -e

ETH="eno2"
HOST_IP="192.168.0.10/24"

echo "Configuring host Ethernet: $ETH"

# Remove existing IP configuration from the Ethernet interface
sudo ip addr flush dev "$ETH"

echo "Flushed existing IP configuration from $ETH"

echo "waiting for 10 seconds..."
sleep 10

echo "Assigning new IP configuration to $ETH"
# Assign fixed IP
sudo ip addr add "$HOST_IP" dev "$ETH"

# Bring interface up
sudo ip link set "$ETH" up

# Enable IPv4 forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# Make IP forwarding persistent
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-ip-forward.conf >/dev/null

# Enable NAT from Ethernet -> WiFi/Internet
sudo iptables -t nat -C POSTROUTING -o wlo1 -j MASQUERADE 2>/dev/null || \
sudo iptables -t nat -A POSTROUTING -o wlo1 -j MASQUERADE

# Allow remote laptop -> Internet
sudo iptables -C FORWARD -i "$ETH" -o wlo1 -j ACCEPT 2>/dev/null || \
sudo iptables -A FORWARD -i "$ETH" -o wlo1 -j ACCEPT

# Allow Internet -> remote laptop for established connections
sudo iptables -C FORWARD -i wlo1 -o "$ETH" \
    -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
sudo iptables -A FORWARD -i wlo1 -o "$ETH" \
    -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

echo
echo "Host configuration complete."
echo
echo "Ethernet IP:"
ip addr show "$ETH" | grep 'inet '

echo
echo "IP forwarding:"
cat /proc/sys/net/ipv4/ip_forward

echo
echo "NAT rules:"
sudo iptables -L FORWARD -v -n
sudo iptables -t nat -L POSTROUTING -v -n

echo
echo "Routing:"
ip route
