#!/usr/bin/env bash
# Deploy the Raspberry Pi monitoring stack from this Mac (rsync + compose).
# No git checkout required on the Pi.
#
# Usage: ./deploy-to-pi.sh [user@host] [remote-path]
#   defaults: pi  →  /home/<user>/homelab
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/envfile.sh
source "${SCRIPT_DIR}/scripts/lib/envfile.sh"

ROOT="$(homelab_root)"
cd "$ROOT"

TARGET="${1:-pi}"
if [[ "$TARGET" == *"@"* ]]; then
  PI_USER="${TARGET%%@*}"
  PI_HOST="${TARGET#*@}"
else
  PI_HOST="$TARGET"
  PI_USER="$(ssh -G "$PI_HOST" 2>/dev/null | awk '/^user /{print $2; exit}')"
  PI_USER="${PI_USER:-wmichelin}"
fi
REMOTE_PATH="${2:-/home/${PI_USER}/homelab}"

if [[ ! -f "$(homelab_secrets_file)" ]]; then
  echo "Missing secrets/homelab.env — copy the example and fill values first." >&2
  exit 1
fi

"${ROOT}/scripts/materialize-env.sh" >/dev/null

echo "Syncing monitoring stack to ${PI_USER}@${PI_HOST}:${REMOTE_PATH}..."
rsync -avz --delete --progress \
  --exclude-from="${ROOT}/.rsyncignore" \
  --exclude 'apps/' \
  --exclude 'infra/' \
  --exclude 'docs/' \
  --exclude 'scripts/' \
  --exclude 'media-stack' \
  --exclude 'immich' \
  --exclude 'g5-exporters/' \
  --exclude 'apple-photos-export/' \
  --exclude 'secrets/' \
  "${ROOT}/" "${PI_USER}@${PI_HOST}:${REMOTE_PATH}/"

echo "Pushing secrets + materialized .env..."
ssh "${PI_USER}@${PI_HOST}" "mkdir -p '${REMOTE_PATH}/secrets' && chmod 700 '${REMOTE_PATH}/secrets'"
scp -q "$(homelab_secrets_file)" "${PI_USER}@${PI_HOST}:${REMOTE_PATH}/secrets/homelab.env"
scp -q "${ROOT}/.env" "${PI_USER}@${PI_HOST}:${REMOTE_PATH}/.env"
ssh "${PI_USER}@${PI_HOST}" "chmod 600 '${REMOTE_PATH}/secrets/homelab.env' '${REMOTE_PATH}/.env'"

# Deploy fails closed: pull/build before reconciling running containers.
echo "Pulling and building images on the Pi..."
ssh "${PI_USER}@${PI_HOST}" "cd '${REMOTE_PATH}' && docker compose pull && docker compose build"

echo "Reconciling the stack..."
ssh "${PI_USER}@${PI_HOST}" "cd '${REMOTE_PATH}' && docker compose up -d --remove-orphans"

echo "Cleaning up dangling images only..."
ssh "${PI_USER}@${PI_HOST}" "docker image prune -f"

echo "Deployment to ${PI_USER}@${PI_HOST} complete."
echo "  Grafana:    http://${PI_HOST}:3000"
echo "  Prometheus: http://${PI_HOST}:9090"
