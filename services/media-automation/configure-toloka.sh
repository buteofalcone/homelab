#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"

require_root
load_env
container_running prowlarr || die 'Prowlarr is not running.'

readonly credentials_file=/etc/homelab/toloka.env
install -d -m 0700 /etc/homelab

if [[ ! -s ${credentials_file} ]]; then
  read -r -p 'Toloka.to username: ' toloka_username
  read -r -s -p 'Toloka.to password: ' toloka_password
  printf '\n'
  [[ -n ${toloka_username} && -n ${toloka_password} ]] || die 'Toloka credentials cannot be empty.'

  tmp_credentials="$(mktemp /etc/homelab/toloka.env.XXXXXX)"
  trap 'rm -f -- "${tmp_credentials:-}"' EXIT
  printf 'TOLOKA_USERNAME_B64=%s\nTOLOKA_PASSWORD_B64=%s\n' \
    "$(printf '%s' "${toloka_username}" | base64 -w0)" \
    "$(printf '%s' "${toloka_password}" | base64 -w0)" >"${tmp_credentials}"
  install -m 0600 -o root -g root "${tmp_credentials}" "${credentials_file}"
  rm -f -- "${tmp_credentials}"
else
  toloka_username="$(sed -n 's/^TOLOKA_USERNAME_B64=//p' "${credentials_file}" | base64 -d)"
  toloka_password="$(sed -n 's/^TOLOKA_PASSWORD_B64=//p' "${credentials_file}" | base64 -d)"
fi

readonly prowlarr_api_key="$(sed -n 's#.*<ApiKey>\([^<]*\)</ApiKey>.*#\1#p' /srv/appdata/prowlarr/config.xml)"
[[ -n ${prowlarr_api_key} ]] || die 'Prowlarr API key is missing.'

readonly work_dir="$(mktemp -d)"
trap 'rm -rf -- "${work_dir}"; rm -f -- "${tmp_credentials:-}"' EXIT

prowlarr_get() {
  local path="$1" output="$2"
  docker exec -e PROWLARR_API_KEY="${prowlarr_api_key}" -e API_PATH="${path}" prowlarr /bin/sh -c \
    'curl -fsS -H "X-Api-Key: ${PROWLARR_API_KEY}" "http://127.0.0.1:9696/api/v1/${API_PATH}"' >"${output}"
}

prowlarr_write() {
  local method="$1" path="$2" input="$3" output="$4"
  docker exec -i -e PROWLARR_API_KEY="${prowlarr_api_key}" -e API_METHOD="${method}" -e API_PATH="${path}" \
    prowlarr /bin/sh -c 'curl -fsS --request "${API_METHOD}" -H "X-Api-Key: ${PROWLARR_API_KEY}" -H "Content-Type: application/json" --data-binary @- "http://127.0.0.1:9696/api/v1/${API_PATH}"' \
    <"${input}" >"${output}"
}

echo STEP_TOLOKA_SCHEMA
prowlarr_get indexer/schema "${work_dir}/schema.json"
prowlarr_get indexer "${work_dir}/indexers.json"
toloka_id="$(python3 - "${work_dir}/indexers.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    for item in json.load(handle):
        if item.get("name") == "Toloka.to":
            print(item.get("id", ""))
            break
PY
)"

TOLOKA_USERNAME="${toloka_username}" TOLOKA_PASSWORD="${toloka_password}" RESOURCE_ID="${toloka_id}" \
  python3 - "${work_dir}/schema.json" "${work_dir}/payload.json" <<'PY'
import json, os, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    item = next(value for value in json.load(handle) if value.get("name") == "Toloka.to")
item.update({"enable": True, "name": "Toloka.to", "appProfileId": 1, "priority": 10})
values = {
    "baseUrl": "https://toloka.to/",
    "username": os.environ["TOLOKA_USERNAME"],
    "password": os.environ["TOLOKA_PASSWORD"],
    "freeleechOnly": False,
    "stripCyrillicLetters": True,
    "torrentBaseSettings.preferMagnetUrl": False,
}
for field in item["fields"]:
    if field.get("name") in values:
        field["value"] = values[field["name"]]
if os.environ.get("RESOURCE_ID"):
    item["id"] = int(os.environ["RESOURCE_ID"])
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(item, handle)
PY
unset toloka_username toloka_password

echo STEP_TOLOKA_VALIDATE
if [[ -n ${toloka_id} ]]; then
  prowlarr_write PUT "indexer/${toloka_id}" "${work_dir}/payload.json" "${work_dir}/response.json"
else
  prowlarr_write POST indexer "${work_dir}/payload.json" "${work_dir}/response.json"
fi

prowlarr_get indexer "${work_dir}/indexers-after.json"
python3 - "${work_dir}/indexers-after.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    matches = [item for item in json.load(handle) if item.get("name") == "Toloka.to" and item.get("enable")]
if len(matches) != 1:
    raise SystemExit("Toloka.to was not enabled uniquely")
print("TOLOKA_INDEXER_OK")
PY

printf 'TOLOKA_CONFIG_OK\n'
