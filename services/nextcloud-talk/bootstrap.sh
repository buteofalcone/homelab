#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"
load_env

container_running nextcloud || die 'The nextcloud container is not running.'
container_running nextcloud-db || die 'The nextcloud-db container is not running.'

status_json="$(docker exec --user www-data nextcloud php occ status --output=json)"
grep -Eq '"installed"[[:space:]]*:[[:space:]]*true' <<<"${status_json}" || die 'Nextcloud is not installed.'
grep -Eq '"maintenance"[[:space:]]*:[[:space:]]*false' <<<"${status_json}" || die 'Nextcloud is in maintenance mode.'
grep -Eq '"versionstring"[[:space:]]*:[[:space:]]*"33\.' <<<"${status_json}" || die 'This helper expects Nextcloud 33.x.'

app_list="$(docker exec --user www-data nextcloud php occ app:list --output=json)"
if grep -Eq '"spreed"[[:space:]]*:' <<<"${app_list}"; then
  if grep -Eq '"enabled"[[:space:]]*:.*"spreed"[[:space:]]*:' <<<"${app_list}"; then
    echo 'Nextcloud Talk is already enabled.'
  else
    docker exec --user www-data nextcloud php occ app:enable spreed --no-interaction
  fi
else
  docker exec --user www-data nextcloud php occ app:install spreed --no-interaction
fi

"${service_dir}/verify.sh"
echo NEXTCLOUD_TALK_BOOTSTRAP_OK
