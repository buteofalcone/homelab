#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"

require_root
load_env

echo 'STEP_PAPERLESS_CONTAINERS'
for container in paperless-broker paperless-db paperless-gotenberg paperless-tika paperless; do
  [[ $(docker inspect -f '{{.State.Status}}' "${container}" 2>/dev/null || true) == running ]] || die "${container} is not running."
done
[[ $(docker inspect -f '{{.State.Health.Status}}' paperless) == healthy ]] || die 'Paperless is not healthy.'

echo 'STEP_PAPERLESS_STORAGE'
mountpoint -q /srv/storage || die '/srv/storage is not mounted.'
for path in /srv/appdata/paperless/data /srv/appdata/paperless/postgres /srv/appdata/paperless/valkey /srv/storage/documents/paperless/media /srv/storage/documents/paperless/export /srv/storage/incoming/documents; do
  [[ -d ${path} ]] || die "Missing directory: ${path}"
  printf 'OK   %s\n' "${path}"
done

echo 'STEP_PAPERLESS_DATABASE'
docker exec paperless-db pg_isready -U paperless -d paperless >/dev/null
docker exec paperless-db psql -U paperless -d paperless -Atqc "select count(*) from django_migrations" | grep -Eq '^[1-9][0-9]*$'

echo 'STEP_PAPERLESS_OCR'
docker exec paperless tesseract --list-langs 2>/dev/null | grep -qx eng
docker exec paperless tesseract --list-langs 2>/dev/null | grep -qx spa
docker exec paperless tesseract --list-langs 2>/dev/null | grep -qx ukr
docker exec paperless curl -fsS http://paperless-tika:9998/version >/dev/null

echo 'STEP_PAPERLESS_HTTP'
curl -fsS "http://127.0.0.1:${PAPERLESS_PORT:-8010}/" >/dev/null
curl -fsS --resolve "paperless.${BASE_DOMAIN}:443:127.0.0.1" "https://paperless.${BASE_DOMAIN}/" >/dev/null
echo 'PAPERLESS_VERIFY_OK'
