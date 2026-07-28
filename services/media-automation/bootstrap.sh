#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"

require_root
load_env

readonly password_file=/etc/homelab/qbittorrent-password
readonly caddy_env=/etc/homelab/media-caddy.env
readonly media_user="${MEDIA_ADMIN_USER:-butenko}"
readonly min_free_gb="${MEDIA_MIN_FREE_GB:-80}"

[[ ${min_free_gb} =~ ^[1-9][0-9]*$ ]] || die 'MEDIA_MIN_FREE_GB must be a positive integer.'
readonly min_free_bytes="$((min_free_gb * 1024 * 1024 * 1024))"

mountpoint -q /srv/storage || die '/srv/storage is not a mounted filesystem.'
install -d -m 0700 /etc/homelab
install -d -m 0750 -o "${PUID}" -g "${PGID}" \
  /srv/appdata/qbittorrent \
  /srv/appdata/sonarr \
  /srv/appdata/prowlarr \
  /srv/storage/downloads/torrents \
  /srv/storage/downloads/incomplete \
  /srv/storage/media/TV

if [[ ! -s ${password_file} ]]; then
  while true; do
    read -r -s -p 'Create the media automation password (12+ safe characters): ' media_password
    printf '\n'
    read -r -s -p 'Repeat the password: ' media_confirmation
    printf '\n'
    if (( ${#media_password} < 12 )); then
      echo 'Password is too short.' >&2
    elif [[ ! ${media_password} =~ ^[A-Za-z0-9._~!@#%^+=-]+$ ]]; then
      echo 'Use letters, numbers, and . _ ~ ! @ # % ^ + = - only.' >&2
    elif [[ ${media_password} != "${media_confirmation}" ]]; then
      echo 'Passwords do not match.' >&2
    else
      break
    fi
  done
  tmp_password="$(mktemp /etc/homelab/qbittorrent-password.XXXXXX)"
  trap 'rm -f -- "${tmp_password:-}" "${tmp_caddy_env:-}"' EXIT
  printf '%s' "${media_password}" >"${tmp_password}"
  install -m 0600 -o root -g root "${tmp_password}" "${password_file}"
  rm -f -- "${tmp_password}"
else
  media_password="$(<"${password_file}")"
fi

if [[ ! -s ${caddy_env} ]]; then
  if container_running caddy; then
    media_hash="$(docker exec caddy caddy hash-password --plaintext "${media_password}")"
  else
    media_hash="$(docker run --rm caddy:2-alpine caddy hash-password --plaintext "${media_password}")"
  fi
  tmp_caddy_env="$(mktemp /etc/homelab/media-caddy.env.XXXXXX)"
  printf "MEDIA_ADMIN_USER='%s'\nMEDIA_ADMIN_HASH='%s'\n" "${media_user}" "${media_hash}" >"${tmp_caddy_env}"
  install -m 0600 -o root -g root "${tmp_caddy_env}" "${caddy_env}"
  rm -f -- "${tmp_caddy_env}"
fi
unset media_confirmation media_hash

cd "${repo_dir}"
compose --profile media-automation config --quiet
compose --profile media-automation pull qbittorrent sonarr prowlarr
compose --profile media-automation up -d qbittorrent

for attempt in {1..30}; do
  if docker exec qbittorrent curl -fsS http://127.0.0.1:8080/ >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

qb_login() {
  local username="$1"
  local password="$2"
  docker exec -e QB_USER="${username}" -e QB_PASSWORD="${password}" qbittorrent /bin/sh -c '
    rm -f /tmp/qb-cookie
    status="$(curl -sS --output /tmp/qb-login-body --write-out "%{http_code}" --cookie-jar /tmp/qb-cookie \
      --header "Referer: http://localhost:8080" \
      --data-urlencode "username=${QB_USER}" \
      --data-urlencode "password=${QB_PASSWORD}" \
      http://localhost:8080/api/v2/auth/login)"
    body="$(cat /tmp/qb-login-body)"
    rm -f /tmp/qb-login-body
    [ "${status}" = 204 ] || { [ "${status}" = 200 ] && [ "${body}" = "Ok." ]; }
  '
}

if ! qb_login "${media_user}" "${media_password}"; then
  temporary_password="$(docker logs qbittorrent 2>&1 | sed -n 's/.*temporary password is provided for this session: //p' | tail -n 1)"
  [[ -n ${temporary_password} ]] || die 'Could not obtain the one-time qBittorrent password.'
  qb_login admin "${temporary_password}" || die 'Could not authenticate to fresh qBittorrent.'
fi

docker exec -e MEDIA_ADMIN_USER="${media_user}" -e BASE_DOMAIN="${BASE_DOMAIN}" -e MIN_FREE_BYTES="${min_free_bytes}" qbittorrent /bin/sh -c '
  password="$(cat /run/secrets/qbittorrent-password)"
  json="$(printf '\''{"web_ui_username":"%s","web_ui_password":"%s","save_path":"/data/downloads/torrents","temp_path":"/data/downloads/incomplete","temp_path_enabled":true,"start_paused_enabled":false,"disk_free_space_limit":%s,"web_ui_host_header_validation_enabled":true,"web_ui_domain_list":"localhost;qbittorrent;torrent.%s","web_ui_csrf_protection_enabled":true,"web_ui_clickjacking_protection_enabled":true,"upnp":false,"random_port":false,"listen_port":6881}'\'' "${MEDIA_ADMIN_USER}" "${password}" "${MIN_FREE_BYTES}" "${BASE_DOMAIN}")"
  curl -fsS --cookie /tmp/qb-cookie --header "Referer: http://localhost:8080" \
    --data-urlencode "json=${json}" http://localhost:8080/api/v2/app/setPreferences
  rm -f /tmp/qb-cookie
'
unset media_password temporary_password

# Recreating removes the log that contained the one-time password.
compose --profile media-automation up -d --force-recreate qbittorrent
compose --profile media-automation up -d sonarr prowlarr

for attempt in {1..60}; do
  [[ -s /srv/appdata/sonarr/config.xml && -s /srv/appdata/prowlarr/config.xml ]] && break
  sleep 2
done
[[ -s /srv/appdata/sonarr/config.xml ]] || die 'Sonarr did not create config.xml.'
[[ -s /srv/appdata/prowlarr/config.xml ]] || die 'Prowlarr did not create config.xml.'
compose --profile media-automation stop sonarr prowlarr

set_xml_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  if grep -q "<${key}>" "${file}"; then
    sed -i -E "s#<${key}>[^<]*</${key}>#<${key}>${value}</${key}>#" "${file}"
  else
    sed -i "s#</Config>#  <${key}>${value}</${key}>\n</Config>#" "${file}"
  fi
}
for config_file in /srv/appdata/sonarr/config.xml /srv/appdata/prowlarr/config.xml; do
  set_xml_value "${config_file}" AuthenticationMethod External
  set_xml_value "${config_file}" AuthenticationType Enabled
done
compose --profile media-automation up -d sonarr prowlarr

install -m 0644 -o "${PUID}" -g "${PGID}" \
  "${repo_dir}/config/homepage/services.yaml" /srv/appdata/homepage/services.yaml
compose up -d --no-deps homepage
compose up -d --build --force-recreate caddy

"${service_dir}/verify.sh"
echo MEDIA_AUTOMATION_BOOTSTRAP_OK
