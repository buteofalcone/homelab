#!/usr/bin/env bash
set -Eeuo pipefail

readonly inbox_root=/srv/storage/incoming
readonly staging_root="${inbox_root}/databases"

[[ ${EUID} -eq 0 ]] || {
  echo 'ERROR: run through sudo make clickhouse-inbox-bootstrap' >&2
  exit 1
}

findmnt --target /srv/storage >/dev/null \
  || { echo 'ERROR: /srv/storage is not a mounted filesystem.' >&2; exit 1; }

[[ -d ${inbox_root} ]] \
  || { echo "ERROR: SMB Inbox root is missing: ${inbox_root}" >&2; exit 1; }

readonly inbox_uid="$(stat -c '%u' "${inbox_root}")"
readonly inbox_gid="$(stat -c '%g' "${inbox_root}")"

echo 'STEP_CLICKHOUSE_INBOX_STORAGE'
install -d -m 0770 -o "${inbox_uid}" -g "${inbox_gid}" \
  "${staging_root}/parquet" \
  "${staging_root}/csv" \
  "${staging_root}/sql"

echo "CLICKHOUSE_INBOX_SMB=smb://192.168.1.130/Inbox/databases"
echo 'CLICKHOUSE_INBOX_BOOTSTRAP_OK'
