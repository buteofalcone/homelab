#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
load_env

cd "${REPO_DIR}"

git status --short
git pull --ff-only
docker compose config >/dev/null
docker compose pull
docker compose up -d --remove-orphans
docker image prune -f

docker compose ps
