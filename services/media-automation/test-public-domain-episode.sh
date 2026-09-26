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

sonarr_get "series/${series_id}" "${work_dir}/series-current.json"
python3 - "${work_dir}/series-current.json" "${work_dir}/series-monitor-payload.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    item = json.load(handle)
if item.get("cleanTitle") != "theadventuresozzieharriet":
    raise SystemExit(f"Unexpected series clean title: {item.get('cleanTitle')}")
item["monitored"] = True
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(item, handle)
PY
sonarr_write PUT "series/${series_id}" "${work_dir}/series-monitor-payload.json" "${work_dir}/series-monitor-response.json"

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

sonarr_get "queue?seriesIds=${series_id}&includeUnknownSeriesItems=true&page=1&pageSize=100" "${work_dir}/queue.json"
presence="$(python3 - "${work_dir}/episode-response.json" "${work_dir}/queue.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    episode = json.load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    queue = json.load(handle)
queued = any(item.get("episodeId") == episode["id"] for item in queue.get("records", []))
print("file" if episode.get("hasFile") else "queued" if queued else "missing")
PY
)"

if [[ ${presence} == file ]]; then
  echo STEP_PUBLIC_DOMAIN_RELEASE_ALREADY_PRESENT
elif [[ ${presence} == missing ]]; then
  echo STEP_PUBLIC_DOMAIN_RELEASE_PUSH
  sonarr_get downloadclient "${work_dir}/download-clients.json"
  python3 - "${work_dir}/download-clients.json" "${work_dir}/release-payload.json" <<'PY'
import json, sys

with open(sys.argv[1], encoding="utf-8") as handle:
    client = next(item for item in json.load(handle) if item.get("implementation") == "QBittorrent")

payload = {
    "title": "The.Adventures.Ozzie.Harriet.S01E01.The.Rivals.480p.WEB-DL.x264",
    "size": 286244644,
    "downloadUrl": "https://archive.org/download/season-1-episode-1/season-1-episode-1_archive.torrent",
    "infoUrl": "https://archive.org/details/season-1-episode-1",
    "publishDate": "2019-01-01T00:00:00Z",
    "protocol": "torrent",
    "downloadClientId": client["id"],
}
if not 1_000_000 <= payload["size"] <= 1_000_000_000:
    raise SystemExit("Public-domain test release exceeds the 1 GB safety limit")
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(payload, handle)
print(f"Selected exact Internet Archive episode ({payload['size']} bytes)")
PY
  if ! sonarr_write POST release/push "${work_dir}/release-payload.json" "${work_dir}/release-response.json"; then
    cat "${work_dir}/release-response.json" >&2
    die 'Sonarr release push failed.'
  fi
  python3 - "${work_dir}/release-response.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    items = json.load(handle)
if len(items) != 1:
    raise SystemExit(f"Unexpected Sonarr release response: {items}")
item = items[0]
if item.get("rejected"):
    raise SystemExit(f"Sonarr rejected the release: {item.get('rejections')}")
print("Sonarr accepted the exact public-domain release")
PY
fi

if [[ ${presence} != file ]]; then
  "${service_dir}/configure-public-domain-torrent.sh"
fi

echo MEDIA_PUBLIC_DOMAIN_TEST_STARTED
