#!/usr/bin/env bash
# Shared helpers for secrets/homelab.env (single source of truth).
# shellcheck shell=bash

_HOMELAB_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOMELAB_ROOT="$(cd "${_HOMELAB_LIB_DIR}/../.." && pwd)"

homelab_root() {
  printf '%s' "$HOMELAB_ROOT"
}

homelab_secrets_file() {
  printf '%s/secrets/homelab.env' "$HOMELAB_ROOT"
}

# Read KEY from an env-style file (first match). Prints value only.
envfile_get() {
  local file="$1" key="$2" line
  [[ -f "$file" ]] || return 1
  line="$(grep -E "^${key}=" "$file" | head -n1 || true)"
  [[ -n "$line" ]] || return 1
  printf '%s' "${line#*=}"
}

# Set KEY=VALUE in file (create file if needed). Preserves other lines.
envfile_set() {
  local file="$1" key="$2" value="$3"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if grep -qE "^${key}=" "$file"; then
    if sed --version >/dev/null 2>&1; then
      sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
      sed -i '' "s|^${key}=.*|${key}=${value}|" "$file"
    fi
  else
    printf '%s=%s\n' "$key" "$value" >>"$file"
  fi
}

# Write DEST containing only the listed keys from SRC (KEY=value lines).
envfile_render() {
  local src="$1" dest="$2"
  shift 2
  local key value tmp
  tmp="$(mktemp)"
  {
    printf '# Generated from %s — do not edit; change secrets/homelab.env and re-run materialize-env.sh\n' "$(basename "$src")"
    for key in "$@"; do
      if value="$(envfile_get "$src" "$key")"; then
        printf '%s=%s\n' "$key" "$value"
      fi
    done
  } >"$tmp"
  mkdir -p "$(dirname "$dest")"
  mv "$tmp" "$dest"
  chmod 600 "$dest"
}
