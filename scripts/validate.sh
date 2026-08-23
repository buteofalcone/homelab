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

python3 -m json.tool "${REPO_DIR}/config/service-catalog.json" >/dev/null
python3 "${REPO_DIR}/scripts/render-service-catalog.py" \
  --catalog "${REPO_DIR}/config/service-catalog.json" \
  --output "${REPO_DIR}/config/homepage/services.yaml" \
  --check

compose --profile nextcloud --profile immich --profile immich-ml-fallback --profile jellyfin --profile beszel-agent --profile timemachine --profile agents --profile books --profile clickhouse --profile photo-ai config --quiet

echo "Shell, service catalog and Docker Compose validation passed."
