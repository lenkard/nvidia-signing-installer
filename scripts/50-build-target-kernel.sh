#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <target-kernel> [--allow-unsigned]" >&2
  exit 1
fi

export NSI_TARGET_KERNEL="$1"
shift || true
source "$SCRIPT_DIR/../helpers/common.sh"
require_root
is_debian || die "This helper targets Debian-family systems using apt."
cd "$PROJECT_DIR"

allow_unsigned="no"
if [[ "${1:-}" == "--allow-unsigned" ]]; then
  allow_unsigned="yes"
fi

log "Preparing NVIDIA modules for target kernel $TARGET_KERNEL"
ensure_target_kernel_and_headers "$TARGET_KERNEL"
print_nvidia_package_matrix
nvidia_pkg_major_warning
install_optional_nvidia_smi_package
ensure_mok_files_or_maybe_unsigned "$allow_unsigned"

log "Installing/reinstalling Debian NVIDIA package stack for target kernel workflow"
apt-get install --reinstall -y \
  nvidia-driver \
  nvidia-kernel-dkms \
  nvidia-driver-libs \
  firmware-misc-nonfree \
  dkms \
  "linux-headers-$TARGET_KERNEL"

log "Removing old installed NVIDIA modules for target kernel $TARGET_KERNEL"
remove_installed_nvidia_modules_for_kernel "$TARGET_KERNEL" || true

nvidia_dkms_version="$(installed_package_version nvidia-kernel-dkms | sed 's/-.*//')"
if [[ -n "$nvidia_dkms_version" ]]; then
  log "Removing old DKMS build state for nvidia/$nvidia_dkms_version on $TARGET_KERNEL"
  dkms remove -m nvidia -v "$nvidia_dkms_version" -k "$TARGET_KERNEL" --all >/dev/null 2>&1 || true
fi

log "Building/installing DKMS modules for target kernel $TARGET_KERNEL"
dkms autoinstall -k "$TARGET_KERNEL"

if [[ "$allow_unsigned" == "no" ]]; then
  log "Signing installed NVIDIA modules for target kernel $TARGET_KERNEL"
  for mod in nvidia nvidia-modeset nvidia-drm nvidia-uvm; do
    sign_installed_module_for_kernel "$TARGET_KERNEL" "$mod"
  done
else
  warn "Skipping module signing for target kernel $TARGET_KERNEL due to --allow-unsigned"
fi

log "Refreshing depmod and initramfs for target kernel $TARGET_KERNEL"
depmod -a "$TARGET_KERNEL"
update-initramfs -u -k "$TARGET_KERNEL"

log "Verifying target kernel result"
if verify_target_kernel_modules "$TARGET_KERNEL" "$([[ "$allow_unsigned" == "no" ]] && echo yes || echo no)"; then
  log "Target kernel verification passed for $TARGET_KERNEL"
else
  die "Target kernel verification failed for $TARGET_KERNEL. Review $LOG_FILE."
fi

cat <<MSG

Target-kernel workflow complete for $TARGET_KERNEL.
Recommended next steps:
- If you have not enrolled MOK yet, reboot and complete MOK enrollment in the blue screen.
- To re-check later, run:
    ./scripts/51-verify-target-kernel.sh $TARGET_KERNEL

Log saved to: $LOG_FILE
MSG
