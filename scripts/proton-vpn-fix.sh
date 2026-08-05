#!/usr/bin/env bash
# Proton VPN helpers for G5 (CLI connect / recover / polkit).
# Run on G5 as wmichelin. See docs/proton-vpn-g5.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
POLKIT_SRC="${ROOT_DIR}/infra/polkit/49-nm-proton-wmichelin.rules"
POLKIT_DST="/etc/polkit-1/rules.d/49-nm-proton-wmichelin.rules"
COUNTRY="${PROTON_CONNECT_COUNTRY:-US}"

usage() {
  cat <<'EOF'
Usage: proton-vpn-fix.sh <command>

Commands:
  status          Show Proton status + egress IP
  connect         Connect (default country: US; override PROTON_CONNECT_COUNTRY)
  disconnect      Disconnect cleanly
  recover         Tear down stale NM Proton/kill-switch conns, then connect
  install-polkit  Install NetworkManager polkit rule (sudo; once per machine)
  check-polkit    Verify NM permissions for this user
  doctor          Status + connectivity checks useful when indexers/Prowlarr fail

Examples:
  ./scripts/proton-vpn-fix.sh install-polkit
  ./scripts/proton-vpn-fix.sh recover
  ./scripts/proton-vpn-fix.sh status
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing command: $1" >&2
    exit 1
  }
}

nm_proton_names() {
  nmcli -t -f NAME connection show 2>/dev/null | grep -iE '^(ProtonVPN|pvpn-)' || true
}

install_polkit() {
  need_cmd sudo
  [[ -f "$POLKIT_SRC" ]] || {
    echo "ERROR: missing $POLKIT_SRC" >&2
    exit 1
  }
  echo "Installing $POLKIT_DST"
  sudo install -m 0644 "$POLKIT_SRC" "$POLKIT_DST"
  sudo systemctl restart polkit
  echo "Restarted polkit. Checking permissions..."
  check_polkit
}

check_polkit() {
  need_cmd nmcli
  local control modify
  control="$(nmcli -t general permissions | awk -F: '$1=="org.freedesktop.NetworkManager.network-control"{print $2}')"
  modify="$(nmcli -t general permissions | awk -F: '$1=="org.freedesktop.NetworkManager.settings.modify.system"{print $2}')"
  echo "network-control: ${control:-unknown}"
  echo "settings.modify.system: ${modify:-unknown}"
  if [[ "$control" == "yes" && "$modify" == "yes" ]]; then
    echo "OK: polkit allows Proton CLI over SSH."
    return 0
  fi
  echo "NOT READY: expected 'yes' for both. Run: $0 install-polkit" >&2
  return 1
}

clean_stale() {
  need_cmd nmcli
  local names
  names="$(nm_proton_names)"
  if [[ -z "$names" ]]; then
    echo "No Proton/pvpn NetworkManager connections to remove."
    return 0
  fi
  echo "Removing stale Proton NM connections:"
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    echo "  - $name"
    if nmcli connection delete "$name" 2>/dev/null; then
      continue
    fi
    echo "    (needs sudo)"
    sudo nmcli connection delete "$name"
  done <<<"$names"
}

cmd_status() {
  need_cmd protonvpn
  protonvpn status || true
  echo
  if curl -4 -fsS --connect-timeout 5 https://ipinfo.io 2>/dev/null; then
    echo
  else
    echo "WARN: could not reach ipinfo.io (egress broken?)" >&2
  fi
}

cmd_connect() {
  need_cmd protonvpn
  check_polkit || true
  protonvpn connect --country "$COUNTRY"
  protonvpn status
}

cmd_disconnect() {
  need_cmd protonvpn
  protonvpn disconnect || true
  clean_stale || true
  protonvpn status || true
}

cmd_recover() {
  need_cmd protonvpn
  echo "==> Checking polkit"
  check_polkit || {
    echo "Install polkit first: $0 install-polkit" >&2
    exit 1
  }
  echo "==> Cleaning stale NM connections"
  clean_stale
  echo "==> Connecting (country=$COUNTRY)"
  protonvpn connect --country "$COUNTRY"
  echo "==> Status"
  protonvpn status
  echo
  curl -4 -fsS --connect-timeout 5 https://ipinfo.io || true
  echo
  echo "If qBittorrent port-forward looks stale: systemctl --user restart proton-qbit-port-forward.service"
}

cmd_doctor() {
  echo "== Proton =="
  protonvpn status 2>&1 || true
  echo
  echo "== Polkit / NM =="
  check_polkit || true
  echo
  echo "== Proton NM connections =="
  nm_proton_names || echo "(none)"
  echo
  echo "== Egress =="
  curl -4 -fsS -o /dev/null -w "google:%{http_code}\n" --connect-timeout 5 https://www.google.com || echo "google:fail"
  curl -4 -fsS -o /dev/null -w "apibay:%{http_code}\n" --connect-timeout 8 \
    https://apibay.org/precompiled/data_top100_recent.json || echo "apibay:fail"
  curl -4 -fsS --connect-timeout 5 https://ipinfo.io 2>/dev/null || echo "ipinfo:fail"
  echo
  echo "== Recent Proton log (certificate / KS) =="
  if [[ -f "$HOME/.cache/Proton/VPN/logs/vpn-cli.log" ]]; then
    grep -E 'ExpiredCertificate|Insufficient|CONN:STATE|Error' \
      "$HOME/.cache/Proton/VPN/logs/vpn-cli.log" | tail -20 || true
  fi
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    status) cmd_status ;;
    connect) cmd_connect ;;
    disconnect) cmd_disconnect ;;
    recover) cmd_recover ;;
    install-polkit) install_polkit ;;
    check-polkit) check_polkit ;;
    doctor) cmd_doctor ;;
    -h|--help|help|"") usage ;;
    *)
      echo "Unknown command: $cmd" >&2
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
