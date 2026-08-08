#!/usr/bin/env bash
set -Eeuo pipefail

readonly repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "${repo_dir}/scripts/lib.sh"
load_env

readonly lan_ip="${SERVER_IP:-192.168.1.130}"

assert_lan_listener() {
  local name="$1"
  local port="$2"
  ss -H -ltn "sport = :${port}" | awk -v suffix=":${port}" '
    $4 ~ (suffix "$") && $4 !~ /^(127\.0\.0\.1|\[::1\]):/ { found=1 }
    END { exit !found }
  ' || die "${name} is not listening beyond loopback on TCP ${port}."
  printf 'OK   %-10s %s:%s\n' "${name}" "${lan_ip}" "${port}"
}

wait_http() {
  local name="$1"
  local url="$2"
  local attempts="${3:-15}"
  local attempt

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if curl -fsS --connect-timeout 2 --max-time 5 "${url}" >/dev/null; then
      printf 'OK   %-10s HTTP ready\n' "${name}"
      return 0
    fi
    if (( attempt == 1 )); then
      printf 'WAIT %-10s HTTP startup\n' "${name}"
    fi
    sleep 2
  done
  die "${name} did not become HTTP-ready: ${url}"
}

assert_lan_listener SMB 445
assert_lan_listener Homepage 3000
assert_lan_listener Nextcloud "${NEXTCLOUD_PORT:-8082}"
assert_lan_listener Immich 2283
assert_lan_listener Jellyfin 8096
assert_lan_listener Books 8081
assert_lan_listener Requests 5055
assert_lan_listener AI 3002

wait_http Homepage "http://${lan_ip}:3000/"
wait_http Nextcloud "http://${lan_ip}:${NEXTCLOUD_PORT:-8082}/status.php"
wait_http Immich "http://${lan_ip}:2283/api/server/ping"
wait_http Jellyfin "http://${lan_ip}:8096/health"
# The full Calibre GUI image may need up to two minutes after recreation before
# its embedded Content Server starts accepting connections.
wait_http Books "http://${lan_ip}:8081/opds" 75
wait_http Requests "http://${lan_ip}:5055/api/v1/settings/public"
wait_http AI "http://${lan_ip}:3002/health"

echo 'LAN_ACCESS_VERIFY_OK'
