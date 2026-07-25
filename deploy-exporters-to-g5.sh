#!/bin/bash
# Deploy G5 exporter stack + SnapRAID metrics helpers.
# Prefer git pull on the G5 checkout; this script rsyncs apps/exporters as a fallback.
# Does not require passwordless sudo (uses docker group + systemd --user).

set -euo pipefail

G5_HOST=${1:-g5}
G5_USER=${2:-wmichelin}
REMOTE_PATH=${3:-/home/$G5_USER/code/homelab/apps/exporters}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SCRIPT_DIR}/apps/exporters"

if [[ ! -d "$SRC" ]]; then
  echo "Missing $SRC — exporters live under apps/exporters now." >&2
  exit 1
fi

echo "Syncing exporters to ${G5_USER}@${G5_HOST}:${REMOTE_PATH}..."
rsync -avz --progress \
  --exclude '.DS_Store' \
  --exclude 'textfile/*.prom' \
  "$SRC/" "${G5_USER}@${G5_HOST}:${REMOTE_PATH}/"

echo "Installing scripts, user systemd units, and starting exporters on g5..."
ssh "${G5_USER}@${G5_HOST}" bash -s -- "$REMOTE_PATH" <<'REMOTE'
set -euo pipefail
REMOTE_PATH=$1
REPO_ROOT="$(cd "$REMOTE_PATH/../.." && pwd)"

chmod +x "$REMOTE_PATH/scripts/"*.sh
mkdir -p "$REMOTE_PATH/textfile"

if [[ -x "$REPO_ROOT/scripts/install-user-units.sh" ]]; then
  "$REPO_ROOT/scripts/install-user-units.sh"
else
  mkdir -p "$HOME/.config/systemd/user"
  cp "$REMOTE_PATH/systemd-user/"*.service "$HOME/.config/systemd/user/"
  cp "$REMOTE_PATH/systemd-user/"*.timer "$HOME/.config/systemd/user/"
  systemctl --user daemon-reload
fi

systemctl --user enable --now snapraid-metrics.timer
# Prefer the compose-based docker-stats-exporter (has docker.sock access).
systemctl --user disable --now docker-stats-metrics.timer 2>/dev/null || true
systemctl --user stop docker-stats-metrics.service 2>/dev/null || true
loginctl enable-linger "$USER" 2>/dev/null || true

TEXTFILE_DIR="$REMOTE_PATH/textfile" "$REMOTE_PATH/scripts/snapraid-metrics.sh" || true

cd "$REMOTE_PATH"
docker rm -f cadvisor 2>/dev/null || true
docker compose pull
docker compose up -d --remove-orphans

echo "Waiting for exporters..."
sleep 8
curl -sf --max-time 5 http://127.0.0.1:9100/metrics >/dev/null && echo "node-exporter OK" || echo "node-exporter NOT READY"
curl -sf --max-time 5 http://127.0.0.1:9633/metrics >/dev/null && echo "smartctl-exporter OK" || echo "smartctl-exporter NOT READY"
sleep 5
grep -E '^snapraid_healthy|^snapraid_sync_success|^docker_container_running|^docker_stats_ok' "$REMOTE_PATH/textfile/"*.prom 2>/dev/null | head -30 || true
curl -sf --max-time 5 http://127.0.0.1:9633/metrics | grep -E '^smartctl_device_smart_status' | head -10 || true
REMOTE

echo ""
echo "G5 exporters deployed."
echo "  node-exporter:      http://${G5_HOST}:9100/metrics"
echo "  smartctl-exporter:  http://${G5_HOST}:9633/metrics"
echo "  docker-stats:       textfile via docker-stats-exporter container"
