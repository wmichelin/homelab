#!/usr/bin/env bash
# Set the G5 static hostname so Avahi publishes g5.local on the LAN.
# Run on the G5 with sudo:
#   sudo ~/code/homelab/scripts/set-g5-hostname.sh
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

NEW_HOST="${1:-g5}"
PRETTY="${2:-Dell G5 5000}"

hostnamectl set-hostname "$NEW_HOST"
hostnamectl set-hostname "$PRETTY" --pretty

# Keep loopback mapping in sync (hostnamectl usually does this; force it)
if grep -qE '^127\.0\.1\.1\s' /etc/hosts; then
  sed -i -E "s/^127\.0\.1\.1\s+.*/127.0.1.1\t${NEW_HOST}/" /etc/hosts
else
  printf '127.0.1.1\t%s\n' "$NEW_HOST" >>/etc/hosts
fi

systemctl restart avahi-daemon

echo "Static hostname: $(hostnamectl --static)"
echo "Pretty hostname: $(hostnamectl --pretty)"
echo "Avahi should now answer: ${NEW_HOST}.local"
echo "From a Mac: ping ${NEW_HOST}.local   # or: ssh g5"
