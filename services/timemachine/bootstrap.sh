#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"

require_root
load_env

mountpoint -q /srv/storage || die '/srv/storage is not a mounted filesystem.'
command -v docker >/dev/null 2>&1 || die 'Docker is not installed.'
docker compose version >/dev/null 2>&1 || die 'Docker Compose plugin is not installed.'

readonly secret_dir=/etc/homelab/timemachine
readonly a1502_password_file="${secret_dir}/a1502-password"
readonly a1466_password_file="${secret_dir}/a1466-password"
readonly fileshare_secret_dir=/etc/homelab/fileshare
readonly fileshare_password_file="${fileshare_secret_dir}/password"
readonly avahi_target=/etc/avahi/services/homelab-timemachine.service

install -d -m 0700 "${secret_dir}"
install -d -m 0700 "${fileshare_secret_dir}"
install -d -m 0700 -o "${PUID}" -g "${PGID}" \
  /srv/storage/timemachine \
  /srv/storage/timemachine/a1502 \
  /srv/storage/timemachine/a1466
install -d -m 0770 -o "${PUID}" -g "${PGID}" \
  /srv/storage/incoming \
  /srv/storage/incoming/books \
  /srv/storage/incoming/calibre-migration \
  /srv/storage/incoming/calibre-merge \
  /srv/storage/incoming/torrents \
  /srv/storage/incoming/media \
  /srv/storage/incoming/transfer

create_password_file() {
  local label="$1"
  local target="$2"
  local password
  local confirmation

  if [[ -s ${target} ]]; then
    printf 'Reusing existing %s password secret.\n' "${label}"
    return
  fi

  while true; do
    read -r -s -p "Create a dedicated ${label} password (12+ characters): " password
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

  umask 077
  printf '%s\n' "${password}" > "${target}"
  unset password confirmation
}

create_password_file 'A1502 Time Machine' "${a1502_password_file}"
create_password_file 'A1466 Time Machine' "${a1466_password_file}"
create_password_file 'homelab SMB Inbox' "${fileshare_password_file}"

if ! command -v avahi-daemon >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y avahi-daemon
fi

install -d -m 0755 /etc/avahi/services
install -m 0644 "${service_dir}/avahi.service" "${avahi_target}"
systemctl enable --now avahi-daemon.service
systemctl reload avahi-daemon.service

cd "${repo_dir}"
docker compose --profile timemachine up -d --build timemachine
docker compose --profile timemachine ps timemachine

echo
echo 'Time Machine service provisioned with conservative 100 GB defaults per Mac.'
echo 'Private SMB Inbox provisioned for Calibre migration and controlled file staging.'
echo 'Do not start real backups on the temporary HDD until the storage plan is approved.'
