#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helpers/common.sh"

log "==> Running guided recovery"
run_as_root "$PROJECT_DIR/scripts/25-recover.sh"
