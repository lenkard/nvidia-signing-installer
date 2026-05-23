#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helpers/common.sh"
require_root

cd "$PROJECT_DIR"

if ! command_exists mokutil; then
  die "mokutil is required. Run scripts/10-install-debian-prereqs.sh first."
fi
if ! command_exists openssl; then
  die "openssl is required. Run scripts/10-install-debian-prereqs.sh first."
fi

if [[ ! -f MOK.priv || ! -f MOK.der ]]; then
  log "Creating MOK keypair in $PROJECT_DIR"
  openssl req -new -x509 -newkey rsa:2048 \
    -keyout MOK.priv \
    -outform DER \
    -out MOK.der \
    -nodes -days 36500 \
    -subj "/CN=Local NVIDIA Secure Boot Module Signing/"
  chmod 600 MOK.priv
else
  log "Existing MOK.priv and MOK.der found; reusing them"
fi

log "Importing MOK.der into MOK enrollment queue"
log "You will be asked for a one-time enrollment password by mokutil"
mokutil --import MOK.der

cat <<MSG

Next manual steps:
1. Reboot the machine.
2. In the blue MOK Manager screen choose:
   Enroll MOK -> Continue -> Yes
3. Enter the password you just created.
4. Boot back into Linux.
5. Then run: sudo ./scripts/30-sign-nvidia-modules.sh

Log saved to: $LOG_FILE
MSG
