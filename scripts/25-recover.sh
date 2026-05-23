#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helpers/common.sh"
require_root

log "Starting recovery flow: purge/reinstall driver + repair installed modules + fresh MOK setup"
"$PROJECT_DIR/scripts/10-install-debian-prereqs.sh"
"$PROJECT_DIR/scripts/15-install-nvidia-driver.sh" --purge-reinstall
"$PROJECT_DIR/scripts/27-repair-installed-modules.sh"
"$PROJECT_DIR/scripts/20-create-or-enroll-mok.sh" --fresh

cat <<MSG

Recovery prep complete.
Next manual step:
- Reboot and complete MOK enrollment in the blue screen
- Then boot back and run:
    sudo ./scripts/30-sign-nvidia-modules.sh
    ./scripts/40-verify.sh

Log saved to: $LOG_FILE
MSG
