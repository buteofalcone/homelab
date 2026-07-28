#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_dir}/.env"
echo "STEP_REPOSITORY_ENV_LOADED"
source /etc/homelab/caddy.env
echo "STEP_CLOUDFLARE_ENV_LOADED"

domain="${1:-${BASE_DOMAIN:-}}"
if [[ ! ${domain} =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]]; then
  echo "Invalid base domain: ${domain}" >&2
  exit 1
fi

tailscale_ip="$(tailscale ip -4 | head -n 1)"
python3 - "${tailscale_ip}" <<'PY'
import ipaddress
import sys

address = ipaddress.ip_address(sys.argv[1])
network = ipaddress.ip_network("100.64.0.0/10")
if address not in network:
    raise SystemExit(f"Refusing non-Tailscale address: {address}")
PY
echo "STEP_TAILSCALE_IP_VALID"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

cloudflare_api() {
  local method="$1"
  local path="$2"
  local output="$3"
  local data="${4:-}"
  local args=(
    --fail
    --silent
    --show-error
    --request "${method}"
    --header "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"
    --header "Content-Type: application/json"
    --output "${output}"
    "https://api.cloudflare.com/client/v4${path}"
  )
  if [[ -n ${data} ]]; then
    args+=(--data "${data}")
  fi
  curl "${args[@]}"
}

cloudflare_api GET "/user/tokens/verify" "${tmp_dir}/token.json"
python3 - "${tmp_dir}/token.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
if data.get("success") is not True or data.get("result", {}).get("status") != "active":
    raise SystemExit("Cloudflare token is not active")
print("CLOUDFLARE_TOKEN_VALID")
PY
echo "STEP_CLOUDFLARE_TOKEN_VALID"

cloudflare_api GET "/zones?name=${domain}&status=active" "${tmp_dir}/zone.json"
zone_id="$(python3 - "${tmp_dir}/zone.json" "${domain}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
matches = [zone for zone in data.get("result", []) if zone.get("name") == sys.argv[2]]
if len(matches) != 1:
    raise SystemExit("Cloudflare zone was not found or is not uniquely active")
print(matches[0]["id"])
PY
)"
echo "STEP_CLOUDFLARE_ZONE_FOUND"

for label in home portainer beszel uptime nextcloud immich jellyfin ai; do
  fqdn="${label}.${domain}"
  cloudflare_api GET "/zones/${zone_id}/dns_records?type=A&name=${fqdn}" "${tmp_dir}/record.json"
  record_id="$(python3 - "${tmp_dir}/record.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    records = json.load(handle).get("result", [])
print(records[0]["id"] if records else "")
PY
)"
  payload="$(python3 - "${fqdn}" "${tailscale_ip}" <<'PY'
import json
import sys

print(json.dumps({
    "type": "A",
    "name": sys.argv[1],
    "content": sys.argv[2],
    "ttl": 300,
    "proxied": False,
}))
PY
)"

  if [[ -n ${record_id} ]]; then
    cloudflare_api PUT "/zones/${zone_id}/dns_records/${record_id}" "${tmp_dir}/write.json" "${payload}"
  else
    cloudflare_api POST "/zones/${zone_id}/dns_records" "${tmp_dir}/write.json" "${payload}"
  fi

  python3 - "${tmp_dir}/write.json" "${fqdn}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
if data.get("success") is not True:
    raise SystemExit(f"Failed to configure {sys.argv[2]}")
PY
  printf 'OK   %s -> %s (DNS only)\n' "${fqdn}" "${tailscale_ip}"
done
