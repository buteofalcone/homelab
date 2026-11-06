#!/usr/bin/env bash
set -Eeuo pipefail

readonly repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly hdd_root=/srv/storage/databases/clickhouse
readonly ssd_root=/srv/appdata/clickhouse
readonly clickhouse_uid=101
readonly clickhouse_gid=101

[[ ${EUID} -eq 0 ]] || {
  echo 'ERROR: run through sudo make clickhouse-bootstrap' >&2
  exit 1
}

findmnt --target /srv/storage >/dev/null \
  || { echo 'ERROR: /srv/storage is not a mounted filesystem.' >&2; exit 1; }

echo 'STEP_CLICKHOUSE_STORAGE'
install -d -m 0750 -o "${clickhouse_uid}" -g "${clickhouse_gid}" \
  "${hdd_root}/data" \
  "${hdd_root}/cold/parquet" \
  "${hdd_root}/cold/csv" \
  "${hdd_root}/cold/sql" \
  "${ssd_root}/tmp" \
  "${ssd_root}/log"

echo 'STEP_CLICKHOUSE_START'
cd "${repo_dir}"
docker compose --profile clickhouse pull clickhouse
docker compose --profile clickhouse up -d clickhouse

echo 'STEP_CLICKHOUSE_WAIT'
for _ in $(seq 1 30); do
  if curl --fail --silent http://127.0.0.1:8123/ping | grep -qx 'Ok.'; then
    echo 'CLICKHOUSE_BOOTSTRAP_OK'
    exit 0
  fi
  sleep 2
done

docker compose --profile clickhouse logs --tail=100 clickhouse >&2 || true
echo 'ERROR: ClickHouse did not become healthy.' >&2
exit 1
