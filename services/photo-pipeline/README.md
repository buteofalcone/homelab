# Photo AI queue and GPU worker

`photo-ai-api` on HPServer owns the durable PostgreSQL/pgvector queue. The
SilverBrick worker only leases jobs over Tailscale and may be stopped at any
time. It never reads Immich PostgreSQL and never receives an original image:
the API proxies Immich's preview thumbnail and the worker bounds it to 1280
pixels before inference.

The processing identity combines asset UUID, input fingerprint, stage, model
revision/weights identity and pipeline version. Expired leases return to
`retry`; completion uses a lease token and one result row per job. A model or
pipeline revision creates selective new work without replacing prior results.

## HPServer

Create independent random values for `PHOTO_AI_DB_PASSWORD` and
`PHOTO_AI_API_TOKEN` in root-only `/opt/homelab/.env`. Create a dedicated
Immich API key as `IMMICH_AI_API_KEY` with asset read/download/search and tag
create/read/asset permissions. Then:

```bash
sudo install -d -m 0700 /srv/appdata/photo-pipeline/postgres
sudo make photo-ai
sudo make photo-ai-reconcile
```

The API binds only to the HPServer Tailscale address. Do not publish port 8766
through Caddy or a router. Bounded central logs are stored under
`/srv/storage/wd3tb/ai/logs`.

## SilverBrick

Copy this directory to SilverBrick, copy `.env.worker.example` to `.env`, set
the same bearer token, then run after Docker Desktop and NVIDIA support are
healthy:

```powershell
docker compose --env-file .env -f worker-compose.yaml up -d --build
docker compose -f worker-compose.yaml logs -f
```

The worker requires CUDA and exits instead of using CPU. Models load
sequentially. An OOM loading the primary vision model switches the process to
the configured Florence-2 fallback. Validate a 100-asset batch for VRAM,
structured JSON, tag quality and lease recovery before reconciling everything.

Faces remain Immich-owned. Location/event guesses and captions stay in the
side database. Only normalized `ai/object/...`, `ai/scene/...` and
`ai/activity/...` tags are written through official Immich endpoints.
