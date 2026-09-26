#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
load_env

printf 'STEP_GIT_STATE\n'
git -C "${REPO_DIR}" status --short --branch

printf 'STEP_UBUNTU_UPDATES\n'
if command -v nala >/dev/null 2>&1; then
  nala list --upgradable 2>/dev/null || true
else
  apt list --upgradable 2>/dev/null || true
fi

printf 'STEP_RENOVATE\n'
printf 'Review the Dependency Dashboard and open PRs at:\n'
printf 'https://github.com/buteofalcone/homelab/issues\n'

printf 'STEP_WATCHTOWER\n'
if container_running watchtower; then
  docker logs --since 168h watchtower 2>&1 \
    | grep -Ei 'update available|new image|found new|failed|error' \
    | tail -n 100 || printf 'No update notices in the last 7 days.\n'
else
  printf 'Watchtower is not running.\n'
fi

printf 'UPDATE_CHECK_OK\n'
