#!/usr/bin/env bash

set -e

IFACE="eno2"
SERVER_IP="192.168.0.1"
RANGE_START="192.168.0.2"
RANGE_END="192.168.0.200"

# Authenticate once before starting background processes.
sudo -v

DNSMASQ_PID=""
TCPDUMP_PID=""

cleanup() {
    echo
    echo "Stopping DHCP debug..."

    trap - INT TERM EXIT

    if [[ -n "$TCPDUMP_PID" ]]; then
        sudo kill "$TCPDUMP_PID" 2>/dev/null || true
    fi

    if [[ -n "$DNSMASQ_PID" ]]; then
        sudo kill "$DNSMASQ_PID" 2>/dev/null || true
    fi

    wait 2>/dev/null || true
    echo "DHCP debug stopped."
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

clear

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

sudo tcpdump -vvv -l -ni "$IFACE" \
    'udp port 67 or udp port 68' \
    2>&1 | while IFS= read -r line; do
        printf '[TCPDUMP] %s\n' "$line"
    done &

TCPDUMP_PID=$!

wait "$DNSMASQ_PID"
