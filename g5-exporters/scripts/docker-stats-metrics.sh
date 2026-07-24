#!/bin/bash
# Emit per-container CPU/memory metrics via `docker stats` into the
# node-exporter textfile collector.
#
# systemd --user units do not inherit supplementary groups (e.g. docker),
# so this script re-execs under `sg docker` when needed.

set -u

if [[ "${1:-}" != "--as-docker" ]]; then
  if ! docker info >/dev/null 2>&1; then
    if command -v sg >/dev/null 2>&1; then
      exec sg docker -c "\"$0\" --as-docker"
    fi
  fi
else
  shift
fi

TEXTFILE_DIR="${TEXTFILE_DIR:-/home/wmichelin/homelab-exporters/textfile}"
OUT="${TEXTFILE_DIR}/docker_stats.prom"
TMP="${OUT}.$$"
DOCKER_BIN="${DOCKER_BIN:-/usr/bin/docker}"

mkdir -p "$TEXTFILE_DIR"

ok=0
err_msg=""

{
  echo "# HELP docker_container_running Whether the container is running (1) or not (0)"
  echo "# TYPE docker_container_running gauge"
  echo "# HELP docker_container_cpu_percent CPU usage percent from docker stats"
  echo "# TYPE docker_container_cpu_percent gauge"
  echo "# HELP docker_container_memory_usage_bytes Memory usage in bytes from docker stats"
  echo "# TYPE docker_container_memory_usage_bytes gauge"
  echo "# HELP docker_container_memory_limit_bytes Memory limit in bytes from docker stats"
  echo "# TYPE docker_container_memory_limit_bytes gauge"
  echo "# HELP docker_stats_ok Whether the last docker stats scrape succeeded"
  echo "# TYPE docker_stats_ok gauge"
  echo "# HELP docker_stats_last_run_timestamp_seconds Unix time of last docker stats scrape"
  echo "# TYPE docker_stats_last_run_timestamp_seconds gauge"
} >"$TMP"

to_bytes() {
  local raw=$1
  raw=${raw// /}
  local num unit
  num=$(echo "$raw" | grep -oE '^[0-9.]+' || echo 0)
  unit=$(echo "$raw" | grep -oE '[A-Za-z]+$' || echo B)
  case "$unit" in
    B|b) awk -v n="$num" 'BEGIN{printf "%.0f", n}' ;;
    KiB|KB|kB) awk -v n="$num" 'BEGIN{printf "%.0f", n*1024}' ;;
    MiB|MB|mB) awk -v n="$num" 'BEGIN{printf "%.0f", n*1024*1024}' ;;
    GiB|GB|gB) awk -v n="$num" 'BEGIN{printf "%.0f", n*1024*1024*1024}' ;;
    TiB|TB) awk -v n="$num" 'BEGIN{printf "%.0f", n*1024*1024*1024*1024}' ;;
    *) echo 0 ;;
  esac
}

# Prefer docker stats; fall back to docker ps (running=1, cpu/mem unknown as 0)
stats_out=""
if stats_out=$("$DOCKER_BIN" stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}' 2>/tmp/docker-stats.err); then
  ok=1
else
  err_msg=$(tr '\n' ' ' </tmp/docker-stats.err 2>/dev/null || true)
  # Fallback: at least report which containers are up
  if ps_out=$("$DOCKER_BIN" ps --format '{{.Names}}' 2>/tmp/docker-ps.err); then
    ok=1
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      name_label=${name//\"/}
      echo "docker_container_running{name=\"${name_label}\"} 1" >>"$TMP"
      echo "docker_container_cpu_percent{name=\"${name_label}\"} 0" >>"$TMP"
      echo "docker_container_memory_usage_bytes{name=\"${name_label}\"} 0" >>"$TMP"
      echo "docker_container_memory_limit_bytes{name=\"${name_label}\"} 0" >>"$TMP"
    done <<<"$ps_out"
  else
    err_msg="${err_msg} $(tr '\n' ' ' </tmp/docker-ps.err 2>/dev/null || true)"
    ok=0
  fi
fi

if [[ -n "$stats_out" ]]; then
  while IFS='|' read -r name cpu mem_usage mem_limit; do
    [[ -z "$name" || "$name" == "NAME" ]] && continue
    name_label=${name//\"/}
    cpu_val=${cpu%%%}
    cpu_val=${cpu_val// /}
    mem_u=$(to_bytes "$mem_usage")
    mem_l=$(to_bytes "$mem_limit")
    echo "docker_container_running{name=\"${name_label}\"} 1" >>"$TMP"
    echo "docker_container_cpu_percent{name=\"${name_label}\"} ${cpu_val:-0}" >>"$TMP"
    echo "docker_container_memory_usage_bytes{name=\"${name_label}\"} ${mem_u}" >>"$TMP"
    echo "docker_container_memory_limit_bytes{name=\"${name_label}\"} ${mem_l}" >>"$TMP"
  done < <(echo "$stats_out" | awk -F'|' '{
    split($3, a, "/")
    gsub(/^ +| +$/, "", a[1])
    gsub(/^ +| +$/, "", a[2])
    print $1 "|" $2 "|" a[1] "|" a[2]
  }')
fi

echo "docker_stats_ok ${ok}" >>"$TMP"
echo "docker_stats_last_run_timestamp_seconds $(date +%s)" >>"$TMP"
mv "$TMP" "$OUT"

if [[ "$ok" -ne 1 ]]; then
  echo "docker-stats-metrics failed: ${err_msg:-unknown}" >&2
  exit 1
fi

exit 0
