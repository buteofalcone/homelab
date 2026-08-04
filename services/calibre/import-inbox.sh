#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd -P)"
source "${repo_dir}/scripts/lib.sh"
require_root
load_env
readonly incoming_root=/srv/storage/incoming/books

[[ -d ${incoming_root} ]] || {
  echo "Missing Calibre inbox: ${incoming_root}" >&2
  exit 1
}

mapfile -d '' books < <(
  find "${incoming_root}" \
    \( -type d -iname '*.epub' -print0 -prune \) -o \
    \( -type f \
       \( -iname '*.azw3' -o -iname '*.docx' -o -iname '*.epub' \
          -o -iname '*.fb2' -o -iname '*.html' -o -iname '*.lit' \
          -o -iname '*.mobi' -o -iname '*.odt' -o -iname '*.pdf' \
          -o -iname '*.rtf' -o -iname '*.txt' \) \
       -print0 \) | sort -z
)

if (( ${#books[@]} == 0 )); then
  echo "No supported books found under ${incoming_root}."
  exit 0
fi

echo "CALIBRE_INBOX_FOUND count=${#books[@]}"
container_running calibre || die 'The calibre container is not running.'

restart_needed=true
restart_calibre() {
  cd "${repo_dir}"
  compose --profile books up -d calibre
  local health
  for _ in {1..48}; do
    health="$(docker inspect calibre --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' 2>/dev/null || true)"
    [[ ${health} == healthy ]] && return 0
    sleep 5
  done
  return 1
}
cleanup() {
  if [[ ${restart_needed} == true ]]; then
    restart_calibre || true
  fi
}
trap cleanup EXIT

echo 'STEP_CALIBRE_OFFLINE_STOP'
compose --profile books stop calibre

imported=0
failed=0
for book in "${books[@]}"; do
  echo "STEP_CALIBRE_IMPORT ${book}"
  if CALIBRE_IMPORT_OFFLINE_MANAGED=true "${service_dir}/import-book.sh" "${book}"; then
    ((imported += 1))
  else
    ((failed += 1))
    printf 'ERROR importing %s\n' "${book}" >&2
  fi
done

echo 'STEP_CALIBRE_OFFLINE_START'
restart_calibre || die 'Calibre did not become healthy after batch import.'
restart_needed=false

echo "CALIBRE_INBOX_IMPORT_RESULT imported=${imported} failed=${failed}"
echo 'Source files remain in Inbox/books; archive them after checking the library.'
(( failed == 0 )) || exit 1
echo 'CALIBRE_INBOX_IMPORT_OK'
