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
container_running radarr || die 'Radarr is not running.'
container_running seerr || die 'Seerr is not running.'

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
  curl -fsS --cookie /tmp/qb-verify-cookie --header "Referer: http://localhost:8080" \
    http://localhost:8080/api/v2/torrents/info >/dev/null
  rm -f /tmp/qb-verify-cookie
'
unset media_password

grep -Fq '<AuthenticationMethod>External</AuthenticationMethod>' /srv/appdata/sonarr/config.xml \
  || die 'Sonarr external authentication is not configured.'
sonarr_api_key="$(sed -n 's#.*<ApiKey>\([^<]*\)</ApiKey>.*#\1#p' /srv/appdata/sonarr/config.xml)"
[[ -n ${sonarr_api_key} ]] || die 'Sonarr API key is missing.'
readonly verify_dir="$(mktemp -d)"
trap 'rm -rf -- "${verify_dir}"' EXIT

sonarr_get() {
  local path="$1" output="$2"
  docker exec -e SONARR_API_KEY="${sonarr_api_key}" -e API_PATH="${path}" sonarr /bin/sh -c \
    'curl -fsS -H "X-Api-Key: ${SONARR_API_KEY}" "http://127.0.0.1:8989/api/v3/${API_PATH}"' >"${output}"
}

sonarr_get rootfolder "${verify_dir}/rootfolders.json"
sonarr_get downloadclient "${verify_dir}/downloadclients.json"
sonarr_get indexer "${verify_dir}/sonarr-indexers.json"
python3 - "${verify_dir}" <<'PY'
import json, os, sys
base = sys.argv[1]
def load(name):
    with open(os.path.join(base, name), encoding="utf-8") as handle:
        return json.load(handle)
if not any(item.get("path") == "/data/media/TV" and item.get("accessible") for item in load("rootfolders.json")):
    raise SystemExit("Sonarr TV root is missing or inaccessible")
if not any(item.get("name") == "qBittorrent" and item.get("enable") for item in load("downloadclients.json")):
    raise SystemExit("Sonarr qBittorrent client is missing or disabled")
if not any(item.get("name") == "Internet Archive (Prowlarr)" for item in load("sonarr-indexers.json")):
    raise SystemExit("Prowlarr indexer is not synced to Sonarr")
PY

grep -Fq '<AuthenticationMethod>External</AuthenticationMethod>' /srv/appdata/radarr/config.xml \
  || die 'Radarr external authentication is not configured.'
radarr_api_key="$(sed -n 's#.*<ApiKey>\([^<]*\)</ApiKey>.*#\1#p' /srv/appdata/radarr/config.xml)"
[[ -n ${radarr_api_key} ]] || die 'Radarr API key is missing.'
radarr_get() {
  local path="$1" output="$2"
  docker exec -e RADARR_API_KEY="${radarr_api_key}" -e API_PATH="${path}" radarr /bin/sh -c \
    'curl -fsS -H "X-Api-Key: ${RADARR_API_KEY}" "http://127.0.0.1:7878/api/v3/${API_PATH}"' >"${output}"
}
radarr_get rootfolder "${verify_dir}/radarr-rootfolders.json"
radarr_get downloadclient "${verify_dir}/radarr-downloadclients.json"
python3 - "${verify_dir}" <<'PY'
import json, os, sys
base = sys.argv[1]
def load(name):
    with open(os.path.join(base, name), encoding="utf-8") as handle:
        return json.load(handle)
if not any(item.get("path") == "/data/media/Movies" and item.get("accessible") for item in load("radarr-rootfolders.json")):
    raise SystemExit("Radarr Movies root is missing or inaccessible")
if not any(item.get("name") == "qBittorrent" and item.get("enable") for item in load("radarr-downloadclients.json")):
    raise SystemExit("Radarr qBittorrent client is missing or disabled")
PY

docker exec seerr wget --no-verbose --tries=1 --spider http://127.0.0.1:5055/api/v1/settings/public

grep -Fq '<AuthenticationMethod>External</AuthenticationMethod>' /srv/appdata/prowlarr/config.xml \
  || die 'Prowlarr external authentication is not configured.'
prowlarr_api_key="$(sed -n 's#.*<ApiKey>\([^<]*\)</ApiKey>.*#\1#p' /srv/appdata/prowlarr/config.xml)"
[[ -n ${prowlarr_api_key} ]] || die 'Prowlarr API key is missing.'
docker exec -e PROWLARR_API_KEY="${prowlarr_api_key}" prowlarr /bin/sh -c \
  'curl -fsS -H "X-Api-Key: ${PROWLARR_API_KEY}" http://127.0.0.1:9696/api/v1/system/status >/dev/null'
docker exec -e PROWLARR_API_KEY="${prowlarr_api_key}" prowlarr /bin/sh -c \
  'curl -fsS -H "X-Api-Key: ${PROWLARR_API_KEY}" http://127.0.0.1:9696/api/v1/applications' >"${verify_dir}/applications.json"
docker exec -e PROWLARR_API_KEY="${prowlarr_api_key}" prowlarr /bin/sh -c \
  'curl -fsS -H "X-Api-Key: ${PROWLARR_API_KEY}" http://127.0.0.1:9696/api/v1/indexer' >"${verify_dir}/prowlarr-indexers.json"
python3 - "${verify_dir}" <<'PY'
import json, os, sys
base = sys.argv[1]
def load(name):
    with open(os.path.join(base, name), encoding="utf-8") as handle:
        return json.load(handle)
if not any(item.get("name") == "Sonarr" and item.get("enable") and item.get("syncLevel") == "fullSync" for item in load("applications.json")):
    raise SystemExit("Prowlarr Sonarr integration is missing")
if not any(item.get("name") == "Radarr" and item.get("enable") and item.get("syncLevel") == "fullSync" for item in load("applications.json")):
    raise SystemExit("Prowlarr Radarr integration is missing")
if not any(item.get("name") == "Internet Archive" and item.get("enable") for item in load("prowlarr-indexers.json")):
    raise SystemExit("Internet Archive indexer is missing or disabled")
if os.path.exists('/etc/homelab/toloka.env') and not any(item.get("name") == "Toloka.to" and item.get("enable") for item in load("prowlarr-indexers.json")):
    raise SystemExit("Toloka credentials exist but the Toloka.to indexer is not enabled")
PY

wait_https_status() {
  local host="$1"
  local expected="$2"
  local path="${3:-/}"
  local status
  for attempt in {1..60}; do
    status="$(curl -sS -o /dev/null -w '%{http_code}' \
      --resolve "${host}:443:127.0.0.1" "https://${host}${path}" 2>/dev/null || true)"
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
wait_https_status "radarr.${BASE_DOMAIN}" 401
wait_https_status "requests.${BASE_DOMAIN}" 200 /api/v1/settings/public

echo MEDIA_AUTOMATION_VERIFY_OK
