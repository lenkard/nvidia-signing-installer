#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helpers/common.sh"
require_root
ensure_sign_file
cd "$PROJECT_DIR"

[[ -f MOK.priv && -f MOK.der ]] || die "MOK.priv and MOK.der must exist in $PROJECT_DIR. Run scripts/20-create-or-enroll-mok.sh first."

mods=(nvidia nvidia-modeset nvidia-drm nvidia-uvm)
found_any=0
for mod in "${mods[@]}"; do
  path="$(module_path_or_empty "$mod")"
  if has_module_file "$path"; then
    found_any=1
    log "Signing $mod => $path"
    "$(kernel_headers_path)" sha256 "$PROJECT_DIR/MOK.priv" "$PROJECT_DIR/MOK.der" "$path"
  else
    warn "Module file for $mod not found; skipping"
  fi
done

[[ "$found_any" -eq 1 ]] || die "No NVIDIA module files found. Install the Debian NVIDIA package first."

log "Refreshing initramfs"
update-initramfs -u -k all

cat <<MSG

Signing complete.
Recommended next steps:
- Reboot if desired
- Run: ./scripts/40-verify.sh

Log saved to: $LOG_FILE
MSG
