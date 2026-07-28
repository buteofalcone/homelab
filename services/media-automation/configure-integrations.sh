#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"

require_root
load_env

container_running qbittorrent || die 'qBittorrent is not running.'
container_running sonarr || die 'Sonarr is not running.'
container_running prowlarr || die 'Prowlarr is not running.'

readonly media_user="${MEDIA_ADMIN_USER:-butenko}"
readonly media_password="$(</etc/homelab/qbittorrent-password)"
readonly sonarr_api_key="$(sed -n 's#.*<ApiKey>\([^<]*\)</ApiKey>.*#\1#p' /srv/appdata/sonarr/config.xml)"
readonly prowlarr_api_key="$(sed -n 's#.*<ApiKey>\([^<]*\)</ApiKey>.*#\1#p' /srv/appdata/prowlarr/config.xml)"
[[ -n ${sonarr_api_key} && -n ${prowlarr_api_key} ]] || die 'An Arr API key is missing.'

readonly work_dir="$(mktemp -d)"
trap 'rm -rf -- "${work_dir}"' EXIT

arr_get() {
  local container="$1" port="$2" version="$3" key="$4" path="$5" output="$6"
  docker exec -e ARR_KEY="${key}" -e ARR_URL="http://127.0.0.1:${port}/api/${version}/${path}" \
    "${container}" /bin/sh -c 'curl -fsS -H "X-Api-Key: ${ARR_KEY}" "${ARR_URL}"' >"${output}"
}

arr_write() {
  local container="$1" port="$2" version="$3" key="$4" method="$5" path="$6" input="$7" output="$8"
  docker exec -i -e ARR_KEY="${key}" -e ARR_METHOD="${method}" \
    -e ARR_URL="http://127.0.0.1:${port}/api/${version}/${path}" \
    "${container}" /bin/sh -c 'curl -fsS --request "${ARR_METHOD}" -H "X-Api-Key: ${ARR_KEY}" -H "Content-Type: application/json" --data-binary @- "${ARR_URL}"' \
    <"${input}" >"${output}"
}

resource_id() {
  local file="$1" name="$2"
  python3 - "${file}" "${name}" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    items = json.load(handle)
for item in items:
    if item.get("name") == sys.argv[2]:
        print(item.get("id", ""))
        break
PY
}

echo STEP_SONARR_ROOT_FOLDER
arr_get sonarr 8989 v3 "${sonarr_api_key}" rootfolder "${work_dir}/rootfolders.json"
if ! python3 - "${work_dir}/rootfolders.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    raise SystemExit(0 if any(item.get("path") == "/data/media/TV" for item in json.load(handle)) else 1)
PY
then
  printf '%s' '{"path":"/data/media/TV"}' >"${work_dir}/rootfolder-payload.json"
  arr_write sonarr 8989 v3 "${sonarr_api_key}" POST rootfolder \
    "${work_dir}/rootfolder-payload.json" "${work_dir}/rootfolder-response.json"
fi

echo STEP_SONARR_QBITTORRENT
arr_get sonarr 8989 v3 "${sonarr_api_key}" downloadclient/schema "${work_dir}/downloadclient-schema.json"
arr_get sonarr 8989 v3 "${sonarr_api_key}" downloadclient "${work_dir}/downloadclients.json"
download_client_id="$(resource_id "${work_dir}/downloadclients.json" qBittorrent)"
MEDIA_USER="${media_user}" MEDIA_PASSWORD="${media_password}" RESOURCE_ID="${download_client_id}" \
  python3 - "${work_dir}/downloadclient-schema.json" "${work_dir}/downloadclient-payload.json" <<'PY'
import json, os, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    item = next(value for value in json.load(handle) if value.get("implementation") == "QBittorrent")
item.update({"enable": True, "name": "qBittorrent", "priority": 1,
             "removeCompletedDownloads": True, "removeFailedDownloads": True})
values = {
    "host": "qbittorrent", "port": 8080, "useSsl": False,
    "username": os.environ["MEDIA_USER"], "password": os.environ["MEDIA_PASSWORD"],
    "tvCategory": "tv-sonarr", "initialState": 0,
    "sequentialOrder": False, "firstAndLast": False, "contentLayout": 0,
}
for field in item["fields"]:
    if field.get("name") in values:
        field["value"] = values[field["name"]]
