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

echo "Setting up ddclient for dynamic DNS..."
ssh "$PI_USER@$PI_IP" "
  # Install ddclient if not already installed
  if ! command -v ddclient &> /dev/null; then
    sudo apt update && sudo apt install -y ddclient
  fi
  
  # Generate ddclient config from template and .env
  cd $REMOTE_PATH
  
  # Check if .env exists and has required variables
  if [ ! -f .env ]; then
    echo 'ERROR: .env file not found. Please create it with DDNS_PASSWORD, HOMELAB_SUBDOMAIN, and DOMAIN'
    exit 1
  fi
  
  source .env
  
  if [ -z \"\$DDNS_PASSWORD\" ] || [ -z \"\$HOMELAB_SUBDOMAIN\" ] || [ -z \"\$DOMAIN\" ]; then
    echo 'ERROR: Missing required variables in .env file'
    echo 'Required: DDNS_PASSWORD, HOMELAB_SUBDOMAIN, DOMAIN'
    exit 1
  fi
  sed -e \"s/REPLACE_WITH_DDNS_PASSWORD/\$DDNS_PASSWORD/g\" \
      -e \"s/REPLACE_WITH_SUBDOMAIN/\$HOMELAB_SUBDOMAIN/g\" \
      ddclient.conf.template > ddclient.conf
  
  # Copy and secure ddclient config
  sudo cp ddclient.conf /etc/ddclient.conf
  sudo chmod 600 /etc/ddclient.conf
  sudo chown root:root /etc/ddclient.conf
  
  # Stop ddclient to reload config
  sudo systemctl stop ddclient
  
  # Enable and start ddclient service with new config
  sudo systemctl enable ddclient
  sudo systemctl start ddclient
  
  # Check status and force immediate update
  sudo systemctl is-active ddclient
  echo 'Running ddclient update...'
  sudo ddclient -daemon=0 -debug -verbose -noquiet
"

echo "Stopping, rebuilding, and starting the stack on the Pi..."
ssh "$PI_USER@$PI_IP" "cd $REMOTE_PATH && docker-compose down && docker-compose up -d --build"

echo "Deployment to $PI_USER@$PI_IP complete!"
echo ""
echo "IMPORTANT: Update these settings before going live:"
echo "1. Enable Dynamic DNS in Namecheap for waltermichelin.com"
echo "2. Update .env file with your HOMELAB_SUBDOMAIN and DDNS_PASSWORD"
echo "3. Add A record for your subdomain in Namecheap"
echo "4. Forward ports 80 and 443 on your router to $PI_IP"
echo ""
echo "Local access (before DNS setup):"
echo "Access Grafana at: http://$PI_IP:3000"
echo "Access n8n at: http://$PI_IP:5678"
echo "Access Ollama at: http://$PI_IP:11434"
echo "Access Open WebUI at: http://$PI_IP:3001"
echo "Access Prometheus at: http://$PI_IP:9090"
echo "Access Traefik Dashboard at: http://$PI_IP:8080"
echo ""
echo "After DNS setup:"
echo "Access Grafana at: https://\${HOMELAB_SUBDOMAIN}.\${DOMAIN} (check your .env file)"
echo "Process Exporter metrics at: http://$PI_IP:9256/metrics"
echo ""
echo "To view ollama logs: ssh $PI_USER@$PI_IP 'docker logs -f ollama'" 