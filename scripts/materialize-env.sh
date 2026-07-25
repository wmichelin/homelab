#!/usr/bin/env bash
# Materialize per-app .env files from secrets/homelab.env.
# Safe for Docker: each stack only gets the keys it needs (Immich env_file
# must not receive Samba/RDP credentials).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/envfile.sh
source "${SCRIPT_DIR}/lib/envfile.sh"

ROOT="$(homelab_root)"
SRC="${HOMELAB_SECRETS_FILE:-$(homelab_secrets_file)}"

if [[ ! -f "$SRC" ]]; then
  echo "Missing $SRC" >&2
  echo "Copy the example and fill values:" >&2
  echo "  cp secrets/homelab.env.example secrets/homelab.env && chmod 600 secrets/homelab.env" >&2
  exit 1
fi

chmod 600 "$SRC" 2>/dev/null || true

envfile_render "$SRC" "${ROOT}/.env" \
  DDNS_PASSWORD HOMELAB_SUBDOMAIN DOMAIN EMAIL \
  GRAFANA_ADMIN_USER GRAFANA_ADMIN_PASSWORD \
  HE_URI HE_TOKEN

envfile_render "$SRC" "${ROOT}/apps/media-stack/.env" \
  WEBUI_PASSWORD QBIT_BT_PORT

envfile_render "$SRC" "${ROOT}/apps/immich/.env" \
  UPLOAD_LOCATION DB_DATA_LOCATION TZ IMMICH_VERSION \
  DB_PASSWORD DB_USERNAME DB_DATABASE_NAME

echo "Materialized:"
echo "  ${ROOT}/.env"
echo "  ${ROOT}/apps/media-stack/.env"
echo "  ${ROOT}/apps/immich/.env"
