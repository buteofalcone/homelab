#!/usr/bin/env bash
set -Eeuo pipefail

readonly network=photo-ai-test
readonly database=photo-ai-db-test
readonly api=photo-ai-api-test
cleanup() {
  docker rm -f "${api}" "${database}" >/dev/null 2>&1 || true
  docker network rm "${network}" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

docker network create "${network}" >/dev/null
docker run -d --rm --name "${database}" --network "${network}" \
  -e POSTGRES_DB=photo_ai -e POSTGRES_USER=photo_ai -e POSTGRES_PASSWORD=test-only \
  pgvector/pgvector:0.8.1-pg16@sha256:33198da2828a14c30348d2ccb4750833d5ed9a44c88d840a0e523d7417120337 >/dev/null
for attempt in {1..30}; do
  docker exec "${database}" pg_isready -U photo_ai -d photo_ai >/dev/null 2>&1 && break
  (( attempt == 30 )) && { docker logs "${database}"; exit 1; }
  sleep 1
done

docker run -d --rm --name "${api}" --network "${network}" \
  -e DATABASE_URL=postgresql://photo_ai:test-only@photo-ai-db-test:5432/photo_ai \
  -e PHOTO_AI_API_TOKEN=test-token-12345678901234567890 \
  -e IMMICH_AI_API_KEY=test-immich-key -e IMMICH_URL=http://invalid \
  -e PHOTO_AI_LOG_DIR=/tmp/logs homelab/photo-ai-api:1.0.0 >/dev/null
for attempt in {1..30}; do
  docker exec "${api}" python -c \
    "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)" \
    >/dev/null 2>&1 && break
  (( attempt == 30 )) && { docker logs "${api}"; exit 1; }
  sleep 1
done

table_count="$(docker exec "${database}" psql -U photo_ai -d photo_ai -Atc \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name LIKE 'ai_%'")"
[[ ${table_count} == 8 ]] || { docker logs "${api}"; echo "Unexpected table count: ${table_count}" >&2; exit 1; }
docker exec "${api}" python -c \
  "import json,urllib.request; print(json.load(urllib.request.urlopen('http://127.0.0.1:8000/health')))"
echo "PHOTO_AI_SMOKE_TEST_OK tables=${table_count} cleanup=automatic"
