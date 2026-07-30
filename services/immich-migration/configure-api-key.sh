#!/usr/bin/env bash
set -Eeuo pipefail

readonly secret_dir=/etc/homelab
readonly secret_file="${secret_dir}/immich-go-api-key"

[[ ${EUID} -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }

read -r -s -p 'Paste the dedicated Immich migration API key: ' api_key
printf '\n'

if (( ${#api_key} < 20 || ${#api_key} > 256 )) || [[ ! ${api_key} =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo 'The API key format is invalid.' >&2
  exit 1
fi

install -d -m 0700 "${secret_dir}"
tmp_file="$(mktemp "${secret_file}.XXXXXX")"
trap 'rm -f -- "${tmp_file}"' EXIT
chmod 0600 "${tmp_file}"
printf '%s\n' "${api_key}" > "${tmp_file}"
unset api_key
chown root:root "${tmp_file}"
mv -f -- "${tmp_file}" "${secret_file}"
trap - EXIT

echo 'IMMICH_MIGRATION_API_KEY_STORED'
