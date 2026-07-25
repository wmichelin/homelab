#!/usr/bin/env bash
# Renew Proton VPN NAT-PMP mappings and sync qBittorrent listen port.
# Bridge-mode Docker: also updates QBIT_BT_PORT and recreates qbittorrent when the
# forwarded port changes so host publishes match the VPN mapping.
set -euo pipefail

GATEWAY="${PROTON_NATPMP_GATEWAY:-10.2.0.1}"
LIFETIME="${PROTON_NATPMP_LIFETIME:-60}"
INTERVAL="${PROTON_PORT_RENEW_INTERVAL:-45}"
QBIT_URL="${QBIT_WEBUI_URL:-http://127.0.0.1:8080}"
QBIT_USER="${QBIT_WEBUI_USER:-admin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_DIR="${ROOT_DIR}/media-stack"
NATPMPC="${NATPMPC_BIN:-${SCRIPT_DIR}/bin/natpmpc}"
export LD_LIBRARY_PATH="${SCRIPT_DIR}/bin/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/proton-qbit"
STATE_FILE="${STATE_DIR}/forwarded_port"
COOKIE_JAR="${STATE_DIR}/qbit.cookies"
ENV_FILE="${COMPOSE_DIR}/.env"
SECRETS_FILE="${ROOT_DIR}/secrets/lan-samba-passwords.txt"

log() { printf '%s %s\n' "$(date -Is)" "$*"; }

docker_cmd() {
  if docker info >/dev/null 2>&1; then
    docker "$@"
  else
    sudo -g docker docker "$@"
  fi
}

read_password() {
  local pw=""
  if [[ -f "${ENV_FILE}" ]]; then
    pw="$(grep -E '^WEBUI_PASSWORD=' "${ENV_FILE}" | head -n1 | cut -d= -f2- || true)"
  fi
  if [[ -z "${pw}" && -f "${SECRETS_FILE}" ]]; then
    pw="$(grep -E '^QBITTORRENT_WEBUI_PASSWORD=' "${SECRETS_FILE}" | head -n1 | cut -d= -f2- || true)"
  fi
  if [[ -z "${pw}" ]]; then
    log "ERROR: qBittorrent WebUI password not found in ${ENV_FILE} or ${SECRETS_FILE}"
    return 1
  fi
  printf '%s' "${pw}"
}

ensure_natpmpc() {
  if [[ ! -x "${NATPMPC}" ]]; then
    if command -v natpmpc >/dev/null 2>&1; then
      NATPMPC="$(command -v natpmpc)"
    else
      log "ERROR: natpmpc not found at ${NATPMPC}"
      return 1
    fi
  fi
}

map_port() {
  local proto="$1"
  local public="${2:-1}"
  local private="${3:-0}"
  local out
  out="$("${NATPMPC}" -a "${public}" "${private}" "${proto}" "${LIFETIME}" -g "${GATEWAY}" 2>&1)" || {
    log "ERROR: natpmpc ${proto} failed:"$'\n'"${out}"
    return 1
  }
  printf '%s\n' "${out}" | awk '
    /Mapped public port/ {
      for (i = 1; i <= NF; i++) {
        if ($i == "port") { print $(i+1); exit }
      }
    }'
}

qbit_login() {
  local pw="$1"
  mkdir -p "${STATE_DIR}"
  rm -f "${COOKIE_JAR}"
  local code bodyfile
  bodyfile="${STATE_DIR}/login.body"
  code="$(curl -sS -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" \
    -o "${bodyfile}" -w '%{http_code}' \
    --data-urlencode "username=${QBIT_USER}" \
    --data-urlencode "password=${pw}" \
    "${QBIT_URL}/api/v2/auth/login")" || return 1
  local body
  body="$(cat "${bodyfile}" 2>/dev/null || true)"
  # Older WebUI returns "Ok."; newer builds return 204 with empty body + SID cookie.
  [[ "${code}" == "200" || "${code}" == "204" ]] || return 1
  [[ -z "${body}" || "${body}" == "Ok." ]] || return 1
  grep -q 'QBT_SID' "${COOKIE_JAR}" 2>/dev/null || return 1
}

qbit_set_listen_port() {
  local port="$1"
  # Clear host-iface binds (needed after any host-network experiments) and set port.
  curl -fsS -b "${COOKIE_JAR}" -c "${COOKIE_JAR}" \
    --data-urlencode "json={\"listen_port\":${port},\"current_network_interface\":\"\",\"current_interface_address\":\"\",\"upnp\":false}" \
    "${QBIT_URL}/api/v2/app/setPreferences" >/dev/null
}

