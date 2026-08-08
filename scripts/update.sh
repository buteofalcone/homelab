#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
load_env

profile_args=()
for profile in "$@"; do
  profile_args+=(--profile "${profile}")
done

cd "${REPO_DIR}"
git status --short
git pull --ff-only
compose "${profile_args[@]}" config --quiet
compose "${profile_args[@]}" pull
compose "${profile_args[@]}" up -d --remove-orphans
docker image prune -f
compose "${profile_args[@]}" ps
