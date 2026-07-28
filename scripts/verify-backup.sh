#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"

require_root
load_env

export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE

command -v restic >/dev/null 2>&1 || die 'Restic is not installed.'
[[ -f ${RESTIC_PASSWORD_FILE} ]] || die "Missing ${RESTIC_PASSWORD_FILE}."

echo 'Recent Restic snapshots:'
restic snapshots --latest 5

echo
echo 'Checking Restic repository metadata and pack integrity:'
restic check

echo
echo 'Checking PostgreSQL dumps:'
for dump in nextcloud.sql.gz immich.sql.gz; do
  path="/srv/appdata/_backup-dumps/${dump}"
  [[ -s ${path} ]] || die "Missing or empty database dump: ${path}"
  gzip -t "${path}"
  stat -c 'OK   %n (%s bytes, modified %y)' "${path}"
done

echo
echo 'RESTIC_AUDIT_OK'
