#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"
source "${repo_dir}/services/immich-migration/storage-guard.sh"
require_root
load_env
photo_load_config
photo_assert_mount

[[ -n ${PHOTO_AI_DB_PASSWORD:-} && ${PHOTO_AI_DB_PASSWORD} != CHANGE_ME_* ]] || die "Configure PHOTO_AI_DB_PASSWORD."
[[ -n ${PHOTO_AI_API_TOKEN:-} && ${PHOTO_AI_API_TOKEN} != CHANGE_ME_* ]] || die "Configure PHOTO_AI_API_TOKEN."
[[ -n ${IMMICH_AI_API_KEY:-} && ${IMMICH_AI_API_KEY} != CHANGE_ME_* ]] || die "Configure the dedicated IMMICH_AI_API_KEY."

install -d -m 0700 -o 999 -g 999 /srv/appdata/photo-pipeline/postgres
install -d -m 0750 -o "${PUID}" -g "${PGID}" "${PHOTO_AI_LOG_DIR}"
install -m 0644 -o root -g root \
  "${repo_dir}/services/immich-migration/logrotate.conf" /etc/logrotate.d/photo-pipeline
logrotate --debug /etc/logrotate.d/photo-pipeline >/dev/null
echo "PHOTO_AI_BOOTSTRAP_OK"
