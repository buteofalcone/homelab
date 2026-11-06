#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=storage-guard.sh
source "${service_dir}/storage-guard.sh"
photo_load_config
require_root
photo_assert_takeout

output_dir="${PHOTO_AI_ROOT}/manifests"
install -d -m 0750 -o "${PUID}" -g "${PGID}" "${output_dir}"
args=(--root "${TAKEOUT_ROOT}" --output-dir "${output_dir}")
if [[ ${1:-} == --hash-duplicate-candidates ]]; then
  args+=(--hash-duplicate-candidates)
elif [[ -n ${1:-} ]]; then
  die 'Usage: inspect-takeout.sh [--hash-duplicate-candidates]'
fi

python3 "${service_dir}/inspect-takeout.py" "${args[@]}"
chown "${PUID}:${PGID}" "${output_dir}"/takeout-*.json "${output_dir}"/takeout-*.jsonl
chmod 0640 "${output_dir}"/takeout-*.json "${output_dir}"/takeout-*.jsonl
echo "IMMICH_TAKEOUT_INSPECT_OK output=${output_dir}/takeout-report.json"
