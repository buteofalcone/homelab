#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"

load_env
container_running sonarr || die 'Sonarr is not running.'
container_running qbittorrent || die 'qBittorrent is not running.'
container_running jellyfin || die 'Jellyfin is not running.'

readonly api_key="$(docker exec sonarr sed -n 's#.*<ApiKey>\([^<]*\)</ApiKey>.*#\1#p' /config/config.xml)"
readonly media_user="${MEDIA_ADMIN_USER:-butenko}"
readonly selected_relative='season-1-episode-1/The.Adventures.Ozzie.Harriet.S01E01.The.Rivals.480p.WEB-DL.x264.mp4'
readonly download_path="/srv/storage/downloads/torrents/${selected_relative}"
readonly work_dir="$(mktemp -d)"
trap 'docker exec qbittorrent rm -f /tmp/public-domain-verify-cookie /tmp/public-domain-verify-login >/dev/null 2>&1 || true; rm -rf -- "${work_dir}"' EXIT

sonarr_get() {
  local path="$1" output="$2"
  docker exec -e ARR_KEY="${api_key}" -e ARR_PATH="${path}" sonarr sh -c \
    'curl -fsS -H "X-Api-Key: ${ARR_KEY}" "http://127.0.0.1:8989/api/v3/${ARR_PATH}"' >"${output}"
}

echo STEP_PUBLIC_DOMAIN_SONARR_IMPORT
sonarr_get series "${work_dir}/series.json"
series_id="$(python3 - "${work_dir}/series.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    print(next(item["id"] for item in json.load(handle) if item.get("tvdbId") == 71598))
PY
)"
sonarr_get "episode?seriesId=${series_id}" "${work_dir}/episodes.json"
episode_file_id="$(python3 - "${work_dir}/episodes.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    item = next(value for value in json.load(handle) if value.get("seasonNumber") == 1 and value.get("episodeNumber") == 1)
assert item.get("hasFile"), item
print(item["episodeFileId"])
PY
)"
sonarr_get "episodefile/${episode_file_id}" "${work_dir}/episode-file.json"
library_path="$(python3 - "${work_dir}/episode-file.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    item = json.load(handle)
assert item.get("size") == 142739698, item
path = item["path"]
assert path.startswith("/data/media/TV/"), path
print("/srv/storage" + path.removeprefix("/data"))
PY
)"

docker exec -e QB_USER="${media_user}" qbittorrent sh -c '
  password="$(cat /run/secrets/qbittorrent-password)"
  status="$(curl -sS -o /tmp/public-domain-verify-login -w "%{http_code}" -c /tmp/public-domain-verify-cookie \
    -H "Referer: http://localhost:8080" \
    --data-urlencode "username=${QB_USER}" --data-urlencode "password=${password}" \
    http://localhost:8080/api/v2/auth/login)"
  body="$(cat /tmp/public-domain-verify-login)"
  { [ "${status}" = 204 ] || { [ "${status}" = 200 ] && [ "${body}" = "Ok." ]; }; }
' || die 'Could not authenticate to qBittorrent.'

echo STEP_PUBLIC_DOMAIN_QBITTORRENT_COMPLETE
docker exec qbittorrent curl -fsS -b /tmp/public-domain-verify-cookie -H 'Referer: http://localhost:8080' \
  'http://localhost:8080/api/v2/torrents/info?category=tv-sonarr' >"${work_dir}/torrents.json"
torrent_hash="$(python3 - "${work_dir}/torrents.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    items = [item for item in json.load(handle) if item.get("name") == "season-1-episode-1"]
assert len(items) == 1, items
item = items[0]
assert item.get("progress") == 1 and item.get("amount_left") == 0, item
print(item["hash"])
PY
)"
docker exec -e TORRENT_HASH="${torrent_hash}" qbittorrent sh -c '
  curl -fsS -b /tmp/public-domain-verify-cookie -H "Referer: http://localhost:8080" \
    "http://localhost:8080/api/v2/torrents/files?hash=${TORRENT_HASH}"
' >"${work_dir}/files.json"
python3 - "${work_dir}/files.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    files = json.load(handle)
assert files[0].get("name") == "season-1-episode-1/The.Adventures.Ozzie.Harriet.S01E01.The.Rivals.480p.WEB-DL.x264.mp4", files[0]
assert files[0].get("progress") == 1 and files[0].get("priority") > 0, files[0]
assert all(item.get("priority") == 0 for item in files[1:]), files[1:]
PY

echo STEP_PUBLIC_DOMAIN_HARDLINK
[[ -f ${download_path} && -f ${library_path} ]] || die 'Download or library file is missing.'
download_stat="$(stat -c '%d:%i:%h:%s' "${download_path}")"
library_stat="$(stat -c '%d:%i:%h:%s' "${library_path}")"
[[ ${download_stat} == "${library_stat}" ]] || die "Download and library paths are not the same hardlink: ${download_stat} != ${library_stat}"
link_count="$(stat -c '%h' "${library_path}")"
(( link_count >= 2 )) || die 'Imported file does not have at least two hardlinks.'

jellyfin_path="/media/TV/${library_path#*/srv/storage/media/TV/}"
docker exec -e MEDIA_FILE="${jellyfin_path}" jellyfin sh -c 'test -f "${MEDIA_FILE}"' \
  || die 'Jellyfin cannot see the imported episode.'

echo MEDIA_PUBLIC_DOMAIN_TEST_VERIFY_OK
