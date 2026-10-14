#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"

require_root
load_env

export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE

command -v restic >/dev/null 2>&1 || die 'Restic is not installed.'
[[ -f ${RESTIC_PASSWORD_FILE} ]] || die "Missing ${RESTIC_PASSWORD_FILE}."

readonly target_root=/srv/storage/restores
readonly target="${target_root}/restic-smoke-$(date +%Y%m%d-%H%M%S)"

mountpoint -q /srv/storage || die '/srv/storage is not a mounted filesystem.'
install -d -m 0750 "${target}"

restic restore latest \
  --target "${target}" \
  --include /opt/homelab/README.md \
  --include /srv/appdata/_backup-dumps/nextcloud.sql.gz \
  --include /srv/appdata/_backup-dumps/immich.sql.gz

readonly restored_readme="${target}/opt/homelab/README.md"
readonly restored_nextcloud="${target}/srv/appdata/_backup-dumps/nextcloud.sql.gz"
readonly restored_immich="${target}/srv/appdata/_backup-dumps/immich.sql.gz"

[[ -s ${restored_readme} ]] || die 'README.md was not restored.'
[[ -s ${restored_nextcloud} ]] || die 'Nextcloud dump was not restored.'
[[ -s ${restored_immich} ]] || die 'Immich dump was not restored.'

gzip -t "${restored_nextcloud}"
gzip -t "${restored_immich}"

echo 'Restored verification files:'
stat -c 'OK   %n (%s bytes)' \
  "${restored_readme}" \
  "${restored_nextcloud}" \
  "${restored_immich}"

echo
echo "RESTORE_SMOKE_OK ${target}"
echo 'The verification directory is intentionally retained for review.'
