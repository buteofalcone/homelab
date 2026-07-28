#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"

require_root
load_env

export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE

command -v restic >/dev/null 2>&1 || die 'Restic is not installed.'
[[ -f ${RESTIC_PASSWORD_FILE} ]] || die "Missing ${RESTIC_PASSWORD_FILE}."

echo 'Recent Restic snapshots:'
restic snapshots --latest 5

echo
echo 'Checking Restic repository metadata and pack integrity:'
restic check

echo
echo 'Checking PostgreSQL dumps:'
for dump in nextcloud.sql.gz immich.sql.gz; do
  path="/srv/appdata/_backup-dumps/${dump}"
  [[ -s ${path} ]] || die "Missing or empty database dump: ${path}"
  gzip -t "${path}"
  stat -c 'OK   %n (%s bytes, modified %y)' "${path}"
done

if container_running open-webui; then
  open_webui_dump=/srv/appdata/_backup-dumps/open-webui.db
  [[ -s ${open_webui_dump} ]] || die "Missing or empty database dump: ${open_webui_dump}"
  python3 - "${open_webui_dump}" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
result = connection.execute("PRAGMA integrity_check").fetchone()[0]
connection.close()
if result != "ok":
    raise SystemExit(f"Open WebUI SQLite integrity check failed: {result}")
print("OK   Open WebUI SQLite dump passed integrity_check")
PY
fi

if container_running qbittorrent && container_running sonarr && container_running prowlarr; then
  echo
  echo 'Checking media automation recovery files in the latest snapshot:'
  for path in \
    /srv/appdata/qbittorrent/qBittorrent/qBittorrent.conf \
    /srv/appdata/sonarr/config.xml \
    /srv/appdata/prowlarr/config.xml \
    /etc/homelab/qbittorrent-password \
    /etc/homelab/media-caddy.env; do
    restic dump latest "${path}" >/dev/null
    printf 'OK   %s\n' "${path}"
  done
fi

echo
echo 'RESTIC_AUDIT_OK'
