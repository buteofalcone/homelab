#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"

require_root
load_env

readonly agents_env=/etc/homelab/agents.env
readonly webui_env=/etc/homelab/open-webui.env
readonly appdata_dir=/srv/appdata/open-webui
readonly database_path=${appdata_dir}/webui.db

[[ -f ${agents_env} ]] || die "Missing ${agents_env}. Configure LM Studio first."

set -a
# shellcheck disable=SC1090
source "${agents_env}"
set +a

[[ -n ${LM_STUDIO_BASE_URL:-} ]] || die 'LM_STUDIO_BASE_URL is missing.'
[[ -n ${LM_STUDIO_API_TOKEN:-} ]] || die 'LM_STUDIO_API_TOKEN is missing.'
[[ ${LM_STUDIO_API_TOKEN} != CHANGE_ME_* ]] || die 'LM Studio token is still a placeholder.'

command -v docker >/dev/null 2>&1 || die 'Docker is not installed.'
docker compose version >/dev/null 2>&1 || die 'Docker Compose plugin is not installed.'
command -v openssl >/dev/null 2>&1 || die 'OpenSSL is not installed.'

install -d -m 0700 /etc/homelab
install -d -m 0750 "${appdata_dir}"

if [[ -s ${database_path} && ! -s ${webui_env} ]]; then
  die "Open WebUI database exists without ${webui_env}; restore the original secret file instead of rotating its encryption key."
fi

if [[ -s ${webui_env} && -s ${database_path} ]]; then
  echo 'Reusing existing Open WebUI secrets.'
else
  read -r -p 'Open WebUI administrator email: ' admin_email
  [[ ${admin_email} =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || die 'Invalid administrator email.'

  while true; do
    read -r -s -p 'Create the Open WebUI administrator password (12+ characters): ' admin_password
    printf '\n'
    read -r -s -p 'Repeat the password: ' admin_confirmation
    printf '\n'
    if (( ${#admin_password} < 12 )); then
      echo 'Password is too short.' >&2
    elif [[ ${admin_password} != "${admin_confirmation}" ]]; then
      echo 'Passwords do not match.' >&2
    else
      break
    fi
  done

  webui_secret="$(openssl rand -hex 32)"
  tmp_env="$(mktemp /etc/homelab/open-webui.env.XXXXXX)"
  trap 'rm -f -- "${tmp_env:-}"' EXIT
  chmod 0600 "${tmp_env}"
  {
    printf 'OPENAI_API_BASE_URL=%s\n' "${LM_STUDIO_BASE_URL}"
    printf 'OPENAI_API_KEY=%s\n' "${LM_STUDIO_API_TOKEN}"
    printf 'WEBUI_SECRET_KEY=%s\n' "${webui_secret}"
    printf 'WEBUI_ADMIN_NAME=%s\n' 'Butenko'
    printf 'WEBUI_ADMIN_EMAIL=%s\n' "${admin_email}"
    printf 'WEBUI_ADMIN_PASSWORD=%s\n' "${admin_password}"
  } > "${tmp_env}"
  install -m 0600 -o root -g root "${tmp_env}" "${webui_env}"
  rm -f -- "${tmp_env}"
  trap - EXIT
  unset admin_password admin_confirmation webui_secret LM_STUDIO_API_TOKEN
  echo 'Created root-only Open WebUI secrets.'
fi

cd "${repo_dir}"
compose --profile agents config --quiet
compose --profile agents pull open-webui
compose --profile agents up -d open-webui

wait_for_health() {
  local attempt
  for attempt in {1..36}; do
    if curl -fsS "http://127.0.0.1:${OPEN_WEBUI_PORT:-3002}/health" >/dev/null; then
      return 0
    fi
    sleep 5
  done
  return 1
}

if ! wait_for_health; then
  compose --profile agents logs --tail=100 open-webui >&2
  die 'Open WebUI did not become healthy within 180 seconds.'
fi

if grep -q '^WEBUI_ADMIN_' "${webui_env}"; then
  sanitized_env="$(mktemp /etc/homelab/open-webui.env.XXXXXX)"
  trap 'rm -f -- "${sanitized_env:-}"' EXIT
  grep -Ev '^WEBUI_ADMIN_(NAME|EMAIL|PASSWORD)=' "${webui_env}" > "${sanitized_env}"
  install -m 0600 -o root -g root "${sanitized_env}" "${webui_env}"
  rm -f -- "${sanitized_env}"
  trap - EXIT
  compose --profile agents up -d --force-recreate open-webui
  if ! wait_for_health; then
    compose --profile agents logs --tail=100 open-webui >&2
    die 'Open WebUI did not become healthy after removing bootstrap credentials.'
  fi
  echo 'Removed one-time administrator bootstrap credentials from the runtime environment.'
fi

compose --profile agents ps open-webui
echo 'OPEN_WEBUI_BOOTSTRAP_OK'
