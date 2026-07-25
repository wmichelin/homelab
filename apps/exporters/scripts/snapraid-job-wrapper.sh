#!/bin/bash
# Wrapper for snapraid sync/scrub systemd oneshots.
# Records success, duration, and timestamp for node-exporter textfile collector,
# then refreshes snapraid status metrics.

set -euo pipefail

TEXTFILE_DIR="${TEXTFILE_DIR:-/var/lib/node_exporter/textfile_collector}"
JOB="${1:?usage: snapraid-job-wrapper.sh <sync|scrub> [snapraid args...]}"
shift

case "$JOB" in
  sync|scrub) ;;
  *)
    echo "unknown job: $JOB" >&2
    exit 2
    ;;
esac

mkdir -p "$TEXTFILE_DIR"
OUT="${TEXTFILE_DIR}/snapraid_jobs.prom"
TMP="${OUT}.$$"

start=$(date +%s)
rc=0
/usr/bin/snapraid "$JOB" "$@" || rc=$?
end=$(date +%s)
duration=$((end - start))
success=$(( rc == 0 ? 1 : 0 ))

# Load existing opposite-job metrics so we don't wipe them
other_job="scrub"
[[ "$JOB" == "scrub" ]] && other_job="sync"

other_success=""
other_duration=""
other_ts=""
if [[ -f "$OUT" ]]; then
  other_success=$(grep -E "^snapraid_${other_job}_success " "$OUT" | awk '{print $2}' || true)
  other_duration=$(grep -E "^snapraid_${other_job}_duration_seconds " "$OUT" | awk '{print $2}' || true)
  other_ts=$(grep -E "^snapraid_${other_job}_last_timestamp_seconds " "$OUT" | awk '{print $2}' || true)
fi

{
  echo "# HELP snapraid_sync_success Whether the last snapraid sync exited 0"
  echo "# TYPE snapraid_sync_success gauge"
  if [[ "$JOB" == "sync" ]]; then
    echo "snapraid_sync_success ${success}"
  elif [[ -n "$other_success" && "$other_job" == "sync" ]]; then
    echo "snapraid_sync_success ${other_success}"
  else
    echo "snapraid_sync_success -1"
  fi

  echo "# HELP snapraid_sync_duration_seconds Duration of the last snapraid sync"
  echo "# TYPE snapraid_sync_duration_seconds gauge"
  if [[ "$JOB" == "sync" ]]; then
    echo "snapraid_sync_duration_seconds ${duration}"
  elif [[ -n "$other_duration" && "$other_job" == "sync" ]]; then
    echo "snapraid_sync_duration_seconds ${other_duration}"
  else
    echo "snapraid_sync_duration_seconds -1"
  fi

  echo "# HELP snapraid_sync_last_timestamp_seconds Unix time of last snapraid sync attempt"
  echo "# TYPE snapraid_sync_last_timestamp_seconds gauge"
  if [[ "$JOB" == "sync" ]]; then
    echo "snapraid_sync_last_timestamp_seconds ${end}"
  elif [[ -n "$other_ts" && "$other_job" == "sync" ]]; then
    echo "snapraid_sync_last_timestamp_seconds ${other_ts}"
  else
    echo "snapraid_sync_last_timestamp_seconds 0"
  fi

  echo "# HELP snapraid_scrub_success Whether the last snapraid scrub exited 0"
  echo "# TYPE snapraid_scrub_success gauge"
  if [[ "$JOB" == "scrub" ]]; then
    echo "snapraid_scrub_success ${success}"
  elif [[ -n "$other_success" && "$other_job" == "scrub" ]]; then
    echo "snapraid_scrub_success ${other_success}"
  else
    echo "snapraid_scrub_success -1"
  fi

  echo "# HELP snapraid_scrub_duration_seconds Duration of the last snapraid scrub"
  echo "# TYPE snapraid_scrub_duration_seconds gauge"
  if [[ "$JOB" == "scrub" ]]; then
    echo "snapraid_scrub_duration_seconds ${duration}"
  elif [[ -n "$other_duration" && "$other_job" == "scrub" ]]; then
    echo "snapraid_scrub_duration_seconds ${other_duration}"
  else
    echo "snapraid_scrub_duration_seconds -1"
  fi

  echo "# HELP snapraid_scrub_last_timestamp_seconds Unix time of last snapraid scrub attempt"
  echo "# TYPE snapraid_scrub_last_timestamp_seconds gauge"
  if [[ "$JOB" == "scrub" ]]; then
    echo "snapraid_scrub_last_timestamp_seconds ${end}"
  elif [[ -n "$other_ts" && "$other_job" == "scrub" ]]; then
    echo "snapraid_scrub_last_timestamp_seconds ${other_ts}"
  else
    echo "snapraid_scrub_last_timestamp_seconds 0"
  fi
} >"$TMP"

mv "$TMP" "$OUT"

# Refresh status metrics (best-effort; don't fail the job on parse issues)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x "${SCRIPT_DIR}/snapraid-metrics.sh" ]]; then
  TEXTFILE_DIR="$TEXTFILE_DIR" "${SCRIPT_DIR}/snapraid-metrics.sh" || true
elif [[ -x /usr/local/bin/snapraid-metrics.sh ]]; then
  TEXTFILE_DIR="$TEXTFILE_DIR" /usr/local/bin/snapraid-metrics.sh || true
fi

exit "$rc"
