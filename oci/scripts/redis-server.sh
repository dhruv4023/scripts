#!/bin/bash

set -e

echo "Installing Redis..."

sudo apt update
sudo apt install redis-server -y

echo "Configuring Redis memory limits..."

sudo cp /etc/redis/redis.conf /etc/redis/redis.conf.backup

sudo sed -i 's/^# maxmemory <bytes>/maxmemory 128mb/' /etc/redis/redis.conf
sudo sed -i 's/^# maxmemory-policy noeviction/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf

sudo systemctl enable redis-server
sudo systemctl restart redis-server

echo "Redis installed and configured."

redis-cli ping
