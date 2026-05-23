#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helpers/common.sh"

cat <<'MSG'
This wrapper runs the common guided flow:
1. Diagnostics
2. Install Debian prerequisites (sudo)
3. Optionally install Debian-packaged NVIDIA driver (sudo)
4. Create/import MOK (sudo)
5. Stop and ask you to reboot + complete MOK enrollment
6. After reboot, run signing and verification manually
MSG

action() { log "==> $*"; }

action "Running diagnostics"
"$PROJECT_DIR/scripts/00-diagnose.sh"

action "Installing prerequisites"
sudo "$PROJECT_DIR/scripts/10-install-debian-prereqs.sh"

read -r -p "Install Debian-packaged nvidia-driver now? [y/N] " reply
if [[ "$reply" =~ ^[Yy]$ ]]; then
  action "Installing Debian-packaged NVIDIA driver"
  sudo "$PROJECT_DIR/scripts/15-install-nvidia-driver.sh"
else
  log "Skipping Debian-packaged NVIDIA driver install"
fi

action "Creating/importing MOK"
sudo "$PROJECT_DIR/scripts/20-create-or-enroll-mok.sh"

cat <<MSG

The next step is manual:
- Reboot now
- Complete MOK enrollment in the blue screen
- Boot back into Linux
- Then run:
    sudo ./scripts/30-sign-nvidia-modules.sh
    ./scripts/40-verify.sh

MSG
