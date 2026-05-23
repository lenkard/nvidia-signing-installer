#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helpers/common.sh"

log "Verify Secure Boot and module state"
log "Secure Boot: $(secure_boot_state | tr '\n' ' ' | sed 's/  */ /g')"
log "GPU/driver support assessment:"
print_driver_support_assessment

for mod in nvidia nvidia-modeset nvidia-drm nvidia-uvm; do
  path="$(module_path_or_empty "$mod")"
  installed_path="$(module_install_path "$mod" 2>/dev/null || true)"
  echo "=== $mod ==="
  if has_module_file "$path"; then
    echo "path: $path"
    modinfo -F signer "$path" 2>/dev/null || true
    modinfo -F sig_id "$path" 2>/dev/null || true
    modinfo -F sig_key "$path" 2>/dev/null || true
    modinfo -F sig_hashalgo "$path" 2>/dev/null || true
  else
    warn "module file for $mod not found"
  fi
  if [[ -n "$installed_path" && -e "$installed_path" ]]; then
    echo "installed_path: $installed_path"
    if xz_module_is_valid "$installed_path"; then
      echo "xz: ok"
    else
      echo "xz: CORRUPT"
    fi
    if modinfo_file_works "$installed_path"; then
      echo "modinfo: ok"
    else
      echo "modinfo: FAILED"
    fi
  fi
  echo
 done

log "Loaded NVIDIA modules:"
lsmod | grep '^nvidia' || true

log "nvidia-smi presence/package status:"
print_nvidia_smi_status

log "nvidia-smi runtime check:"
if command_exists nvidia-smi; then
  nvidia-smi || true
else
  warn "nvidia-smi not found. NVIDIA userspace utilities may be missing or split into a separate package."
fi

log "Recent relevant kernel messages:"
dmesg -T | grep -Ei 'secure|lockdown|nvidia|module verification|mok|nouveau|not supported by the NVIDIA' | tail -n 200 || true

log "Verification complete. Log saved to $LOG_FILE"
