#!/usr/bin/env bash
# Deploy Headscale to the pantry DigitalOcean droplet (shared host, separate container).
# Does not modify the Pantry repo. Pantry keeps port 8080; Headscale binds 127.0.0.1:8081.
#
# Prerequisites:
#   - SSH as root to the droplet (same key pantry deploy uses)
#   - DNS: hs.waltermichelin.com A → droplet IP (see terraform/headscale/)
#   - DROPLET_HOST in secrets/homelab.env, or pass as $1
#
# Usage:
#   ./scripts/deploy-headscale-to-droplet.sh [droplet-ip-or-host]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib/envfile.sh
source "${SCRIPT_DIR}/lib/envfile.sh"

SECRETS="$(homelab_secrets_file)"
DOMAIN="hs.waltermichelin.com"
REMOTE_DIR="/opt/headscale"
EMAIL="wmichelin@gmail.com"

if [[ -f "$SECRETS" ]]; then
  # shellcheck disable=SC1090
  set -a
  # shellcheck source=/dev/null
  source <(grep -E '^(DROPLET_HOST|HEADSCALE_DROPLET_HOST)=' "$SECRETS" 2>/dev/null || true)
  set +a
fi

DROPLET_HOST="${1:-${HEADSCALE_DROPLET_HOST:-${DROPLET_HOST:-}}}"
if [[ -z "$DROPLET_HOST" ]]; then
  echo "Set DROPLET_HOST (or HEADSCALE_DROPLET_HOST) in secrets/homelab.env, or pass the droplet IP." >&2
  echo "Pantry terraform output: (cd ../Pantry/terraform && terraform output -raw droplet_ip)" >&2
  exit 1
fi

echo "Deploying Headscale to root@${DROPLET_HOST} (${DOMAIN})..."

rsync -avz --delete \
  --exclude '.DS_Store' \
  "${ROOT}/apps/headscale/" \
  "root@${DROPLET_HOST}:${REMOTE_DIR}/"

ssh -o StrictHostKeyChecking=accept-new "root@${DROPLET_HOST}" bash -s <<EOF
set -euo pipefail
DOMAIN="${DOMAIN}"
REMOTE_DIR="${REMOTE_DIR}"
EMAIL="${EMAIL}"

if ! command -v docker &>/dev/null; then
  apt-get update -y
  apt-get install -y docker.io docker-compose-v2
  systemctl enable docker && systemctl start docker
elif ! docker compose version &>/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y docker-compose-v2
fi
# Prefer compose plugin; fall back to docker-compose if present.
compose() {
  if docker compose version &>/dev/null 2>&1; then
    docker compose "\$@"
  elif command -v docker-compose &>/dev/null; then
    docker-compose "\$@"
  else
    echo "docker compose not available" >&2
    exit 1
  fi
}

if ! command -v nginx &>/dev/null; then
  apt-get update -y
  apt-get install -y nginx certbot python3-certbot-nginx
fi

cd "\$REMOTE_DIR"
compose pull
compose up -d

# First boot: HTTP vhost + certbot. Later: only reload (do not clobber HTTPS).
if [[ ! -f "/etc/letsencrypt/live/\$DOMAIN/fullchain.pem" ]]; then
  cp "\$REMOTE_DIR/nginx-hs.conf" "/etc/nginx/sites-available/\$DOMAIN"
  ln -sf "/etc/nginx/sites-available/\$DOMAIN" "/etc/nginx/sites-enabled/\$DOMAIN"
  rm -f /etc/nginx/sites-enabled/default
  nginx -t && systemctl reload nginx
  if ! certbot --nginx -d "\$DOMAIN" --non-interactive --agree-tos -m "\$EMAIL" --redirect; then
    echo "WARNING: certbot failed (often DNS not propagated yet)." >&2
    echo "Add Namecheap A record hs → this droplet, wait for dig, then:" >&2
    echo "  certbot --nginx -d \$DOMAIN --non-interactive --agree-tos -m \$EMAIL --redirect" >&2
  fi
else
  # Keep proxy target current without wiping certbot-managed SSL server blocks.
  if ! grep -q '127.0.0.1:8081' "/etc/nginx/sites-available/\$DOMAIN" 2>/dev/null; then
    echo "Warning: existing nginx site for \$DOMAIN may not proxy to :8081 — check manually." >&2
  fi
  nginx -t && systemctl reload nginx
fi

echo "Headscale container:"
compose ps
EOF

echo
echo "Done. Control plane: https://${DOMAIN}"
echo "Next:"
echo "  ssh root@${DROPLET_HOST} 'cd ${REMOTE_DIR} && docker compose exec headscale headscale users create homelab'"
echo "  ssh root@${DROPLET_HOST} 'cd ${REMOTE_DIR} && docker compose exec headscale headscale users list'"
echo "  ssh root@${DROPLET_HOST} 'cd ${REMOTE_DIR} && docker compose exec headscale headscale preauthkeys create --user <ID> --reusable --expiration 24h'"
echo "  Join G5 / Mac / phone with login server https://${DOMAIN}"
echo "  Update apps/headscale/extra-records.json with G5's Tailscale IP, then re-run this script."
