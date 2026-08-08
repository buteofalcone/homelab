#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"

require_root
load_env
mountpoint -q /srv/storage || die '/srv/storage is not a mounted filesystem.'

install -d -m 0770 -o "${PUID}" -g "${PGID}" \
  /srv/storage/incoming/google-photos-takeout \
  /srv/storage/incoming/google-photos-takeout/sample \
  /srv/storage/incoming/google-photos-takeout/full

"${service_dir}/install-immich-go.sh"

echo 'IMMICH_MIGRATION_BOOTSTRAP_OK'
echo 'Copy a small representative Takeout sample into Inbox/google-photos-takeout/sample.'
