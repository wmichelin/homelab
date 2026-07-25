#!/usr/bin/env bash
# Install / update / uninstall the Apple Photos export LaunchAgent.
#
# Usage:
#   ./install-launchagent.sh              # install or refresh
#   ./install-launchagent.sh --run-now    # install and kick once
#   ./install-launchagent.sh --uninstall
#   HOUR=6 MINUTE=30 ./install-launchagent.sh   # custom daily time
set -euo pipefail

LABEL="com.homelab.apple-photos-export"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/launchd/${LABEL}.plist.template"
RUN_SCHEDULED="${SCRIPT_DIR}/run-scheduled.sh"
PLIST_DEST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="${HOME}/Library/Logs/homelab"
HOUR="${HOUR:-2}"
MINUTE="${MINUTE:-0}"

RUN_NOW=0
UNINSTALL=0
for arg in "$@"; do
  case "$arg" in
    --run-now) RUN_NOW=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help)
      sed -n '2,10p' "$0"
      exit 0
      ;;
    *)
      echo "unknown arg: $arg" >&2
      exit 1
      ;;
  esac
done

uid="$(id -u)"
domain="gui/${uid}"

unload_if_loaded() {
  if launchctl print "${domain}/${LABEL}" >/dev/null 2>&1; then
    launchctl bootout "${domain}/${LABEL}" 2>/dev/null || true
  fi
}

if [[ "$UNINSTALL" -eq 1 ]]; then
  unload_if_loaded
  rm -f "$PLIST_DEST"
  echo "Removed ${LABEL}"
  exit 0
fi

if [[ ! -f "$TEMPLATE" ]]; then
  echo "error: missing template: $TEMPLATE" >&2
  exit 1
fi
if [[ ! -x "$RUN_SCHEDULED" ]]; then
  chmod +x "$RUN_SCHEDULED"
fi
if [[ ! -f "${SCRIPT_DIR}/config.env" ]]; then
  echo "warning: ${SCRIPT_DIR}/config.env not found — copy from config.example.env first" >&2
fi

mkdir -p "$(dirname "$PLIST_DEST")" "$LOG_DIR"

# shellcheck disable=SC2016
sed \
  -e "s|__RUN_SCHEDULED__|${RUN_SCHEDULED}|g" \
  -e "s|__PKG_ROOT__|${SCRIPT_DIR}|g" \
  -e "s|__LOG_DIR__|${LOG_DIR}|g" \
  -e "s|__HOME__|${HOME}|g" \
  "$TEMPLATE" \
| awk -v hour="$HOUR" -v minute="$MINUTE" '
  /<key>Hour<\/key>/ { print; getline; print "\t\t<integer>" hour "</integer>"; next }
  /<key>Minute<\/key>/ { print; getline; print "\t\t<integer>" minute "</integer>"; next }
  { print }
' > "$PLIST_DEST"

unload_if_loaded
launchctl bootstrap "$domain" "$PLIST_DEST"
launchctl enable "${domain}/${LABEL}"

echo "Installed ${LABEL}"
echo "  plist:    $PLIST_DEST"
echo "  schedule: daily ${HOUR}:$(printf '%02d' "$MINUTE") local"
echo "  logs:     ${LOG_DIR}/apple-photos-export.log"
echo "            ${LOG_DIR}/apple-photos-export.err.log"
echo
echo "Full Disk Access: System Settings → Privacy & Security → Full Disk Access"
echo "  enable /bin/bash (launchd runs the job via bash)."
echo "  If exports still fail with permission errors, also enable osxphotos:"
echo "    $(command -v osxphotos 2>/dev/null || echo ~/.local/bin/osxphotos)"

if [[ "$RUN_NOW" -eq 1 ]]; then
  echo
  echo "Starting one run now…"
  launchctl kickstart -k "${domain}/${LABEL}"
fi