if os.environ.get("RESOURCE_ID"):
    item["id"] = int(os.environ["RESOURCE_ID"])
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(item, handle)
PY
if [[ -n ${download_client_id} ]]; then
  arr_write sonarr 8989 v3 "${sonarr_api_key}" PUT "downloadclient/${download_client_id}" \
    "${work_dir}/downloadclient-payload.json" "${work_dir}/downloadclient-response.json"
else
  arr_write sonarr 8989 v3 "${sonarr_api_key}" POST downloadclient \
    "${work_dir}/downloadclient-payload.json" "${work_dir}/downloadclient-response.json"
fi

echo STEP_PROWLARR_SONARR
arr_get prowlarr 9696 v1 "${prowlarr_api_key}" applications/schema "${work_dir}/application-schema.json"
arr_get prowlarr 9696 v1 "${prowlarr_api_key}" applications "${work_dir}/applications.json"
application_id="$(resource_id "${work_dir}/applications.json" Sonarr)"
SONARR_API_KEY="${sonarr_api_key}" RESOURCE_ID="${application_id}" \
  python3 - "${work_dir}/application-schema.json" "${work_dir}/application-payload.json" <<'PY'
import json, os, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    item = next(value for value in json.load(handle) if value.get("implementation") == "Sonarr")
item.update({"enable": True, "name": "Sonarr", "syncLevel": "fullSync"})
values = {
    "prowlarrUrl": "http://prowlarr:9696", "baseUrl": "http://sonarr:8989",
    "apiKey": os.environ["SONARR_API_KEY"],
    "syncCategories": [5000, 5010, 5020, 5030, 5040, 5045, 5050, 5080, 5090],
}
for field in item["fields"]:
    if field.get("name") in values:
        field["value"] = values[field["name"]]
if os.environ.get("RESOURCE_ID"):
    item["id"] = int(os.environ["RESOURCE_ID"])
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(item, handle)
PY
if [[ -n ${application_id} ]]; then
  arr_write prowlarr 9696 v1 "${prowlarr_api_key}" PUT "applications/${application_id}" \
    "${work_dir}/application-payload.json" "${work_dir}/application-response.json"
else
  arr_write prowlarr 9696 v1 "${prowlarr_api_key}" POST applications \
    "${work_dir}/application-payload.json" "${work_dir}/application-response.json"
fi

echo STEP_PROWLARR_INTERNET_ARCHIVE
arr_get prowlarr 9696 v1 "${prowlarr_api_key}" indexer/schema "${work_dir}/indexer-schema.json"
arr_get prowlarr 9696 v1 "${prowlarr_api_key}" indexer "${work_dir}/indexers.json"
indexer_id="$(resource_id "${work_dir}/indexers.json" 'Internet Archive')"
RESOURCE_ID="${indexer_id}" python3 - "${work_dir}/indexer-schema.json" "${work_dir}/indexer-payload.json" <<'PY'
import json, os, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    item = next(value for value in json.load(handle) if value.get("name") == "Internet Archive")
item.update({"enable": True, "name": "Internet Archive", "appProfileId": 1, "priority": 25})
values = {"baseUrl": "https://archive.org/", "titleOnly": True, "noMagnet": False,
          "sort": 2, "type": 1, "torrentBaseSettings.preferMagnetUrl": False}
for field in item["fields"]:
    if field.get("name") in values:
        field["value"] = values[field["name"]]
if os.environ.get("RESOURCE_ID"):
    item["id"] = int(os.environ["RESOURCE_ID"])
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(item, handle)
PY
if [[ -n ${indexer_id} ]]; then
  arr_write prowlarr 9696 v1 "${prowlarr_api_key}" PUT "indexer/${indexer_id}" \
    "${work_dir}/indexer-payload.json" "${work_dir}/indexer-response.json"
else
  arr_write prowlarr 9696 v1 "${prowlarr_api_key}" POST indexer \
    "${work_dir}/indexer-payload.json" "${work_dir}/indexer-response.json"
fi

echo MEDIA_AUTOMATION_INTEGRATIONS_OK
