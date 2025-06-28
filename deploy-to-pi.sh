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

rsync -avz --progress --exclude-from=.rsyncignore ./ "$PI_USER@$PI_IP:$REMOTE_PATH"

echo "Stopping, rebuilding, and starting the stack on the Pi..."
ssh "$PI_USER@$PI_IP" "cd $REMOTE_PATH && docker-compose down && docker-compose up -d --build"

echo "Deployment to $PI_USER@$PI_IP complete!"
echo "Access Grafana at: http://$PI_IP:3000"
echo "Access n8n at: http://$PI_IP:5678"
echo "Access Ollama at: http://$PI_IP:11434"
echo "Access Open WebUI at: http://$PI_IP:3001"
echo "Access Prometheus at: http://$PI_IP:9090"
echo "Process Exporter metrics at: http://$PI_IP:9256/metrics"
echo ""
echo "To view ollama logs: ssh $PI_USER@$PI_IP 'docker logs -f ollama'" 