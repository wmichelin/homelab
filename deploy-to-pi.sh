#!/bin/bash

# Usage: ./deploy-to-pi.sh <pi-username> <pi-ip> [<remote-path>]

set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <pi-username> <pi-ip> [<remote-path>]"
  exit 1
fi

PI_USER=$1
PI_IP=$2
REMOTE_PATH=${3:-/home/$PI_USER/homelab}

echo "Syncing project to $PI_USER@$PI_IP:$REMOTE_PATH..."
rsync -avz --progress --exclude-from=.rsyncignore ./ "$PI_USER@$PI_IP:$REMOTE_PATH"

# Deploy "fails closed": we pull/build BEFORE touching the running stack, so a
# failed image pull or build leaves the existing stack up instead of tearing it
# down first. `up -d` then recreates only the containers whose config/image
# changed. We never run `compose down` or a system-wide prune (the old script
# did, which is how a half-finished deploy could leave everything offline).
echo "Pulling and building images on the Pi..."
ssh "$PI_USER@$PI_IP" "cd $REMOTE_PATH && docker compose pull && docker compose build"

echo "Reconciling the stack..."
ssh "$PI_USER@$PI_IP" "cd $REMOTE_PATH && docker compose up -d --remove-orphans"

echo "Cleaning up dangling images only..."
ssh "$PI_USER@$PI_IP" "docker image prune -f"

echo "Deployment to $PI_USER@$PI_IP complete!"
echo ""
echo "Local access:"
echo "Access Grafana at: http://$PI_IP:3000"
echo "Access Prometheus at: http://$PI_IP:9090"
echo "Hubitat Exporter metrics at: http://$PI_IP:5000/metrics"
echo "Process Exporter metrics at: http://$PI_IP:9256/metrics"
echo ""
