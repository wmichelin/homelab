#!/bin/bash
# Self-healing watchdog for the homelab monitoring stack.
#
# The Pi is not publicly reachable, so an external HTTP uptime check (e.g. a
# DigitalOcean uptime check) cannot probe Grafana. Instead we check locally and
# repair in place: if Grafana's health endpoint isn't OK, reconcile the stack
# with `docker compose up -d`, which recreates any missing/stopped containers.
#
# Runs from homelab-watchdog.timer (every 5 minutes). Logs go to the journal:
#   journalctl -u homelab-watchdog.service

set -euo pipefail

COMPOSE_DIR="/home/wmichelin/homelab"
HEALTH_URL="http://localhost:3000/api/health"

code=$(curl -s -o /dev/null -m 10 -w "%{http_code}" "$HEALTH_URL" || echo "000")

if [ "$code" = "200" ]; then
  echo "grafana healthy (HTTP $code)"
  exit 0
fi

echo "grafana unhealthy (HTTP $code) - reconciling stack"
cd "$COMPOSE_DIR"
docker compose up -d --remove-orphans

# Give Grafana a moment, then re-check so the journal records the outcome.
sleep 15
recheck=$(curl -s -o /dev/null -m 10 -w "%{http_code}" "$HEALTH_URL" || echo "000")
echo "grafana after reconcile: HTTP $recheck"
[ "$recheck" = "200" ]
