#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"

require_root
load_env

readonly calibre_image="${CALIBRE_IMAGE:-lscr.io/linuxserver/calibre@sha256:1e9d545e20af654af9aca439a54cdd3988cf067f64efcd409cc2bc053aeb6d15}"
readonly staging_dir=/srv/storage/incoming/calibre-merge
readonly library_dir=/srv/storage/books
readonly timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
readonly previous_dir="/srv/storage/books.before-calibre-merge-${timestamp}"
readonly failed_dir="/srv/storage/calibre-merge-failed-${timestamp}"
readonly completed_dir="/srv/storage/incoming/calibre-merge.completed-${timestamp}"
export_dir=''

cleanup() {
  case "${export_dir}" in
    /srv/storage/incoming/.calibre-merge-export.*)
      rm -rf -- "${export_dir}"
      ;;
  esac
}
trap cleanup EXIT

book_count() {
  python3 - "$1" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
count = connection.execute("SELECT count(*) FROM books").fetchone()[0]
connection.close()
print(count)
PY
}

mountpoint -q /srv/storage || die '/srv/storage is not a mounted filesystem.'
"${service_dir}/migration-preflight.sh" "${staging_dir}"
[[ -d ${library_dir} ]] || die "Missing current Calibre library: ${library_dir}"
for path in "${previous_dir}" "${failed_dir}" "${completed_dir}"; do
  [[ ! -e ${path} ]] || die "Safety target already exists: ${path}"
done

source_books="$(book_count "${staging_dir}/metadata.db")"
current_books="$(book_count "${library_dir}/metadata.db")"

echo
echo "Current live library: ${current_books} books"
echo "Additional staged library: ${source_books} books"
echo "Rollback copy will be: ${previous_dir}"
echo 'Duplicate title/author records keep existing formats and add only missing formats.'
read -r -p 'Type MERGE_CALIBRE to continue: ' confirmation
[[ ${confirmation} == MERGE_CALIBRE ]] || die 'Merge cancelled.'

rollback_required=0
calibre_stopped=0
rollback() {
  local exit_code=$?
  trap - ERR INT TERM
  if (( rollback_required == 1 )); then
    echo 'Calibre merge failed; restoring the pre-merge library.' >&2
    compose --profile books stop calibre >/dev/null 2>&1 || true
    if [[ -d ${library_dir} ]]; then
      mv -- "${library_dir}" "${failed_dir}" || true
    fi
    if [[ -d ${previous_dir} ]]; then
      mv -- "${previous_dir}" "${library_dir}" || true
    fi
    if [[ -d ${completed_dir} ]]; then
      rmdir -- "${staging_dir}" >/dev/null 2>&1 || true
      if [[ ! -e ${staging_dir} ]]; then
        mv -- "${completed_dir}" "${staging_dir}" || true
      fi
    fi
  fi
  if (( calibre_stopped == 1 )); then
    compose --profile books up -d calibre >/dev/null 2>&1 || true
  fi
  cleanup
  exit "${exit_code}"
}
trap rollback ERR INT TERM

cd "${repo_dir}"
compose --profile books stop calibre
calibre_stopped=1

cp -a --reflink=auto -- "${library_dir}" "${previous_dir}"
rollback_required=1
export_dir="$(mktemp -d /srv/storage/incoming/.calibre-merge-export.XXXXXX)"
chown -R "${PUID}:${PGID}" "${export_dir}"

docker run --rm \
  --user "${PUID}:${PGID}" \
  --env CALIBRE_CONFIG_DIRECTORY=/tmp/calibre-config \
  --entrypoint calibredb \
  --volume "${staging_dir}:/source:rw" \
  --volume "${export_dir}:/export:rw" \
  "${calibre_image}" \
  export --with-library /source --all --to-dir /export --progress

docker run --rm \
  --user "${PUID}:${PGID}" \
  --env CALIBRE_CONFIG_DIRECTORY=/tmp/calibre-config \
  --entrypoint calibredb \
  --volume "${library_dir}:/target:rw" \
  --volume "${export_dir}:/export:ro" \
  "${calibre_image}" \
  add --with-library /target --recurse --one-book-per-directory \
  --automerge ignore /export

merged_books="$(book_count "${library_dir}/metadata.db")"
(( merged_books >= current_books )) || die 'Merged library book count decreased unexpectedly.'

mv -- "${staging_dir}" "${completed_dir}"
install -d -m 0770 -o "${PUID}" -g "${PGID}" "${staging_dir}"
compose --profile books up -d calibre

for attempt in {1..48}; do
  calibre_health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' calibre 2>/dev/null || true)"
  if [[ ${calibre_health} == healthy ]]; then
    rollback_required=0
    calibre_stopped=0
    trap - ERR INT TERM
    printf 'CALIBRE_LIBRARY_MERGE_OK before=%s source=%s after=%s rollback=%s staged_copy=%s\n' \
      "${current_books}" "${source_books}" "${merged_books}" "${previous_dir}" "${completed_dir}"
    exit 0
  fi
  sleep 5
done

compose --profile books logs --tail=100 calibre >&2
echo 'Merged Calibre library did not become healthy within 240 seconds.' >&2
false
