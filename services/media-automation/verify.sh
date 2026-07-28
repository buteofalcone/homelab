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
container_running prowlarr || die 'Prowlarr is not running.'

media_password="$(</etc/homelab/qbittorrent-password)"
docker exec -e QB_USER="${MEDIA_ADMIN_USER:-butenko}" -e QB_PASSWORD="${media_password}" qbittorrent /bin/sh -c '
  rm -f /tmp/qb-verify-cookie
  status="$(curl -sS --output /tmp/qb-verify-body --write-out "%{http_code}" --cookie-jar /tmp/qb-verify-cookie \
    --header "Referer: http://localhost:8080" \
    --data-urlencode "username=${QB_USER}" --data-urlencode "password=${QB_PASSWORD}" \
    http://localhost:8080/api/v2/auth/login)"
  body="$(cat /tmp/qb-verify-body)"
  rm -f /tmp/qb-verify-body
  [ "${status}" = 204 ] || { [ "${status}" = 200 ] && [ "${body}" = "Ok." ]; }
  [ "$(curl -fsS --cookie /tmp/qb-verify-cookie --header "Referer: http://localhost:8080" http://localhost:8080/api/v2/torrents/info)" = "[]" ]
  rm -f /tmp/qb-verify-cookie
'
unset media_password

grep -Fq '<AuthenticationMethod>External</AuthenticationMethod>' /srv/appdata/sonarr/config.xml \
  || die 'Sonarr external authentication is not configured.'
sonarr_api_key="$(sed -n 's#.*<ApiKey>\([^<]*\)</ApiKey>.*#\1#p' /srv/appdata/sonarr/config.xml)"
[[ -n ${sonarr_api_key} ]] || die 'Sonarr API key is missing.'
[[ "$(docker exec -e SONARR_API_KEY="${sonarr_api_key}" sonarr /bin/sh -c 'curl -fsS -H "X-Api-Key: ${SONARR_API_KEY}" http://127.0.0.1:8989/api/v3/series')" == '[]' ]] \
  || die 'Sonarr already contains series; automatic use is not expected yet.'

grep -Fq '<AuthenticationMethod>External</AuthenticationMethod>' /srv/appdata/prowlarr/config.xml \
  || die 'Prowlarr external authentication is not configured.'
prowlarr_api_key="$(sed -n 's#.*<ApiKey>\([^<]*\)</ApiKey>.*#\1#p' /srv/appdata/prowlarr/config.xml)"
[[ -n ${prowlarr_api_key} ]] || die 'Prowlarr API key is missing.'
docker exec -e PROWLARR_API_KEY="${prowlarr_api_key}" prowlarr /bin/sh -c \
  'curl -fsS -H "X-Api-Key: ${PROWLARR_API_KEY}" http://127.0.0.1:9696/api/v1/system/status >/dev/null'

wait_https_status() {
  local host="$1"
  local expected="$2"
  local status
  for attempt in {1..60}; do
    status="$(curl -sS -o /dev/null -w '%{http_code}' \
      --resolve "${host}:443:127.0.0.1" "https://${host}/" 2>/dev/null || true)"
    [[ ${status} == "${expected}" ]] && return 0
    sleep 2
  done
  die "Unexpected HTTPS status for ${host}: ${status:-unavailable}; expected ${expected}."
}

# A newly added hostname may need several seconds for its first ACME DNS-01
# certificate. Do not fail the bootstrap while Caddy is still obtaining it.
wait_https_status "torrent.${BASE_DOMAIN}" 200
wait_https_status "sonarr.${BASE_DOMAIN}" 401
wait_https_status "prowlarr.${BASE_DOMAIN}" 401

echo MEDIA_AUTOMATION_VERIFY_OK
