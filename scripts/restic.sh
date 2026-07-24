#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
require_root
load_env

command -v restic >/dev/null 2>&1 || die "Restic is not installed."
[[ -f "${RESTIC_PASSWORD_FILE}" ]] || die "Missing ${RESTIC_PASSWORD_FILE}. Run restic-init.sh."

export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE
exec restic "$@"
