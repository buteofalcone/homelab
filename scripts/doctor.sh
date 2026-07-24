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

check "Docker daemon" docker info
check "Docker Compose" docker compose version
check "Storage mount exists" mountpoint /srv/storage
check "Repository environment file" test -f "${ENV_FILE}"
check "Compose configuration" docker compose --project-directory "${REPO_DIR}" config
check "Homepage HTTP" curl -fsS "http://127.0.0.1:${HOMEPAGE_PORT:-3000}"
check "Beszel HTTP" curl -fsS "http://127.0.0.1:${BESZEL_PORT:-8090}"
check "Uptime Kuma HTTP" curl -fsS "http://127.0.0.1:${UPTIME_KUMA_PORT:-3001}"
check "Portainer HTTPS" curl -kfsS "https://127.0.0.1:${PORTAINER_PORT:-9443}"

printf '\nContainers:\n'
docker compose --project-directory "${REPO_DIR}" ps

exit "${failed}"
