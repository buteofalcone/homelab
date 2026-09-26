#!/usr/bin/env bash

# Shared storage safety checks. This file is sourced by migration commands.

photo_load_config() {
  local guard_service_dir guard_repo_dir
  guard_service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  guard_repo_dir="$(cd "${guard_service_dir}/../.." && pwd)"
  # shellcheck source=../../scripts/lib.sh
  source "${guard_repo_dir}/scripts/lib.sh"
  load_env

  WD3TB_UUID="${WD3TB_UUID:-6a4f504f-0103-4015-84b2-48bfa947d5b7}"
  WD3TB_MOUNT="${WD3TB_MOUNT:-/srv/storage/wd3tb}"
  TAKEOUT_ROOT="${TAKEOUT_ROOT:-${WD3TB_MOUNT}/takeout-extracted/Takeout}"
  IMMICH_UPLOAD_LOCATION="${IMMICH_UPLOAD_LOCATION:-${WD3TB_MOUNT}/immich}"
  PHOTO_AI_ROOT="${PHOTO_AI_ROOT:-${WD3TB_MOUNT}/ai}"
  PHOTO_AI_LOG_DIR="${PHOTO_AI_LOG_DIR:-${PHOTO_AI_ROOT}/logs}"
  PHOTO_SAMPLE_DIR="${PHOTO_SAMPLE_DIR:-${PHOTO_AI_ROOT}/cache/takeout-sample}"
  export WD3TB_UUID WD3TB_MOUNT TAKEOUT_ROOT IMMICH_UPLOAD_LOCATION
  export PHOTO_AI_ROOT PHOTO_AI_LOG_DIR PHOTO_SAMPLE_DIR
}

photo_assert_mount() {
  local actual_uuid actual_target
  mountpoint -q "${WD3TB_MOUNT}" || die "Required storage is not mounted: ${WD3TB_MOUNT}"
  actual_target="$(findmnt -n -o TARGET --target "${WD3TB_MOUNT}")"
  [[ ${actual_target} == "${WD3TB_MOUNT}" ]] || die "${WD3TB_MOUNT} is not the mount root (actual: ${actual_target})."
  actual_uuid="$(findmnt -n -o UUID --target "${WD3TB_MOUNT}")"
  [[ ${actual_uuid} == "${WD3TB_UUID}" ]] || die "Unexpected UUID at ${WD3TB_MOUNT}: ${actual_uuid:-missing}"
}

photo_assert_takeout() {
  photo_assert_mount
  [[ -d ${TAKEOUT_ROOT} ]] || die "Takeout root is missing: ${TAKEOUT_ROOT}"
  find "${TAKEOUT_ROOT}" -mindepth 1 -maxdepth 2 -type d -iname 'Google *' -print -quit | grep -q . ||
    die "No Google Photos directory was found under ${TAKEOUT_ROOT}."
}

photo_assert_immich_storage() {
  photo_assert_mount
  [[ -d ${IMMICH_UPLOAD_LOCATION} ]] || die "Immich storage is missing: ${IMMICH_UPLOAD_LOCATION}"
  [[ $(findmnt -n -o UUID --target "${IMMICH_UPLOAD_LOCATION}") == "${WD3TB_UUID}" ]] ||
    die "Immich storage is not on wd3tb: ${IMMICH_UPLOAD_LOCATION}"
}

photo_available_bytes() {
  stat -f -c '%a %S' "${WD3TB_MOUNT}" | awk '{print $1 * $2}'
}

photo_rotate_log() {
  local path="$1" timestamp
  [[ -s ${path} ]] || return 0
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  mv -- "${path}" "${path}.${timestamp}"
  gzip -f -- "${path}.${timestamp}"
}

photo_prepare_logs() {
  install -d -m 0750 -o "${PUID}" -g "${PGID}" "${PHOTO_AI_LOG_DIR}"
  touch "${PHOTO_AI_LOG_DIR}/import.log" \
    "${PHOTO_AI_LOG_DIR}/immich-go.log" \
    "${PHOTO_AI_LOG_DIR}/ai-worker.log" \
    "${PHOTO_AI_LOG_DIR}/failed-assets.log" \
    "${PHOTO_AI_LOG_DIR}/verification.log"
  chown "${PUID}:${PGID}" "${PHOTO_AI_LOG_DIR}"/*.log
  chmod 0640 "${PHOTO_AI_LOG_DIR}"/*.log
}

photo_asset_count() {
  docker exec immich-database psql -U postgres -d immich -Atc 'SELECT count(*) FROM asset'
}

photo_album_count() {
  docker exec immich-database psql -U postgres -d immich -Atc 'SELECT count(*) FROM album'
}
