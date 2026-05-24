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

apt_package_version_from_suite() {
  local pkg="$1" suite_pattern="$2"
  apt-cache policy "$pkg" 2>/dev/null | awk -v pat="$suite_pattern" '
    /^[[:space:]]+[0-9]/ { ver=$1 }
    $0 ~ pat && ver != "" { print ver; exit }
  '
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

gpu_pci_ids() {
  lspci -nn | sed -nE 's/.*\[10de:([0-9a-fA-F]{4})\].*/10de:\1/p'
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

module_basename_candidates() {
  local name="$1"
  case "$name" in
    nvidia) printf '%s\n' nvidia nvidia-current ;;
    nvidia-modeset) printf '%s\n' nvidia-modeset nvidia-current-modeset ;;
    nvidia-drm) printf '%s\n' nvidia-drm nvidia-current-drm ;;
    nvidia-uvm) printf '%s\n' nvidia-uvm nvidia-current-uvm ;;
    nvidia-peermem) printf '%s\n' nvidia-peermem nvidia-current-peermem ;;
    *) return 1 ;;
  esac
}

module_install_path() {
  module_install_path_for "$1" "$TARGET_KERNEL"
}

module_install_path_for() {
  local name="$1" kernel="$2" base path candidate
  base="/lib/modules/$kernel/updates/dkms"
  while IFS= read -r candidate; do
    for path in "$base/$candidate.ko.xz" "$base/$candidate.ko"; do
      [[ -e "$path" ]] && { echo "$path"; return 0; }
    done
  done < <(module_basename_candidates "$name")
  echo "$base/$(module_basename_candidates "$name" | head -n1).ko.xz"
}

has_module_file() {
  local p="$1"
  [[ -n "$p" && -e "$p" ]]
}

xz_module_is_valid() {
  local p="$1"
  [[ -e "$p" ]] || return 1
  [[ "$p" != *.xz ]] && return 0
  xz -t "$p" >/dev/null 2>&1
}

modinfo_file_works() {
  local p="$1" tmp
  [[ -e "$p" ]] || return 1
  if [[ "$p" == *.xz ]]; then
    tmp="$(mktemp --suffix=.ko)"
    xz -dc "$p" > "$tmp" || { rm -f "$tmp"; return 1; }
    modinfo "$tmp" >/dev/null 2>&1
    local rc=$?
    rm -f "$tmp"
    return $rc
  fi
  modinfo "$p" >/dev/null 2>&1
}

sign_module_file() {
  local kernel="$1" file="$2"
  ensure_sign_file_for "$kernel"
  [[ -f "$PROJECT_DIR/MOK.priv" && -f "$PROJECT_DIR/MOK.der" ]] || die "MOK.priv and MOK.der must exist in $PROJECT_DIR."
  "$(kernel_headers_path_for "$kernel")" sha256 "$PROJECT_DIR/MOK.priv" "$PROJECT_DIR/MOK.der" "$file"
}

sign_installed_module_for_kernel() {
  local kernel="$1" module="$2" path tmp
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
  local kernel="$1" removed=0 base
  base="/lib/modules/$kernel/updates/dkms"
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
  local path="$1" backup_dir="$PROJECT_DIR/backups/$TIMESTAMP"
  if [[ -e "$path" ]]; then
    mkdir -p "$backup_dir"
    mv "$path" "$backup_dir/"
    log "Moved existing $(basename "$path") to $backup_dir"
  fi
}

nvidia_pkg_major_warning() {
  local candidate major
  candidate="$(apt_candidate_version nvidia-driver || true)"
  if [[ -n "$candidate" && "$candidate" != "(none)" ]]; then
    major="$(version_major "$candidate")"
    if [[ "$major" -lt 570 ]]; then
      warn "Debian candidate nvidia-driver ($candidate) appears older than 570. RTX 5070 Ti / Blackwell may not be supported well or at all."
    fi
  fi
}

likely_gpu_requires_newer_branch() {
  local id
  while IFS= read -r id; do
    case "$id" in
      10de:2c05) return 0 ;;
    esac
  done < <(gpu_pci_ids)
  return 1
}

driver_support_verdict() {
  local installed major
  installed="$(installed_package_version nvidia-driver)"
  if [[ -z "$installed" ]]; then
    echo "missing-driver-package"
    return 0
  fi
  major="$(version_major "$installed")"
  if likely_gpu_requires_newer_branch && [[ "$major" -lt 570 ]]; then
    echo "too-old-heuristic"
    return 0
  fi
  if journalctl -k -b 0 2>/dev/null | grep -q 'not supported by the NVIDIA .* driver release'; then
    echo "unsupported-by-kernel-log"
    return 0
  fi
  echo "ok"
}

print_driver_support_assessment() {
  local verdict installed ids
  verdict="$(driver_support_verdict)"
  installed="$(installed_package_version nvidia-driver)"
  ids="$(gpu_pci_ids | tr '\n' ' ')"
  echo "detected_gpu_pci_ids: ${ids:-none}"
  echo "installed_nvidia_driver: ${installed:-none}"
  echo "driver_support_verdict: $verdict"
  case "$verdict" in
    too-old-heuristic|unsupported-by-kernel-log)
      warn "Packages installed successfully, but this driver branch does not support your GPU."
      ;;
  esac
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

nvidia_smi_package_is_transitional() {
  apt-cache show nvidia-smi 2>/dev/null | grep -q 'Transitional dummy package'
}

