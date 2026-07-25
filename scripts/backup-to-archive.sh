#!/bin/bash
# Backup homelab config/docs/secrets (NOT the media pool) for offsite copy.
set -euo pipefail

ROOT="${HOME}/code/homelab"
OUT_DIR="${ROOT}/backups"
STAMP=$(date +%Y%m%d-%H%M%S)
NAME="g5-homelab-${STAMP}"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$OUT_DIR"
mkdir -p "$STAGE/$NAME"

cp -a "$ROOT/README.md" "$ROOT/.gitignore" "$STAGE/$NAME/" 2>/dev/null || true
cp -a "$ROOT/docs" "$STAGE/$NAME/"
cp -a "$ROOT/scripts" "$STAGE/$NAME/"
cp -a "$ROOT/secrets" "$STAGE/$NAME/"
cp -a "$ROOT/infra" "$STAGE/$NAME/"

# Compose + env examples (not runtime media DBs)
mkdir -p "$STAGE/$NAME/apps/media-stack" "$STAGE/$NAME/apps/immich" "$STAGE/$NAME/apps/exporters"
cp -a "$ROOT/apps/media-stack/docker-compose.yml" "$STAGE/$NAME/apps/media-stack/"
cp -a "$ROOT/apps/media-stack/.env.example" "$STAGE/$NAME/apps/media-stack/" 2>/dev/null || true
cp -a "$ROOT/apps/immich/docker-compose.yml" "$ROOT/apps/immich/"hwaccel*.yml \
  "$ROOT/apps/immich/enable-nvidia.sh" "$STAGE/$NAME/apps/immich/" 2>/dev/null || true
cp -a "$ROOT/apps/immich/.env.example" "$STAGE/$NAME/apps/immich/" 2>/dev/null || true
cp -a "$ROOT/apps/exporters/docker-compose.yml" "$ROOT/apps/exporters/scripts" \
  "$ROOT/apps/exporters/systemd" "$ROOT/apps/exporters/systemd-user" \
  "$STAGE/$NAME/apps/exporters/" 2>/dev/null || true

# App configs (Radarr/Jellyfin/etc) — needed to restore stack settings
if [[ -d "$ROOT/apps/media-stack/config" ]]; then
  rsync -a \
    --exclude '*/logs/' \
    --exclude '*/log/' \
    --exclude '*.log' \
    --exclude 'GeoDB/' \
    --exclude '*.db-wal' \
    --exclude '*.db-shm' \
    "$ROOT/apps/media-stack/config/" "$STAGE/$NAME/apps/media-stack/config/"
fi

{
  echo "host=$(hostname)"
  echo "created=$STAMP"
  echo "user=$USER"
  echo "repo=$ROOT"
  df -h /mnt/storage /mnt/tm/walter /mnt/tm/marissa 2>/dev/null || true
} > "$STAGE/$NAME/BACKUP_MANIFEST.txt"

TAR="$OUT_DIR/${NAME}.tar.gz"
tar -C "$STAGE" -czf "$TAR" "$NAME"
chmod 600 "$TAR"

ENCRYPT=0
[[ "${1:-}" == "--encrypt" ]] && ENCRYPT=1
if [[ "$ENCRYPT" -eq 1 ]]; then
  if command -v gpg >/dev/null; then
    gpg --batch --yes -c --cipher-algo AES256 -o "${TAR}.gpg" "$TAR"
    shred -u "$TAR" 2>/dev/null || rm -f "$TAR"
    TAR="${TAR}.gpg"
    chmod 600 "$TAR"
  else
    echo "gpg not found; left unencrypted: $TAR" >&2
  fi
fi

ls -1t "$OUT_DIR"/g5-homelab-*.tar.gz* 2>/dev/null | tail -n +11 | xargs -r rm -f

echo "Created: $TAR"
ls -lh "$TAR"
