#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"
load_env

container_running calibre || die 'The calibre container is not running.'

docker exec --user "${PUID}:${PGID}" calibre /bin/bash -lc '
  set -Eeuo pipefail
  readonly input=/tmp/calibre-verify.txt
  readonly output=/tmp/calibre-verify.epub
  trap '\''rm -f -- "${input}" "${output}"'\'' EXIT
  printf "%s\n" "Calibre verification" "Temporary conversion test." > "${input}"
  ebook-convert "${input}" "${output}" >/tmp/calibre-verify.log 2>&1
  test -s "${output}"
  ebook-meta "${output}" >/dev/null
  test -s "/config/Calibre Library/metadata.db"
'

gui_status="$(docker exec calibre curl -ksS -o /dev/null -w '%{http_code}' https://127.0.0.1:8181/)"
[[ ${gui_status} == 200 || ${gui_status} == 401 ]] || die "Unexpected Calibre GUI status: ${gui_status}"
docker exec calibre curl -fsS http://127.0.0.1:8081/ >/dev/null

echo CALIBRE_VERIFY_OK
