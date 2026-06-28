#!/usr/bin/env bash

set -euo pipefail

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

load_config() {
  local root
  root="$(repo_root)"
  if [[ -f "$root/config.env" ]]; then
    # shellcheck disable=SC1091
    source "$root/config.env"
  else
    # shellcheck disable=SC1091
    source "$root/config.env.example"
  fi
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

tailscale_bin() {
  if [[ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]]; then
    printf '%s\n' /Applications/Tailscale.app/Contents/MacOS/Tailscale
  elif command -v tailscale >/dev/null 2>&1; then
    command -v tailscale
  else
    die "找不到 Tailscale 命令"
  fi
}
