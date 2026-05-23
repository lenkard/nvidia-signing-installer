#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
SCRIPT_BASENAME="$(basename "${BASH_SOURCE[1]:-$0}" .sh)"
LOG_FILE="$LOG_DIR/${TIMESTAMP}-${SCRIPT_BASENAME}.log"

exec > >(tee -a "$LOG_FILE") 2>&1

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this script with sudo/root."
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

apt_candidate_version() {
  apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2; exit}'
}

version_major() {
  local v="${1:-0}"
  printf '%s\n' "$v" | sed -E 's/^([0-9]+).*/\1/'
}

gpu_summary() {
  lspci -nn | grep -Ei 'vga|3d|display' || true
}

secure_boot_state() {
  if command_exists mokutil; then
    mokutil --sb-state 2>/dev/null || true
  else
    echo "mokutil not installed"
  fi
}

kernel_headers_path() {
  echo "/usr/src/linux-headers-$(uname -r)/scripts/sign-file"
}

ensure_sign_file() {
  local sf
  sf="$(kernel_headers_path)"
  [[ -x "$sf" ]] || die "sign-file not found at $sf. Install linux-headers-$(uname -r)."
}

module_path_or_empty() {
  local mod="$1"
  modinfo -n "$mod" 2>/dev/null || true
}

has_module_file() {
  local p="$1"
  [[ -n "$p" && -e "$p" ]]
}

nvidia_modules_present() {
  local found=1
  for m in nvidia nvidia-modeset nvidia-drm nvidia-uvm; do
    if has_module_file "$(module_path_or_empty "$m")"; then
      found=0
    fi
  done
  return "$found"
}

current_kernel() { uname -r; }

is_debian() {
  [[ -r /etc/os-release ]] && . /etc/os-release && [[ "${ID:-}" == "debian" ]]
}

os_summary() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    echo "$PRETTY_NAME"
  else
    uname -a
  fi
}
