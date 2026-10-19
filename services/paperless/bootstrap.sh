#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"

require_root
load_env
mountpoint -q /srv/storage || die '/srv/storage is not a mounted filesystem.'
command -v docker >/dev/null 2>&1 || die 'Docker is not installed.'
docker compose version >/dev/null 2>&1 || die 'Docker Compose plugin is not installed.'

readonly secret_file=/etc/homelab/paperless.env
install -d -m 0700 /etc/homelab
install -d -m 0750 -o "${PUID}" -g "${PGID}" \
  /srv/appdata/paperless/data \
  /srv/appdata/paperless/valkey \
  /srv/storage/documents/paperless/media \
  /srv/storage/documents/paperless/export
install -d -m 0700 -o 999 -g 999 /srv/appdata/paperless/postgres
install -d -m 0770 -o "${PUID}" -g "${PGID}" /srv/storage/incoming/documents

if [[ ! -s ${secret_file} ]]; then
  admin_user='butenko'
  read -r -p "Paperless administrator username [${admin_user}]: " requested_user
  admin_user="${requested_user:-${admin_user}}"
  [[ ${admin_user} =~ ^[A-Za-z0-9._@+-]+$ ]] || die 'Username contains unsupported characters.'
  while true; do
    read -r -s -p 'Create the Paperless administrator password (12+ safe characters): ' admin_password
    printf '\n'
    read -r -s -p 'Repeat the password: ' confirmation
    printf '\n'
    if (( ${#admin_password} < 12 )); then
      echo 'Password is too short.' >&2
    elif [[ ! ${admin_password} =~ ^[A-Za-z0-9._@+:-]+$ ]]; then
      echo 'Use only letters, numbers and . _ @ + : - characters.' >&2
    elif [[ ${admin_password} != "${confirmation}" ]]; then
      echo 'Passwords do not match.' >&2
    else
      break
    fi
  done
  db_password="$(openssl rand -hex 32)"
  secret_key="$(openssl rand -hex 48)"
  umask 077
  {
    printf 'POSTGRES_PASSWORD=%s\n' "${db_password}"
    printf 'PAPERLESS_DBPASS=%s\n' "${db_password}"
    printf 'PAPERLESS_SECRET_KEY=%s\n' "${secret_key}"
    printf 'PAPERLESS_ADMIN_USER=%s\n' "${admin_user}"
    printf 'PAPERLESS_ADMIN_PASSWORD=%s\n' "${admin_password}"
  } > "${secret_file}"
  chmod 0600 "${secret_file}"
  unset admin_password confirmation db_password secret_key
else
  echo 'Reusing existing root-only Paperless secrets.'
fi

cd "${repo_dir}"
echo 'STEP_PAPERLESS_PULL'
docker compose --profile paperless pull paperless-broker paperless-db paperless-gotenberg paperless-tika paperless
echo 'STEP_PAPERLESS_START'
docker compose --profile paperless up -d paperless-broker paperless-db paperless-gotenberg paperless-tika paperless

echo 'STEP_PAPERLESS_READY'
for _ in {1..60}; do
  if [[ $(docker inspect -f '{{.State.Health.Status}}' paperless 2>/dev/null || true) == healthy ]]; then
    break
  fi
  sleep 5
done
[[ $(docker inspect -f '{{.State.Health.Status}}' paperless 2>/dev/null || true) == healthy ]] || die 'Paperless did not become healthy.'

"${repo_dir}/scripts/deploy-homepage.sh"
"${repo_dir}/scripts/configure-cloudflare-dns.sh" "${BASE_DOMAIN}"
docker compose up -d --build caddy
docker compose exec -T -w /etc/caddy caddy /bin/sh -c \
  'set -a; . /run/secrets/caddy.env; [ ! -f /run/secrets/media-caddy.env ] || . /run/secrets/media-caddy.env; set +a; exec caddy reload --config Caddyfile'

"${service_dir}/verify.sh"
echo 'PAPERLESS_BOOTSTRAP_OK'
