#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"
source "${repo_dir}/services/immich-migration/storage-guard.sh"
require_root
load_env
photo_load_config
photo_assert_mount
[[ -n ${PHOTO_AI_API_TOKEN:-} && ${PHOTO_AI_API_TOKEN} != CHANGE_ME_* ]] || die "PHOTO_AI_API_TOKEN is not configured."
work_dir="$(mktemp -d /tmp/photo-ai-reconcile.XXXXXX)"
trap 'rm -rf -- "${work_dir}"' EXIT
curl_config="${work_dir}/curl.conf"
printf 'silent\nshow-error\nfail-with-body\nheader = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\n' \
  "${PHOTO_AI_API_TOKEN}" > "${curl_config}"
chmod 0600 "${curl_config}"
unset PHOTO_AI_API_TOKEN
curl --config "${curl_config}" --request POST --data '{"max_assets":1000000}' \
  "http://${HP_TAILSCALE_IP}:${PHOTO_AI_PORT:-8766}/v1/assets/reconcile"
echo
