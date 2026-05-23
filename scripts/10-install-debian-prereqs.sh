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
  linux-headers-$(uname -r) \
  firmware-misc-nonfree

candidate="$(apt_candidate_version nvidia-driver || true)"
if [[ -z "$candidate" || "$candidate" == "(none)" ]]; then
  warn "No nvidia-driver candidate found. Ensure your apt sources include contrib/non-free/non-free-firmware as appropriate."
else
  log "nvidia-driver candidate: $candidate"
  major="$(version_major "$candidate")"
  if [[ "$major" -lt 570 ]]; then
    warn "Candidate is older than 570. Blackwell / RTX 5070 Ti may still fail even after Secure Boot signing."
  fi
fi

log "Done. Log saved to $LOG_FILE"
