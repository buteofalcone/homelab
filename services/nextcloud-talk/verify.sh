#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"
load_env

container_running nextcloud || die 'The nextcloud container is not running.'

app_list="$(docker exec --user www-data nextcloud php occ app:list --output=json)"
grep -Eq '"enabled"[[:space:]]*:.*"spreed"[[:space:]]*:[[:space:]]*"23\.' <<<"${app_list}" \
  || die 'Nextcloud Talk 23.x is not enabled.'

docker exec --user www-data nextcloud php occ integrity:check-app spreed >/dev/null

talk_commands="$(docker exec --user www-data nextcloud php occ list --raw)"
grep -Fq 'talk:room:create' <<<"${talk_commands}" || die 'Nextcloud Talk OCC commands are unavailable.'

http_status="$(curl -ksS -o /dev/null -w '%{http_code}' "https://nextcloud.${BASE_DOMAIN}/apps/spreed/")"
[[ ${http_status} == 200 || ${http_status} == 302 || ${http_status} == 303 ]] \
  || die "Unexpected Nextcloud Talk route status: ${http_status}"

echo NEXTCLOUD_TALK_VERIFY_OK
