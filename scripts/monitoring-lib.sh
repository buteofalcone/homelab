#!/usr/bin/env bash

MONITORING_ENV_FILE="${MONITORING_ENV_FILE:-/etc/homelab/monitoring.env}"

load_monitoring_env() {
  if [[ -f "${MONITORING_ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${MONITORING_ENV_FILE}"
    set +a
  fi
}

uptime_push() {
  local url_variable="$1"
  local status="$2"
  local message="$3"
  local push_url

  [[ "${url_variable}" =~ ^UPTIME_KUMA_[A-Z0-9_]+_PUSH_URL$ ]] || return 2
  push_url="${!url_variable:-}"
  [[ -n "${push_url}" ]] || return 0
  [[ "${push_url}" == http://127.0.0.1:*/* || "${push_url}" == http://localhost:*/* ]] || {
    printf 'Refusing non-local Uptime Kuma push URL from %s.\n' "${url_variable}" >&2
    return 2
  }

  curl -fsS --max-time 10 --retry 2 --get "${push_url}" \
    --data-urlencode "status=${status}" \
    --data-urlencode "msg=${message}" \
    --data-urlencode 'ping=' \
    >/dev/null
}
