#!/bin/bash

SWAPFILE="/swapfile"
SWAPSIZE="2G"

# Check if swap already exists
if swapon --show | grep -q "$SWAPFILE"; then
    echo "Swap already exists at $SWAPFILE"
    exit 0
fi

echo "Creating swap file..."

# Create swap file
sudo fallocate -l $SWAPSIZE $SWAPFILE

# If fallocate fails, use dd instead
if [ ! -f "$SWAPFILE" ]; then
    sudo dd if=/dev/zero of=$SWAPFILE bs=1M count=2048
fi

# Set correct permissions
sudo chmod 600 $SWAPFILE

# Setup swap area
sudo mkswap $SWAPFILE

# Enable swap
sudo swapon $SWAPFILE

# Make permanent after reboot
echo "$SWAPFILE none swap sw 0 0" | sudo tee -a /etc/fstab

# Verify
echo "Swap created successfully:"
swapon --show
free -h
