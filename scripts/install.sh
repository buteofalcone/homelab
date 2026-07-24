#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
require_root
load_env

command -v docker >/dev/null 2>&1 || die "Docker is not installed."
docker compose version >/dev/null 2>&1 || die "Docker Compose plugin is not installed."

install -d -m 0755 \
  /srv/appdata/homepage \
  /srv/appdata/portainer \
  /srv/appdata/beszel \
  /srv/appdata/beszel-agent \
  /srv/appdata/uptime-kuma \
  /srv/storage/files \
  /srv/storage/backups \
  /srv/storage/downloads \
  /etc/homelab

cp -a "${REPO_DIR}/services/homepage/config/." /srv/appdata/homepage/

# Homepage templates use this variable at runtime.
cat > /srv/appdata/homepage/.env <<EOF
HOMEPAGE_VAR_SERVER_IP=${SERVER_IP}
EOF

chown -R "${PUID}:${PGID}" /srv/appdata/homepage
chmod 0750 /srv/appdata/homepage

cd "${REPO_DIR}"
docker compose config >/dev/null
docker compose pull
docker compose up -d

printf '\nBase stack started.\n'
printf 'Homepage:    http://%s:%s\n' "${SERVER_IP}" "${HOMEPAGE_PORT:-3000}"
printf 'Portainer:   https://%s:%s\n' "${SERVER_IP}" "${PORTAINER_PORT:-9443}"
printf 'Beszel:      http://%s:%s\n' "${SERVER_IP}" "${BESZEL_PORT:-8090}"
printf 'Uptime Kuma: http://%s:%s\n' "${SERVER_IP}" "${UPTIME_KUMA_PORT:-3001}"
printf '\nRun: %s/scripts/doctor.sh\n' "${REPO_DIR}"
