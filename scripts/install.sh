#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
require_root
load_env

command -v docker >/dev/null 2>&1 || die "Docker is not installed."
docker compose version >/dev/null 2>&1 || die "Docker Compose plugin is not installed."
mountpoint -q /srv/storage || die "/srv/storage is not a mounted filesystem."

install -d -m 0755 \
  /srv/appdata/homepage \
  /srv/appdata/portainer \
  /srv/appdata/beszel \
  /srv/appdata/beszel-agent \
  /srv/appdata/uptime-kuma \
  /srv/appdata/caddy/data \
  /srv/appdata/caddy/config \
  /srv/appdata/nextcloud/html \
  /srv/appdata/nextcloud/postgres \
  /srv/appdata/immich/postgres \
  /srv/appdata/immich/model-cache \
  /srv/appdata/jellyfin/config \
  /srv/appdata/jellyfin/cache \
  /srv/appdata/_backup-dumps \
  /srv/storage/files/nextcloud \
  /srv/storage/photos \
  /srv/storage/media/Movies \
  /srv/storage/media/TV \
  /srv/storage/media/Music \
  /srv/storage/media/HomeVideos \
  /srv/storage/backups \
  /srv/storage/downloads \
  /srv/storage/restores \
  /etc/homelab

cp -a "${REPO_DIR}/config/homepage/." /srv/appdata/homepage/

cat > /srv/appdata/homepage/.env <<EOF
HOMEPAGE_VAR_SERVER_IP=${SERVER_IP}
HOMEPAGE_VAR_BASE_DOMAIN=${BASE_DOMAIN}
EOF

chown -R "${PUID}:${PGID}" \
  /srv/appdata/homepage \
  /srv/appdata/jellyfin \
  /srv/storage/photos \
  /srv/storage/media \
  /srv/storage/downloads

chown -R 33:33 /srv/storage/files/nextcloud
chmod 0750 /srv/appdata/homepage
chmod 0700 /etc/homelab

cd "${REPO_DIR}"
compose --profile nextcloud --profile immich --profile jellyfin --profile beszel-agent config --quiet
compose pull
compose up -d

printf '\nBase stack started.\n'
printf 'Homepage:    http://%s:%s or https://home.%s\n' "${SERVER_IP}" "${HOMEPAGE_PORT:-3000}" "${BASE_DOMAIN}"
printf 'Portainer:   https://%s:%s or https://portainer.%s\n' "${SERVER_IP}" "${PORTAINER_PORT:-9443}" "${BASE_DOMAIN}"
printf 'Beszel:      http://%s:%s or https://beszel.%s\n' "${SERVER_IP}" "${BESZEL_PORT:-8090}" "${BASE_DOMAIN}"
printf 'Uptime Kuma: http://%s:%s or https://uptime.%s\n' "${SERVER_IP}" "${UPTIME_KUMA_PORT:-3001}" "${BASE_DOMAIN}"
printf '\nOptional applications:\n'
printf '  make nextcloud\n  make immich\n  make jellyfin\n'
printf '\nRun diagnostics: make doctor\n'
