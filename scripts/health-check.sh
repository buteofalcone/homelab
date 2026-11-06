#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/monitoring-lib.sh"
require_root
load_monitoring_env

failed=0
disk_usage_limit="${DISK_USAGE_LIMIT_PERCENT:-90}"
smart_temperature_limit="${SMART_TEMPERATURE_LIMIT_C:-55}"

storage_status=up
storage_message='Storage mount is healthy'
if ! mountpoint -q /srv/storage; then
  storage_status=down
  storage_message='/srv/storage is not mounted'
  failed=1
else
  storage_usage="$(df -P /srv/storage | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }')"
  if [[ ! "${storage_usage}" =~ ^[0-9]+$ ]] || (( storage_usage >= disk_usage_limit )); then
    storage_status=down
    storage_message="Storage usage is ${storage_usage:-unknown}% (limit ${disk_usage_limit}%)"
    failed=1
  else
    storage_message="Storage mounted; usage ${storage_usage}%"
  fi
fi
printf '%s: %s\n' "${storage_status^^}" "${storage_message}"
uptime_push UPTIME_KUMA_STORAGE_PUSH_URL "${storage_status}" "${storage_message}" || true

smart_status=up
smart_messages=()
for device in /dev/sda /dev/sdb; do
  smart_output=''
  if ! smart_output="$(smartctl -H -A "${device}" 2>&1)"; then
    smart_status=down
    smart_messages+=("${device}: smartctl failed")
    continue
  fi
  if ! grep -q 'SMART overall-health self-assessment test result: PASSED' <<<"${smart_output}"; then
    smart_status=down
    smart_messages+=("${device}: overall health is not PASSED")
    continue
  fi

  device_issue=false
  for attribute_id in 5 197 198 199; do
    raw_value="$(awk -v id="${attribute_id}" '$1 == id { print $10; exit }' <<<"${smart_output}")"
    if [[ "${raw_value}" =~ ^[0-9]+$ ]] && (( raw_value > 0 )); then
      smart_status=down
      device_issue=true
      smart_messages+=("${device}: SMART attribute ${attribute_id}=${raw_value}")
    fi
  done

  temperature="$(awk '$1 == 194 { print $10; exit }' <<<"${smart_output}")"
  if [[ "${temperature}" =~ ^[0-9]+$ ]] && (( temperature >= smart_temperature_limit )); then
    smart_status=down
    device_issue=true
    smart_messages+=("${device}: temperature ${temperature}C")
  fi
  if [[ "${device_issue}" == false ]]; then
    smart_messages+=("${device}: PASSED${temperature:+, ${temperature}C}")
  fi
done

smart_message="$(printf '%s; ' "${smart_messages[@]}")"
smart_message="${smart_message%; }"
if [[ "${smart_status}" == down ]]; then
  failed=1
fi
printf '%s: %s\n' "${smart_status^^}" "${smart_message}"
uptime_push UPTIME_KUMA_SMART_PUSH_URL "${smart_status}" "${smart_message}" || true

exit "${failed}"
