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

assert_lan_listener SMB 445
assert_lan_listener Homepage 3000
assert_lan_listener Nextcloud 8080
assert_lan_listener Immich 2283
assert_lan_listener Jellyfin 8096

curl -fsS "http://${lan_ip}:3000/" >/dev/null
curl -fsS "http://${lan_ip}:8080/status.php" >/dev/null
curl -fsS "http://${lan_ip}:2283/api/server/ping" >/dev/null
curl -fsS "http://${lan_ip}:8096/health" >/dev/null

echo 'LAN_ACCESS_VERIFY_OK'
