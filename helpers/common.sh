#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
SCRIPT_BASENAME="$(basename "${BASH_SOURCE[1]:-$0}" .sh)"
LOG_FILE="$LOG_DIR/${TIMESTAMP}-${SCRIPT_BASENAME}.log"
SESSION_LOG="${NSI_SESSION_LOG:-}"

if [[ -n "$SESSION_LOG" ]]; then
  mkdir -p "$(dirname "$SESSION_LOG")"
  touch "$SESSION_LOG"
  exec > >(tee -a "$LOG_FILE" "$SESSION_LOG") 2>&1
else
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this script with sudo/root."
}

run_as_root() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
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

confirm_or_die() {
  local prompt="$1"
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || die "Aborted by user."
}

migrate_existing_file() {
  local path="$1"
  local backup_dir="$PROJECT_DIR/backups/$TIMESTAMP"
  if [[ -e "$path" ]]; then
    mkdir -p "$backup_dir"
    mv "$path" "$backup_dir/"
    log "Moved existing $(basename "$path") to $backup_dir"
  fi
}

nvidia_pkg_major_warning() {
  local candidate
  candidate="$(apt_candidate_version nvidia-driver || true)"
  if [[ -n "$candidate" && "$candidate" != "(none)" ]]; then
    local major
    major="$(version_major "$candidate")"
    if [[ "$major" -lt 570 ]]; then
      warn "Debian candidate nvidia-driver ($candidate) appears older than 570. RTX 5070 Ti / Blackwell may not be supported well or at all."
    fi
  fi
}

print_manual_mok_steps() {
  cat <<'MSG'
Manual step required:
- Reboot now
- In the blue MOK Manager screen choose: Enroll MOK -> Continue -> Yes
- Enter the one-time password you created during mokutil import
- Boot back into Linux
MSG
}
