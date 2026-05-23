#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helpers/common.sh"
require_root
is_debian || die "This helper targets Debian-family systems using apt."

log "Checking installed NVIDIA module files for corruption"
corrupt=0
for m in nvidia nvidia-modeset nvidia-drm nvidia-uvm nvidia-peermem; do
  p="$(module_install_path "$m" 2>/dev/null || true)"
  if [[ -n "$p" && -e "$p" ]]; then
    if ! xz_module_is_valid "$p" || ! modinfo_file_works "$p"; then
      warn "Detected broken installed module: $p"
      corrupt=1
    else
      log "Healthy module file: $p"
    fi
  fi
done

if [[ "$corrupt" -eq 0 ]]; then
  log "No corrupted installed NVIDIA .ko.xz files detected for current kernel."
else
  warn "Removing broken installed NVIDIA module files for current kernel"
  remove_installed_nvidia_modules || true
fi

log "Refreshing package indexes"
apt-get update
log "Package version matrix:"
print_nvidia_package_matrix
nvidia_pkg_major_warning

log "Reinstalling Debian NVIDIA DKMS/userspace stack cleanly"
apt-get install --reinstall -y \
  nvidia-driver \
  nvidia-kernel-dkms \
  nvidia-driver-libs \
  firmware-misc-nonfree \
  dkms \
  linux-headers-$(uname -r)
install_optional_nvidia_smi_package

log "Rebuilding NVIDIA DKMS module for kernel $(uname -r)"
dkms remove -m nvidia -v "$(installed_package_version nvidia-kernel-dkms | sed 's/-.*//')" -k "$(uname -r)" --all >/dev/null 2>&1 || true
dkms autoinstall -k "$(uname -r)"

depmod -a "$(uname -r)"
update-initramfs -u -k all

log "Post-repair verification"
failed=0
for m in nvidia nvidia-modeset nvidia-drm nvidia-uvm; do
  p="$(module_install_path "$m" 2>/dev/null || true)"
  if [[ -n "$p" && -e "$p" ]]; then
    if ! xz_module_is_valid "$p"; then
      warn "xz test still failing for $p"
      failed=1
    fi
    if ! modinfo_file_works "$p"; then
      warn "modinfo still failing for $p"
      failed=1
    fi
  else
    warn "Expected installed module missing: $m"
    failed=1
  fi
done

if ! command_exists nvidia-smi; then
  warn "nvidia-smi is still missing after reinstall. Check whether your Debian apt sources provide a separate nvidia-smi package."
  failed=1
fi

if [[ "$failed" -ne 0 ]]; then
  die "Repair completed with remaining module-file or userspace problems. Review $LOG_FILE."
fi

log "Post-repair nvidia-smi status"
print_nvidia_smi_status

cat <<MSG

Installed NVIDIA module repair complete.
Recommended next steps:
- If Secure Boot is enabled and MOK setup is still needed, run:
    sudo ./scripts/20-create-or-enroll-mok.sh --fresh
- If MOK is already enrolled, run:
    sudo ./scripts/30-sign-nvidia-modules.sh
    ./scripts/40-verify.sh

Log saved to: $LOG_FILE
MSG
