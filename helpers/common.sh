#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
SCRIPT_BASENAME="$(basename "${BASH_SOURCE[1]:-$0}" .sh)"
TARGET_KERNEL="${NSI_TARGET_KERNEL:-${TARGET_KERNEL:-$(uname -r)}}"
TARGET_KERNEL_SAFE="$(printf '%s' "$TARGET_KERNEL" | tr '/ ' '__')"
LOG_SUFFIX=""
if [[ -n "${NSI_TARGET_KERNEL:-}" || -n "${TARGET_KERNEL:-}" ]]; then
  LOG_SUFFIX="-${TARGET_KERNEL_SAFE}"
fi
LOG_FILE="$LOG_DIR/${TIMESTAMP}-${SCRIPT_BASENAME}${LOG_SUFFIX}.log"
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

default_kernel() { uname -r; }
current_kernel() { echo "$TARGET_KERNEL"; }

kernel_headers_path() {
  kernel_headers_path_for "$TARGET_KERNEL"
}

kernel_headers_path_for() {
  local kernel="$1"
  echo "/usr/src/linux-headers-$kernel/scripts/sign-file"
}

ensure_sign_file() {
  ensure_sign_file_for "$TARGET_KERNEL"
}

ensure_sign_file_for() {
  local kernel="$1"
  local sf
  sf="$(kernel_headers_path_for "$kernel")"
  [[ -x "$sf" ]] || die "sign-file not found at $sf. Install linux-headers-$kernel."
}

module_path_or_empty() {
  local mod="$1"
  modinfo -k "$TARGET_KERNEL" -n "$mod" 2>/dev/null || true
}

module_path_for_kernel_or_empty() {
  local kernel="$1"
  local mod="$2"
  modinfo -k "$kernel" -n "$mod" 2>/dev/null || true
}

module_install_path() {
  module_install_path_for "$1" "$TARGET_KERNEL"
}

module_install_path_for() {
  local name="$1"
  local kernel="$2"
  local base="/lib/modules/$kernel/updates/dkms"
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

sign_module_file() {
  local kernel="$1"
  local file="$2"
  ensure_sign_file_for "$kernel"
  [[ -f "$PROJECT_DIR/MOK.priv" && -f "$PROJECT_DIR/MOK.der" ]] || die "MOK.priv and MOK.der must exist in $PROJECT_DIR."
  "$(kernel_headers_path_for "$kernel")" sha256 "$PROJECT_DIR/MOK.priv" "$PROJECT_DIR/MOK.der" "$file"
}

sign_installed_module_for_kernel() {
  local kernel="$1"
  local module="$2"
  local path tmp
  path="$(module_install_path_for "$module" "$kernel" 2>/dev/null || true)"
  [[ -n "$path" && -e "$path" ]] || { warn "Installed module file not found for $module on $kernel"; return 1; }
  if [[ "$path" == *.xz ]]; then
    tmp="$(mktemp --suffix=.ko)"
    xz -dc "$path" > "$tmp"
    sign_module_file "$kernel" "$tmp"
    xz -zc "$tmp" > "$path"
    rm -f "$tmp"
  else
    sign_module_file "$kernel" "$path"
  fi
}

remove_installed_nvidia_modules() {
  remove_installed_nvidia_modules_for_kernel "$TARGET_KERNEL"
}

remove_installed_nvidia_modules_for_kernel() {
  local kernel="$1"
  local removed=0
  local base="/lib/modules/$kernel/updates/dkms"
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
  for pkg in nvidia-driver nvidia-kernel-dkms nvidia-driver-libs nvidia-smi firmware-misc-nonfree dkms linux-headers-$TARGET_KERNEL; do
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

kernel_package_name() { echo "linux-image-$1"; }
headers_package_name() { echo "linux-headers-$1"; }

kernel_installed() {
  [[ -d "/lib/modules/$1" ]]
}

apt_package_available() {
  local candidate
  candidate="$(apt_candidate_version "$1" || true)"
  [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

ensure_target_kernel_and_headers() {
  local kernel="$1"
  local image_pkg headers_pkg
  image_pkg="$(kernel_package_name "$kernel")"
  headers_pkg="$(headers_package_name "$kernel")"
  apt-get update
  if ! kernel_installed "$kernel"; then
    if apt_package_available "$image_pkg"; then
      log "Installing target kernel package: $image_pkg"
      apt-get install -y "$image_pkg"
    else
      die "Target kernel package $image_pkg is not installed and not available in apt."
    fi
  fi
  if ! dpkg -s "$headers_pkg" >/dev/null 2>&1; then
    if apt_package_available "$headers_pkg"; then
      log "Installing target kernel headers: $headers_pkg"
      apt-get install -y "$headers_pkg"
    else
      die "Target kernel headers package $headers_pkg is not installed and not available in apt."
    fi
  fi
}

ensure_mok_files_or_maybe_unsigned() {
  local allow_unsigned="$1"
  if [[ -f "$PROJECT_DIR/MOK.priv" && -f "$PROJECT_DIR/MOK.der" ]]; then
    return 0
  fi
  if [[ "$allow_unsigned" == "yes" ]]; then
    warn "MOK files missing; continuing with unsigned build because --allow-unsigned was selected."
    return 0
  fi
  die "MOK.priv and MOK.der are missing. Run scripts/20-create-or-enroll-mok.sh first or use --allow-unsigned."
}

verify_target_kernel_modules() {
  local kernel="$1"
  local require_signing="$2"
  local failed=0
  for mod in nvidia nvidia-modeset nvidia-drm nvidia-uvm; do
    local installed_path
    installed_path="$(module_install_path_for "$mod" "$kernel" 2>/dev/null || true)"
    if [[ -z "$installed_path" || ! -e "$installed_path" ]]; then
      warn "Expected installed module missing for $mod on $kernel"
      failed=1
      continue
    fi
    if ! xz_module_is_valid "$installed_path"; then
      warn "xz test failed for $installed_path"
      failed=1
    fi
    if ! modinfo_file_works "$installed_path"; then
      warn "modinfo failed for $installed_path"
      failed=1
    fi
    if [[ "$require_signing" == "yes" ]]; then
      if [[ -z "$(modinfo -F signer "$installed_path" 2>/dev/null || true)" ]]; then
        warn "Signer field missing for $installed_path"
        failed=1
      fi
    fi
  done
  [[ -e "/boot/initrd.img-$kernel" ]] || { warn "initramfs missing for $kernel at /boot/initrd.img-$kernel"; failed=1; }
  if ! command_exists nvidia-smi; then
    warn "nvidia-smi is missing"
    failed=1
  fi
  return "$failed"
}
