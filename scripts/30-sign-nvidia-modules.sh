#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helpers/common.sh"
require_root
cd "$PROJECT_DIR"

ensure_mok_files_or_maybe_unsigned no

mods=(nvidia nvidia-modeset nvidia-drm nvidia-uvm)
found_any=0
for mod in "${mods[@]}"; do
  if sign_installed_module_for_kernel "$TARGET_KERNEL" "$mod"; then
    found_any=1
    log "Signed installed module for $mod on kernel $TARGET_KERNEL"
  fi
done

[[ "$found_any" -eq 1 ]] || die "No installed NVIDIA module files found for kernel $TARGET_KERNEL."

log "Refreshing depmod and initramfs for $TARGET_KERNEL"
depmod -a "$TARGET_KERNEL"
update-initramfs -u -k "$TARGET_KERNEL"

cat <<MSG

Signing complete for kernel $TARGET_KERNEL.
Recommended next steps:
- Reboot if desired
- Run: TARGET_KERNEL=$TARGET_KERNEL ./scripts/40-verify.sh

Log saved to: $LOG_FILE
MSG
