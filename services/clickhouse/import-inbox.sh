#!/usr/bin/env bash
set -Eeuo pipefail

readonly inbox_root=/srv/storage/incoming/databases
readonly cold_root=/srv/storage/databases/clickhouse/cold

[[ ${EUID} -eq 0 ]] || {
  echo 'ERROR: run through sudo make clickhouse-inbox-import' >&2
  exit 1
}

findmnt --target /srv/storage >/dev/null \
  || { echo 'ERROR: /srv/storage is not a mounted filesystem.' >&2; exit 1; }

for path in "${inbox_root}/parquet" "${inbox_root}/csv" "${inbox_root}/sql" \
            "${cold_root}/parquet" "${cold_root}/csv" "${cold_root}/sql"; do
  [[ -d ${path} ]] || { echo "ERROR: missing directory: ${path}" >&2; exit 1; }
done

moved=0
conflicts=0
ignored=0

for kind in parquet csv sql; do
  echo "STEP_CLICKHOUSE_INBOX_${kind^^}"
  while IFS= read -r -d '' source_file; do
    name="$(basename "${source_file}")"
    lower_name="${name,,}"
    valid=false
    case "${kind}:${lower_name}" in
      parquet:*.parquet|csv:*.csv|sql:*.sql|sql:*.sql.gz) valid=true ;;
    esac
    if [[ ${valid} != true ]]; then
      echo "IGNORED unexpected extension: ${source_file}"
      ((ignored+=1))
      continue
    fi

    destination="${cold_root}/${kind}/${name}"
    if [[ -e ${destination} ]]; then
      echo "CONFLICT destination exists; left in Inbox: ${name}" >&2
      ((conflicts+=1))
      continue
    fi

    mv -- "${source_file}" "${destination}"
    echo "MOVED ${kind}/${name}"
    ((moved+=1))
  done < <(find "${inbox_root}/${kind}" -maxdepth 1 -type f -print0)
done

echo "CLICKHOUSE_INBOX_IMPORT_OK moved=${moved} conflicts=${conflicts} ignored=${ignored}"
if (( conflicts > 0 )); then
  exit 1
fi
