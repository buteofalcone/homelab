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
    prowlarr /bin/sh -c 'curl --fail-with-body --silent --show-error --request "${API_METHOD}" -H "X-Api-Key: ${PROWLARR_API_KEY}" -H "Content-Type: application/json" --data-binary @- "http://127.0.0.1:9696/api/v1/${API_PATH}"' \
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
    "stripCyrillicLetters": False,
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
toloka_id="$(python3 - "${work_dir}/indexers-after.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    matches = [item for item in json.load(handle) if item.get("name") == "Toloka.to" and item.get("enable")]
if len(matches) != 1:
    raise SystemExit("Toloka.to was not enabled uniquely")
print(matches[0]["id"])
PY
)"
printf 'TOLOKA_INDEXER_OK\n'

readonly sonarr_api_key="$(sed -n 's#.*<ApiKey>\([^<]*\)</ApiKey>.*#\1#p' /srv/appdata/sonarr/config.xml)"
readonly radarr_api_key="$(sed -n 's#.*<ApiKey>\([^<]*\)</ApiKey>.*#\1#p' /srv/appdata/radarr/config.xml)"
[[ -n ${sonarr_api_key} && -n ${radarr_api_key} ]] || die 'Sonarr or Radarr API key is missing.'

echo STEP_TOLOKA_APP_SYNC
for attempt in {1..5}; do
  docker exec -e ARR_KEY="${sonarr_api_key}" sonarr /bin/sh -c \
    'curl -fsS -H "X-Api-Key: ${ARR_KEY}" http://127.0.0.1:8989/api/v3/indexer' >"${work_dir}/sonarr-indexers.json"
  docker exec -e ARR_KEY="${radarr_api_key}" radarr /bin/sh -c \
    'curl -fsS -H "X-Api-Key: ${ARR_KEY}" http://127.0.0.1:7878/api/v3/indexer' >"${work_dir}/radarr-indexers.json"
  if python3 - "${work_dir}/sonarr-indexers.json" "${work_dir}/radarr-indexers.json" <<'PY'
import json, sys
for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as handle:
        if not any(item.get("name") == "Toloka.to (Prowlarr)" and item.get("enableAutomaticSearch") and item.get("enableInteractiveSearch") for item in json.load(handle)):
            raise SystemExit(1)
PY
  then
    printf 'TOLOKA_APP_SYNC_OK\n'
    break
  fi
  sleep 2
done

ensure_arr_toloka() {
  local container="$1" port="$2" api_key="$3" categories="$4"
  local schema_file="${work_dir}/${container}-indexer-schema.json"
  local indexers_file="${work_dir}/${container}-indexers.json"
  local payload_file="${work_dir}/${container}-toloka-payload.json"
  local response_file="${work_dir}/${container}-toloka-response.json"

  docker exec -e ARR_KEY="${api_key}" "${container}" /bin/sh -c \
    'curl -fsS -H "X-Api-Key: ${ARR_KEY}" "http://127.0.0.1:'"${port}"'/api/v3/indexer/schema"' >"${schema_file}"
  docker exec -e ARR_KEY="${api_key}" "${container}" /bin/sh -c \
    'curl -fsS -H "X-Api-Key: ${ARR_KEY}" "http://127.0.0.1:'"${port}"'/api/v3/indexer"' >"${indexers_file}"
  if python3 - "${indexers_file}" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    raise SystemExit(0 if any(item.get("name") == "Toloka.to (Prowlarr)" for item in json.load(handle)) else 1)
PY
  then
    return 0
  fi

  TOLOKA_ID="${toloka_id}" PROWLARR_API_KEY="${prowlarr_api_key}" APP_CATEGORIES="${categories}" \
    python3 - "${schema_file}" "${payload_file}" <<'PY'
import json, os, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    item = next(value for value in json.load(handle) if value.get("implementation") == "Torznab")
item.update({"enable": True, "name": "Toloka.to (Prowlarr)", "priority": 10})
values = {
    "baseUrl": f"http://prowlarr:9696/{os.environ['TOLOKA_ID']}/",
    "apiPath": "/api",
    "apiKey": os.environ["PROWLARR_API_KEY"],
    "categories": [int(value) for value in os.environ["APP_CATEGORIES"].split(",")],
    "minimumSeeders": 1,
}
for field in item["fields"]:
    if field.get("name") in values:
        field["value"] = values[field["name"]]
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(item, handle)
PY
  docker exec -i -e ARR_KEY="${api_key}" "${container}" /bin/sh -c \
    'curl --fail-with-body --silent --show-error -X POST -H "X-Api-Key: ${ARR_KEY}" -H "Content-Type: application/json" --data-binary @- "http://127.0.0.1:'"${port}"'/api/v3/indexer"' \
    <"${payload_file}" >"${response_file}"
}

# Prowlarr 2.5 can stop an application sync when an existing same-name
# indexer lacks its internal mapping. Ensure the equivalent Torznab entry
# directly and idempotently in any app that the normal sync did not reach.
ensure_arr_toloka sonarr 8989 "${sonarr_api_key}" '5000,5040,5050,5070,5080'
ensure_arr_toloka radarr 7878 "${radarr_api_key}" '2000,2020,2040'

docker exec -e ARR_KEY="${sonarr_api_key}" sonarr /bin/sh -c \
  'curl -fsS -H "X-Api-Key: ${ARR_KEY}" http://127.0.0.1:8989/api/v3/indexer' >"${work_dir}/sonarr-indexers.json"
docker exec -e ARR_KEY="${radarr_api_key}" radarr /bin/sh -c \
  'curl -fsS -H "X-Api-Key: ${ARR_KEY}" http://127.0.0.1:7878/api/v3/indexer' >"${work_dir}/radarr-indexers.json"
python3 - "${work_dir}/sonarr-indexers.json" "${work_dir}/radarr-indexers.json" <<'PY'
import json, sys
for app, path in zip(("Sonarr", "Radarr"), sys.argv[1:]):
    with open(path, encoding="utf-8") as handle:
        if not any(item.get("name") == "Toloka.to (Prowlarr)" and item.get("enableAutomaticSearch") and item.get("enableInteractiveSearch") for item in json.load(handle)):
            raise SystemExit(f"Toloka.to did not sync to {app}")
PY

printf 'TOLOKA_CONFIG_OK\n'
