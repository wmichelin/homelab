#!/usr/bin/env bash
# Deploy G5 stacks from this Mac via rsync + docker compose.
# No git checkout / git pull required on the G5.
#
# Usage:
#   ./deploy-to-g5.sh                 # all G5 apps
#   ./deploy-to-g5.sh exporters
#   ./deploy-to-g5.sh media-stack
#   ./deploy-to-g5.sh immich
#   ./deploy-to-g5.sh all [host] [remote-path]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/envfile.sh
source "${SCRIPT_DIR}/scripts/lib/envfile.sh"

ROOT="$(homelab_root)"
cd "$ROOT"

SCOPE="${1:-all}"
if [[ "$SCOPE" != "all" && "$SCOPE" != "exporters" && "$SCOPE" != "media-stack" && "$SCOPE" != "immich" ]]; then
  # Back-compat: ./deploy-to-g5.sh g5 wmichelin  →  treat as host override with scope=all
  G5_HOST="$SCOPE"
  G5_USER="${2:-wmichelin}"
  REMOTE_PATH="${3:-/home/${G5_USER}/code/homelab}"
  SCOPE=all
else
  G5_HOST="${2:-g5}"
  G5_USER="${3:-wmichelin}"
  REMOTE_PATH="${4:-/home/${G5_USER}/code/homelab}"
fi

if [[ "$G5_HOST" == *"@"* ]]; then
  G5_USER="${G5_HOST%%@*}"
  G5_HOST="${G5_HOST#*@}"
fi

SECRETS="$(homelab_secrets_file)"
if [[ ! -f "$SECRETS" ]]; then
  echo "Missing secrets/homelab.env — copy the example and fill values first." >&2
  exit 1
fi

"${ROOT}/scripts/materialize-env.sh" >/dev/null

remote() {
  ssh "${G5_USER}@${G5_HOST}" "$@"
}

echo "Ensuring remote layout at ${G5_USER}@${G5_HOST}:${REMOTE_PATH}..."
remote "mkdir -p '${REMOTE_PATH}'/{apps,infra,scripts,secrets,docs} \
  && ln -sfn apps/media-stack '${REMOTE_PATH}/media-stack' \
  && ln -sfn apps/immich '${REMOTE_PATH}/immich' \
  && ln -sfn '${REMOTE_PATH}' \"\$HOME/networked-storage\" \
  && ln -sfn '${REMOTE_PATH}/apps/exporters' \"\$HOME/homelab-exporters\" \
  && chmod 700 '${REMOTE_PATH}/secrets'"

echo "Syncing repo (code only)..."
rsync -avz --progress \
  --exclude-from="${ROOT}/.rsyncignore" \
  --exclude 'apple-photos-export/' \
  --exclude 'grafana/' \
  --exclude 'prometheus/' \
  --exclude 'blackbox/' \
  --exclude 'network-exporter/' \
  --exclude 'process-exporter/' \
  --exclude 'systemd/' \
  --exclude 'docker-compose.yml' \
  --exclude 'deploy-to-pi.sh' \
  --exclude 'g5-exporters/' \
  "${ROOT}/" "${G5_USER}@${G5_HOST}:${REMOTE_PATH}/"

echo "Pushing secrets + materialized app env files..."
scp -q "$SECRETS" "${G5_USER}@${G5_HOST}:${REMOTE_PATH}/secrets/homelab.env"
scp -q "${ROOT}/apps/media-stack/.env" "${G5_USER}@${G5_HOST}:${REMOTE_PATH}/apps/media-stack/.env"
scp -q "${ROOT}/apps/immich/.env" "${G5_USER}@${G5_HOST}:${REMOTE_PATH}/apps/immich/.env"
remote "chmod 600 '${REMOTE_PATH}/secrets/homelab.env' \
  '${REMOTE_PATH}/apps/media-stack/.env' \
  '${REMOTE_PATH}/apps/immich/.env'"

install_units() {
  remote "chmod +x '${REMOTE_PATH}/scripts/'*.sh '${REMOTE_PATH}/apps/exporters/scripts/'*.sh 2>/dev/null || true
    '${REMOTE_PATH}/scripts/install-user-units.sh'
    systemctl --user enable --now snapraid-metrics.timer
    systemctl --user enable --now proton-qbit-port-forward.service
    systemctl --user disable --now docker-stats-metrics.timer 2>/dev/null || true
    systemctl --user stop docker-stats-metrics.service 2>/dev/null || true
    loginctl enable-linger \"\$USER\" 2>/dev/null || true"
}

compose_up() {
  local dir="$1"
  remote "cd '${REMOTE_PATH}/${dir}' && docker compose pull && docker compose up -d --remove-orphans"
}

case "$SCOPE" in
  all)
    install_units
    compose_up apps/exporters
    compose_up apps/media-stack
    compose_up apps/immich
    ;;
  exporters)
    install_units
    compose_up apps/exporters
    remote "TEXTFILE_DIR='${REMOTE_PATH}/apps/exporters/textfile' \
      '${REMOTE_PATH}/apps/exporters/scripts/snapraid-metrics.sh' || true"
    ;;
  media-stack)
    compose_up apps/media-stack
    ;;
  immich)
    compose_up apps/immich
    ;;
esac

echo ""
echo "G5 deploy (${SCOPE}) complete → ${G5_USER}@${G5_HOST}:${REMOTE_PATH}"
echo "  Immich:     http://${G5_HOST}:2283"
echo "  Jellyfin:   http://${G5_HOST}:8096"
echo "  node-exp:   http://${G5_HOST}:9100/metrics"
