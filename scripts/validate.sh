#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
load_env

while IFS= read -r -d '' script; do
  bash -n "${script}"
done < <(find "${REPO_DIR}/scripts" -type f -name '*.sh' -print0)

if [[ -d "${REPO_DIR}/services" ]]; then
  while IFS= read -r -d '' script; do
    bash -n "${script}"
  done < <(find "${REPO_DIR}/services" -type f -name '*.sh' -print0)
fi

compose --profile nextcloud --profile immich --profile jellyfin --profile beszel-agent --profile timemachine --profile agents --profile books config --quiet

echo "Shell and Docker Compose validation passed."
