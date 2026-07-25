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

"${ROOT}/scripts/materialize-env.sh" --target pi >/dev/null

echo "Syncing monitoring stack to ${PI_USER}@${PI_HOST}:${REMOTE_PATH}..."
set +e
rsync -avz --delete --progress \
  --exclude-from="${ROOT}/.rsyncignore" \
  --exclude 'apps/' \
  --exclude 'infra/' \
  --exclude 'docs/' \
  --exclude 'scripts/' \
  --exclude 'media-stack' \
  --exclude 'immich' \
  --exclude 'apple-photos-export/' \
  --exclude 'secrets/' \
  --exclude 'fail2ban/' \
  --exclude 'fail2ban-exporter/' \
  --exclude 'traefik/' \
  --exclude 'hubitat-exporter/' \
  --exclude 'g5-exporters/' \
  "${ROOT}/" "${PI_USER}@${PI_HOST}:${REMOTE_PATH}/"
rsync_rc=$?
set -e
# 23 = partial transfer (e.g. root-owned leftover dirs we cannot delete)
if [[ "$rsync_rc" -ne 0 && "$rsync_rc" -ne 23 ]]; then
  exit "$rsync_rc"
fi
if [[ "$rsync_rc" -eq 23 ]]; then
  echo "Warning: rsync reported partial transfer (code 23); continuing."
fi

echo "Pushing Pi-scoped .env (monitoring keys only)..."
ssh "${PI_USER}@${PI_HOST}" "mkdir -p '${REMOTE_PATH}'"
scp -q "${ROOT}/.env" "${PI_USER}@${PI_HOST}:${REMOTE_PATH}/.env"
ssh "${PI_USER}@${PI_HOST}" "chmod 600 '${REMOTE_PATH}/.env'"

# Deploy fails closed for build, but tolerate arch-incompatible pulls (e.g. pantry on arm64).
echo "Pulling and building images on the Pi..."
ssh "${PI_USER}@${PI_HOST}" "cd '${REMOTE_PATH}' && docker compose pull --ignore-pull-failures && docker compose build"

echo "Reconciling the stack..."
ssh "${PI_USER}@${PI_HOST}" "cd '${REMOTE_PATH}' && docker compose up -d --remove-orphans"

echo "Installing systemd units (stack + watchdog)..."
ssh "${PI_USER}@${PI_HOST}" bash -s -- "$REMOTE_PATH" <<'REMOTE'
set -euo pipefail
REMOTE_PATH=$1
UNIT_DIR="${REMOTE_PATH}/systemd"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for unit in homelab-stack.service homelab-watchdog.service homelab-watchdog.timer; do
  sed "s|__HOMELAB_ROOT__|${REMOTE_PATH}|g" "${UNIT_DIR}/${unit}" > "${TMP}/${unit}"
done
chmod +x "${REMOTE_PATH}/systemd/homelab-watchdog.sh"

sudo cp "${TMP}/homelab-stack.service" /etc/systemd/system/homelab-stack.service
sudo cp "${TMP}/homelab-watchdog.service" /etc/systemd/system/homelab-watchdog.service
sudo cp "${TMP}/homelab-watchdog.timer" /etc/systemd/system/homelab-watchdog.timer
sudo systemctl daemon-reload
sudo systemctl enable --now homelab-stack.service
sudo systemctl enable --now homelab-watchdog.timer
REMOTE

echo "Cleaning up dangling images only..."
ssh "${PI_USER}@${PI_HOST}" "docker image prune -f"

echo "Deployment to ${PI_USER}@${PI_HOST} complete."
echo "  Grafana:    http://${PI_HOST}:3000"
echo "  Prometheus: http://${PI_HOST}:9090"
