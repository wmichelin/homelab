#!/usr/bin/env bash
# Install / refresh systemd --user units from infra/systemd/user.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_SRC="${ROOT}/infra/systemd/user"
UNIT_DST="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

mkdir -p "$UNIT_DST"
for f in "$UNIT_SRC"/*; do
  [[ -f "$f" ]] || continue
  base="$(basename "$f")"
  # docker-stats lives in compose (docker-stats-exporter); skip legacy units
  case "$base" in
    docker-stats-metrics.*) continue ;;
  esac
  ln -sfn "$f" "$UNIT_DST/$base"
  echo "linked $UNIT_DST/$base"
done

# Drop stale symlinks to removed unit files
for stale in docker-stats-metrics.service docker-stats-metrics.timer; do
  if [[ -L "$UNIT_DST/$stale" ]]; then
    rm -f "$UNIT_DST/$stale"
    echo "removed stale $UNIT_DST/$stale"
  fi
done

systemctl --user daemon-reload
echo "Reloaded systemd --user. Enable examples:"
echo "  systemctl --user enable --now proton-qbit-port-forward.service"
echo "  systemctl --user enable --now g5-backup-gdrive.timer"
echo "  systemctl --user enable --now snapraid-metrics.timer"
