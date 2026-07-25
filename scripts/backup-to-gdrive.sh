#!/bin/bash
# Upload latest homelab backup archive to Google Drive via rclone.
# One-time setup:  rclone config   → create remote named "gdrive" (Google Drive)
# Then:            ~/code/homelab/scripts/backup-to-gdrive.sh
set -euo pipefail

ROOT="${HOME}/code/homelab"
REMOTE="${RCLONE_REMOTE:-gdrive}"
DEST="${RCLONE_DEST:-G5-networked-storage}"

if ! command -v rclone >/dev/null; then
  echo "rclone not installed" >&2
  exit 1
fi

if ! rclone listremotes 2>/dev/null | grep -qx "${REMOTE}:"; then
  cat >&2 <<EOF
No rclone remote named '${REMOTE}' yet.

Run this once (opens a browser to sign into Google):

  rclone config

Choose: n (new) → name: gdrive → storage: Google Drive (drive)
Complete the browser login, then re-run this script.
EOF
  exit 2
fi

# Make a fresh archive (unencrypted; Drive is account-private — use --encrypt if preferred)
"$ROOT/scripts/backup-to-archive.sh"

LATEST=$(ls -1t "$ROOT/backups"/g5-homelab-*.tar.gz* | head -1)
echo "Uploading $LATEST → ${REMOTE}:${DEST}/"
rclone copy "$LATEST" "${REMOTE}:${DEST}/" --progress
rclone lsl "${REMOTE}:${DEST}/" | tail -5
echo "Done."
