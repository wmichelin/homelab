#!/bin/sh
# Start cursor-proxy once (OpenCode's plugin loader can init twice → EADDRINUSE).
set -eu
PORT="${CURSOR_PROXY_PORT:-32124}"
PROXY_SCRIPT="/home/wmichelin/code/homelab/apps/opencode/cursor-proxy.cjs"

if [ -f "$PROXY_SCRIPT" ]; then
  PORT="$PORT" node "$PROXY_SCRIPT" &
  PROXY_PID=$!
  trap 'kill "$PROXY_PID" 2>/dev/null || true' EXIT INT TERM
fi

exec "$@"
