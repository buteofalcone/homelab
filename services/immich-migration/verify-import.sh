#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=storage-guard.sh
source "${service_dir}/storage-guard.sh"
photo_load_config
require_root
photo_assert_takeout
photo_assert_immich_storage
photo_prepare_logs

args=(
  --takeout-report "${PHOTO_AI_ROOT}/manifests/takeout-report.json"
  --import-log "${PHOTO_AI_LOG_DIR}/import.log"
  --immich-go-log "${PHOTO_AI_LOG_DIR}/immich-go.log"
  --output-dir "${PHOTO_AI_ROOT}/manifests"
)
if [[ ${1:-} == --accept-sample ]]; then
  args+=(--accept-sample)
elif [[ -n ${1:-} ]]; then
  die 'Usage: verify-import.sh [--accept-sample]'
fi
python3 "${service_dir}/verify-import.py" "${args[@]}" 2>&1 | tee -a "${PHOTO_AI_LOG_DIR}/verification.log"
chown "${PUID}:${PGID}" "${PHOTO_AI_ROOT}/manifests"/verification-* \
  "${PHOTO_AI_ROOT}/manifests"/sample-accepted.json 2>/dev/null || true
chmod 0640 "${PHOTO_AI_ROOT}/manifests"/verification-* \
  "${PHOTO_AI_ROOT}/manifests"/sample-accepted.json 2>/dev/null || true
echo "IMMICH_IMPORT_VERIFY_OK output=${PHOTO_AI_ROOT}/manifests/verification-report.json"
