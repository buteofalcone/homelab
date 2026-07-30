#!/usr/bin/env bash
set -Eeuo pipefail

readonly key_file="${1:-/etc/homelab/immich-go-api-key}"

[[ ${EUID} -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
[[ -s ${key_file} ]] || { echo "Missing API key: ${key_file}" >&2; exit 1; }

api_key="$(tr -d '\r\n' < "${key_file}")"
if (( ${#api_key} < 20 || ${#api_key} > 256 )) || [[ ! ${api_key} =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo 'Stored API key format is invalid.' >&2
  exit 1
fi

curl_config="$(mktemp /tmp/immich-api-key-check.XXXXXX)"
response_file="$(mktemp /tmp/immich-api-key-response.XXXXXX)"
trap 'rm -f -- "${curl_config}" "${response_file}"' EXIT
chmod 0600 "${curl_config}" "${response_file}"
printf 'silent\nshow-error\nfail\nheader = "x-api-key: %s"\n' "${api_key}" > "${curl_config}"
unset api_key

curl --config "${curl_config}" --output "${response_file}" \
  http://127.0.0.1:2283/api/users/me

python3 - "${response_file}" <<'PY'
import json
from pathlib import Path
import sys

payload = json.loads(Path(sys.argv[1]).read_text())
if not isinstance(payload.get("id"), str) or not payload["id"]:
    raise SystemExit("Immich API did not return a valid user identity.")
print("IMMICH_MIGRATION_API_KEY_VALID")
PY
