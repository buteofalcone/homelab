#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"

require_root
load_env
container_running qbittorrent || die 'qBittorrent is not running.'

readonly media_user="${MEDIA_ADMIN_USER:-butenko}"
readonly old_path='season-1-episode-1/Season 1 Episode 1.ia.mp4'
readonly new_path='season-1-episode-1/The.Adventures.Ozzie.Harriet.S01E01.The.Rivals.480p.WEB-DL.x264.mp4'
readonly work_dir="$(mktemp -d)"
trap 'docker exec qbittorrent rm -f /tmp/public-domain-cookie /tmp/public-domain-login >/dev/null 2>&1 || true; rm -rf -- "${work_dir}"' EXIT

docker exec -e QB_USER="${media_user}" qbittorrent sh -c '
  password="$(cat /run/secrets/qbittorrent-password)"
  rm -f /tmp/public-domain-cookie
  status="$(curl -sS -o /tmp/public-domain-login -w "%{http_code}" -c /tmp/public-domain-cookie \
    -H "Referer: http://localhost:8080" \
    --data-urlencode "username=${QB_USER}" --data-urlencode "password=${password}" \
    http://localhost:8080/api/v2/auth/login)"
  body="$(cat /tmp/public-domain-login)"
  { [ "${status}" = 204 ] || { [ "${status}" = 200 ] && [ "${body}" = "Ok." ]; }; }
' || die 'Could not authenticate to qBittorrent.'

echo STEP_PUBLIC_DOMAIN_TORRENT_METADATA
torrent_hash=''
for attempt in {1..30}; do
  docker exec qbittorrent curl -fsS -b /tmp/public-domain-cookie -H 'Referer: http://localhost:8080' \
    'http://localhost:8080/api/v2/torrents/info?category=tv-sonarr' >"${work_dir}/torrents.json"
  torrent_hash="$(python3 - "${work_dir}/torrents.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    items = [item for item in json.load(handle) if item.get("name") == "season-1-episode-1"]
if len(items) == 1:
    print(items[0]["hash"])
PY
)"
  [[ -n ${torrent_hash} ]] && break
  sleep 1
done
[[ -n ${torrent_hash} ]] || die 'The exact Internet Archive torrent did not appear in qBittorrent.'

docker exec -e TORRENT_HASH="${torrent_hash}" qbittorrent sh -c '
  curl -fsS -b /tmp/public-domain-cookie -H "Referer: http://localhost:8080" \
    "http://localhost:8080/api/v2/torrents/files?hash=${TORRENT_HASH}"
' >"${work_dir}/files.json"

rename_required="$(python3 - "${work_dir}/files.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    files = json.load(handle)
expected = [
    (0, 142739698),
    (1, 142739698),
    (2, 8033),
    (3, 20480),
    (4, 1223),
]
actual = [(item.get("index"), item.get("size")) for item in files]
if actual != expected:
    raise SystemExit(f"Unexpected Internet Archive torrent contents: {actual}")
old = "season-1-episode-1/Season 1 Episode 1.ia.mp4"
new = "season-1-episode-1/The.Adventures.Ozzie.Harriet.S01E01.The.Rivals.480p.WEB-DL.x264.mp4"
if files[0].get("name") not in (old, new):
    raise SystemExit(f"Unexpected selected file: {files[0].get('name')}")
print("yes" if files[0].get("name") == old else "no")
PY
)"

if [[ ${rename_required} == yes ]]; then
  docker exec -e TORRENT_HASH="${torrent_hash}" -e OLD_PATH="${old_path}" -e NEW_PATH="${new_path}" qbittorrent sh -c '
    curl -fsS -b /tmp/public-domain-cookie -H "Referer: http://localhost:8080" \
      --data-urlencode "hash=${TORRENT_HASH}" \
      --data-urlencode "oldPath=${OLD_PATH}" \
      --data-urlencode "newPath=${NEW_PATH}" \
      http://localhost:8080/api/v2/torrents/renameFile
  '
fi

echo STEP_PUBLIC_DOMAIN_SINGLE_FILE
docker exec -e TORRENT_HASH="${torrent_hash}" qbittorrent sh -c '
  curl -fsS -b /tmp/public-domain-cookie -H "Referer: http://localhost:8080" \
    --data-urlencode "hash=${TORRENT_HASH}" \
    --data-urlencode "id=1|2|3|4" \
    --data-urlencode "priority=0" \
    http://localhost:8080/api/v2/torrents/filePrio
  curl -fsS -b /tmp/public-domain-cookie -H "Referer: http://localhost:8080" \
    --data-urlencode "hash=${TORRENT_HASH}" \
    --data-urlencode "urls=https://ia601407.us.archive.org/30/items/" \
    http://localhost:8080/api/v2/torrents/addWebSeeds
'

echo PUBLIC_DOMAIN_TORRENT_CONFIGURED
