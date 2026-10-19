#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"

require_root
load_env

readonly calibre_image="${CALIBRE_IMAGE:-lscr.io/linuxserver/calibre@sha256:1e9d545e20af654af9aca439a54cdd3988cf067f64efcd409cc2bc053aeb6d15}"
readonly staging_dir="${1:-/srv/storage/incoming/calibre-migration}"

case "${staging_dir}" in
  /srv/storage/incoming/calibre-migration|/srv/storage/incoming/calibre-merge) ;;
  *) die "Unsupported Calibre staging directory: ${staging_dir}" ;;
esac

mountpoint -q /srv/storage || die '/srv/storage is not a mounted filesystem.'
[[ -d ${staging_dir} ]] || die "Missing migration directory: ${staging_dir}"
[[ -s ${staging_dir}/metadata.db ]] || die 'The staged Calibre library does not contain a non-empty metadata.db.'

if find "${staging_dir}" -type l -print -quit | grep -q .; then
  die 'The staged library contains symbolic links. Copy the real files before migration.'
fi

readonly listing_file="$(mktemp)"
readonly verification_library="$(mktemp -d)"
trap 'rm -f -- "${listing_file}"; rm -rf -- "${verification_library}"' EXIT

# Calibre probes the library root with a temporary file even for a list
# operation. Keep the staged library immutable and run that probe against a
# disposable writable copy of the database instead.
cp --reflink=auto --preserve=timestamps \
  "${staging_dir}/metadata.db" "${verification_library}/metadata.db"
chown -R "${PUID}:${PGID}" "${verification_library}"

docker run --rm \
  --user "${PUID}:${PGID}" \
  --env CALIBRE_CONFIG_DIRECTORY=/tmp/calibre-config \
  --entrypoint calibredb \
  --volume "${verification_library}:/verification:rw" \
  "${calibre_image}" \
  list --with-library /verification --for-machine > "${listing_file}"

grep -q '^\[' "${listing_file}" || die 'Calibre could not read the staged metadata database.'

readonly book_count="$(awk '{ count += gsub(/"id"[[:space:]]*:/, "") } END { print count + 0 }' "${listing_file}")"
readonly file_count="$(find "${staging_dir}" -type f | wc -l)"
readonly byte_count="$(du -sb "${staging_dir}" | awk '{print $1}')"

(( book_count > 0 )) || die 'The staged Calibre database contains no books.'
(( file_count > 1 )) || die 'The staged Calibre library contains no book files.'

printf 'CALIBRE_MIGRATION_PREFLIGHT_OK books=%s files=%s bytes=%s\n' \
  "${book_count}" "${file_count}" "${byte_count}"
