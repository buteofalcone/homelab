#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"
load_env

(( $# == 1 )) || die 'Usage: make calibre-import BOOK=/srv/storage/incoming/books/example.pdf'
container_running calibre || die 'The calibre container is not running.'
mountpoint -q /srv/storage || die '/srv/storage is not a mounted filesystem.'

readonly incoming_root=/srv/storage/incoming/books
source_path="$(realpath -e -- "$1")" || die 'Input file does not exist.'
[[ -f ${source_path} ]] || die 'Input path is not a regular file.'
case "${source_path}" in
  "${incoming_root}"/*) ;;
  *) die "Input must be inside ${incoming_root}." ;;
esac

relative_path="${source_path#${incoming_root}/}"
extension="${source_path##*.}"
extension="${extension,,}"
case "${extension}" in
  azw3|docx|epub|fb2|html|lit|mobi|odt|pdf|rtf|txt) ;;
  *) die "Unsupported input extension: ${extension}" ;;
esac

container_source="/incoming/${relative_path}"
tmp_epub="/tmp/calibre-import-$RANDOM-$RANDOM.epub"
trap 'docker exec calibre rm -f -- "${tmp_epub}" >/dev/null 2>&1 || true' EXIT

library_id="$(docker exec --user "${PUID}:${PGID}" calibre \
  calibredb list --with-library 'http://127.0.0.1:8081/#-')"
[[ -n ${library_id} && ${library_id} != *$'\n'* ]] || die 'Calibre Content Server did not return exactly one library.'
readonly library_url="http://127.0.0.1:8081/#${library_id}"

if [[ ${extension} == epub ]]; then
  docker exec --user "${PUID}:${PGID}" calibre \
    calibredb add --with-library "${library_url}" "${container_source}"
else
  docker exec --user "${PUID}:${PGID}" calibre \
    ebook-convert "${container_source}" "${tmp_epub}"
  docker exec --user "${PUID}:${PGID}" calibre ebook-meta "${tmp_epub}" >/dev/null
  docker exec --user "${PUID}:${PGID}" calibre \
    calibredb add --with-library "${library_url}" "${tmp_epub}"
fi

echo "CALIBRE_IMPORT_OK ${source_path}"
echo 'The source file remains in incoming; remove or archive it only after checking the imported book.'
