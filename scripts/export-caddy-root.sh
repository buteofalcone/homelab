#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
require_root
load_env

destination="/srv/storage/files/homelab-caddy-root.crt"
tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT

compose cp caddy:/data/caddy/pki/authorities/local/root.crt "${tmp}"
install -m 0644 "${tmp}" "${destination}"
chown "${PUID}:${PGID}" "${destination}"

echo "Caddy root certificate exported to ${destination}"
echo "Import it into the trust store of every client that uses *.${BASE_DOMAIN}."
