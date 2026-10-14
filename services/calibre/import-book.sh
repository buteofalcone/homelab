#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"
require_root
load_env

(( $# == 1 )) || die 'Usage: make calibre-import BOOK=/srv/storage/incoming/books/example.pdf'
mountpoint -q /srv/storage || die '/srv/storage is not a mounted filesystem.'
docker container inspect calibre >/dev/null 2>&1 || die 'The calibre container does not exist.'

readonly calibre_image="$(docker inspect calibre --format '{{.Config.Image}}')"
readonly import_managed="${CALIBRE_IMPORT_OFFLINE_MANAGED:-false}"
restart_needed=false

wait_for_calibre() {
  local health
  for _ in {1..48}; do
    health="$(docker inspect calibre --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' 2>/dev/null || true)"
    [[ ${health} == healthy ]] && return 0
    sleep 5
  done
  return 1
}

restart_calibre() {
  cd "${repo_dir}"
  compose --profile books up -d calibre
  wait_for_calibre || die 'Calibre did not become healthy after offline import.'
}

cleanup() {
  if [[ ${restart_needed} == true ]]; then
    restart_calibre || true
  fi
}
trap cleanup EXIT

if [[ ${import_managed} == true ]]; then
  container_running calibre && die 'Managed offline import requires Calibre to be stopped.'
else
  container_running calibre || die 'The calibre container is not running.'
  echo 'STEP_CALIBRE_OFFLINE_STOP'
  compose --profile books stop calibre
  restart_needed=true
fi

readonly incoming_root=/srv/storage/incoming/books
source_path="$(realpath -e -- "$1")" || die 'Input path does not exist.'
if [[ ! -f ${source_path} && ! -d ${source_path} ]]; then
  die 'Input path must be a regular book file or an exploded EPUB directory.'
fi
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

exploded_epub=false
if [[ -d ${source_path} ]]; then
  [[ ${extension} == epub && -s "${source_path}/META-INF/container.xml" ]] \
    || die 'A directory input must be an exploded EPUB with META-INF/container.xml.'
  source_opf="$(find "${source_path}" -type f -iname '*.opf' -print -quit)"
  [[ -n ${source_opf} ]] || die 'Exploded EPUB does not contain an OPF package document.'
  exploded_epub=true
fi

container_source="/incoming/${relative_path}"
if [[ ${exploded_epub} == true ]]; then
  opf_relative="${source_opf#${incoming_root}/}"
  container_source="/incoming/${opf_relative}"
fi
tmp_epub="/tmp/calibre-import-$RANDOM-$RANDOM.epub"
readonly -a run_args=(
  --rm
  --user "${PUID}:${PGID}"
  --env HOME=/tmp
  --volume "${incoming_root}:/incoming:ro"
  --volume /srv/storage/books:/library
)

if [[ ${extension} == epub && ${exploded_epub} == false ]]; then
  docker run "${run_args[@]}" --entrypoint calibredb "${calibre_image}" \
    add --with-library /library "${container_source}"
else
  docker run "${run_args[@]}" --entrypoint /bin/bash "${calibre_image}" \
    -euo pipefail -c '
      source_path="$1"
      output_path="$2"
      ebook-convert "${source_path}" "${output_path}"
      ebook-meta "${output_path}" >/dev/null
      calibredb add --with-library /library "${output_path}"
    ' calibre-import "${container_source}" "${tmp_epub}"
fi

if [[ ${import_managed} == false ]]; then
  echo 'STEP_CALIBRE_OFFLINE_START'
  restart_calibre
  restart_needed=false
fi

echo "CALIBRE_IMPORT_OK ${source_path}"
echo 'The source file remains in incoming; remove or archive it only after checking the imported book.'
