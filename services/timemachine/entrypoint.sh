#!/usr/bin/env bash
set -Eeuo pipefail

readonly config_template=/etc/samba/smb.conf.template
readonly config_file=/etc/samba/smb.conf
readonly a1502_password_file=/run/secrets/a1502-password
readonly a1466_password_file=/run/secrets/a1466-password
readonly fileshare_password_file=/run/secrets/fileshare-password

require_match() {
  local name="$1"
  local value="$2"
  local pattern="$3"
  if [[ ! ${value} =~ ${pattern} ]]; then
    printf 'Invalid %s.\n' "${name}" >&2
    exit 1
  fi
}

: "${PUID:=1000}"
: "${PGID:=1000}"
: "${TIMEMACHINE_A1502_USER:=tm-a1502}"
: "${TIMEMACHINE_A1466_USER:=tm-a1466}"
: "${FILESHARE_USER:=homelab}"
: "${TIMEMACHINE_A1502_MAX_SIZE:=100G}"
: "${TIMEMACHINE_A1466_MAX_SIZE:=100G}"

require_match PUID "${PUID}" '^[0-9]+$'
require_match PGID "${PGID}" '^[0-9]+$'
require_match TIMEMACHINE_A1502_USER "${TIMEMACHINE_A1502_USER}" '^[a-z_][a-z0-9_-]{0,30}$'
require_match TIMEMACHINE_A1466_USER "${TIMEMACHINE_A1466_USER}" '^[a-z_][a-z0-9_-]{0,30}$'
require_match FILESHARE_USER "${FILESHARE_USER}" '^[a-z_][a-z0-9_-]{0,30}$'
require_match TIMEMACHINE_A1502_MAX_SIZE "${TIMEMACHINE_A1502_MAX_SIZE}" '^[1-9][0-9]*[KMGT]$'
require_match TIMEMACHINE_A1466_MAX_SIZE "${TIMEMACHINE_A1466_MAX_SIZE}" '^[1-9][0-9]*[KMGT]$'

[[ -f ${config_template} ]] || { echo 'Missing Samba configuration template.' >&2; exit 1; }
[[ -s ${a1502_password_file} ]] || { echo 'Missing A1502 password secret.' >&2; exit 1; }
[[ -s ${a1466_password_file} ]] || { echo 'Missing A1466 password secret.' >&2; exit 1; }
[[ -s ${fileshare_password_file} ]] || { echo 'Missing fileshare password secret.' >&2; exit 1; }

if [[ ${FILESHARE_USER} == "${TIMEMACHINE_A1502_USER}" || ${FILESHARE_USER} == "${TIMEMACHINE_A1466_USER}" ]]; then
  echo 'The fileshare account must be different from both Time Machine accounts.' >&2
  exit 1
fi

ensure_group() {
  local group_name="$1"
  local group_id="$2"
  local current_id

  if getent group "${group_name}" >/dev/null; then
    current_id="$(getent group "${group_name}" | cut -d: -f3)"
    [[ ${current_id} == "${group_id}" ]] || {
      printf 'Group %s already exists with GID %s, expected %s.\n' \
        "${group_name}" "${current_id}" "${group_id}" >&2
      exit 1
    }
  else
    groupadd --gid "${group_id}" "${group_name}"
  fi
}

ensure_user() {
  local username="$1"
  shift
  if ! id -u "${username}" >/dev/null 2>&1; then
    useradd --no-create-home --shell /usr/sbin/nologin "$@" "${username}"
  fi
}

ensure_group timemachine "${PGID}"
ensure_user timemachine --uid "${PUID}" --gid timemachine
ensure_user "${TIMEMACHINE_A1502_USER}"
ensure_user "${TIMEMACHINE_A1466_USER}"
ensure_user "${FILESHARE_USER}"

install_samba_password() {
  local username="$1"
  local password_file="$2"
  local password
  IFS= read -r password < "${password_file}"
  password="${password%$'\r'}"
  if (( ${#password} < 12 )); then
    printf 'Password for %s must contain at least 12 characters.\n' "${username}" >&2
    exit 1
  fi
  printf '%s\n%s\n' "${password}" "${password}" | smbpasswd -s -a "${username}" >/dev/null
  unset password
}

install_samba_password "${TIMEMACHINE_A1502_USER}" "${a1502_password_file}"
install_samba_password "${TIMEMACHINE_A1466_USER}" "${a1466_password_file}"
install_samba_password "${FILESHARE_USER}" "${fileshare_password_file}"

sed \
  -e "s/@A1502_USER@/${TIMEMACHINE_A1502_USER}/g" \
  -e "s/@A1466_USER@/${TIMEMACHINE_A1466_USER}/g" \
  -e "s/@A1502_MAX_SIZE@/${TIMEMACHINE_A1502_MAX_SIZE}/g" \
  -e "s/@A1466_MAX_SIZE@/${TIMEMACHINE_A1466_MAX_SIZE}/g" \
  -e "s/@FILESHARE_USER@/${FILESHARE_USER}/g" \
  "${config_template}" > "${config_file}"

testparm -s "${config_file}" >/dev/null
exec /usr/sbin/smbd --foreground --no-process-group --debug-stdout
