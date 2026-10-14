#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
require_root
load_env

install -d -m 0750 -o "${PUID}" -g "${PGID}" /srv/appdata/homepage
cp -a "${REPO_DIR}/config/homepage/." /srv/appdata/homepage/

cat > /srv/appdata/homepage/.env <<EOF
HOMEPAGE_VAR_SERVER_IP=${SERVER_IP}
HOMEPAGE_VAR_BASE_DOMAIN=${BASE_DOMAIN}
EOF

chown -R "${PUID}:${PGID}" /srv/appdata/homepage

cd "${REPO_DIR}"
compose config --quiet
compose restart homepage

printf 'HOMEPAGE_DEPLOY_OK\n'