install_optional_nvidia_smi_package() {
  local candidate
  candidate="$(apt_candidate_version nvidia-smi || true)"
  if command_exists nvidia-smi; then
    log "nvidia-smi already present"
    return 0
  fi
  if [[ -n "$candidate" && "$candidate" != "(none)" ]]; then
    if nvidia_smi_package_is_transitional; then
      warn "nvidia-smi package is transitional in this repository; installing nvidia-driver-cuda to provide /usr/bin/nvidia-smi"
      apt-get install -y nvidia-driver-cuda
    else
      log "Installing nvidia-smi package: $candidate"
      apt-get install -y nvidia-smi
    fi
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

nvidia_repo_distro_token() {
  local vid
  vid="$(. /etc/os-release && echo "${VERSION_ID:-}")"
  case "$vid" in
    12) echo "debian12" ;;
    13) echo "debian13" ;;
    *) return 1 ;;
  esac
}

nvidia_official_repo_configured() {
  [[ -f /etc/apt/sources.list.d/cuda-$(nvidia_repo_distro_token)-x86_64.list ]]
}

ensure_target_kernel_and_headers() {
  local kernel="$1" image_pkg headers_pkg
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
  local kernel="$1" require_signing="$2" failed=0 installed_path
  for mod in nvidia nvidia-modeset nvidia-drm nvidia-uvm; do
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

install_nvidia_from_backports() {
  require_root
  apt-get update
  if ! apt_package_available nvidia-driver; then
    die "No nvidia-driver package available from configured apt sources."
  fi
  local bp_ver
  bp_ver="$(apt_package_version_from_suite nvidia-driver 'trixie-backports/.*/non-free')"
  if [[ -z "$bp_ver" ]]; then
    die "No backports nvidia-driver version detected. Ensure trixie-backports non-free is enabled."
  fi
  log "Installing NVIDIA packages from trixie-backports: $bp_ver"
  apt-get install -y -t trixie-backports \
    nvidia-driver nvidia-kernel-dkms nvidia-driver-libs nvidia-smi nvidia-settings
}

configure_nvidia_official_network_repo() {
  require_root
  local token keyring_deb keyring_url
  token="$(nvidia_repo_distro_token)" || die "Unsupported Debian VERSION_ID for NVIDIA documented repo path."
  keyring_deb="/tmp/cuda-keyring_1.1-1_all.deb"
  keyring_url="https://developer.download.nvidia.com/compute/cuda/repos/${token}/x86_64/cuda-keyring_1.1-1_all.deb"
  log "Downloading NVIDIA cuda-keyring from $keyring_url"
  wget -O "$keyring_deb" "$keyring_url"
  dpkg -i "$keyring_deb"
  apt-get update
  log "NVIDIA official network repo configured for $token"
}

install_nvidia_from_official_repo() {
  require_root
  local purge_first="${1:-yes}"
  if [[ "$purge_first" == "yes" ]]; then
    log "Purging Debian NVIDIA packages before switching to NVIDIA official repo"
    apt-get purge -y 'nvidia-*' 'libnvidia-*' 'xserver-xorg-video-nvidia*' || true
    apt-get autoremove -y || true
  fi
  configure_nvidia_official_network_repo
  log "Installing NVIDIA proprietary desktop driver per NVIDIA Debian docs"
  apt-get install -y nvidia-driver nvidia-kernel-dkms nvidia-driver-cuda nvidia-settings
  if apt_package_available nvidia-smi; then
    apt-get install -y nvidia-smi
  fi
}

dkms_mok_enrolled_verdict() {
  local pub fingerprint enrolled
  pub="/var/lib/dkms/mok.pub"
  [[ -f "$pub" ]] || { echo "missing-dkms-mok-pub"; return 0; }
  fingerprint="$(openssl x509 -inform DER -in "$pub" -fingerprint -sha1 -noout 2>/dev/null | cut -d= -f2 | tr '[:upper:]' '[:lower:]')"
  enrolled="$(mokutil --list-enrolled 2>/dev/null | sed -n 's/^SHA1 Fingerprint: //p' | tr '[:upper:]' '[:lower:]')"
  if grep -q "$fingerprint" <<<"$enrolled"; then
    echo "enrolled"
  else
    echo "not-enrolled"
  fi
}

print_dkms_mok_status() {
  local verdict pub
  pub="/var/lib/dkms/mok.pub"
  verdict="$(dkms_mok_enrolled_verdict)"
  echo "dkms_mok_pub: $pub"
  echo "dkms_mok_enrollment: $verdict"
  if [[ "$verdict" == "not-enrolled" ]]; then
    warn "DKMS signed modules are using a key that is not enrolled in MOK; Secure Boot will reject the modules until you import /var/lib/dkms/mok.pub and reboot."
  fi
}

print_external_nvidia_guidance() {
  cat <<'MSG'
NVIDIA documented Debian repo guidance:
- Preferred order for this project: Debian stable -> Debian backports -> NVIDIA official Debian repo.
- Use NVIDIA's documented network repository enablement with cuda-keyring on Debian 12/13.
- For desktop/proprietary setups, NVIDIA documents nvidia-driver + nvidia-kernel-dkms.
- In NVIDIA's repo, the nvidia-smi package may be transitional; /usr/bin/nvidia-smi can come from nvidia-driver-cuda.
- Prefer one packaging source at a time; purge conflicting Debian NVIDIA packages before switching sources when possible.
- Avoid mixing Debian-packaged NVIDIA with upstream .run installations.
MSG
}
