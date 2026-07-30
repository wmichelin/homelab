#!/usr/bin/env bash
# After adding the Namecheap A record for hs → pantry droplet IP, finish TLS + print join steps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib/envfile.sh
source "${SCRIPT_DIR}/lib/envfile.sh"

SECRETS="$(homelab_secrets_file)"
DOMAIN="hs.waltermichelin.com"

if [[ -f "$SECRETS" ]]; then
  set -a
  # shellcheck source=/dev/null
  source <(grep -E '^(DROPLET_HOST|HEADSCALE_DROPLET_HOST)=' "$SECRETS" 2>/dev/null || true)
  set +a
fi

DROPLET_HOST="${1:-${HEADSCALE_DROPLET_HOST:-${DROPLET_HOST:-}}}"
: "${DROPLET_HOST:?Set DROPLET_HOST or pass droplet IP}"

echo "Checking public DNS for ${DOMAIN}..."
ip="$(dig +short "$DOMAIN" @1.1.1.1 | head -1)"
if [[ -z "$ip" ]]; then
  echo "DNS not live yet. Add Namecheap Advanced DNS A record: host=hs value=${DROPLET_HOST}" >&2
  echo "See terraform/headscale/README.md" >&2
  exit 1
fi
echo "  ${DOMAIN} → ${ip}"

echo "Issuing / renewing Let's Encrypt cert on droplet..."
ssh "root@${DROPLET_HOST}" \
  "certbot --nginx -d ${DOMAIN} --non-interactive --agree-tos -m wmichelin@gmail.com --redirect && systemctl reload nginx"

echo "HTTPS check:"
curl -fsS -o /dev/null -w "  https://${DOMAIN} → HTTP %{http_code}\n" "https://${DOMAIN}/" || true

echo
echo "Join G5 (needs sudo on G5):"
echo "  ssh g5"
echo "  curl -fsSL https://tailscale.com/install.sh | sh"
echo "  sudo tailscale up --login-server=https://${DOMAIN} --authkey=\$(cat ~/code/homelab/secrets/headscale-preauth.key) --accept-dns --hostname=g5"
echo "  tailscale ip -4"
echo "Then put that IP into apps/headscale/extra-records.json and re-run ./scripts/deploy-headscale-to-droplet.sh"
