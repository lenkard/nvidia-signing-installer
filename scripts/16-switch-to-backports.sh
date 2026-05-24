#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helpers/common.sh"
require_root
is_debian || die "This helper targets Debian-family systems using apt."

apt-get update
bp_ver="$(apt_package_version_from_suite nvidia-driver 'trixie-backports/.*/non-free')"
if [[ -z "$bp_ver" ]]; then
  die "No backports nvidia-driver version detected. Ensure trixie-backports non-free is enabled."
fi

log "Backports NVIDIA candidate detected: $bp_ver"
log "Current installed nvidia-driver: $(installed_package_version nvidia-driver)"
if is_blackwell_gpu; then
  warn "Blackwell GPU detected. Backports proprietary path is not preferred; use NVIDIA official repo open modules if backports is still too old."
fi

log "Installing NVIDIA stack from trixie-backports"
install_nvidia_from_backports

log "Post-backports GPU/driver support assessment"
print_driver_support_assessment
print_nvidia_package_matrix
print_nvidia_smi_status

cat <<MSG

Backports NVIDIA installation complete.
If Secure Boot is enabled, continue with fresh MOK import/signing as needed.
Recommended next checks:
  ./scripts/00-diagnose.sh
  ./scripts/40-verify.sh

Log saved to: $LOG_FILE
MSG
