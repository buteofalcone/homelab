#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"

require_root
load_env

export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE

command -v restic >/dev/null 2>&1 || die 'Restic is not installed.'
[[ -f ${RESTIC_PASSWORD_FILE} ]] || die "Missing ${RESTIC_PASSWORD_FILE}."
mountpoint -q /srv/storage || die '/srv/storage is not a mounted filesystem.'

readonly target="/srv/storage/restores/management-verify-$(date +%Y%m%d-%H%M%S)"
readonly services=(homepage portainer beszel beszel-agent uptime-kuma caddy jellyfin open-webui calibre)

install -d -m 0750 "${target}"
restic restore latest \
  --target "${target}" \
  --include /srv/appdata/homepage \
  --include /srv/appdata/portainer \
  --include /srv/appdata/beszel \
  --include /srv/appdata/beszel-agent \
  --include /srv/appdata/uptime-kuma \
  --include /srv/appdata/caddy \
  --include /srv/appdata/jellyfin \
  --include /srv/appdata/open-webui \
  --include /srv/appdata/calibre

for service in "${services[@]}"; do
  restored_path="${target}/srv/appdata/${service}"
  [[ -d ${restored_path} ]] || die "Restored service directory is missing: ${service}"
  file_count="$(find "${restored_path}" -type f -size +0c -printf '.' | wc -c)"
  byte_count="$(du -sb "${restored_path}" | cut -f1)"
  [[ "${file_count}" -gt 0 ]] || die "No non-empty files were restored for ${service}"
  printf 'OK   %-14s %s non-empty files, %s bytes\n' "${service}" "${file_count}" "${byte_count}"
done

printf '\nMANAGEMENT_RESTORE_VERIFY_OK %s\n' "${target}"
printf 'The restored tree is retained for audit and was not copied into live paths.\n'
