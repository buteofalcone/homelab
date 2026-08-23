#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"
source "${service_dir}/storage-guard.sh"
require_root
load_env
photo_load_config

readonly source_dir="${IMMICH_OLD_UPLOAD_LOCATION:-/srv/storage/photos}"
readonly target_dir="${IMMICH_UPLOAD_LOCATION}"
readonly approval="COPY-IMMICH-TO-WD3TB-${WD3TB_UUID}"

photo_assert_mount
[[ -d ${source_dir} ]] || die "Missing current Immich storage: ${source_dir}"
[[ ${source_dir} != "${target_dir}" ]] || die "Source and target are identical."
[[ ${PHOTO_STORAGE_APPROVAL:-} == "${approval}" ]] || die "Set PHOTO_STORAGE_APPROVAL=${approval} after review."
docker inspect immich-server >/dev/null 2>&1 || die "Immich container does not exist."

echo "Creating verified database dump before storage copy."
"${repo_dir}/scripts/database-dumps.sh"
gzip -t /srv/appdata/_backup-dumps/immich.sql.gz

install -d -m 0750 -o butenko -g butenko "${target_dir}"
for directory in upload library thumbs encoded-video profile backups; do
  install -d -m 0750 -o butenko -g butenko "${target_dir}/${directory}"
done

echo "Stopping only Immich server; database and Valkey stay available."
docker stop immich-server
restart_required=true
cleanup() {
  if [[ ${restart_required} == true ]]; then
    docker start immich-server >/dev/null || true
  fi
}
trap cleanup EXIT

rsync -aHAX --numeric-ids --info=stats2 "${source_dir}/" "${target_dir}/"
echo "Verifying copied bytes with checksum dry-run; no files are deleted."
verification="$(rsync -aHAXnc --numeric-ids --out-format='%i %n' "${source_dir}/" "${target_dir}/")"
[[ -z ${verification} ]] || die "Checksum verification found differences; source is preserved."

echo "Recreating only immich-server with the reviewed /data location."
if ! compose --profile immich up -d --no-deps --force-recreate immich-server; then
  echo "Recreate failed; restoring the old /data binding." >&2
  IMMICH_UPLOAD_LOCATION="${source_dir}" compose --profile immich up -d --no-deps --force-recreate immich-server
  die "Storage switch failed; rollback is active."
fi
restart_required=false

actual_source="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' immich-server)"
if [[ ${actual_source} != "${target_dir}" ]]; then
  IMMICH_UPLOAD_LOCATION="${source_dir}" compose --profile immich up -d --no-deps --force-recreate immich-server
  die "Unexpected /data source ${actual_source}; rolled back."
fi
for attempt in {1..30}; do
  curl --fail --silent http://127.0.0.1:2283/api/server/version >/dev/null && break
  (( attempt == 30 )) && {
    IMMICH_UPLOAD_LOCATION="${source_dir}" compose --profile immich up -d --no-deps --force-recreate immich-server
    die "Immich API did not recover; rolled back."
  }
  sleep 2
done
echo "IMMICH_STORAGE_MIGRATION_OK source=${source_dir} target=${target_dir} rollback_preserved=true"
