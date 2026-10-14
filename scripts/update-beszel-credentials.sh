#!/usr/bin/env bash
set -euo pipefail

readonly env_file="${1:-.env}"

if [[ ! -f "${env_file}" ]]; then
  echo "Environment file not found: ${env_file}" >&2
  exit 1
fi

IFS= read -r beszel_key
IFS= read -r beszel_token

# PowerShell native pipelines may terminate input lines with CRLF.
beszel_key="${beszel_key%$'\r'}"
beszel_token="${beszel_token%$'\r'}"

if [[ ! "${beszel_key}" =~ ^ssh-ed25519[[:space:]][A-Za-z0-9+/=]+$ ]]; then
  echo "Refusing invalid Beszel public key format." >&2
  exit 1
fi

if [[ ! "${beszel_token}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  echo "Refusing invalid Beszel token format." >&2
  exit 1
fi

umask 077
temp_file="$(mktemp "${env_file}.tmp.XXXXXX")"
trap 'rm -f "${temp_file}"' EXIT

key_replaced=false
token_replaced=false

while IFS= read -r line || [[ -n "${line}" ]]; do
  case "${line}" in
    BESZEL_AGENT_KEY=*)
      # The public key contains a space. Quote it so both Docker Compose and
      # shell scripts that source .env receive the same value.
      printf "BESZEL_AGENT_KEY='%s'\n" "${beszel_key}" >>"${temp_file}"
      key_replaced=true
      ;;
    BESZEL_AGENT_TOKEN=*)
      printf 'BESZEL_AGENT_TOKEN=%s\n' "${beszel_token}" >>"${temp_file}"
      token_replaced=true
      ;;
    *)
      printf '%s\n' "${line}" >>"${temp_file}"
      ;;
  esac
done <"${env_file}"

if [[ "${key_replaced}" != true || "${token_replaced}" != true ]]; then
  echo "Beszel credential entries are missing from ${env_file}." >&2
  exit 1
fi

chmod --reference="${env_file}" "${temp_file}"
chown --reference="${env_file}" "${temp_file}"
mv -f "${temp_file}" "${env_file}"
trap - EXIT

unset beszel_key beszel_token
echo "Beszel credentials updated without printing their values."
