#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"

require_root
load_env

readonly calibre_image="${CALIBRE_IMAGE:-lscr.io/linuxserver/calibre@sha256:1e9d545e20af654af9aca439a54cdd3988cf067f64efcd409cc2bc053aeb6d15}"
readonly calibre_config=/srv/appdata/calibre
readonly library_dir=/srv/storage/books
readonly incoming_dir=/srv/storage/incoming/books
readonly password_file=/etc/homelab/calibre-gui-password

mountpoint -q /srv/storage || die '/srv/storage is not a mounted filesystem.'
command -v docker >/dev/null 2>&1 || die 'Docker is not installed.'
docker compose version >/dev/null 2>&1 || die 'Docker Compose plugin is not installed.'

install -d -m 0700 /etc/homelab
install -d -m 0750 -o "${PUID}" -g "${PGID}" \
  "${calibre_config}" \
  "${library_dir}" \
  "${incoming_dir}"

if [[ -s ${password_file} ]]; then
  echo 'Reusing existing Calibre GUI password.'
else
  while true; do
    read -r -s -p 'Create the Calibre administration password (12+ characters): ' gui_password
    printf '\n'
    read -r -s -p 'Repeat the password: ' gui_confirmation
    printf '\n'
    if (( ${#gui_password} < 12 )); then
      echo 'Password is too short.' >&2
    elif [[ ${gui_password} != "${gui_confirmation}" ]]; then
      echo 'Passwords do not match.' >&2
    else
      break
    fi
  done

  tmp_password="$(mktemp /etc/homelab/calibre-gui-password.XXXXXX)"
  trap 'rm -f -- "${tmp_password:-}"' EXIT
  chmod 0600 "${tmp_password}"
  printf '%s' "${gui_password}" > "${tmp_password}"
  install -m 0600 -o root -g root "${tmp_password}" "${password_file}"
  rm -f -- "${tmp_password}"
  trap - EXIT
  unset gui_password gui_confirmation
  echo 'Created root-only Calibre GUI password.'
fi

cd "${repo_dir}"
compose --profile books config --quiet
compose --profile books pull calibre

if [[ ! -s ${library_dir}/metadata.db ]]; then
  echo 'STEP_CALIBRE_LIBRARY_INITIALIZE'
  docker run --rm \
    --user "${PUID}:${PGID}" \
    --entrypoint /bin/bash \
    --env HOME=/config \
    --volume "${calibre_config}:/config" \
    --volume "${library_dir}:/library" \
    "${calibre_image}" \
    -lc '
      printf "%s\n" \
        "Welcome to the Butenko Calibre library" \
        "This EPUB was generated automatically to verify ebook-convert and calibredb." \
        > /tmp/butenko-calibre-welcome.txt
      ebook-convert /tmp/butenko-calibre-welcome.txt /tmp/butenko-calibre-welcome.epub >/tmp/ebook-convert.log 2>&1
      ebook-meta /tmp/butenko-calibre-welcome.epub >/dev/null
      calibredb add --with-library /library /tmp/butenko-calibre-welcome.epub >/tmp/calibredb-add.log
      test -s /library/metadata.db
    '
else
  echo 'Reusing existing Calibre library.'
fi

docker run --rm \
  --user "${PUID}:${PGID}" \
  --entrypoint calibre-debug \
  --env HOME=/config \
  --volume "${calibre_config}:/config" \
  "${calibre_image}" \
  -c 'from calibre.gui2 import config; from calibre.srv.opts import change_settings; from calibre.utils.config import dynamic, prefs; prefs["library_path"] = "/config/Calibre Library"; dynamic.set("welcome_wizard_was_run", True); config["autolaunch_server"] = True; change_settings(port=8081, listen_on="0.0.0.0", use_bonjour=False, enable_local_write=True)'

if docker container inspect calibre-content >/dev/null 2>&1; then
  docker rm -f calibre-content >/dev/null
  echo 'Removed the obsolete separate Content Server container; its appdata directory was preserved.'
fi

compose --profile books up -d --force-recreate calibre

install -m 0644 -o "${PUID}" -g "${PGID}" \
  "${repo_dir}/config/homepage/services.yaml" \
  /srv/appdata/homepage/services.yaml
compose up -d --no-deps homepage
compose exec -w /etc/caddy caddy /bin/sh -c \
  'set -a; . /run/secrets/caddy.env; set +a; exec caddy validate --config Caddyfile'
compose exec -w /etc/caddy caddy /bin/sh -c \
  'set -a; . /run/secrets/caddy.env; set +a; exec caddy reload --config Caddyfile'

for attempt in {1..48}; do
  gui_health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' calibre 2>/dev/null || true)"
  if [[ ${gui_health} == healthy ]]; then
    compose --profile books ps calibre
    echo 'CALIBRE_BOOTSTRAP_OK'
    exit 0
  fi
  sleep 5
done

compose --profile books logs --tail=100 calibre >&2
die 'Calibre did not become healthy within 240 seconds.'
