#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=storage-guard.sh
source "${service_dir}/storage-guard.sh"
photo_load_config
require_root
photo_assert_takeout

[[ ! -e ${PHOTO_SAMPLE_DIR} ]] || [[ -d ${PHOTO_SAMPLE_DIR} && -z $(find "${PHOTO_SAMPLE_DIR}" -mindepth 1 -print -quit) ]] ||
  die "Sample already exists and will not be overwritten: ${PHOTO_SAMPLE_DIR}"
install -d -m 0750 -o "${PUID}" -g "${PGID}" "${PHOTO_SAMPLE_DIR}"
python3 "${service_dir}/prepare-sample.py" \
  --root "${TAKEOUT_ROOT}" \
  --destination "${PHOTO_SAMPLE_DIR}" \
  --max-bytes "${PHOTO_SAMPLE_MAX_BYTES:-2147483648}" \
  --max-media "${PHOTO_SAMPLE_MAX_MEDIA:-300}"
chown -R "${PUID}:${PGID}" "${PHOTO_SAMPLE_DIR}"
find "${PHOTO_SAMPLE_DIR}" -type d -exec chmod 0750 {} +
find "${PHOTO_SAMPLE_DIR}" -type f -exec chmod 0640 {} +
echo "IMMICH_TAKEOUT_SAMPLE_READY path=${PHOTO_SAMPLE_DIR}"
