#!/usr/bin/env bash
# Point macOS at the G5 for *.g5.lan only (does not change global DNS).
# Pi is not involved — media names stay up if the Pi is offline.
#
# Usage: sudo ./scripts/install-mac-g5-lan-resolver.sh [g5-dns-ip]
set -euo pipefail

G5_DNS="${1:-192.168.0.54}"
RESOLVER_DIR="/etc/resolver"
RESOLVER_FILE="${RESOLVER_DIR}/g5.lan"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This helper is for macOS only." >&2
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Re-run with sudo so we can write ${RESOLVER_FILE}" >&2
  exit 1
fi

mkdir -p "$RESOLVER_DIR"
cat >"$RESOLVER_FILE" <<EOF
# Managed by homelab scripts/install-mac-g5-lan-resolver.sh
# Split DNS: only *.g5.lan → G5 (Caddy + lan-dns on the same host)
nameserver ${G5_DNS}
EOF

echo "Installed ${RESOLVER_FILE} → nameserver ${G5_DNS}"
echo "Verify:  dscacheutil -q host -a name sonarr.g5.lan"
echo "         open http://sonarr.g5.lan"
