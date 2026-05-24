#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helpers/common.sh"
require_root
is_debian || die "This helper targets Debian-family systems using apt."

log "Detected/assumed Blackwell workflow: preferring NVIDIA open kernel modules"

if nvidia_official_repo_configured; then
  log "NVIDIA official repo already configured"
else
  warn "NVIDIA official repo not configured yet. Configuring it now because Blackwell prefers open kernel modules."
  configure_nvidia_official_network_repo
fi

log "Installing NVIDIA driver with open kernel modules"
apt-get install -y nvidia-driver nvidia-kernel-open-dkms nvidia-settings
install_optional_nvidia_smi_package

log "Post-install package matrix"
print_nvidia_package_matrix
log "Post-install nvidia-smi status"
print_nvidia_smi_status
log "Post-install GPU/driver support assessment"
print_driver_support_assessment
log "Post-install DKMS MOK enrollment status"
print_dkms_mok_status

cat <<MSG

Blackwell/open-module installation complete.
If Secure Boot is enabled and the DKMS MOK is not enrolled, import /var/lib/dkms/mok.pub and reboot.
Then run:
  ./scripts/00-diagnose.sh
  ./scripts/40-verify.sh

AI/CUDA note:
- Open kernel modules still work with the NVIDIA user-space CUDA driver stack.
- This is the preferred path for Blackwell.

Log saved to: $LOG_FILE
MSG
