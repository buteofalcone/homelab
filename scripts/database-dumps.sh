#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
require_root
load_env

dump_dir="/srv/appdata/_backup-dumps"
install -d -m 0700 "${dump_dir}"

if container_running nextcloud-db; then
  tmp="${dump_dir}/nextcloud.sql.gz.tmp"
  docker exec nextcloud-db pg_dump -U nextcloud --clean --if-exists nextcloud | gzip -9 > "${tmp}"
  mv "${tmp}" "${dump_dir}/nextcloud.sql.gz"
  chmod 0600 "${dump_dir}/nextcloud.sql.gz"
  echo "Created Nextcloud database dump."
fi

if container_running immich-database; then
  tmp="${dump_dir}/immich.sql.gz.tmp"
  docker exec -e PGPASSWORD="${IMMICH_DB_PASSWORD}" immich-database \
    pg_dump -U postgres --clean --if-exists immich | gzip -9 > "${tmp}"
  mv "${tmp}" "${dump_dir}/immich.sql.gz"
  chmod 0600 "${dump_dir}/immich.sql.gz"
  echo "Created Immich database dump."
fi
