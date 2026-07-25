#!/usr/bin/env bash
# Wrapper for launchd / cron: set PATH, skip if export root is offline, then export.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"

# launchd PATH is minimal; osxphotos lives in ~/.local/bin, exiftool in Homebrew.
export PATH="${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

ts() { date '+%Y-%m-%d %H:%M:%S'; }

echo "[$(ts)] scheduled Apple Photos export starting"

if [[ -z "${PHOTOS_DEST:-}" || -z "${LIVE_DEST:-}" ]]; then
  echo "[$(ts)] error: PHOTOS_EXPORT_ROOT (or PHOTOS_DEST + LIVE_DEST) not configured" >&2
  exit 1
fi

root="$(dirname "$PHOTOS_DEST")"
if [[ ! -d "$root" ]]; then
  echo "[$(ts)] skip: export root not mounted: $root"
  exit 0
fi

if [[ ! -d "$PHOTOS_LIBRARY" ]]; then
  echo "[$(ts)] error: Photos library not found: $PHOTOS_LIBRARY" >&2
  exit 1
fi

if ! command -v osxphotos >/dev/null 2>&1; then
  echo "[$(ts)] error: osxphotos not on PATH" >&2
  exit 1
fi

# Daily jobs only need recent adds; set PHOTOS_ADDED_IN_LAST=all for a full scan.
export PHOTOS_ADDED_IN_LAST="${PHOTOS_ADDED_IN_LAST:-7d}"
echo "[$(ts)] PHOTOS_ADDED_IN_LAST=${PHOTOS_ADDED_IN_LAST}"

"${SCRIPT_DIR}/export-photos.sh"
echo "[$(ts)] scheduled Apple Photos export finished"
