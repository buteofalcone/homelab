#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
readonly key_file="${1:-/etc/homelab/immich-go-api-key}"
readonly api_url='http://127.0.0.1:2283/api/system-config'
readonly remote_url='http://100.91.171.26:3003'
readonly fallback_url='http://immich-machine-learning:3003'
readonly backup_dir='/etc/homelab/immich-system-config'

source "${repo_dir}/scripts/lib.sh"
require_root

[[ -s ${key_file} ]] || die "Missing Immich API key: ${key_file}"
command -v python3 >/dev/null || die 'python3 is required.'

api_key="$(tr -d '\r\n' < "${key_file}")"
if (( ${#api_key} < 20 || ${#api_key} > 256 )) || [[ ! ${api_key} =~ ^[A-Za-z0-9_-]+$ ]]; then
  die 'Stored Immich API key format is invalid.'
fi

echo 'STEP_IMMICH_ML_CONNECTIVITY'
docker exec immich-server node - "${remote_url}" "${fallback_url}" <<'NODE'
(async () => {
  const urls = process.argv.slice(2);
  for (const url of urls) {
    const response = await fetch(`${url}/ping`, { signal: AbortSignal.timeout(10000) });
    const body = await response.text();
    if (!response.ok || body.trim() !== 'pong') {
      throw new Error(`${url} returned ${response.status}: ${body}`);
    }
    console.log(`OK   ${url}`);
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
NODE

work_dir="$(mktemp -d /tmp/immich-remote-ml-config.XXXXXX)"
chmod 0700 "${work_dir}"
curl_config="${work_dir}/curl.conf"
current_config="${work_dir}/current.json"
desired_config="${work_dir}/desired.json"
verify_config="${work_dir}/verify.json"
response_file="${work_dir}/response.json"
updated=false

cleanup() {
  rm -rf -- "${work_dir}"
}

rollback() {
  if [[ ${updated} == true ]]; then
    echo 'Immich ML configuration failed; restoring the previous system configuration.' >&2
    curl --config "${curl_config}" --request PUT \
      --header 'Content-Type: application/json' \
      --data-binary "@${current_config}" \
      --output /dev/null "${api_url}" || true
  fi
  cleanup
}
trap rollback ERR
trap cleanup EXIT

printf 'silent\nshow-error\nfail\nheader = "x-api-key: %s"\n' "${api_key}" > "${curl_config}"
chmod 0600 "${curl_config}"
unset api_key

echo 'STEP_IMMICH_ML_CONFIG_READ'
curl --config "${curl_config}" --output "${current_config}" "${api_url}"

python3 - "${current_config}" "${desired_config}" "${remote_url}" "${fallback_url}" <<'PY'
import json
from pathlib import Path
import shutil
import sys

source, destination, remote_url, fallback_url = sys.argv[1:]
config = json.loads(Path(source).read_text())
machine_learning = config.get("machineLearning")
if not isinstance(machine_learning, dict) or not isinstance(machine_learning.get("urls"), list):
    raise SystemExit("Immich API returned an unexpected machineLearning configuration.")
desired_urls = [remote_url, fallback_url]
if machine_learning["urls"] == desired_urls:
    shutil.copyfile(source, destination)
    raise SystemExit(0)
machine_learning["urls"] = desired_urls
Path(destination).write_text(json.dumps(config, separators=(",", ":")))
PY
chmod 0600 "${current_config}" "${desired_config}"

if cmp -s "${current_config}" "${desired_config}"; then
  echo 'IMMICH_REMOTE_ML_CONFIG_OK unchanged=true'
  trap - ERR EXIT
  cleanup
  exit 0
fi

install -d -m 0700 -o root -g root "${backup_dir}"
backup_file="${backup_dir}/system-config.before-remote-ml-$(date -u +%Y%m%dT%H%M%SZ).json"
install -m 0600 -o root -g root "${current_config}" "${backup_file}"

echo 'STEP_IMMICH_ML_CONFIG_UPDATE'
curl --config "${curl_config}" --request PUT \
  --header 'Content-Type: application/json' \
  --data-binary "@${desired_config}" \
  --output "${response_file}" "${api_url}"
updated=true

echo 'STEP_IMMICH_ML_CONFIG_VERIFY'
curl --config "${curl_config}" --output "${verify_config}" "${api_url}"
python3 - "${verify_config}" "${remote_url}" "${fallback_url}" <<'PY'
import json
from pathlib import Path
import sys

config = json.loads(Path(sys.argv[1]).read_text())
actual = config.get("machineLearning", {}).get("urls")
expected = [sys.argv[2], sys.argv[3]]
if actual != expected:
    raise SystemExit(f"Unexpected Immich ML URL order: {actual!r}")
print("IMMICH_REMOTE_ML_CONFIG_OK")
PY

updated=false
trap - ERR EXIT
cleanup
echo "IMMICH_REMOTE_ML_BACKUP_OK ${backup_file}"
