#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd -P)"
source "${repo_dir}/scripts/lib.sh"

require_root
load_env

readonly secret_dir=/etc/homelab/fileshare
readonly password_file="${secret_dir}/password"
password=''
confirmation=''
temporary=''

cleanup() {
  unset password confirmation
  [[ -z ${temporary} ]] || rm -f -- "${temporary}"
}
trap cleanup EXIT

while true; do
  read -r -s -p 'Create a new homelab SMB Inbox password (12+ characters): ' password
  printf '\n'
  read -r -s -p 'Repeat the password: ' confirmation
  printf '\n'
  if (( ${#password} < 12 )); then
    echo 'Password is too short.' >&2
  elif [[ ${password} != "${confirmation}" ]]; then
    echo 'Passwords do not match.' >&2
  else
    break
  fi
done

install -d -m 0700 "${secret_dir}"
temporary="$(mktemp "${secret_dir}/.password.XXXXXX")"
chmod 0600 "${temporary}"
printf '%s\n' "${password}" > "${temporary}"
install -o root -g root -m 0600 "${temporary}" "${password_file}"
unset password confirmation

cd "${repo_dir}"
docker compose --profile timemachine up -d --force-recreate timemachine

health=''
for _ in {1..30}; do
  health="$(docker inspect timemachine --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' 2>/dev/null || true)"
  [[ ${health} == healthy ]] && break
  sleep 2
done
[[ ${health} == healthy ]] || die "Samba did not become healthy after password reset: ${health:-missing}"
docker exec timemachine pdbedit -L | grep -q '^homelab:' \
  || die 'The homelab Samba account is missing after password reset.'

echo 'SMB_INBOX_PASSWORD_RESET_OK'
