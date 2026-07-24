#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
require_root
load_env

command -v restic >/dev/null 2>&1 || apt-get update && apt-get install -y restic

install -d -m 0700 "$(dirname "${RESTIC_PASSWORD_FILE}")"
install -d -m 0700 "${RESTIC_REPOSITORY}"

if [[ ! -f "${RESTIC_PASSWORD_FILE}" ]]; then
  umask 077
  openssl rand -base64 48 > "${RESTIC_PASSWORD_FILE}"
fi

export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE

if restic snapshots >/dev/null 2>&1; then
  echo "Restic repository already initialized."
else
  restic init
fi

echo "Restic repository: ${RESTIC_REPOSITORY}"
echo "Password file: ${RESTIC_PASSWORD_FILE}"
