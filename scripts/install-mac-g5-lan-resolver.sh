#!/usr/bin/env bash
# Deprecated: *.g5.lan is served by Headscale MagicDNS (requires Tailscale app).
# See docs/headscale-tailscale.md
set -euo pipefail
echo "Deprecated: do not install /etc/resolver/g5.lan anymore." >&2
echo "Use the Tailscale app with login server https://hs.waltermichelin.com" >&2
echo "Docs: docs/headscale-tailscale.md" >&2
exit 1
