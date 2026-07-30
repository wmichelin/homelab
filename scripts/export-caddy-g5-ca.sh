#!/usr/bin/env bash
# Copy Caddy's internal CA root from G5 (g5-caddy) so clients can trust https://*.g5.lan.
#
# Usage:
#   ./scripts/export-caddy-g5-ca.sh [host] [user]
# Writes: secrets/g5-caddy-root.crt (gitignored)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

G5_HOST="${1:-g5}"
G5_USER="${2:-wmichelin}"
OUT="${ROOT}/secrets/g5-caddy-root.crt"

mkdir -p "${ROOT}/secrets"
chmod 700 "${ROOT}/secrets"

ssh "${G5_USER}@${G5_HOST}" \
  'docker exec g5-caddy cat /data/caddy/pki/authorities/local/root.crt' \
  >"${OUT}"

chmod 600 "${OUT}"
echo "Wrote ${OUT}"
echo "macOS (system trust): sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ${OUT}"
echo "iOS: AirDrop/email the cert → Settings → Profile Downloaded → install → Certificate Trust Settings"
