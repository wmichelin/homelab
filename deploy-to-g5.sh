#!/usr/bin/env bash
# Deploy G5 stacks from this Mac via rsync + docker compose.
# No git checkout / git pull required on the G5.
#
# Usage:
#   ./deploy-to-g5.sh [--system] [all|exporters|media-stack|immich] [host] [user] [remote-path]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/envfile.sh
source "${SCRIPT_DIR}/scripts/lib/envfile.sh"

ROOT="$(homelab_root)"
cd "$ROOT"

INSTALL_SYSTEM=0
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --system) INSTALL_SYSTEM=1 ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

SCOPE="${1:-all}"
if [[ "$SCOPE" != "all" && "$SCOPE" != "exporters" && "$SCOPE" != "media-stack" && "$SCOPE" != "immich" ]]; then
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

remote() {
  ssh "${G5_USER}@${G5_HOST}" "$@"
}

# Remote QBIT_BT_PORT wins so Proton port-forward state is not clobbered.
echo "Syncing QBIT_BT_PORT from G5 (if present)..."
REMOTE_PORT="$(remote "set -e; p=\$(grep -E '^QBIT_BT_PORT=' '${REMOTE_PATH}/secrets/homelab.env' 2>/dev/null | head -1 | cut -d= -f2- || true); \
  if [ -z \"\$p\" ]; then p=\$(grep -E '^QBIT_BT_PORT=' '${REMOTE_PATH}/apps/media-stack/.env' 2>/dev/null | head -1 | cut -d= -f2- || true); fi; \
  printf '%s' \"\$p\"")" || true
if [[ -n "${REMOTE_PORT:-}" ]]; then
  envfile_set "$SECRETS" QBIT_BT_PORT "$REMOTE_PORT"
  echo "  QBIT_BT_PORT=${REMOTE_PORT} (from G5)"
fi

"${ROOT}/scripts/materialize-env.sh" --target g5 >/dev/null

echo "Ensuring remote layout at ${G5_USER}@${G5_HOST}:${REMOTE_PATH}..."
remote "mkdir -p '${REMOTE_PATH}'/{apps,infra,scripts,secrets,docs} \
  && ln -sfn apps/media-stack '${REMOTE_PATH}/media-stack' \
  && ln -sfn apps/immich '${REMOTE_PATH}/immich' \
  && ln -sfn '${REMOTE_PATH}' \"\$HOME/networked-storage\" \
  && ln -sfn '${REMOTE_PATH}/apps/exporters' \"\$HOME/homelab-exporters\" \
  && chmod 700 '${REMOTE_PATH}/secrets'"

echo "Syncing repo (code only, --delete)..."
set +e
rsync -avz --delete --progress \
  --exclude-from="${ROOT}/.rsyncignore" \
  --exclude 'apple-photos-export/' \
  --exclude 'grafana/' \
  --exclude 'prometheus/' \
  --exclude 'blackbox/' \
  --exclude 'network-exporter/' \
  --exclude 'process-exporter/' \
  --exclude 'systemd/' \
  --exclude '/docker-compose.yml' \
  --exclude '/deploy-to-pi.sh' \
  --exclude 'apps/media-stack/config/' \
  --exclude 'apps/immich/library/' \
  --exclude 'apps/immich/postgres/' \
  --exclude 'apps/exporters/textfile/' \
  --exclude 'backups/' \
  --exclude 'logs/' \
  --exclude 'secrets/' \
  "${ROOT}/" "${G5_USER}@${G5_HOST}:${REMOTE_PATH}/"
rsync_rc=$?
set -e
if [[ "$rsync_rc" -ne 0 && "$rsync_rc" -ne 23 ]]; then
  exit "$rsync_rc"
fi
if [[ "$rsync_rc" -eq 23 ]]; then
  echo "Warning: rsync reported partial transfer (code 23); continuing."
fi

echo "Pushing G5 secrets + materialized app env files..."
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
    rm -f \"\$HOME/.config/systemd/user/docker-stats-metrics.service\" \
          \"\$HOME/.config/systemd/user/docker-stats-metrics.timer\"
    systemctl --user daemon-reload
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

if [[ "$INSTALL_SYSTEM" -eq 1 ]]; then
  echo "Installing G5 system units/scripts (sudo on remote)..."
  remote "cd '${REMOTE_PATH}' && sudo ./scripts/install-g5-system.sh"
fi

echo ""
echo "G5 deploy (${SCOPE}) complete → ${G5_USER}@${G5_HOST}:${REMOTE_PATH}"
echo "  Hub:        http://g5.lan  (lan-dns on G5 + Mac resolver — docs/g5-lan-subdomains.md)"
echo "  Immich:     http://immich.g5.lan  (or http://${G5_HOST}:2283)"
echo "  Jellyfin:   http://jellyfin.g5.lan  (or http://${G5_HOST}:8096)"
echo "  Sonarr:     http://sonarr.g5.lan"
echo "  node-exp:   http://${G5_HOST}:9100/metrics"
