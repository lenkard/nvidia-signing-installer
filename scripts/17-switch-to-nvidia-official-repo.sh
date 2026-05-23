#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helpers/common.sh"
require_root
is_debian || die "This helper targets Debian-family systems using apt."

purge_first="yes"
if [[ "${1:-}" == "--keep-existing-packages" ]]; then
  purge_first="no"
fi

log "Configuring NVIDIA official Debian repo according to NVIDIA documentation"
install_nvidia_from_official_repo "$purge_first"

log "Post-install package matrix"
print_nvidia_package_matrix
log "Post-install nvidia-smi status"
print_nvidia_smi_status
log "Post-install GPU/driver support assessment"
print_driver_support_assessment
print_external_nvidia_guidance

cat <<MSG

NVIDIA official repo remediation complete.
Recommended next steps:
- Re-run diagnostics:
    ./scripts/00-diagnose.sh
- If Secure Boot is enabled, use the existing MOK/signing flow.
- If you want modules for another kernel, use the existing target-kernel workflow.

Log saved to: $LOG_FILE
MSG
