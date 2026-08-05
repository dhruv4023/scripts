#!/bin/bash

set -e

echo "Installing RabbitMQ..."

sudo apt update

sudo apt install curl gnupg2 apt-transport-https software-properties-common -y

sudo apt install erlang -y

sudo apt install rabbitmq-server -y

echo "Configuring RabbitMQ memory limits..."

sudo mkdir -p /etc/rabbitmq

sudo tee /etc/rabbitmq/rabbitmq.conf > /dev/null <<EOF
vm_memory_high_watermark.relative = 0.4
disk_free_limit.absolute = 500MB
management.tcp.port = 15672
EOF

sudo systemctl daemon-reload
sudo systemctl enable rabbitmq-server
sudo systemctl restart rabbitmq-server

sudo rabbitmq-plugins enable rabbitmq_management

echo "RabbitMQ installed and configured."

sudo rabbitmqctl status