qbit_cap_upload_lightly() {
  local limit_kib="${QBIT_UP_LIMIT_KIB:-1024}"
  curl -fsS -b "${COOKIE_JAR}" -c "${COOKIE_JAR}" \
    --data-urlencode "json={\"up_limit\":$((limit_kib * 1024))}" \
    "${QBIT_URL}/api/v2/app/setPreferences" >/dev/null || true
}

read_env_bt_port() {
  if [[ -f "${ENV_FILE}" ]] && grep -qE '^QBIT_BT_PORT=' "${ENV_FILE}"; then
    grep -E '^QBIT_BT_PORT=' "${ENV_FILE}" | head -n1 | cut -d= -f2-
  else
    printf ''
  fi
}

write_env_bt_port() {
  local port="$1"
  touch "${ENV_FILE}"
  if grep -qE '^QBIT_BT_PORT=' "${ENV_FILE}"; then
    sed -i "s/^QBIT_BT_PORT=.*/QBIT_BT_PORT=${port}/" "${ENV_FILE}"
  else
    printf 'QBIT_BT_PORT=%s\n' "${port}" >> "${ENV_FILE}"
  fi
}

recreate_qbittorrent_if_needed() {
  local port="$1"
  local published
  published="$(read_env_bt_port)"
  if [[ "${published}" == "${port}" ]]; then
    # Confirm container actually publishes this port.
    if docker_cmd inspect qbittorrent --format '{{json .HostConfig.PortBindings}}' 2>/dev/null \
      | grep -q "\"${port}/"; then
      return 0
    fi
  fi
  log "Publishing Docker BT port ${published:-?} -> ${port} (compose recreate)"
  write_env_bt_port "${port}"
  (
    cd "${COMPOSE_DIR}"
    docker_cmd compose up -d qbittorrent
  )
  # Wait for WebUI after recreate.
  local i
  for i in $(seq 1 30); do
    if curl -fsS -m 2 -o /dev/null "${QBIT_URL}/"; then
      return 0
    fi
    sleep 1
  done
  log "WARN: qBittorrent WebUI not ready after recreate"
  return 1
}

renew_once() {
  ensure_natpmpc
  local udp_port tcp_port port
  udp_port="$(map_port udp)"
  tcp_port="$(map_port tcp)"
  if [[ -z "${udp_port}" || -z "${tcp_port}" ]]; then
    log "ERROR: failed to parse mapped ports (udp='${udp_port}' tcp='${tcp_port}')"
    return 1
  fi
  if [[ "${udp_port}" != "${tcp_port}" ]]; then
    log "WARN: UDP port ${udp_port} != TCP port ${tcp_port}; using TCP"
  fi
  port="${tcp_port}"

  # Re-map explicitly public==private (Proton sometimes reports private 0).
  map_port udp "${port}" "${port}" >/dev/null
  map_port tcp "${port}" "${port}" >/dev/null

  mkdir -p "${STATE_DIR}"
  printf '%s\n' "${port}" > "${STATE_FILE}.tmp"
  mv -f "${STATE_FILE}.tmp" "${STATE_FILE}"
  if [[ -d /run/user/$(id -u)/Proton/VPN ]]; then
    printf '%s\n' "${port}" > "/run/user/$(id -u)/Proton/VPN/forwarded_port" 2>/dev/null || true
  fi

  recreate_qbittorrent_if_needed "${port}"

  local pw
  pw="$(read_password)"
  if ! qbit_login "${pw}"; then
    log "ERROR: qBittorrent login failed at ${QBIT_URL}"
    return 1
  fi

  local current
  current="$(curl -fsS -b "${COOKIE_JAR}" "${QBIT_URL}/api/v2/app/preferences" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("listen_port",""))')"
  if [[ "${current}" != "${port}" ]]; then
    log "Updating qBittorrent listen_port ${current:-?} -> ${port}"
    qbit_set_listen_port "${port}"
    qbit_cap_upload_lightly
  else
    log "Renewed NAT-PMP mapping for port ${port} (qBittorrent already matches)"
  fi
}

main() {
  log "Starting Proton→qBittorrent port-forward loop (gateway=${GATEWAY}, interval=${INTERVAL}s)"
  while true; do
    if renew_once; then
      :
    else
      log "Renewal failed; will retry"
    fi
    sleep "${INTERVAL}"
  done
}

main "$@"
