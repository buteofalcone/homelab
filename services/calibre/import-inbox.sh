#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly incoming_root=/srv/storage/incoming/books

[[ ${EUID} -eq 0 ]] || {
  echo 'Run through make calibre-import-inbox (sudo is applied by Makefile).' >&2
  exit 1
}
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
imported=0
failed=0
for book in "${books[@]}"; do
  echo "STEP_CALIBRE_IMPORT ${book}"
  if "${service_dir}/import-book.sh" "${book}"; then
    ((imported += 1))
  else
    ((failed += 1))
    printf 'ERROR importing %s\n' "${book}" >&2
  fi
done

echo "CALIBRE_INBOX_IMPORT_RESULT imported=${imported} failed=${failed}"
echo 'Source files remain in Inbox/books; archive them after checking the library.'
(( failed == 0 )) || exit 1
echo 'CALIBRE_INBOX_IMPORT_OK'
