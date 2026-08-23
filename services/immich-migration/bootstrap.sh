#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"

require_root
# shellcheck source=storage-guard.sh
source "${service_dir}/storage-guard.sh"
photo_load_config
photo_assert_mount

install -d -m 0750 -o "${PUID}" -g "${PGID}" \
  "${PHOTO_AI_ROOT}/manifests" \
  "${PHOTO_AI_ROOT}/cache" \
  "${PHOTO_AI_ROOT}/exports" \
  "${PHOTO_AI_LOG_DIR}"
photo_prepare_logs

"${service_dir}/install-immich-go.sh"

echo 'IMMICH_MIGRATION_BOOTSTRAP_OK'
echo 'Run make immich-takeout-inspect, then make immich-takeout-sample.'
