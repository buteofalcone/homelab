#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"

require_root
load_env
mountpoint -q /srv/storage || die '/srv/storage is not mounted.'
container_running sonarr || die 'Sonarr is not running.'

readonly min_free_gb="${MEDIA_MIN_FREE_GB:-80}"
readonly available_bytes="$(df --output=avail -B1 /srv/storage | tail -n 1 | tr -d ' ')"
readonly required_bytes="$((min_free_gb * 1024 * 1024 * 1024))"
(( available_bytes >= required_bytes )) || die "Less than ${min_free_gb} GiB is free on /srv/storage."

readonly api_key="$(sed -n 's#.*<ApiKey>\([^<]*\)</ApiKey>.*#\1#p' /srv/appdata/sonarr/config.xml)"
[[ -n ${api_key} ]] || die 'Sonarr API key is missing.'
readonly work_dir="$(mktemp -d)"
trap 'rm -rf -- "${work_dir}"' EXIT

sonarr_get() {
  local path="$1" output="$2"
  docker exec -e ARR_KEY="${api_key}" -e ARR_PATH="${path}" sonarr /bin/sh -c \
    'curl -fsS -H "X-Api-Key: ${ARR_KEY}" "http://127.0.0.1:8989/api/v3/${ARR_PATH}"' >"${output}"
}

sonarr_write() {
  local method="$1" path="$2" input="$3" output="$4"
  docker exec -i -e ARR_KEY="${api_key}" -e ARR_METHOD="${method}" -e ARR_PATH="${path}" sonarr /bin/sh -c \
    'curl -fsS --request "${ARR_METHOD}" -H "X-Api-Key: ${ARR_KEY}" -H "Content-Type: application/json" --data-binary @- "http://127.0.0.1:8989/api/v3/${ARR_PATH}"' \
    <"${input}" >"${output}"
}

echo STEP_PUBLIC_DOMAIN_SERIES
sonarr_get series "${work_dir}/series.json"
series_id="$(python3 - "${work_dir}/series.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    for item in json.load(handle):
        if item.get("tvdbId") == 71598:
            print(item["id"])
            break
PY
)"

if [[ -z ${series_id} ]]; then
  sonarr_get 'series/lookup?term=tvdb%3A71598' "${work_dir}/lookup.json"
  sonarr_get qualityprofile "${work_dir}/profiles.json"
  python3 - "${work_dir}/lookup.json" "${work_dir}/profiles.json" "${work_dir}/series-payload.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    item = next(value for value in json.load(handle) if value.get("tvdbId") == 71598)
with open(sys.argv[2], encoding="utf-8") as handle:
    profile = next(value for value in json.load(handle) if value.get("name") == "SD")
item.update({
    "qualityProfileId": profile["id"],
    "rootFolderPath": "/data/media/TV",
    "monitored": False,
    "seasonFolder": True,
    "addOptions": {
        "monitor": "none",
        "searchForMissingEpisodes": False,
        "searchForCutoffUnmetEpisodes": False,
    },
})
with open(sys.argv[3], "w", encoding="utf-8") as handle:
    json.dump(item, handle)
PY
  sonarr_write POST series "${work_dir}/series-payload.json" "${work_dir}/series-response.json"
  series_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["id"])' "${work_dir}/series-response.json")"
fi

echo STEP_PUBLIC_DOMAIN_EPISODE
sonarr_get "episode?seriesId=${series_id}" "${work_dir}/episodes.json"
episode_id="$(python3 - "${work_dir}/episodes.json" "${work_dir}/episode-payload.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    item = next(value for value in json.load(handle) if value.get("seasonNumber") == 1 and value.get("episodeNumber") == 1)
item["monitored"] = True
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(item, handle)
print(item["id"])
PY
)"
sonarr_write PUT "episode/${episode_id}" "${work_dir}/episode-payload.json" "${work_dir}/episode-response.json"

echo STEP_PUBLIC_DOMAIN_RELEASE
sonarr_get "release?episodeId=${episode_id}" "${work_dir}/releases.json"
python3 - "${work_dir}/releases.json" "${work_dir}/release-payload.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    items = json.load(handle)
candidates = [
    item for item in items
    if "the rivals" in item.get("title", "").lower()
    and "internet archive" in item.get("indexer", "").lower()
    and 1_000_000 <= item.get("size", 0) <= 1_000_000_000
]
if len(candidates) != 1:
    summary = [(item.get("title"), item.get("size"), item.get("rejections")) for item in candidates]
    raise SystemExit(f"Expected one small Internet Archive release, found {len(candidates)}: {summary}")
item = candidates[0]
item["downloadAllowed"] = True
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(item, handle)
print(f"Selected {item['title']} ({item['size']} bytes)")
PY
sonarr_write POST release "${work_dir}/release-payload.json" "${work_dir}/release-response.json"

echo MEDIA_PUBLIC_DOMAIN_TEST_STARTED
