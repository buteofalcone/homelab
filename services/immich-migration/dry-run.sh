#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly sample_dir=/srv/storage/incoming/google-photos-takeout/sample
readonly secret_file=/etc/homelab/immich-go-api-key
readonly state_dir=/srv/appdata/immich-go

[[ ${EUID} -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
[[ -s ${secret_file} ]] || { echo "Missing API key: ${secret_file}" >&2; exit 1; }
command -v immich-go >/dev/null 2>&1 || { echo 'immich-go is not installed.' >&2; exit 1; }

"${service_dir}/preflight.sh"

api_key="$(tr -d '\r\n' < "${secret_file}")"
if (( ${#api_key} < 20 || ${#api_key} > 256 )) || [[ ! ${api_key} =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo 'Stored API key format is invalid.' >&2
  exit 1
fi

install -d -m 0700 "${state_dir}" "${state_dir}/logs"
config_file="$(mktemp /tmp/immich-go-config.XXXXXX.yaml)"
trap 'rm -f -- "${config_file}"' EXIT
chmod 0600 "${config_file}"
printf '%s\n' \
  'concurrent-tasks: 2' \
  'on-errors: stop' \
  'upload:' \
  "  api-key: '${api_key}'" \
  '  client-timeout: 20m' \
  '  device-uuid: hp-server-google-takeout' \
  '  no-ui: true' \
  '  overwrite: false' \
  '  pause-immich-jobs: false' \
  '  server: http://127.0.0.1:2283' \
  '  session-tag: true' \
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

asset_count() {
  docker exec immich-database psql -U postgres -d immich -Atc 'SELECT count(*) FROM asset'
}
album_count() {
  docker exec immich-database psql -U postgres -d immich -Atc 'SELECT count(*) FROM album'
}

before_assets="$(asset_count)"
before_albums="$(album_count)"
before_bytes="$(du -sb /srv/storage/photos | awk '{print $1}')"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
log_file="${state_dir}/logs/google-photos-dry-run-${timestamp}.log"

shopt -s nullglob
archives=("${sample_dir}"/*.zip)
if (( ${#archives[@]} > 0 )); then
  inputs=("${archives[@]}")
else
  inputs=("${sample_dir}")
fi

immich-go upload from-google-photos \
  --config "${config_file}" \
  --dry-run \
  --no-ui \
  --log-file "${log_file}" \
  --log-level INFO \
  "${inputs[@]}"

after_assets="$(asset_count)"
after_albums="$(album_count)"
after_bytes="$(du -sb /srv/storage/photos | awk '{print $1}')"

[[ ${after_assets} == "${before_assets}" ]] || { echo 'Dry-run changed the Immich asset count.' >&2; exit 1; }
[[ ${after_albums} == "${before_albums}" ]] || { echo 'Dry-run changed the Immich album count.' >&2; exit 1; }
[[ ${after_bytes} == "${before_bytes}" ]] || { echo 'Dry-run changed /srv/storage/photos.' >&2; exit 1; }

echo "IMMICH_TAKEOUT_DRY_RUN_OK assets=${after_assets} albums=${after_albums} photos_bytes=${after_bytes} log=${log_file}"
