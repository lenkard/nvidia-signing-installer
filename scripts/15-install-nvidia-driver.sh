#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helpers/common.sh"
require_root
is_debian || die "This helper targets Debian-family systems using apt."

mode="install"
if [[ "${1:-}" == "--purge-reinstall" ]]; then
  mode="purge-reinstall"
fi

candidate="$(apt_candidate_version nvidia-driver || true)"
if [[ -z "$candidate" || "$candidate" == "(none)" ]]; then
  die "No nvidia-driver candidate found. Check apt sources for contrib/non-free/non-free-firmware."
fi
log "Debian nvidia-driver candidate: $candidate"
nvidia_pkg_major_warning

apt-get update
if [[ "$mode" == "purge-reinstall" ]]; then
  log "Purging Debian NVIDIA packages before reinstall"
  apt-get purge -y 'nvidia-*' 'libnvidia-*' 'xserver-xorg-video-nvidia*' || true
  apt-get autoremove -y || true
fi

log "Installing Debian-packaged NVIDIA driver stack"
apt-get install -y nvidia-driver firmware-misc-nonfree dkms linux-headers-$(uname -r)
install_optional_nvidia_smi_package

log "Post-install nvidia-smi status"
print_nvidia_smi_status
log "Post-install GPU/driver support assessment"
print_driver_support_assessment
verdict="$(driver_support_verdict)"
if [[ "$verdict" == "too-old-heuristic" || "$verdict" == "unsupported-by-kernel-log" ]]; then
  warn "Packages installed successfully, but this driver branch does not support your GPU."
  bp_ver="$(apt_package_version_from_suite nvidia-driver 'trixie-backports/.*/non-free')"
  if [[ -n "$bp_ver" ]]; then
    warn "A newer backports NVIDIA branch appears available: $bp_ver"
    warn "You can try: sudo ./scripts/16-switch-to-backports.sh"
  else
    warn "No newer backports NVIDIA version detected from current apt metadata."
  fi
  print_external_nvidia_guidance
fi

cat <<MSG

Install step complete.
If Secure Boot is enabled, continue with:
  sudo ./scripts/20-create-or-enroll-mok.sh --fresh

MSG
