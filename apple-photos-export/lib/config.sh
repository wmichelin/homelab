# Shared config for Apple Photos export scripts.
# Sourced by bash entrypoints. Loads optional package-local config.env.
#
# Required: PHOTOS_EXPORT_ROOT (or set PHOTOS_DEST + LIVE_DEST explicitly)
# Do not put `set -u` here — this file is meant to be sourced.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Back-compat alias used by migrate-live-photos.sh
REPO_ROOT="$PKG_ROOT"

if [[ -f "${PKG_ROOT}/config.env" ]]; then
  # shellcheck disable=SC1091
  set -a
  # shellcheck source=/dev/null
  source "${PKG_ROOT}/config.env"
  set +a
fi

: "${HOME:?}"

PHOTOS_LIBRARY="${PHOTOS_LIBRARY:-${HOME}/Pictures/Photos Library.photoslibrary}"
OSXPHOTOS_SUPPORT="${OSXPHOTOS_SUPPORT:-${HOME}/Library/Application Support/osxphotos}"

if [[ -n "${PHOTOS_EXPORT_ROOT:-}" ]]; then
  PHOTOS_DEST="${PHOTOS_DEST:-${PHOTOS_EXPORT_ROOT}/Photos}"
  LIVE_DEST="${LIVE_DEST:-${PHOTOS_EXPORT_ROOT}/Live Photos}"
fi

PHOTOS_DEST="${PHOTOS_DEST:-}"
LIVE_DEST="${LIVE_DEST:-}"
PHOTOS_EXPORT_DB="${PHOTOS_EXPORT_DB:-${OSXPHOTOS_SUPPORT}/photos-export.db}"
LIVE_MOVIES_STATE="${LIVE_MOVIES_STATE:-${OSXPHOTOS_SUPPORT}/live-movies.json}"
PHOTOS_REPORT="${PHOTOS_REPORT:-${OSXPHOTOS_SUPPORT}/export-photos-report.csv}"

require_destinations() {
  if [[ -z "$PHOTOS_DEST" || -z "$LIVE_DEST" ]]; then
    echo "error: set PHOTOS_EXPORT_ROOT (or PHOTOS_DEST and LIVE_DEST)." >&2
    echo "  cp config.example.env config.env   # then edit" >&2
    echo "  export PHOTOS_EXPORT_ROOT=/path/to/export/root" >&2
    exit 1
  fi
}

require_export_root_mounted() {
  require_destinations
  local root
  root="$(dirname "$PHOTOS_DEST")"
  if [[ ! -d "$root" ]]; then
    echo "error: export root is not available: $root" >&2
    exit 1
  fi
}

require_library() {
  if [[ ! -d "$PHOTOS_LIBRARY" ]]; then
    echo "error: Photos library not found at: $PHOTOS_LIBRARY" >&2
    exit 1
  fi
}

# Prefer new generic DB name; migrate legacy personal names if present.
resolve_photos_export_db() {
  local support="$OSXPHOTOS_SUPPORT"
  local preferred="$PHOTOS_EXPORT_DB"
  if [[ -f "$preferred" ]]; then
    printf '%s\n' "$preferred"
    return 0
  fi
  local legacy
  for legacy in "${support}/safe-photos.db" "${support}/safe-export.db"; do
    if [[ -f "$legacy" && ! -f "$preferred" ]]; then
      mkdir -p "$(dirname "$preferred")"
      mv "$legacy" "$preferred"
      for s in shm wal; do
        [[ -f "${legacy}-$s" ]] && mv "${legacy}-$s" "${preferred}-$s"
      done
      echo "Renamed $(basename "$legacy") → $(basename "$preferred")" >&2
      printf '%s\n' "$preferred"
      return 0
    fi
  done
  printf '%s\n' "$preferred"
}

resolve_live_movies_state() {
  local preferred="$LIVE_MOVIES_STATE"
  if [[ -f "$preferred" ]]; then
    printf '%s\n' "$preferred"
    return 0
  fi
  local legacy="${OSXPHOTOS_SUPPORT}/safe-live-movies.json"
  if [[ -f "$legacy" && ! -f "$preferred" ]]; then
    mkdir -p "$(dirname "$preferred")"
    mv "$legacy" "$preferred"
    echo "Renamed $(basename "$legacy") → $(basename "$preferred")" >&2
  fi
  printf '%s\n' "$preferred"
}

osxphotos_python() {
  local bin py
  bin="$(command -v osxphotos || true)"
  if [[ -n "$bin" ]]; then
    py="$(dirname "$bin")/python"
    if [[ -x "$py" ]]; then
      printf '%s\n' "$py"
      return 0
    fi
  fi
  if [[ -x "${HOME}/.local/share/uv/tools/osxphotos/bin/python" ]]; then
    printf '%s\n' "${HOME}/.local/share/uv/tools/osxphotos/bin/python"
    return 0
  fi
  command -v python3
}
