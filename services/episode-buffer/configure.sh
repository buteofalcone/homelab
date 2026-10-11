#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"
require_root

readonly config_dir="/etc/homelab"
readonly config_file="${config_dir}/episode-buffer.env"
readonly example_file="${REPO_DIR}/config/episode-buffer.env.example"

install -d -m 0700 "${config_dir}" /srv/appdata/episode-buffer /srv/storage/recycle/sonarr
chown "${PUID:-1000}:${PGID:-1000}" /srv/storage/recycle/sonarr

read -r -p 'Primary Jellyfin username: ' jellyfin_username
read -r -s -p 'Dedicated Jellyfin API key: ' jellyfin_api_key
printf '\n'
[[ -n "${jellyfin_username}" && -n "${jellyfin_api_key}" ]] || die 'Username and API key are required.'

temp_file="$(mktemp)"
trap 'rm -f "${temp_file}"' EXIT
cp "${example_file}" "${temp_file}"
python3 - "${temp_file}" "${jellyfin_username}" "${jellyfin_api_key}" <<'PY'
import pathlib
import shlex
import sys

path = pathlib.Path(sys.argv[1])
values = {"JELLYFIN_USERNAME": sys.argv[2], "JELLYFIN_API_KEY": sys.argv[3]}
lines = []
for line in path.read_text(encoding="utf-8").splitlines():
    key = line.split("=", 1)[0]
    if key in values:
        line = f"{key}={shlex.quote(values[key])}"
    lines.append(line)
path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
install -o root -g root -m 0600 "${temp_file}" "${config_file}"

"${REPO_DIR}/services/episode-buffer/run.sh" prepare
"${REPO_DIR}/services/episode-buffer/run.sh" baseline
"${REPO_DIR}/services/episode-buffer/run.sh" verify
printf 'EPISODE_BUFFER_CONFIGURE_OK mode=dry-run\n'
