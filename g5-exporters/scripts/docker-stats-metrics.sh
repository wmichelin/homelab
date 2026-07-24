#!/bin/bash
# Emit per-container CPU/memory metrics via `docker stats` into the
# node-exporter textfile collector. Works with Docker's containerd snapshotter
# where cAdvisor cannot resolve overlayfs layerdb mounts.

set -euo pipefail

TEXTFILE_DIR="${TEXTFILE_DIR:-/home/wmichelin/homelab-exporters/textfile}"
OUT="${TEXTFILE_DIR}/docker_stats.prom"
TMP="${OUT}.$$"

mkdir -p "$TEXTFILE_DIR"

{
  echo "# HELP docker_container_running Whether the container is running (1) or not (0)"
  echo "# TYPE docker_container_running gauge"
  echo "# HELP docker_container_cpu_percent CPU usage percent from docker stats"
  echo "# TYPE docker_container_cpu_percent gauge"
  echo "# HELP docker_container_memory_usage_bytes Memory usage in bytes from docker stats"
  echo "# TYPE docker_container_memory_usage_bytes gauge"
  echo "# HELP docker_container_memory_limit_bytes Memory limit in bytes from docker stats"
  echo "# TYPE docker_container_memory_limit_bytes gauge"
  echo "# HELP docker_stats_last_run_timestamp_seconds Unix time of last docker stats scrape"
  echo "# TYPE docker_stats_last_run_timestamp_seconds gauge"
} >"$TMP"

# Format: name|cpu%|memUsage|memLimit|pids
# mem fields are human (e.g. 123.4MiB); convert to bytes below.
while IFS='|' read -r name cpu mem_usage mem_limit; do
  [[ -z "$name" || "$name" == "NAME" ]] && continue
  # sanitize name for prometheus label
  name_label=${name//\"/}

  cpu_val=${cpu%%%}
  cpu_val=${cpu_val// /}

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

  mem_u=$(to_bytes "$mem_usage")
  mem_l=$(to_bytes "$mem_limit")

  echo "docker_container_running{name=\"${name_label}\"} 1" >>"$TMP"
  echo "docker_container_cpu_percent{name=\"${name_label}\"} ${cpu_val:-0}" >>"$TMP"
  echo "docker_container_memory_usage_bytes{name=\"${name_label}\"} ${mem_u}" >>"$TMP"
  echo "docker_container_memory_limit_bytes{name=\"${name_label}\"} ${mem_l}" >>"$TMP"
done < <(docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}' 2>/dev/null | awk -F'|' '{
  # MemUsage looks like "123.4MiB / 15.6GiB"
  split($3, a, "/")
  gsub(/^ +| +$/, "", a[1])
  gsub(/^ +| +$/, "", a[2])
  print $1 "|" $2 "|" a[1] "|" a[2]
}')

echo "docker_stats_last_run_timestamp_seconds $(date +%s)" >>"$TMP"
mv "$TMP" "$OUT"
