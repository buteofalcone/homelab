#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"

require_root
load_env

readonly calibre_image="${CALIBRE_IMAGE:-lscr.io/linuxserver/calibre@sha256:1e9d545e20af654af9aca439a54cdd3988cf067f64efcd409cc2bc053aeb6d15}"
readonly staging_dir=/srv/storage/incoming/calibre-migration

mountpoint -q /srv/storage || die '/srv/storage is not a mounted filesystem.'
[[ -d ${staging_dir} ]] || die "Missing migration directory: ${staging_dir}"
[[ -s ${staging_dir}/metadata.db ]] || die 'The staged Calibre library does not contain a non-empty metadata.db.'

if find "${staging_dir}" -type l -print -quit | grep -q .; then
  die 'The staged library contains symbolic links. Copy the real files before migration.'
fi

readonly listing_file="$(mktemp)"
trap 'rm -f -- "${listing_file}"' EXIT

docker run --rm \
  --user "${PUID}:${PGID}" \
  --entrypoint calibredb \
  --volume "${staging_dir}:/migration:ro" \
  "${calibre_image}" \
  list --with-library /migration --for-machine > "${listing_file}"

grep -q '^\[' "${listing_file}" || die 'Calibre could not read the staged metadata database.'

readonly book_count="$(awk '{ count += gsub(/"id"[[:space:]]*:/, "") } END { print count + 0 }' "${listing_file}")"
readonly file_count="$(find "${staging_dir}" -type f | wc -l)"
readonly byte_count="$(du -sb "${staging_dir}" | awk '{print $1}')"

(( book_count > 0 )) || die 'The staged Calibre database contains no books.'
(( file_count > 1 )) || die 'The staged Calibre library contains no book files.'

printf 'CALIBRE_MIGRATION_PREFLIGHT_OK books=%s files=%s bytes=%s\n' \
  "${book_count}" "${file_count}" "${byte_count}"
