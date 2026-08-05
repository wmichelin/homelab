#!/usr/bin/env bash
# Allow Docker containers on G5 to reach host-networked qBittorrent WebUI :8080.
# Proton VPN kill-switch / UFW often drops bridge→host INPUT for non-docker-proxy
# listeners; published exporters (:9100) still work because of docker-proxy rules.
#
# Usage (on G5):
#   sudo ./scripts/g5-allow-docker-qbit-webui.sh
#   sudo ./scripts/g5-allow-docker-qbit-webui.sh --check
set -euo pipefail

COMMENT='qBit WebUI from Docker bridges'
CIDR='172.16.0.0/12'
PORT='8080'

check_only=0
if [[ "${1:-}" == "--check" ]]; then
  check_only=1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0 $*" >&2
  exit 1
fi

echo "== before =="
iptables -L INPUT -n -v --line-numbers | head -40 || true
if command -v ufw >/dev/null; then
  ufw status verbose | head -40 || true
fi

if [[ "$check_only" -eq 1 ]]; then
  exit 0
fi

if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -qi 'Status: active'; then
  # Idempotent: delete matching rules then re-add.
  while ufw status numbered | grep -q "${CIDR}.*${PORT}/tcp"; do
    num="$(ufw status numbered | sed -n "s/^\[\([0-9]\+\)\].*${CIDR}.*${PORT}\/tcp.*/\1/p" | head -1)"
    [[ -n "$num" ]] || break
    ufw --force delete "$num"
  done
  ufw allow from "$CIDR" to any port "$PORT" proto tcp comment "$COMMENT"
  ufw reload || true
  echo "Applied UFW allow from ${CIDR} to port ${PORT}/tcp"
else
  # Plain iptables fallback (insert near top; skip if identical rule exists).
  if ! iptables -C INPUT -s "$CIDR" -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; then
    iptables -I INPUT 1 -s "$CIDR" -p tcp --dport "$PORT" -j ACCEPT -m comment --comment "$COMMENT"
    echo "Inserted iptables INPUT accept ${CIDR} → tcp/${PORT}"
  else
    echo "iptables rule already present"
  fi
  if command -v netfilter-persistent >/dev/null; then
    netfilter-persistent save
  elif [[ -d /etc/iptables ]]; then
    iptables-save >/etc/iptables/rules.v4
  else
    echo "WARN: install iptables-persistent or re-run after reboot" >&2
  fi
fi

echo "== after =="
iptables -L INPUT -n -v --line-numbers | head -40 || true
ufw status numbered 2>/dev/null | head -40 || true

echo
echo "Verify from a media-stack container:"
echo "  docker exec radarr curl -fsS -m 3 -o /dev/null -w '%{http_code}\\n' http://172.18.0.1:8080/"
echo "  docker exec radarr curl -fsS -m 3 -o /dev/null -w '%{http_code}\\n' http://host.docker.internal:8080/"
