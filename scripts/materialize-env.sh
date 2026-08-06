#!/usr/bin/env bash
# Materialize per-app .env files from secrets/homelab.env.
# Safe for Docker: each stack only gets the keys it needs.
#
# Usage:
#   ./scripts/materialize-env.sh           # all targets
#   ./scripts/materialize-env.sh --target pi
#   ./scripts/materialize-env.sh --target g5
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/envfile.sh
source "${SCRIPT_DIR}/lib/envfile.sh"

ROOT="$(homelab_root)"
SRC="${HOMELAB_SECRETS_FILE:-$(homelab_secrets_file)}"
TARGET=all

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="${2:?}"
      shift 2
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$SRC" ]]; then
  echo "Missing $SRC" >&2
  echo "Copy the example and fill values:" >&2
  echo "  cp secrets/homelab.env.example secrets/homelab.env && chmod 600 secrets/homelab.env" >&2
  exit 1
fi

chmod 600 "$SRC" 2>/dev/null || true

# Keep WEBUI_PASSWORD and legacy QBITTORRENT_WEBUI_PASSWORD aligned when only one is set.
if webui="$(envfile_get "$SRC" WEBUI_PASSWORD 2>/dev/null || true)"; then
  :
fi
if qbit="$(envfile_get "$SRC" QBITTORRENT_WEBUI_PASSWORD 2>/dev/null || true)"; then
  :
fi
if [[ -n "${webui:-}" && -z "${qbit:-}" ]]; then
  envfile_set "$SRC" QBITTORRENT_WEBUI_PASSWORD "$webui"
elif [[ -z "${webui:-}" && -n "${qbit:-}" ]]; then
  envfile_set "$SRC" WEBUI_PASSWORD "$qbit"
fi

materialize_pi() {
  envfile_render "$SRC" "${ROOT}/.env" \
    DDNS_PASSWORD HOMELAB_SUBDOMAIN DOMAIN EMAIL \
    GRAFANA_ADMIN_USER GRAFANA_ADMIN_PASSWORD \
    HE_URI HE_TOKEN
  echo "  ${ROOT}/.env"
}

materialize_g5() {
  envfile_render "$SRC" "${ROOT}/apps/media-stack/.env" \
    WEBUI_PASSWORD QBIT_BT_PORT NZBGET_USER NZBGET_PASS
  envfile_render "$SRC" "${ROOT}/apps/immich/.env" \
    UPLOAD_LOCATION DB_DATA_LOCATION TZ IMMICH_VERSION \
    DB_PASSWORD DB_USERNAME DB_DATABASE_NAME
  envfile_render "$SRC" "${ROOT}/apps/opencode/.env" \
    OPENCODE_SERVER_USERNAME OPENCODE_SERVER_PASSWORD
  # Caddy loads OPENCODE_PASSWORD_HASH from media-stack/.env (OpenCode itself is open on localhost).
  local oc_user oc_pass oc_hash
  oc_user="$(envfile_get "$SRC" OPENCODE_SERVER_USERNAME 2>/dev/null || echo opencode)"
  oc_pass="$(envfile_get "$SRC" OPENCODE_SERVER_PASSWORD 2>/dev/null || true)"
  if [[ -n "${oc_pass:-}" ]] && command -v docker >/dev/null; then
    oc_hash="$(docker run --rm caddy:2.10-alpine caddy hash-password --plaintext "$oc_pass")"
    envfile_set "${ROOT}/apps/media-stack/.env" OPENCODE_SERVER_USERNAME "$oc_user"
    envfile_set "${ROOT}/apps/media-stack/.env" OPENCODE_PASSWORD_HASH "$oc_hash"
  fi
  echo "  ${ROOT}/apps/media-stack/.env"
  echo "  ${ROOT}/apps/immich/.env"
  echo "  ${ROOT}/apps/opencode/.env"
}

echo "Materialized (${TARGET}):"
case "$TARGET" in
  all)
    materialize_pi
    materialize_g5
    ;;
  pi) materialize_pi ;;
  g5) materialize_g5 ;;
  *)
    echo "Unknown --target $TARGET (use all|pi|g5)" >&2
    exit 1
    ;;
esac
