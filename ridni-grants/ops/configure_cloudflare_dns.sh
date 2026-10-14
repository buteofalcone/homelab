#!/bin/sh
set -eu

: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN is required}"
api="https://api.cloudflare.com/client/v4"
auth="Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"
zone_name="butenko.online"
record_name="grants.butenko.online"
record_ip="100.65.83.35"

zone_json="$(curl -fsS -H "$auth" -H "Content-Type: application/json" "$api/zones?name=$zone_name&status=active")"
zone_id="$(printf '%s' "$zone_json" | grep -o '"id":"[^"]*"' | head -n 1 | cut -d '"' -f 4)"
test -n "$zone_id" || { echo "Cloudflare zone not found" >&2; exit 1; }

record_json="$(curl -fsS -H "$auth" -H "Content-Type: application/json" "$api/zones/$zone_id/dns_records?type=A&name=$record_name")"
record_id="$(printf '%s' "$record_json" | grep -o '"id":"[^"]*"' | head -n 1 | cut -d '"' -f 4 || true)"
payload="{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$record_ip\",\"ttl\":1,\"proxied\":false}"

if test -n "$record_id"; then
  result="$(curl -fsS -X PATCH -H "$auth" -H "Content-Type: application/json" --data "$payload" "$api/zones/$zone_id/dns_records/$record_id")"
  action="updated"
else
  result="$(curl -fsS -X POST -H "$auth" -H "Content-Type: application/json" --data "$payload" "$api/zones/$zone_id/dns_records")"
  action="created"
fi

printf '%s' "$result" | grep -q '"success":true'
echo "DNS $action: $record_name -> $record_ip"
