#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
readonly env_file="${repo_dir}/.env"
readonly desired_version="v3.0.3"
readonly backup_file="/etc/homelab/immich-version-pin.env.before"

source "${repo_dir}/scripts/lib.sh"
require_root
load_env

current_image_version="$(docker inspect immich-server --format '{{index .Config.Labels "org.opencontainers.image.version"}}')"
[[ ${current_image_version} == "${desired_version}" ]] \
  || die "Live Immich is ${current_image_version}; expected ${desired_version}. Do not pin across an unreviewed upgrade."

current_setting="$(grep -E '^IMMICH_VERSION=' "${env_file}" || true)"
if [[ ${current_setting} == "IMMICH_VERSION=${desired_version}" ]]; then
  echo "IMMICH_VERSION_PIN_OK version=${desired_version} unchanged=true"
  exit 0
fi

install -m 0600 -o root -g root "${env_file}" "${backup_file}"
tmp_env="$(mktemp /etc/homelab/immich-env.XXXXXX)"
trap 'rm -f "${tmp_env}"' EXIT

awk -v version="${desired_version}" '
  BEGIN { replaced = 0 }
  /^IMMICH_VERSION=/ { print "IMMICH_VERSION=" version; replaced = 1; next }
  { print }
  END { if (!replaced) print "IMMICH_VERSION=" version }
' "${env_file}" > "${tmp_env}"
install -m 0600 -o root -g root "${tmp_env}" "${env_file}"
unset IMMICH_VERSION

rollback() {
  echo 'Immich version pin failed; restoring the previous .env and containers.' >&2
  install -m 0600 -o root -g root "${backup_file}" "${env_file}"
  docker compose --project-directory "${repo_dir}" --profile immich up -d immich-server immich-machine-learning || true
}
trap rollback ERR

docker compose --project-directory "${repo_dir}" --profile immich pull immich-server immich-machine-learning
docker compose --project-directory "${repo_dir}" --profile immich up -d immich-server immich-machine-learning

for _ in {1..60}; do
  if curl -fsS http://127.0.0.1:2283/api/server/ping >/dev/null; then
    break
  fi
  sleep 2
done

curl -fsS http://127.0.0.1:2283/api/server/ping >/dev/null \
  || die 'Immich API did not recover after the version pin.'

for container in immich-server immich-machine-learning; do
  version="$(docker inspect "${container}" --format '{{index .Config.Labels "org.opencontainers.image.version"}}')"
  [[ ${version} == "${desired_version}" ]] || die "${container} is ${version}, not ${desired_version}."
done

trap - ERR
echo "IMMICH_VERSION_PIN_OK version=${desired_version} backup=${backup_file}"
