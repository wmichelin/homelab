#!/bin/bash
# Deploy g5 exporter stack + SnapRAID metrics helpers to the G5 host.
# Does not require passwordless sudo (uses docker group + systemd --user).

set -euo pipefail

G5_HOST=${1:-g5}
G5_USER=${2:-wmichelin}
REMOTE_PATH=${3:-/home/$G5_USER/homelab-exporters}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SCRIPT_DIR}/g5-exporters"

echo "Syncing exporters to ${G5_USER}@${G5_HOST}:${REMOTE_PATH}..."
rsync -avz --progress \
  --exclude '.DS_Store' \
  --exclude 'textfile/*.prom' \
  "$SRC/" "${G5_USER}@${G5_HOST}:${REMOTE_PATH}/"

echo "Installing scripts, user systemd units, and starting exporters on g5..."
ssh "${G5_USER}@${G5_HOST}" bash -s -- "$REMOTE_PATH" <<'REMOTE'
set -euo pipefail
REMOTE_PATH=$1

chmod +x "$REMOTE_PATH/scripts/"*.sh
mkdir -p "$REMOTE_PATH/textfile"

mkdir -p "$HOME/.config/systemd/user"
cp "$REMOTE_PATH/systemd-user/"*.service "$HOME/.config/systemd/user/"
cp "$REMOTE_PATH/systemd-user/"*.timer "$HOME/.config/systemd/user/"

systemctl --user daemon-reload
systemctl --user enable --now snapraid-metrics.timer
# Prefer the compose-based docker-stats-exporter (has docker.sock access).
# Disable the host timer so it cannot overwrite metrics with empty files.
systemctl --user disable --now docker-stats-metrics.timer 2>/dev/null || true
systemctl --user stop docker-stats-metrics.service 2>/dev/null || true
# Linger so user timers keep running without an interactive login
loginctl enable-linger "$USER" 2>/dev/null || true

TEXTFILE_DIR="$REMOTE_PATH/textfile" "$REMOTE_PATH/scripts/snapraid-metrics.sh" || true

cd "$REMOTE_PATH"
# Stop legacy cadvisor if present from earlier deploys
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
