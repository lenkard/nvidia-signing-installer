#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <target-kernel> [--unsigned-ok]" >&2
  exit 1
fi

export NSI_TARGET_KERNEL="$1"
shift || true
source "$SCRIPT_DIR/../helpers/common.sh"

require_signing="yes"
if [[ "${1:-}" == "--unsigned-ok" ]]; then
  require_signing="no"
fi

log "Verifying target kernel $TARGET_KERNEL"
log "OS: $(os_summary)"
log "Secure Boot: $(secure_boot_state | tr '\n' ' ' | sed 's/  */ /g')"
log "Package matrix for target kernel $TARGET_KERNEL:"
print_nvidia_package_matrix
log "nvidia-smi presence/package status:"
print_nvidia_smi_status
log "GPU/driver support assessment:"
print_driver_support_assessment

for mod in nvidia nvidia-modeset nvidia-drm nvidia-uvm; do
  path="$(module_install_path_for "$mod" "$TARGET_KERNEL" 2>/dev/null || true)"
  echo "=== $mod ($TARGET_KERNEL) ==="
  if [[ -n "$path" && -e "$path" ]]; then
    echo "installed_path: $path"
    if xz_module_is_valid "$path"; then echo "xz: ok"; else echo "xz: CORRUPT"; fi
    if modinfo_file_works "$path"; then echo "modinfo: ok"; else echo "modinfo: FAILED"; fi
    modinfo -F signer "$path" 2>/dev/null || true
    modinfo -F sig_id "$path" 2>/dev/null || true
    modinfo -F sig_key "$path" 2>/dev/null || true
    modinfo -F sig_hashalgo "$path" 2>/dev/null || true
  else
    warn "installed module missing: $mod"
  fi
  echo
 done

if verify_target_kernel_modules "$TARGET_KERNEL" "$require_signing"; then
  log "Verification passed for target kernel $TARGET_KERNEL"
else
  die "Verification failed for target kernel $TARGET_KERNEL. Review $LOG_FILE."
fi
