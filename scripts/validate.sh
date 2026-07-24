#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
load_env

while IFS= read -r -d '' script; do
  bash -n "${script}"
done < <(find "${REPO_DIR}/scripts" -type f -name '*.sh' -print0)

compose --profile nextcloud --profile immich --profile jellyfin --profile beszel-agent config --quiet

echo "Shell and Docker Compose validation passed."
