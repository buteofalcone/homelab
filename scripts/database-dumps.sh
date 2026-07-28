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

if container_running open-webui; then
  tmp="${dump_dir}/open-webui.db.tmp"
  rm -f -- "${tmp}"
  docker exec open-webui rm -f /tmp/open-webui.db
  docker exec open-webui python -c \
    "import sqlite3; source=sqlite3.connect('/app/backend/data/webui.db'); target=sqlite3.connect('/tmp/open-webui.db'); source.backup(target); target.close(); source.close()"
  docker cp open-webui:/tmp/open-webui.db "${tmp}"
  docker exec open-webui rm -f /tmp/open-webui.db
  mv "${tmp}" "${dump_dir}/open-webui.db"
  chmod 0600 "${dump_dir}/open-webui.db"
  echo "Created Open WebUI database dump."
fi
