#!/usr/bin/env bash
# Install G5 system scripts + systemd units from this repo (requires sudo).
# Does NOT rewrite /etc/fstab, /etc/snapraid.conf, or /etc/samba/smb.conf.
#
# Units ExecStart the repo scripts under ~/code/homelab so they stay in sync
# with rsync deploys. Optional /usr/local copies are kept for PATH convenience.
#
# Usage (on G5, from repo root):
#   sudo ./scripts/install-g5-system.sh
# Or from Mac (needs passwordless sudo or an interactive TTY):
#   ./deploy-to-g5.sh --system
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEXTFILE_DIR="${TEXTFILE_DIR:-${ROOT}/apps/exporters/textfile}"
REPO_SCRIPTS="${ROOT}/apps/exporters/scripts"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

install -d -m 755 /usr/local/bin /usr/local/sbin /etc/systemd/system

# Convenience copies (units use repo paths; these keep tribal /usr/local refs working)
install -m 755 "${REPO_SCRIPTS}/snapraid-job-wrapper.sh" /usr/local/bin/snapraid-job-wrapper.sh
install -m 755 "${REPO_SCRIPTS}/snapraid-metrics.sh" /usr/local/bin/snapraid-metrics.sh
install -m 755 "$ROOT/infra/storage/g5-remount-mergerfs" /usr/local/sbin/g5-remount-mergerfs

install -d -m 755 -o wmichelin -g wmichelin "$TEXTFILE_DIR"

for unit in "$ROOT"/infra/systemd/system/*; do
  [[ -f "$unit" ]] || continue
  install -m 644 "$unit" "/etc/systemd/system/$(basename "$unit")"
done

systemctl daemon-reload

systemctl enable --now snapraid-metrics.timer
systemctl enable --now snapraid-sync.timer
systemctl enable --now snapraid-scrub.timer
# oneshot helper — no [Install] section; start manually after hotplug:
#   sudo systemctl start g5-remount-mergerfs.service

echo "Installed system units (ExecStart → ${REPO_SCRIPTS}) + /usr/local helpers."
echo "TEXTFILE_DIR=${TEXTFILE_DIR}"
systemctl --no-pager --full status snapraid-metrics.timer snapraid-sync.timer snapraid-scrub.timer || true
systemctl --no-pager --full status g5-remount-mergerfs.service || true
