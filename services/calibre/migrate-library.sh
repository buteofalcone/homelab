#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"

require_root
load_env

readonly staging_dir=/srv/storage/incoming/calibre-migration
readonly library_dir=/srv/storage/books
readonly timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
readonly previous_dir="/srv/storage/books.before-calibre-migration-${timestamp}"
readonly failed_dir="/srv/storage/calibre-migration-failed-${timestamp}"

mountpoint -q /srv/storage || die '/srv/storage is not a mounted filesystem.'
"${service_dir}/migration-preflight.sh"
[[ -d ${library_dir} ]] || die "Missing current Calibre library: ${library_dir}"
[[ ! -e ${previous_dir} ]] || die "Backup target already exists: ${previous_dir}"
[[ ! -e ${failed_dir} ]] || die "Failure target already exists: ${failed_dir}"

echo
echo "Current library will be preserved as: ${previous_dir}"
echo "Staged library will become: ${library_dir}"
read -r -p 'Type MIGRATE_CALIBRE to continue: ' confirmation
[[ ${confirmation} == MIGRATE_CALIBRE ]] || die 'Migration cancelled.'

cd "${repo_dir}"
compose --profile books stop calibre

rollback_required=1
rollback() {
  local exit_code=$?
  if (( rollback_required == 1 )); then
    echo 'Migration failed; restoring the previous Calibre library.' >&2
    compose --profile books stop calibre >/dev/null 2>&1 || true
    if [[ -d ${library_dir} ]]; then
      mv -- "${library_dir}" "${failed_dir}" || true
    fi
    if [[ -d ${previous_dir} ]]; then
      mv -- "${previous_dir}" "${library_dir}" || true
    fi
    install -d -m 0770 -o "${PUID}" -g "${PGID}" "${staging_dir}"
    compose --profile books up -d calibre >/dev/null 2>&1 || true
  fi
  exit "${exit_code}"
}
trap rollback ERR INT TERM

mv -- "${library_dir}" "${previous_dir}"
mv -- "${staging_dir}" "${library_dir}"
install -d -m 0770 -o "${PUID}" -g "${PGID}" "${staging_dir}"

compose --profile books up -d calibre

for attempt in {1..48}; do
  calibre_health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' calibre 2>/dev/null || true)"
  if [[ ${calibre_health} == healthy ]]; then
    rollback_required=0
    trap - ERR INT TERM
    printf 'CALIBRE_LIBRARY_MIGRATION_OK previous=%s\n' "${previous_dir}"
    exit 0
  fi
  sleep 5
done

compose --profile books logs --tail=100 calibre >&2
echo 'Migrated Calibre library did not become healthy within 240 seconds.' >&2
false
