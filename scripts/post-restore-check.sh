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

check 'Recovery host prerequisites' "${REPO_DIR}/scripts/recovery-preflight.sh"
check 'Compose configuration' compose --profile nextcloud --profile immich --profile jellyfin --profile beszel-agent --profile timemachine --profile agents --profile books config --quiet
check 'Backup timer is active' systemctl is-active --quiet homelab-backup.timer
check 'Health timer is active' systemctl is-active --quiet homelab-health.timer
check 'Nextcloud database accepts connections' docker exec nextcloud-db pg_isready -U nextcloud -d nextcloud
check 'Nextcloud reports installed state' docker exec -u www-data nextcloud php occ status --exit-code
check 'Immich database accepts connections' docker exec immich-database pg_isready -U postgres -d immich
check 'Immich API health' curl -fsS "http://127.0.0.1:${IMMICH_PORT:-2283}/api/server/ping"
check 'Caddy trusted Homepage HTTPS' curl -fsS --resolve "home.${BASE_DOMAIN}:443:127.0.0.1" "https://home.${BASE_DOMAIN}/"
check 'Caddy trusted Nextcloud HTTPS' curl -fsS --resolve "nextcloud.${BASE_DOMAIN}:443:127.0.0.1" "https://nextcloud.${BASE_DOMAIN}/status.php"
check 'Caddy trusted Immich HTTPS' curl -fsS --resolve "immich.${BASE_DOMAIN}:443:127.0.0.1" "https://immich.${BASE_DOMAIN}/api/server/ping"

if container_running timemachine; then
  check 'Time Machine container health' test "$(docker inspect -f '{{.State.Health.Status}}' timemachine)" = healthy
else
  printf 'SKIP Time Machine container is not running\n'
fi

if container_running open-webui; then
  check 'Open WebUI health' curl -fsS "http://127.0.0.1:${OPEN_WEBUI_PORT:-3002}/health"
else
  printf 'SKIP Open WebUI container is not running\n'
fi

if container_running calibre; then
  check 'Calibre GUI health' test "$(docker inspect -f '{{.State.Health.Status}}' calibre)" = healthy
else
  printf 'SKIP Calibre GUI container is not running\n'
fi

if container_running calibre; then
  check 'Calibre Content Server HTTPS' curl -fsS --resolve "books.${BASE_DOMAIN}:443:127.0.0.1" "https://books.${BASE_DOMAIN}/"
else
  printf 'SKIP Calibre Content Server because Calibre is not running\n'
fi

if (( failed == 0 )); then
  printf '\nPOST_RESTORE_CHECK_OK\n'
else
  printf '\nPOST_RESTORE_CHECK_FAILED\n'
fi

exit "${failed}"
