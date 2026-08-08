#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
load_env

failed=0

check() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'OK   %s\n' "${description}"
  else
    printf 'FAIL %s\n' "${description}"
    failed=1
  fi
}

check_optional_http() {
  local container="$1"
  local description="$2"
  local url="$3"
  if container_running "${container}"; then
    check "${description}" curl -fsS "${url}"
  else
    printf 'SKIP %s (container is not running)\n' "${description}"
  fi
}

check "Docker daemon" docker info
check "Docker Compose" docker compose version
check "Storage mount exists" mountpoint /srv/storage
check "Repository environment file" test -f "${ENV_FILE}"
check "Compose configuration" compose --profile nextcloud --profile immich --profile jellyfin --profile beszel-agent --profile agents --profile books config --quiet
check "Homepage HTTP" curl -fsS "http://127.0.0.1:${HOMEPAGE_PORT:-3000}"
check "Beszel HTTP" curl -fsS "http://127.0.0.1:${BESZEL_PORT:-8090}"
check "Uptime Kuma HTTP" curl -fsS "http://127.0.0.1:${UPTIME_KUMA_PORT:-3001}"
check "Portainer HTTPS" curl -kfsS "https://127.0.0.1:${PORTAINER_PORT:-9443}"
check "Caddy trusted HTTPS" curl -fsS --resolve "home.${BASE_DOMAIN}:443:127.0.0.1" "https://home.${BASE_DOMAIN}/"

check_optional_http nextcloud "Nextcloud HTTP" "http://127.0.0.1:${NEXTCLOUD_PORT:-8082}/status.php"
if container_running nextcloud; then
  check "Nextcloud Talk" "${REPO_DIR}/services/nextcloud-talk/verify.sh"
fi
check_optional_http immich-server "Immich HTTP" "http://127.0.0.1:${IMMICH_PORT:-2283}/api/server/ping"
check_optional_http jellyfin "Jellyfin HTTP" "http://127.0.0.1:${JELLYFIN_PORT:-8096}/health"
check_optional_http open-webui "Open WebUI HTTP" "http://127.0.0.1:${OPEN_WEBUI_PORT:-3002}/health"

if container_running calibre; then
  check "Calibre GUI health" test "$(docker inspect -f '{{.State.Health.Status}}' calibre)" = healthy
else
  printf 'SKIP Calibre GUI (container is not running)\n'
fi

if container_running calibre; then
  check "Calibre Content Server HTTPS" curl -fsS --resolve "books.${BASE_DOMAIN}:443:127.0.0.1" "https://books.${BASE_DOMAIN}/"
else
  printf 'SKIP Calibre Content Server (Calibre container is not running)\n'
fi

printf '\nContainers:\n'
compose --profile nextcloud --profile immich --profile jellyfin --profile beszel-agent --profile agents --profile books ps

exit "${failed}"
