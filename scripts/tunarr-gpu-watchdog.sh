#!/usr/bin/env bash
# Keep Tunarr's CUDA path healthy: if the GPU vanishes inside the container
# while the host GPU is fine, recreate tunarr to re-attach it.
#
# Intended as a systemd --user timer on G5 (every few minutes).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_DIR="${COMPOSE_DIR:-$ROOT/apps/media-stack}"
TUNARR_API="${TUNARR_API:-http://127.0.0.1:8000/api}"

log() { printf '%s %s\n' "$(date -Is)" "$*"; }

gpu_ok_in_container() {
  docker exec tunarr nvidia-smi -L 2>/dev/null | grep -q 'GPU '
}

host_gpu_ok() {
  command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L 2>/dev/null | grep -q 'GPU '
}

recreate_tunarr() {
  log "recreating tunarr container to re-attach GPU"
  (
    cd "$COMPOSE_DIR"
    docker compose up -d --force-recreate tunarr
  )
  for _ in $(seq 1 45); do
    if curl -sfS "$TUNARR_API/channels" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  log "ERROR: tunarr API did not come up after recreate"
  return 1
}

if ! docker inspect tunarr >/dev/null 2>&1; then
  log "tunarr container missing; skipping"
  exit 0
fi

running="$(docker inspect -f '{{.State.Running}}' tunarr 2>/dev/null || echo false)"
if [[ "$running" != "true" ]]; then
  log "tunarr not running; skipping"
  exit 0
fi

if gpu_ok_in_container; then
  exit 0
fi

log "GPU missing inside tunarr (NVML/CUDA)"
if ! host_gpu_ok; then
  log "host nvidia-smi also unhealthy; skipping recreate"
  exit 0
fi

recreate_tunarr

if gpu_ok_in_container; then
  log "GPU OK after recreate"
else
  log "GPU still missing after recreate"
  exit 1
fi
