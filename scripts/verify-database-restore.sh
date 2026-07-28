#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"

require_root
load_env

export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE

command -v restic >/dev/null 2>&1 || die 'Restic is not installed.'
command -v gzip >/dev/null 2>&1 || die 'gzip is not installed.'
command -v docker >/dev/null 2>&1 || die 'Docker is not installed.'
[[ -f ${RESTIC_PASSWORD_FILE} ]] || die "Missing ${RESTIC_PASSWORD_FILE}."
mountpoint -q /srv/storage || die '/srv/storage is not a mounted filesystem.'

readonly timestamp="$(date +%Y%m%d-%H%M%S)"
readonly restore_root="/srv/storage/restores/database-verify-${timestamp}"
readonly nextcloud_dump="${restore_root}/srv/appdata/_backup-dumps/nextcloud.sql.gz"
readonly immich_dump="${restore_root}/srv/appdata/_backup-dumps/immich.sql.gz"
readonly nextcloud_container="homelab-verify-nextcloud-${timestamp}"
readonly immich_container="homelab-verify-immich-${timestamp}"
readonly nextcloud_db_image='postgres:16-alpine'
readonly immich_db_image="${IMMICH_DB_IMAGE:-ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23}"

cleanup() {
  docker rm -f "${nextcloud_container}" "${immich_container}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_for_postgres() {
  local container="$1"
  local user="$2"
  local database="$3"
  local attempt

  for attempt in {1..60}; do
    if docker exec "${container}" pg_isready -U "${user}" -d "${database}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  docker logs --tail=100 "${container}" >&2 || true
  die "temporary PostgreSQL container did not become ready: ${container}"
}

query_scalar() {
  local container="$1"
  local user="$2"
  local database="$3"
  local query="$4"
  docker exec "${container}" psql -X -A -t -v ON_ERROR_STOP=1 -U "${user}" -d "${database}" -c "${query}"
}

install -d -m 0750 "${restore_root}"
restic restore latest \
  --target "${restore_root}" \
  --include /srv/appdata/_backup-dumps/nextcloud.sql.gz \
  --include /srv/appdata/_backup-dumps/immich.sql.gz

[[ -s ${nextcloud_dump} ]] || die 'Nextcloud dump was not restored.'
[[ -s ${immich_dump} ]] || die 'Immich dump was not restored.'
gzip -t "${nextcloud_dump}"
gzip -t "${immich_dump}"

printf 'STEP_NEXTCLOUD_TEMP_DATABASE\n'
docker run -d --rm \
  --name "${nextcloud_container}" \
  --network none \
  --tmpfs /var/lib/postgresql/data:rw,noexec,nosuid,size=1g \
  -e POSTGRES_HOST_AUTH_METHOD=trust \
  -e POSTGRES_DB=nextcloud \
  -e POSTGRES_USER=nextcloud \
  "${nextcloud_db_image}" >/dev/null
wait_for_postgres "${nextcloud_container}" nextcloud nextcloud
docker exec "${nextcloud_container}" \
  psql -X -v ON_ERROR_STOP=1 -U nextcloud -d nextcloud \
  -c 'CREATE ROLE oc_admin;' >/dev/null
gzip -dc "${nextcloud_dump}" | docker exec -i "${nextcloud_container}" \
  psql -X -v ON_ERROR_STOP=1 -U nextcloud -d nextcloud >/dev/null

nextcloud_table_count="$(query_scalar "${nextcloud_container}" nextcloud nextcloud "SELECT count(*) FROM pg_tables WHERE schemaname='public';")"
[[ "${nextcloud_table_count}" =~ ^[0-9]+$ && "${nextcloud_table_count}" -ge 50 ]] \
  || die "Nextcloud import has an unexpected table count: ${nextcloud_table_count}"
for table_name in oc_appconfig oc_users oc_filecache; do
  [[ "$(query_scalar "${nextcloud_container}" nextcloud nextcloud "SELECT to_regclass('public.${table_name}') IS NOT NULL;")" == 't' ]] \
    || die "Nextcloud control table is missing after import: ${table_name}"
done
printf 'OK   Nextcloud dump imported (%s public tables)\n' "${nextcloud_table_count}"

printf 'STEP_IMMICH_TEMP_DATABASE\n'
docker run -d --rm \
  --name "${immich_container}" \
  --network none \
  --tmpfs /var/lib/postgresql/data:rw,noexec,nosuid,size=1g \
  -e POSTGRES_HOST_AUTH_METHOD=trust \
  -e POSTGRES_DB=immich \
  -e POSTGRES_USER=postgres \
  "${immich_db_image}" >/dev/null
wait_for_postgres "${immich_container}" postgres immich
gzip -dc "${immich_dump}" | docker exec -i "${immich_container}" \
  psql -X -v ON_ERROR_STOP=1 -U postgres -d immich >/dev/null

immich_table_count="$(query_scalar "${immich_container}" postgres immich "SELECT count(*) FROM pg_tables WHERE schemaname='public';")"
[[ "${immich_table_count}" =~ ^[0-9]+$ && "${immich_table_count}" -ge 30 ]] \
  || die "Immich import has an unexpected table count: ${immich_table_count}"
for table_name in asset user kysely_migrations; do
  [[ "$(query_scalar "${immich_container}" postgres immich "SELECT to_regclass('public.\"${table_name}\"') IS NOT NULL;")" == 't' ]] \
    || die "Immich control table is missing after import: ${table_name}"
done
printf 'OK   Immich dump imported (%s public tables)\n' "${immich_table_count}"

printf '\nDATABASE_RESTORE_VERIFY_OK %s\n' "${restore_root}"
printf 'The restored compressed dumps are retained; temporary databases are removed automatically.\n'
