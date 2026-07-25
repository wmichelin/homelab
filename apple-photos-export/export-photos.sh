#!/usr/bin/env bash
# Export Apple Photos library to a destination root:
#   $PHOTOS_DEST  — stills (incl. Live Photo HEIC/JPG) + real videos
#   $LIVE_DEST    — Live Photo companion .mov only
#
# Run from Terminal.app (Full Disk Access required for Photos library).
#
# Configure via config.env or environment:
#   PHOTOS_EXPORT_ROOT=/path/to/export/root
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"

require_export_root_mounted
require_library

PHOTOS_EXPORT_DB="$(resolve_photos_export_db)"
LIVE_MOVIES_STATE="$(resolve_live_movies_state)"

mkdir -p "$PHOTOS_DEST" "$LIVE_DEST" "$OSXPHOTOS_SUPPORT"

echo "Library:  $PHOTOS_LIBRARY"
echo "Photos:   $PHOTOS_DEST"
echo "Live:     $LIVE_DEST"
echo
echo "=== Pass 1/2: stills + real videos → $PHOTOS_DEST ==="
echo "(--skip-live: Live Photo stills included, companion .mov excluded)"
echo "ExportDB: $PHOTOS_EXPORT_DB"
osxphotos export "$PHOTOS_DEST" \
  --library "$PHOTOS_LIBRARY" \
  --directory "{created.year}/{created.mm}" \
  --filename "{created.strftime,%Y%m%d-%H%M%S}_{original_name}" \
  --exportdb "$PHOTOS_EXPORT_DB" \
  --skip-live \
  --update \
  --retry 3 \
  --exiftool \
  --download-missing \
  --use-photokit \
  --report "$PHOTOS_REPORT" \
  --verbose \
  "$@"

echo
echo "=== Pass 2/2: Live Photo companion movies → $LIVE_DEST ==="
"$(osxphotos_python)" "$SCRIPT_DIR/export-live-movies.py" \
  --dest "$LIVE_DEST" \
  --library "$PHOTOS_LIBRARY" \
  --state "$LIVE_MOVIES_STATE" \
  "$@"

echo
echo "Done."
