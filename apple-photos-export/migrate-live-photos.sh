#!/usr/bin/env bash
# Move already-exported Live Photo *companion movies* from Photos/ into Live Photos/.
# Stills (HEIC/JPG/…) stay in Photos/.
#
# Detection: same-stem still (.HEIC/.JPG/.JPEG/.PNG) + .mov/.MOV under Photos.
# Also moves matching _edited.mov siblings. Unpaired movies are left in Photos.
#
# Usage:
#   migrate-live-photos.sh                 # dry-run summary (default)
#   migrate-live-photos.sh --execute       # move movies + scrub Photos export DB
#   migrate-live-photos.sh --verbose
#
# Configure via config.env or PHOTOS_EXPORT_ROOT.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"

EXECUTE=0
VERBOSE=0
for arg in "$@"; do
  case "$arg" in
    --execute) EXECUTE=1 ;;
    --verbose|-v) VERBOSE=1 ;;
    -h|--help)
      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "usage: $0 [--execute] [--verbose]" >&2
      exit 2
      ;;
  esac
done

require_destinations
PHOTOS_EXPORT_DB="$(resolve_photos_export_db)"

if [[ ! -d "$PHOTOS_DEST" ]]; then
  echo "error: missing $PHOTOS_DEST" >&2
  exit 1
fi

STILL_EXTS=(HEIC heic JPG jpg JPEG jpeg PNG png)
MOVED_LIST="$(mktemp)"
trap 'rm -f "$MOVED_LIST"' EXIT

logv() {
  if [[ "$VERBOSE" -eq 1 ]]; then
    echo "$@"
  fi
}

find_still_for_stem() {
  local stem="$1"
  local ext
  for ext in "${STILL_EXTS[@]}"; do
    if [[ -f "${stem}.${ext}" ]]; then
      printf '%s\n' "${stem}.${ext}"
      return 0
    fi
  done
  return 1
}

# Movies to move for this Live Photo pair (not stills).
collect_movies() {
  local stem="$1"
  local mov="$2"
  local f
  local -a seen=()

  emit() {
    local path="$1"
    local s
    [[ -f "$path" ]] || return 0
    for s in "${seen[@]+"${seen[@]}"}"; do
      [[ "$s" == "$path" ]] && return 0
    done
    seen+=("$path")
    printf '%s\n' "$path"
  }

  emit "$mov"
  for f in "${stem}_edited".mov "${stem}_edited".MOV; do
    emit "$f"
  done
}

pairs=0
unpaired_mov=0
file_count=0
PROGRESS_EVERY=100

echo "Source:      $PHOTOS_DEST"
echo "Destination: $LIVE_DEST"
echo "Moves:       companion .mov only (stills stay in Photos)"
if [[ "$EXECUTE" -eq 1 ]]; then
  echo "Mode:        EXECUTE"
else
  echo "Mode:        dry-run (pass --execute to apply)"
fi
[[ "$VERBOSE" -eq 1 ]] || echo "Listing:     summary only (pass --verbose for per-file)"
echo

while IFS= read -r -d '' mov; do
  stem="${mov%.*}"
  if ! find_still_for_stem "$stem" >/dev/null; then
    unpaired_mov=$((unpaired_mov + 1))
    continue
  fi

  pairs=$((pairs + 1))
  if [[ $((pairs % PROGRESS_EVERY)) -eq 0 ]]; then
    echo "... paired $pairs so far"
  fi

  while IFS= read -r src; do
    [[ -n "$src" ]] || continue
    rel="${src#"$PHOTOS_DEST"/}"
    dest="${LIVE_DEST}/${rel}"
    file_count=$((file_count + 1))

    if [[ "$EXECUTE" -eq 1 ]]; then
      mkdir -p "$(dirname "$dest")"
      if [[ -e "$dest" ]]; then
        if [[ -e "$src" ]]; then
          logv "EXISTS at dest, removing source: $rel"
          rm -f "$src"
        else
          logv "EXISTS (already migrated): $rel"
        fi
        printf '%s\n' "$rel" >> "$MOVED_LIST"
      else
        mv "$src" "$dest"
        logv "MOVED: $rel"
        printf '%s\n' "$rel" >> "$MOVED_LIST"
      fi
    else
      logv "WOULD MOVE: $rel"
      printf '%s\n' "$rel" >> "$MOVED_LIST"
    fi
  done < <(collect_movies "$stem" "$mov")

done < <(find "$PHOTOS_DEST" -type f \( -iname '*.mov' \) -print0 2>/dev/null)

echo
echo "Pairs:              $pairs"
echo "Movies to move:     $file_count"
echo "Unpaired .mov left: $unpaired_mov"

scrub_export_db() {
  local db="$1"
  local list="$2"
  if [[ ! -f "$db" ]]; then
    echo "No export DB at $db — skip scrub"
    return 0
  fi
  if [[ ! -s "$list" ]]; then
    echo "No moved paths to scrub from DB"
    return 0
  fi

  local n
  n="$(wc -l < "$list" | tr -d ' ')"
  echo "Scrubbing $n path(s) from $(basename "$db")..."

  local sql_list
  sql_list="$(mktemp)"
  sed "s/'/''/g" "$list" | sed "s/.*/INSERT OR IGNORE INTO temp.moved_paths(filepath) VALUES ('&');/" > "$sql_list"

  sqlite3 "$db" <<SQL
BEGIN;
CREATE TEMP TABLE moved_paths (filepath TEXT PRIMARY KEY);
.read ${sql_list}
DELETE FROM history
WHERE filepath_id IN (
  SELECT id FROM history_path
  WHERE filepath_normalized IN (SELECT filepath FROM temp.moved_paths)
     OR filepath_normalized IN (SELECT lower(filepath) FROM temp.moved_paths)
);
DELETE FROM history_path
WHERE filepath_normalized IN (SELECT filepath FROM temp.moved_paths)
   OR filepath_normalized IN (SELECT lower(filepath) FROM temp.moved_paths);
DELETE FROM export_data
WHERE filepath IN (SELECT filepath FROM temp.moved_paths)
   OR filepath_normalized IN (SELECT filepath FROM temp.moved_paths)
   OR filepath_normalized IN (SELECT lower(filepath) FROM temp.moved_paths);
COMMIT;
SQL
  rm -f "$sql_list"
  echo "Export DB scrub complete."
}

if [[ "$EXECUTE" -eq 1 ]]; then
  mkdir -p "$LIVE_DEST"
  scrub_export_db "$PHOTOS_EXPORT_DB" "$MOVED_LIST"
  echo
  echo "Migration complete. Resume with:"
  echo "  ${REPO_ROOT}/export-photos.sh"
else
  echo
  echo "Dry-run only. To apply:"
  echo "  $0 --execute"
fi
