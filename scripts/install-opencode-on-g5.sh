#!/usr/bin/env bash
# Install OpenCode + Cursor CLI proxy on G5 (Docker) and enable opencode-web.
# Run from Mac (repo root). Idempotent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/envfile.sh
source "${SCRIPT_DIR}/lib/envfile.sh"

ROOT="$(homelab_root)"
SECRETS="$(homelab_secrets_file)"
G5_HOST="${1:-g5}"
G5_USER="${2:-wmichelin}"
REMOTE_PATH="${3:-/home/${G5_USER}/code/homelab}"

if [[ ! -f "$SECRETS" ]]; then
  echo "Missing secrets/homelab.env" >&2
  exit 1
fi

if ! envfile_get "$SECRETS" OPENCODE_SERVER_PASSWORD >/dev/null 2>&1; then
  pw="$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)"
  envfile_set "$SECRETS" OPENCODE_SERVER_PASSWORD "$pw"
  echo "Generated OPENCODE_SERVER_PASSWORD in secrets/homelab.env"
fi
envfile_set "$SECRETS" OPENCODE_SERVER_USERNAME "opencode"

"${ROOT}/scripts/materialize-env.sh" --target g5 >/dev/null

echo "Syncing opencode app + user unit..."
rsync -avz \
  "${ROOT}/apps/opencode/" \
  "${G5_USER}@${G5_HOST}:${REMOTE_PATH}/apps/opencode/"
rsync -avz \
  "${ROOT}/infra/systemd/user/opencode-web.service" \
  "${G5_USER}@${G5_HOST}:${REMOTE_PATH}/infra/systemd/user/opencode-web.service"
scp -q "${ROOT}/apps/opencode/.env" "${G5_USER}@${G5_HOST}:${REMOTE_PATH}/apps/opencode/.env"
ssh "${G5_USER}@${G5_HOST}" "chmod 600 '${REMOTE_PATH}/apps/opencode/.env'"

echo "Installing OpenCode binary + Node (host tools for Cursor proxy) on ${G5_HOST}..."
ssh "${G5_USER}@${G5_HOST}" bash -s <<EOF
set -euo pipefail
export PATH="\$HOME/.local/bin:\$PATH"

if ! command -v cursor-agent >/dev/null; then
  echo "cursor-agent not found in PATH (\$HOME/.local/bin). Install Cursor CLI first." >&2
  exit 1
fi
cursor-agent status || true

if ! command -v node >/dev/null || [[ "\$(node -v | sed 's/v//;s/\\..*//')" -lt 18 ]]; then
  if ! command -v fnm >/dev/null && [[ ! -x "\$HOME/.local/share/fnm/fnm" ]]; then
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "\$HOME/.local/share/fnm" --skip-shell
  fi
  export PATH="\$HOME/.local/share/fnm:\$PATH"
  eval "\$("\$HOME/.local/share/fnm/fnm" env)"
  fnm install 22
  fnm use 22
  fnm default 22
fi

if [[ ! -x "\$HOME/.opencode/bin/opencode" ]]; then
  curl -fsSL https://opencode.ai/install | bash
fi
"\$HOME/.opencode/bin/opencode" --version

mkdir -p "\$HOME/.config/opencode" "\$HOME/code"
# Do NOT symlink opencode.json here when OPENCODE_CONFIG points at the same file —
# the cursor-proxy plugin would start twice (EADDRINUSE on :32124) and exit.
rm -f "\$HOME/.config/opencode/opencode.json"

'${REMOTE_PATH}/scripts/install-user-units.sh'
systemctl --user daemon-reload
# Prefer Docker-published :4096 (reachable from g5-caddy).
systemctl --user stop opencode-web.service 2>/dev/null || true
pkill -f "[.]opencode/bin/opencode web" 2>/dev/null || true
cd '${REMOTE_PATH}/apps/opencode'
docker compose up -d --remove-orphans
systemctl --user enable opencode-web.service
loginctl enable-linger "\$USER" 2>/dev/null || true
sleep 2
docker compose ps
EOF

echo ""
echo "OpenCode web on G5 :4096 (Tailscale-only; no basic auth — EventSource)."
echo "Proxy/DNS:"
echo "  ./deploy-to-g5.sh media-stack"
echo "  ./scripts/deploy-headscale-to-droplet.sh"
echo "Open https://opencode.g5.lan/?directory=/home/wmichelin/code/homelab"
