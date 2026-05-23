#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helpers/common.sh"
require_root
is_debian || die "This helper targets Debian-family systems using apt."

candidate="$(apt_candidate_version nvidia-driver || true)"
if [[ -z "$candidate" || "$candidate" == "(none)" ]]; then
  die "No nvidia-driver candidate found. Check apt sources for contrib/non-free/non-free-firmware."
fi
major="$(version_major "$candidate")"
log "Debian nvidia-driver candidate: $candidate"
if [[ "$major" -lt 570 ]]; then
  warn "Candidate appears older than 570. RTX 5070 Ti / Blackwell may still not work after install."
fi

apt-get update
apt-get install -y nvidia-driver firmware-misc-nonfree dkms linux-headers-$(uname -r)

cat <<MSG

Install complete.
If Secure Boot is enabled, continue with:
  sudo ./scripts/20-create-or-enroll-mok.sh

MSG
