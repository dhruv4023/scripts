#!/usr/bin/env bash

set -e

IFACE="eno2"
SERVER_IP="192.168.102.1"
RANGE_START="192.168.102.100"
RANGE_END="192.168.102.200"

cleanup() {
    echo
    echo "Stopping DHCP debug..."
    if [[ -n "${DNSMASQ_PID:-}" ]]; then
        sudo kill "$DNSMASQ_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

clear

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    DHCP DEBUG SERVER                       ║"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  Interface : %-44s ║\n" "$IFACE"
printf "║  Server IP : %-44s ║\n" "$SERVER_IP"
printf "║  DHCP Pool : %-44s ║\n" "$RANGE_START - $RANGE_END"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  DHCPMASQ → left       TCPDUMP → right                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo

echo "Starting dnsmasq..."

sudo dnsmasq \
    --no-daemon \
    --log-dhcp \
    --log-debug \
    --port=0 \
    --interface="$IFACE" \
    --bind-interfaces \
    --dhcp-broadcast \
    --dhcp-range="$RANGE_START,$RANGE_END,255.255.255.0,12h" \
    > >(while IFS= read -r line; do
        printf '[DNSMASQ] %s\n' "$line"
    done) 2>&1 &

DNSMASQ_PID=$!

sleep 1

echo
echo "Starting packet capture..."
echo

sudo tcpdump -vvv -l -ni "$IFACE" \
    'udp port 67 or udp port 68' \
    2>&1 | while IFS= read -r line; do
        printf '[TCPDUMP] %s\n' "$line"
    done &

TCPDUMP_PID=$!

wait "$DNSMASQ_PID"
