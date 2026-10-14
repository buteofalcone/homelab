#!/usr/bin/env bash
set -Eeuo pipefail

failed=0
check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'OK   %s\n' "${label}"
  else
    printf 'FAIL %s\n' "${label}"
    failed=1
  fi
}

check "Dashboard service" systemctl is-active --quiet hp-dashboard.service
check "Collector timer" systemctl is-active --quiet hp-dashboard-collector.timer
check "Firewall" systemctl is-active --quiet hp-dashboard-firewall.service
check "Local HTTP health" curl -fsS http://127.0.0.1:8787/healthz
check "Status API" curl -fsS http://127.0.0.1:8787/api/v1/status
check "Status file permissions" test "$(stat -c '%U:%G:%a' /run/hp-dashboard/status.json)" = "root:hp-dashboard:640"
check "Dashboard user is not in docker group" bash -c '! id -nG hp-dashboard | tr " " "\n" | grep -qx docker'
check "Dashboard user has no general sudo" bash -c '! sudo -n -u hp-dashboard sudo -n true'
check "HTTPS endpoint" curl -fsS https://dashboard.butenko.online/healthz

exit "${failed}"
