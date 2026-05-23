#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helpers/common.sh"

log "Starting diagnostics"
log "OS: $(os_summary)"
log "Kernel: $(current_kernel)"
log "Secure Boot: $(secure_boot_state | tr '\n' ' ' | sed 's/  */ /g')"

log "GPU summary:"
gpu_summary

log "Display manager services:"
systemctl list-unit-files | grep -E 'gdm|sddm|lightdm' || true

log "NVIDIA package installed/candidate versions:"
print_nvidia_package_matrix
printf '%-28s installed=%s candidate=%s\n' "mokutil" "$(installed_package_version mokutil)" "$(apt_candidate_version mokutil || true)"
printf '%-28s installed=%s candidate=%s\n' "openssl" "$(installed_package_version openssl)" "$(apt_candidate_version openssl || true)"

candidate="$(apt_candidate_version nvidia-driver || true)"
if [[ -n "$candidate" && "$candidate" != "(none)" ]]; then
  major="$(version_major "$candidate")"
  if [[ "$major" -lt 570 ]]; then
    warn "Debian candidate nvidia-driver appears older than 570. RTX 5070 Ti / Blackwell may not be supported well or at all."
  fi
else
  warn "No nvidia-driver apt candidate detected. Check apt sources and non-free/non-free-firmware components."
fi

log "Loaded NVIDIA modules:"
lsmod | grep '^nvidia' || true

log "modinfo paths:"
for m in nvidia nvidia-modeset nvidia-drm nvidia-uvm nouveau; do
  echo "$m => $(module_path_or_empty "$m")"
done

log "Installed NVIDIA module file health under /lib/modules/$(uname -r)/updates/dkms:"
for m in nvidia nvidia-modeset nvidia-drm nvidia-uvm nvidia-peermem; do
  p="$(module_install_path "$m" 2>/dev/null || true)"
  if [[ -n "$p" && -e "$p" ]]; then
    echo "$m => $p"
    if xz_module_is_valid "$p"; then
      echo "  xz: ok"
    else
      echo "  xz: CORRUPT"
    fi
    if modinfo_file_works "$p"; then
      echo "  modinfo: ok"
    else
      echo "  modinfo: FAILED"
    fi
  fi
done

log "mokutil enrolled keys:"
if command_exists mokutil; then
  mokutil --list-enrolled 2>/dev/null | sed -n '1,80p' || true
fi

log "Recent kernel messages matching secure/nvidia/mok/lockdown:"
dmesg -T | grep -Ei 'secure|lockdown|nvidia|module verification|mok|nouveau' | tail -n 200 || true

log "journalctl kernel messages matching secure/nvidia/mok/lockdown:"
journalctl -k -b 0 | grep -Ei 'secure|lockdown|nvidia|module verification|mok|nouveau' | tail -n 200 || true

log "nvidia-smi presence/package status:"
print_nvidia_smi_status

log "nvidia-smi runtime check:"
if command_exists nvidia-smi; then
  nvidia-smi || true
else
  warn "nvidia-smi not found. NVIDIA userspace utilities may be missing or split into a separate package."
fi

log "Diagnostics complete. Log saved to $LOG_FILE"
