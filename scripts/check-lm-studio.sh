#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"

require_root

readonly agents_env=/etc/homelab/agents.env
[[ -f ${agents_env} ]] || die "Missing ${agents_env}. Create it from config/agents.env.example."

set -a
# shellcheck disable=SC1090
source "${agents_env}"
set +a

[[ -n ${LM_STUDIO_BASE_URL:-} ]] || die 'LM_STUDIO_BASE_URL is empty.'
[[ -n ${LM_STUDIO_MODEL:-} ]] || die 'LM_STUDIO_MODEL is empty.'
[[ -n ${LM_STUDIO_API_TOKEN:-} ]] || die 'LM_STUDIO_API_TOKEN is empty.'
[[ ${LM_STUDIO_API_TOKEN} != CHANGE_ME_* ]] || die 'Replace the placeholder LM Studio token.'

readonly response_file="$(mktemp)"
trap 'rm -f "${response_file}"' EXIT
chmod 0600 "${response_file}"

curl --fail --silent --show-error \
  --connect-timeout 5 \
  --max-time 30 \
  --header "Authorization: Bearer ${LM_STUDIO_API_TOKEN}" \
  "${LM_STUDIO_BASE_URL%/}/models" \
  --output "${response_file}"

grep -Fq "${LM_STUDIO_MODEL}" "${response_file}" \
  || die "Configured model is not visible through the LM Studio API: ${LM_STUDIO_MODEL}"

printf 'OK   Authenticated LM Studio API is reachable through Tailscale\n'
printf 'OK   Configured model is available: %s\n' "${LM_STUDIO_MODEL}"
printf 'LM_STUDIO_API_OK\n'
