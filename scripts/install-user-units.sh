#!/usr/bin/env bash
# Install / refresh systemd --user units from this repo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_SRC="${ROOT}/infra/systemd/user"
UNIT_DST="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

mkdir -p "$UNIT_DST"
for f in "$UNIT_SRC"/*; do
  [[ -f "$f" ]] || continue
  base="$(basename "$f")"
  ln -sfn "$f" "$UNIT_DST/$base"
  echo "linked $UNIT_DST/$base"
done

systemctl --user daemon-reload
echo "Reloaded systemd --user. Enable examples:"
echo "  systemctl --user enable --now proton-qbit-port-forward.service"
echo "  systemctl --user enable --now g5-backup-gdrive.timer"
