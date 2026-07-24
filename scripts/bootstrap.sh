#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"

if [[ -f "${ENV_FILE}" ]]; then
  echo "${ENV_FILE} already exists; refusing to overwrite it."
  exit 0
fi

command -v openssl >/dev/null 2>&1 || die "openssl is required."

cp "${REPO_DIR}/.env.example" "${ENV_FILE}"

server_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
server_ip="${server_ip:-192.168.1.130}"
timezone="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
timezone="${timezone:-Europe/Madrid}"

replace() {
  local key="$1"
  local value="$2"
  sed -i "s|^${key}=.*$|${key}=${value}|" "${ENV_FILE}"
}

random_hex() {
  openssl rand -hex 24
}

replace TZ "${timezone}"
replace PUID "$(id -u)"
replace PGID "$(id -g)"
replace SERVER_IP "${server_ip}"
replace NEXTCLOUD_ADMIN_PASSWORD "$(random_hex)"
replace NEXTCLOUD_DB_PASSWORD "$(random_hex)"
replace NEXTCLOUD_REDIS_PASSWORD "$(random_hex)"
replace IMMICH_DB_PASSWORD "$(random_hex)"

chmod 0600 "${ENV_FILE}"

echo "Created ${ENV_FILE} with generated passwords."
echo "Review BASE_DOMAIN and SERVER_IP before installation:"
echo "  nano ${ENV_FILE}"
