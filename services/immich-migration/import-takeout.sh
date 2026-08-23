#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly secret_file=/etc/homelab/immich-go-api-key
readonly state_dir=/srv/appdata/immich-go
# shellcheck source=storage-guard.sh
source "${service_dir}/storage-guard.sh"
photo_load_config
require_root

mode="${1:-}"
action="${2:-apply}"
[[ ${mode} == sample || ${mode} == full ]] || die 'Usage: import-takeout.sh {sample|full} [dry-run|apply]'
[[ ${action} == dry-run || ${action} == apply ]] || die 'Usage: import-takeout.sh {sample|full} [dry-run|apply]'
photo_assert_takeout
photo_assert_immich_storage
[[ -s ${secret_file} ]] || die "Missing API key: ${secret_file}"
command -v immich-go >/dev/null 2>&1 || die 'immich-go is not installed.'
docker inspect immich-server >/dev/null 2>&1 || die 'Immich server container is unavailable.'

if [[ ${mode} == sample ]]; then
  input_dir="${PHOTO_SAMPLE_DIR}"
  [[ -d ${input_dir} ]] || die "Sample is missing: ${input_dir}"
  "${service_dir}/preflight.sh"
  on_errors=stop
  pause_jobs=false
else
  input_dir="${TAKEOUT_ROOT}"
  on_errors=continue
  pause_jobs=true
  backup_dump=/srv/appdata/_backup-dumps/immich.sql.gz
  [[ -s ${backup_dump} ]] || die "Verified Immich dump is required before full import: ${backup_dump}"
  backup_age="$(( $(date +%s) - $(stat -c %Y "${backup_dump}") ))"
  (( backup_age <= 86400 )) || die 'Immich database dump is older than 24 hours.'
  [[ -s ${PHOTO_AI_ROOT}/manifests/sample-accepted.json ]] ||
    die "Sample acceptance marker is missing: ${PHOTO_AI_ROOT}/manifests/sample-accepted.json"
  source_bytes="$(du -sb "${TAKEOUT_ROOT}" | awk '{print $1}')"
  required_bytes="$(( source_bytes * 3 / 2 + 100 * 1024 * 1024 * 1024 ))"
  available_bytes="$(photo_available_bytes)"
  (( available_bytes >= required_bytes )) ||
    die "Insufficient wd3tb space: available=${available_bytes} required=${required_bytes}"
fi

api_key="$(tr -d '\r\n' < "${secret_file}")"
if (( ${#api_key} < 20 || ${#api_key} > 256 )) || [[ ! ${api_key} =~ ^[A-Za-z0-9_-]+$ ]]; then
  die 'Stored API key format is invalid.'
fi

install -d -m 0700 "${state_dir}"
photo_prepare_logs
photo_rotate_log "${PHOTO_AI_LOG_DIR}/immich-go.log"
config_file="$(mktemp /tmp/immich-go-config.XXXXXX.yaml)"
excluded_album_state="$(mktemp /tmp/immich-excluded-albums.XXXXXX.json)"
trap 'rm -f -- "${config_file}" "${excluded_album_state}"' EXIT
chmod 0600 "${config_file}"
chmod 0600 "${excluded_album_state}"
printf '%s\n' \
  'concurrent-tasks: 2' \
  "on-errors: ${on_errors}" \
  'upload:' \
  "  api-key: '${api_key}'" \
  '  client-timeout: 20m' \
  '  device-uuid: hp-server-google-takeout' \
  '  no-ui: true' \
  '  overwrite: false' \
  "  pause-immich-jobs: ${pause_jobs}" \
  '  server: http://127.0.0.1:2283' \
  '  session-tag: false' \
  '  from-google-photos:' \
  '    include-archived: true' \
  '    include-partner: false' \
  '    include-trashed: false' \
  '    include-unmatched: true' \
  '    include-untitled-albums: false' \
  '    people-tag: true' \
  '    sync-albums: true' \
  '    takeout-tag: true' > "${config_file}"
unset api_key

before_assets="$(photo_asset_count)"
before_albums="$(photo_album_count)"
before_bytes="$(du -sb "${IMMICH_UPLOAD_LOCATION}" | awk '{print $1}')"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
printf '%s mode=%s action=%s event=start assets=%s albums=%s bytes=%s\n' \
  "${timestamp}" "${mode}" "${action}" "${before_assets}" "${before_albums}" "${before_bytes}" >> "${PHOTO_AI_LOG_DIR}/import.log"

command=(immich-go upload from-google-photos --config "${config_file}" --no-ui \
  --log-file "${PHOTO_AI_LOG_DIR}/immich-go.log" --log-level INFO)
[[ ${action} == dry-run ]] && command+=(--dry-run)
command+=("${input_dir}")

exec 9>"${state_dir}/import.lock"
flock -n 9 || die 'Another Takeout import is already running.'
if [[ ${action} == apply ]]; then
  "${service_dir}/excluded-albums.py" snapshot \
    --state-file "${excluded_album_state}" --name 'Без назви'
fi
set +e
"${command[@]}"
exit_code=$?
set -e

if [[ ${action} == apply ]]; then
  set +e
  "${service_dir}/excluded-albums.py" apply \
    --state-file "${excluded_album_state}" --name 'Без назви'
  cleanup_exit=$?
  set -e
  if (( cleanup_exit != 0 && exit_code == 0 )); then
    exit_code=${cleanup_exit}
  fi
fi

after_assets="$(photo_asset_count)"
after_albums="$(photo_album_count)"
after_bytes="$(du -sb "${IMMICH_UPLOAD_LOCATION}" | awk '{print $1}')"
grep -Ei '(^| )(ERR|WRN).*\b(fail|error|missing metadata|unsupported)\b' "${PHOTO_AI_LOG_DIR}/immich-go.log" \
  >> "${PHOTO_AI_LOG_DIR}/failed-assets.log" || true
printf '%s mode=%s action=%s event=finish exit=%s assets_before=%s assets_after=%s albums_before=%s albums_after=%s bytes_before=%s bytes_after=%s\n' \
  "$(date -u +%Y%m%dT%H%M%SZ)" "${mode}" "${action}" "${exit_code}" \
  "${before_assets}" "${after_assets}" "${before_albums}" "${after_albums}" "${before_bytes}" "${after_bytes}" \
  >> "${PHOTO_AI_LOG_DIR}/import.log"

if [[ ${action} == dry-run ]]; then
  [[ ${after_assets} == "${before_assets}" ]] || die 'Dry-run changed the Immich asset count.'
  [[ ${after_albums} == "${before_albums}" ]] || die 'Dry-run changed the Immich album count.'
  [[ ${after_bytes} == "${before_bytes}" ]] || die 'Dry-run changed Immich storage bytes.'
fi
(( exit_code == 0 )) || exit "${exit_code}"
echo "IMMICH_TAKEOUT_IMPORT_OK mode=${mode} action=${action} assets_before=${before_assets} assets_after=${after_assets} albums_before=${before_albums} albums_after=${after_albums}"
