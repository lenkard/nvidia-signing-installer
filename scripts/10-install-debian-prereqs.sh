#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helpers/common.sh"
require_root

is_debian || die "This helper currently targets Debian-family systems using apt."

log "Installing Debian prerequisites"
apt-get update
apt-get install -y \
  mokutil \
  openssl \
  dkms \
  whiptail \
  linux-headers-$(uname -r) \
  firmware-misc-nonfree

candidate="$(apt_candidate_version nvidia-driver || true)"
if [[ -z "$candidate" || "$candidate" == "(none)" ]]; then
  warn "No nvidia-driver candidate found. Ensure your apt sources include contrib/non-free/non-free-firmware as appropriate."
else
  log "nvidia-driver candidate: $candidate"
  nvidia_pkg_major_warning
fi

log "Done. Log saved to $LOG_FILE"
