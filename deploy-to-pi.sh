#!/bin/bash

# Usage: ./deploy-to-pi.sh <pi-username> <pi-ip> [<remote-path>]

set -e

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <pi-username> <pi-ip> [<remote-path>]"
  exit 1
fi

PI_USER=$1
PI_IP=$2
REMOTE_PATH=${3:-/home/$PI_USER/homelab}

echo "Syncing project to $PI_USER@$PI_IP:$REMOTE_PATH..."

rsync -avz --progress --exclude='.git' --exclude='node_modules' --exclude='*.log' --exclude='.DS_Store' ./ "$PI_USER@$PI_IP:$REMOTE_PATH"

echo "Stopping, rebuilding, and starting the stack on the Pi..."
ssh "$PI_USER@$PI_IP" "cd $REMOTE_PATH && docker-compose down && docker-compose up -d --build"

echo "Deployment to $PI_USER@$PI_IP complete!"
echo "Access Grafana at: http://$PI_IP:3000" 