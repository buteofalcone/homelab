#!/usr/bin/env bash
set -Eeuo pipefail

readonly repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly hdd_root=/srv/storage/databases/clickhouse
readonly ssd_root=/srv/appdata/clickhouse

[[ ${EUID} -eq 0 ]] || {
  echo 'ERROR: run through sudo make clickhouse-verify' >&2
  exit 1
}

findmnt --target /srv/storage >/dev/null \
  || { echo 'ERROR: /srv/storage is not a mounted filesystem.' >&2; exit 1; }

for path in "${hdd_root}/data" "${hdd_root}/cold" "${ssd_root}/tmp" "${ssd_root}/log"; do
  [[ -d ${path} ]] || { echo "ERROR: missing ${path}" >&2; exit 1; }
done

cd "${repo_dir}"
docker compose --profile clickhouse ps clickhouse
curl --fail --silent http://127.0.0.1:8123/ping | grep -qx 'Ok.'
docker compose --profile clickhouse exec -T clickhouse \
  clickhouse-client --query 'SELECT version(), 1'

echo "CLICKHOUSE_STORAGE_HDD=${hdd_root}"
echo "CLICKHOUSE_WORKING_SSD=${ssd_root}"
echo 'CLICKHOUSE_VERIFY_OK'
