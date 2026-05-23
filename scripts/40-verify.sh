#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helpers/common.sh"

log "Verify Secure Boot and module state"
log "Secure Boot: $(secure_boot_state | tr '\n' ' ' | sed 's/  */ /g')"

for mod in nvidia nvidia-modeset nvidia-drm nvidia-uvm; do
  path="$(module_path_or_empty "$mod")"
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
  echo
 done

log "Loaded NVIDIA modules:"
lsmod | grep '^nvidia' || true

log "nvidia-smi:"
if command_exists nvidia-smi; then
  nvidia-smi || true
else
  warn "nvidia-smi not found"
fi

log "Recent relevant kernel messages:"
dmesg -T | grep -Ei 'secure|lockdown|nvidia|module verification|mok|nouveau' | tail -n 200 || true

log "Verification complete. Log saved to $LOG_FILE"
