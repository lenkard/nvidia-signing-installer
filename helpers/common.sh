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

installed_package_version() {
  dpkg-query -W -f='${Version}\n' "$1" 2>/dev/null || true
}

installed_package_owns_path() {
  local p="$1"
  dpkg-query -S "$p" 2>/dev/null | head -n1 | cut -d: -f1 || true
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

module_install_path() {
  local name="$1"
  local base="/lib/modules/$(uname -r)/updates/dkms"
  case "$name" in
    nvidia) echo "$base/nvidia.ko.xz" ;;
    nvidia-modeset) echo "$base/nvidia-modeset.ko.xz" ;;
    nvidia-drm) echo "$base/nvidia-drm.ko.xz" ;;
    nvidia-uvm) echo "$base/nvidia-uvm.ko.xz" ;;
    nvidia-peermem) echo "$base/nvidia-peermem.ko.xz" ;;
    *) return 1 ;;
  esac
}

has_module_file() {
  local p="$1"
  [[ -n "$p" && -e "$p" ]]
}

xz_module_is_valid() {
  local p="$1"
  [[ -e "$p" ]] || return 1
  xz -t "$p" >/dev/null 2>&1
}

modinfo_file_works() {
  local p="$1"
  [[ -e "$p" ]] || return 1
  modinfo "$p" >/dev/null 2>&1
}

remove_installed_nvidia_modules() {
  local removed=0
  local base="/lib/modules/$(uname -r)/updates/dkms"
  if [[ -d "$base" ]]; then
    while IFS= read -r -d '' file; do
      log "Removing installed module file: $file"
      rm -f "$file"
      removed=1
    done < <(find "$base" -maxdepth 1 -type f \( -name 'nvidia*.ko' -o -name 'nvidia*.ko.xz' \) -print0)
  fi
  return $removed
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

print_nvidia_package_matrix() {
  for pkg in nvidia-driver nvidia-kernel-dkms nvidia-driver-libs nvidia-smi firmware-misc-nonfree dkms linux-headers-$(uname -r); do
    printf '%-28s installed=%s candidate=%s\n' "$pkg" "$(installed_package_version "$pkg")" "$(apt_candidate_version "$pkg")"
  done
}

print_nvidia_smi_status() {
  if command_exists nvidia-smi; then
    local bin
    bin="$(command -v nvidia-smi)"
    printf 'nvidia-smi path: %s\n' "$bin"
    printf 'nvidia-smi owner: %s\n' "$(installed_package_owns_path "$bin")"
  else
    echo 'nvidia-smi path: MISSING'
    echo 'nvidia-smi owner: UNKNOWN'
  fi
  printf 'nvidia-smi package installed=%s candidate=%s\n' "$(installed_package_version nvidia-smi)" "$(apt_candidate_version nvidia-smi)"
}

install_optional_nvidia_smi_package() {
  local candidate
  candidate="$(apt_candidate_version nvidia-smi || true)"
  if [[ -n "$candidate" && "$candidate" != "(none)" ]]; then
    log "Installing nvidia-smi package: $candidate"
    apt-get install -y nvidia-smi
  else
    warn "No separate nvidia-smi apt candidate found; relying on current package set"
  fi
}
