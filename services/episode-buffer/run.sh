#!/usr/bin/env bash
set -Eeuo pipefail

readonly repo_dir="$(cd "$(dirname "$0")/../.." && pwd)"
readonly config_file="/etc/homelab/episode-buffer.env"
readonly sonarr_config="/srv/appdata/sonarr/config.xml"

[[ -r "${config_file}" ]] || { echo "ERROR: Missing ${config_file}" >&2; exit 1; }
[[ -r "${sonarr_config}" ]] || { echo "ERROR: Missing ${sonarr_config}" >&2; exit 1; }
docker inspect sonarr jellyfin >/dev/null 2>&1 || { echo 'ERROR: Sonarr and Jellyfin must be running.' >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "${config_file}"
set +a

SONARR_API_KEY="$(sed -n 's#.*<ApiKey>\([^<]*\)</ApiKey>.*#\1#p' "${sonarr_config}")"
SONARR_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' sonarr)"
[[ -n "${SONARR_API_KEY}" && -n "${SONARR_IP}" ]] || { echo 'ERROR: Cannot resolve Sonarr API access.' >&2; exit 1; }

export SONARR_API_KEY
export SONARR_URL="http://${SONARR_IP}:8989"
export JELLYFIN_URL="${JELLYFIN_URL:-http://127.0.0.1:8096}"
export EPISODE_BUFFER_STATE="${EPISODE_BUFFER_STATE:-/srv/appdata/episode-buffer/state.json}"

exec python3 "${repo_dir}/services/episode-buffer/episode_buffer.py" "${1:-run}"
