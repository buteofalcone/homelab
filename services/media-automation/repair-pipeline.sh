#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"

require_root
load_env

readonly media_user="${MEDIA_ADMIN_USER:-butenko}"
readonly password_file=/etc/homelab/qbittorrent-password
[[ -s "${password_file}" ]] || die 'Missing qBittorrent password file.'

echo STEP_QBITTORRENT_SECRET_PREFLIGHT
media_password="$(<"${password_file}")"
docker exec -e QB_USER="${media_user}" -e QB_PASSWORD="${media_password}" qbittorrent /bin/sh -c '
  rm -f /tmp/qb-repair-cookie /tmp/qb-repair-body
  status="$(curl -sS --output /tmp/qb-repair-body --write-out "%{http_code}" \
    --cookie-jar /tmp/qb-repair-cookie --header "Referer: http://localhost:8080" \
    --data-urlencode "username=${QB_USER}" --data-urlencode "password=${QB_PASSWORD}" \
    http://localhost:8080/api/v2/auth/login)"
  body="$(cat /tmp/qb-repair-body)"
  rm -f /tmp/qb-repair-cookie /tmp/qb-repair-body
  [ "${status}" = 204 ] || { [ "${status}" = 200 ] && [ "${body}" = "Ok." ]; }
' || die 'The root-only qBittorrent password does not match the running service.'

echo STEP_MEDIA_NETWORK_RECREATE
compose --profile media-automation up -d --force-recreate qbittorrent seerr

for container in qbittorrent seerr; do
  for attempt in {1..60}; do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${container}" 2>/dev/null || true)"
    [[ "${status}" == healthy || "${status}" == running ]] && break
    sleep 2
  done
  [[ "${status}" == healthy || "${status}" == running ]] || die "${container} did not become ready."
done

docker inspect seerr --format '{{json .NetworkSettings.Networks}}' | grep -q '"homelab"' \
  || die 'Seerr is still disconnected from the homelab Docker network.'
docker exec seerr getent hosts sonarr radarr >/dev/null \
  || die 'Seerr cannot resolve Sonarr or Radarr on the Docker network.'

echo STEP_MEDIA_INTEGRATIONS_REFRESH
"${service_dir}/configure-integrations.sh"
if [[ -s /etc/homelab/toloka.env ]]; then
  "${service_dir}/configure-toloka.sh"
fi

echo STEP_QBITTORRENT_ARR_LOGIN_VERIFY
media_password="$(<"${password_file}")"
for container in sonarr radarr; do
  docker exec -e QB_USER="${media_user}" -e QB_PASSWORD="${media_password}" "${container}" /bin/sh -c '
    rm -f /tmp/qb-arr-cookie /tmp/qb-arr-body
    status="$(curl -sS --output /tmp/qb-arr-body --write-out "%{http_code}" \
      --cookie-jar /tmp/qb-arr-cookie --header "Referer: http://qbittorrent:8080" \
      --data-urlencode "username=${QB_USER}" --data-urlencode "password=${QB_PASSWORD}" \
      http://qbittorrent:8080/api/v2/auth/login)"
    body="$(cat /tmp/qb-arr-body)"
    rm -f /tmp/qb-arr-cookie /tmp/qb-arr-body
    [ "${status}" = 204 ] || { [ "${status}" = 200 ] && [ "${body}" = "Ok." ]; }
  ' || die "${container} cannot authenticate to qBittorrent."
done
unset media_password

echo STEP_MEDIA_PIPELINE_VERIFY
"${service_dir}/verify.sh"
printf 'MEDIA_AUTOMATION_PIPELINE_REPAIR_OK\n'
