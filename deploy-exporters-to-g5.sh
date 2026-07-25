#!/usr/bin/env bash
# Back-compat wrapper — exporters now deploy via deploy-to-g5.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${ROOT}/deploy-to-g5.sh" exporters "$@"
