#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"

require_root
load_env

mountpoint -q /srv/storage || die '/srv/storage is not a mounted filesystem.'
container_running qbittorrent || die 'qBittorrent is not running.'
container_running sonarr || die 'Sonarr is not running.'

media_password="$(</etc/homelab/qbittorrent-password)"
docker exec -e QB_USER="${MEDIA_ADMIN_USER:-butenko}" -e QB_PASSWORD="${media_password}" qbittorrent /bin/sh -c '
  rm -f /tmp/qb-verify-cookie
  result="$(curl -sS --cookie-jar /tmp/qb-verify-cookie \
    --header "Referer: http://localhost:8080" \
    --data-urlencode "username=${QB_USER}" --data-urlencode "password=${QB_PASSWORD}" \
    http://127.0.0.1:8080/api/v2/auth/login)"
  [ "${result}" = "Ok." ]
  [ "$(curl -fsS --cookie /tmp/qb-verify-cookie --header "Referer: http://localhost:8080" http://127.0.0.1:8080/api/v2/torrents/info)" = "[]" ]
  rm -f /tmp/qb-verify-cookie
'
unset media_password

grep -Fq '<AuthenticationMethod>External</AuthenticationMethod>' /srv/appdata/sonarr/config.xml \
  || die 'Sonarr external authentication is not configured.'
sonarr_api_key="$(sed -n 's#.*<ApiKey>\([^<]*\)</ApiKey>.*#\1#p' /srv/appdata/sonarr/config.xml)"
[[ -n ${sonarr_api_key} ]] || die 'Sonarr API key is missing.'
[[ "$(docker exec -e SONARR_API_KEY="${sonarr_api_key}" sonarr /bin/sh -c 'curl -fsS -H "X-Api-Key: ${SONARR_API_KEY}" http://127.0.0.1:8989/api/v3/series')" == '[]' ]] \
  || die 'Sonarr already contains series; automatic use is not expected yet.'

curl -fsS --resolve "torrent.${BASE_DOMAIN}:443:127.0.0.1" "https://torrent.${BASE_DOMAIN}/" >/dev/null
sonarr_status="$(curl -sS -o /dev/null -w '%{http_code}' --resolve "sonarr.${BASE_DOMAIN}:443:127.0.0.1" "https://sonarr.${BASE_DOMAIN}/")"
[[ ${sonarr_status} == 401 ]] || die "Unexpected unauthenticated Sonarr status: ${sonarr_status}"

echo MEDIA_AUTOMATION_VERIFY_OK
