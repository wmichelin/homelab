#!/bin/bash
# Emit SnapRAID status + last sync/scrub job metrics for node-exporter textfile.
# Job outcomes are read from systemd unit properties (no need to wrap the oneshots).

set -euo pipefail

TEXTFILE_DIR="${TEXTFILE_DIR:-/home/wmichelin/homelab-exporters/textfile}"
OUT="${TEXTFILE_DIR}/snapraid.prom"
TMP="${OUT}.$$"

mkdir -p "$TEXTFILE_DIR"

status_rc=0
status_out=$(snapraid status 2>&1) || status_rc=$?

error_count=0
danger_count=0
bad_block_count=0
sync_percent=100
has_unsynced=0

if echo "$status_out" | grep -qiE '[0-9]+ error'; then
  error_count=$(echo "$status_out" | grep -oiE '[0-9]+ error' | head -1 | grep -oE '[0-9]+' || echo 0)
fi

if echo "$status_out" | grep -qiE '[0-9]+ danger'; then
  danger_count=$(echo "$status_out" | grep -oiE '[0-9]+ danger' | head -1 | grep -oE '[0-9]+' || echo 0)
fi

if echo "$status_out" | grep -qiE '[0-9]+ bad block'; then
  bad_block_count=$(echo "$status_out" | grep -oiE '[0-9]+ bad block' | head -1 | grep -oE '[0-9]+' || echo 0)
fi

if echo "$status_out" | grep -qiE 'not synced|to be synced'; then
  has_unsynced=1
  pct=$(echo "$status_out" | grep -oiE '[0-9]+%' | head -1 | tr -d '%' || true)
  if [[ -n "${pct:-}" ]]; then
    if echo "$status_out" | grep -qi 'not synced'; then
      sync_percent=$((100 - pct))
    else
      sync_percent=$pct
    fi
  else
    sync_percent=0
  fi
fi

status_ok=0
[[ "$status_rc" -eq 0 ]] && status_ok=1

healthy=0
if [[ "$status_rc" -eq 0 && "$error_count" -eq 0 && "$danger_count" -eq 0 && "$bad_block_count" -eq 0 ]]; then
  healthy=1
fi

# Last oneshot outcomes from systemd / journal (readable without root)
read_unit_metrics() {
  local unit=$1
  local prefix=$2
  local result status ts_unix success duration

  result=$(systemctl show "$unit" -p Result --value 2>/dev/null || echo "unknown")
  status=$(systemctl show "$unit" -p ExecMainStatus --value 2>/dev/null || echo "-1")
  local exit_ts
  exit_ts=$(systemctl show "$unit" -p ExecMainExitTimestamp --value 2>/dev/null || echo "")
  local start_ts
  start_ts=$(systemctl show "$unit" -p ExecMainStartTimestamp --value 2>/dev/null || echo "")

  # Fall back to journal when oneshot timestamps were cleared after reboot
  if [[ -z "$exit_ts" || "$exit_ts" == "n/a" ]]; then
    exit_ts=$(journalctl -u "$unit" -n 50 --output=short-unix --no-pager 2>/dev/null \
      | awk '/Finished|Failed|Succeeded/ {print $1; exit}' || true)
  fi

  success=-1
  if [[ "$result" == "success" && "$status" == "0" ]]; then
    # Distinguish "never ran this boot" (empty timestamps) from a real success
    if [[ -n "$exit_ts" && "$exit_ts" != "n/a" ]]; then
      success=1
    else
      # Check journal for a prior successful finish
      if journalctl -u "$unit" -n 20 --no-pager 2>/dev/null | grep -qE 'Finished|Succeeded'; then
        success=1
      else
        success=-1
      fi
    fi
  elif [[ "$result" == "exit-code" || "$result" == "failed" || "$result" == "timeout" || "$result" == "signal" ]]; then
    success=0
  elif [[ "$status" == "0" ]]; then
    success=1
  elif [[ "$status" =~ ^[0-9]+$ && "$status" != "0" ]]; then
    success=0
  fi

  ts_unix=0
  if [[ -n "$exit_ts" && "$exit_ts" != "n/a" && "$exit_ts" != "0" ]]; then
    if [[ "$exit_ts" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      ts_unix=${exit_ts%%.*}
    else
      ts_unix=$(date -d "$exit_ts" +%s 2>/dev/null || echo 0)
    fi
  fi

  duration=-1
  if [[ -n "$start_ts" && "$start_ts" != "n/a" && "$ts_unix" -gt 0 ]]; then
    local start_unix
    start_unix=$(date -d "$start_ts" +%s 2>/dev/null || echo 0)
    if [[ "$start_unix" -gt 0 ]]; then
      duration=$((ts_unix - start_unix))
    fi
  fi

  echo "${prefix}_success ${success}"
  echo "${prefix}_duration_seconds ${duration}"
  echo "${prefix}_last_timestamp_seconds ${ts_unix}"
}

{
  cat <<EOF
# HELP snapraid_status_ok Whether snapraid status completed successfully (1) or failed (0)
# TYPE snapraid_status_ok gauge
snapraid_status_ok ${status_ok}
# HELP snapraid_healthy Whether SnapRAID reports a healthy array
# TYPE snapraid_healthy gauge
snapraid_healthy ${healthy}
# HELP snapraid_errors Number of errors reported by snapraid status
# TYPE snapraid_errors gauge
snapraid_errors ${error_count}
# HELP snapraid_dangers Number of dangers reported by snapraid status
# TYPE snapraid_dangers gauge
snapraid_dangers ${danger_count}
# HELP snapraid_bad_blocks Number of bad blocks reported by snapraid status
# TYPE snapraid_bad_blocks gauge
snapraid_bad_blocks ${bad_block_count}
# HELP snapraid_sync_percent Estimated percent of array that is synced
# TYPE snapraid_sync_percent gauge
snapraid_sync_percent ${sync_percent}
# HELP snapraid_has_unsynced Whether snapraid status reports unsynced data
# TYPE snapraid_has_unsynced gauge
snapraid_has_unsynced ${has_unsynced}
# HELP snapraid_status_last_run_timestamp_seconds Unix time of last snapraid status metrics collection
# TYPE snapraid_status_last_run_timestamp_seconds gauge
snapraid_status_last_run_timestamp_seconds $(date +%s)
# HELP snapraid_sync_success Whether the last snapraid-sync.service run succeeded
# TYPE snapraid_sync_success gauge
# HELP snapraid_sync_duration_seconds Duration of the last snapraid sync
# TYPE snapraid_sync_duration_seconds gauge
# HELP snapraid_sync_last_timestamp_seconds Unix time of last snapraid sync exit
# TYPE snapraid_sync_last_timestamp_seconds gauge
# HELP snapraid_scrub_success Whether the last snapraid-scrub.service run succeeded
# TYPE snapraid_scrub_success gauge
# HELP snapraid_scrub_duration_seconds Duration of the last snapraid scrub
# TYPE snapraid_scrub_duration_seconds gauge
# HELP snapraid_scrub_last_timestamp_seconds Unix time of last snapraid scrub exit
# TYPE snapraid_scrub_last_timestamp_seconds gauge
EOF
  read_unit_metrics snapraid-sync.service snapraid_sync
  read_unit_metrics snapraid-scrub.service snapraid_scrub
} >"$TMP"

mv "$TMP" "$OUT"
