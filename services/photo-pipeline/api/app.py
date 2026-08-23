from __future__ import annotations

from contextlib import asynccontextmanager
from datetime import datetime, timezone
import hashlib
import hmac
import json
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import re
import unicodedata
from typing import Any
from uuid import UUID

from fastapi import Depends, FastAPI, Header, HTTPException, Response, status
import httpx
from psycopg import Connection
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool
from pydantic import BaseModel, Field


DATABASE_URL = os.environ["DATABASE_URL"]
API_TOKEN = os.environ["PHOTO_AI_API_TOKEN"]
IMMICH_URL = os.getenv("IMMICH_URL", "http://immich-server:2283").rstrip("/")
IMMICH_API_KEY = os.environ["IMMICH_AI_API_KEY"]
PIPELINE_VERSION = os.getenv("PHOTO_AI_PIPELINE_VERSION", "1.0.0")
LEASE_SECONDS = int(os.getenv("PHOTO_AI_LEASE_SECONDS", "900"))
MAX_TAGS_PER_ASSET = int(os.getenv("PHOTO_AI_MAX_TAGS", "50"))
MODEL_CONFIG = json.loads(
    os.getenv(
        "PHOTO_AI_MODELS_JSON",
        json.dumps(
            [
                {
                    "stage": "embedding",
                    "model_name": "google/siglip2-base-patch16-512",
                    "model_revision": "a89f5c5093f902bf39d3cd4d81d2c09867f0724b",
                    "weights_sha256": "77f0c8fff80e7b0b3cb419512f06d4b6a367dfbc4d9d45f8a4489ef8a2fca0d2",
                    "config": {"max_edge": 1280, "enabled": True},
                },
                {
                    "stage": "vision",
                    "model_name": "Qwen/Qwen3-VL-4B-Instruct-FP8",
                    "model_revision": "fefbb44cbcce8d1bb7e20b920b94f77432b3446d",
                    "weights_sha256": "626990c774750398e4dd00d811cb2b386fb0d7c9853f104868a53530b4446fad",
                    "config": {"max_edge": 1280, "temperature": 0, "enabled": True},
                },
                {
                    "stage": "vision",
                    "model_name": "microsoft/Florence-2-large",
                    "model_revision": "21a599d414c4d928c9032694c424fb94458e3594",
                    "weights_sha256": "81014ea03fa1506ed4f874d0c269f87f4882e67be0667bd8cb2bc5ade38189db",
                    "config": {"max_edge": 1280, "enabled": False, "fallback_for": "Qwen/Qwen3-VL-4B-Instruct-FP8"},
                },
            ]
        ),
    )
)

LOG_DIR = Path(os.getenv("PHOTO_AI_LOG_DIR", "/logs"))
LOG_DIR.mkdir(parents=True, exist_ok=True)
logger = logging.getLogger("photo-ai")
logger.setLevel(logging.INFO)
for filename, level in (("ai-worker.log", logging.INFO), ("failed-assets.log", logging.ERROR)):
    handler = RotatingFileHandler(LOG_DIR / filename, maxBytes=100 * 1024 * 1024, backupCount=10)
    handler.setLevel(level)
    handler.setFormatter(logging.Formatter("%(asctime)sZ %(levelname)s %(message)s"))
    logger.addHandler(handler)

pool = ConnectionPool(DATABASE_URL, min_size=1, max_size=10, kwargs={"row_factory": dict_row}, open=False)


class LeaseRequest(BaseModel):
    worker_id: str = Field(min_length=1, max_length=128)
    batch_size: int = Field(default=1, ge=1, le=10)
    stages: list[str] | None = None


class HeartbeatRequest(BaseModel):
    lease_token: UUID


class CompleteRequest(BaseModel):
    lease_token: UUID
    result: dict[str, Any]


class FailRequest(BaseModel):
    lease_token: UUID
    error: str = Field(min_length=1, max_length=4000)
    retryable: bool = True
    fallback_model_name: str | None = Field(default=None, max_length=512)


class ReconcileRequest(BaseModel):
    updated_after: datetime | None = None
    max_assets: int | None = Field(default=None, ge=1, le=1_000_000)


def require_token(authorization: str | None = Header(default=None)) -> None:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing bearer token")
    if not hmac.compare_digest(authorization[7:], API_TOKEN):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Invalid bearer token")


def immich_headers() -> dict[str, str]:
    return {"x-api-key": IMMICH_API_KEY, "accept": "application/json"}


async def immich_request(method: str, path: str, **kwargs: Any) -> httpx.Response:
    headers = kwargs.pop("headers", {})
    headers.update(immich_headers())
    async with httpx.AsyncClient(timeout=120, follow_redirects=True) as client:
        response = await client.request(method, IMMICH_URL + "/api" + path, headers=headers, **kwargs)
    response.raise_for_status()
    return response


def ensure_schema(connection: Connection[Any]) -> None:
    connection.execute(Path("/app/schema.sql").read_text(encoding="utf-8"))
    connection.commit()


@asynccontextmanager
async def lifespan(_: FastAPI):
    pool.open(wait=True)
    with pool.connection() as connection:
        ensure_schema(connection)
    yield
    pool.close()


app = FastAPI(title="Photo AI Queue", version=PIPELINE_VERSION, lifespan=lifespan)


@app.get("/health")
def health() -> dict[str, str]:
    with pool.connection() as connection:
        connection.execute("SELECT 1").fetchone()
    return {"status": "ok", "pipelineVersion": PIPELINE_VERSION}


async def fetch_assets(updated_after: datetime | None, maximum: int | None) -> list[dict[str, Any]]:
    assets: list[dict[str, Any]] = []
    page = 1
    while True:
        body: dict[str, Any] = {"page": page, "size": 1000, "withExif": True}
        if updated_after:
            body["updatedAfter"] = updated_after.astimezone(timezone.utc).isoformat()
        payload = (await immich_request("POST", "/search/metadata", json=body)).json()
        result = payload.get("assets", payload)
        items = result.get("items", [])
        assets.extend(items)
        if maximum and len(assets) >= maximum:
            return assets[:maximum]
        if len(items) < 1000 or not result.get("nextPage"):
            break
        page += 1
    return assets


def fingerprint(asset: dict[str, Any]) -> str:
    source = "\0".join(
        str(asset.get(key, "")) for key in ("id", "checksum", "updatedAt", "thumbhash", "fileModifiedAt")
    )
    return hashlib.sha256(source.encode()).hexdigest()


@app.post("/v1/assets/reconcile", dependencies=[Depends(require_token)])
async def reconcile(request: ReconcileRequest) -> dict[str, int]:
    assets = await fetch_assets(request.updated_after, request.max_assets)
    jobs_created = 0
    with pool.connection() as connection, connection.transaction():
        model_ids: list[tuple[str, UUID]] = []
        for model in MODEL_CONFIG:
            row = connection.execute(
                """
                INSERT INTO ai_models (stage, model_name, model_revision, weights_sha256, config)
                VALUES (%s, %s, %s, %s, %s::jsonb)
                ON CONFLICT (stage, model_name, model_revision, weights_sha256)
                DO UPDATE SET config = EXCLUDED.config
                RETURNING id
                """,
                (
                    model["stage"], model["model_name"], model["model_revision"],
                    model["weights_sha256"], json.dumps(model.get("config", {})),
                ),
            ).fetchone()
            if model.get("config", {}).get("enabled", True):
                model_ids.append((model["stage"], row["id"]))
        for asset in assets:
            asset_id = UUID(asset["id"])
            asset_fingerprint = fingerprint(asset)
            connection.execute(
                """
                INSERT INTO ai_assets
                    (asset_id, checksum, input_fingerprint, original_filename, media_type,
                     file_created_at, immich_updated_at)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (asset_id) DO UPDATE SET
                    checksum = EXCLUDED.checksum,
                    input_fingerprint = EXCLUDED.input_fingerprint,
                    original_filename = EXCLUDED.original_filename,
                    media_type = EXCLUDED.media_type,
                    file_created_at = EXCLUDED.file_created_at,
                    immich_updated_at = EXCLUDED.immich_updated_at,
                    last_seen_at = now()
                """,
                (
                    asset_id, asset.get("checksum", "missing"), asset_fingerprint,
                    asset.get("originalFileName"), str(asset.get("type", "unknown")),
                    asset.get("fileCreatedAt"), asset.get("updatedAt"),
                ),
            )
            for stage, model_id in model_ids:
                cursor = connection.execute(
                    """
                    INSERT INTO ai_jobs (asset_id, stage, model_id, pipeline_version, input_fingerprint)
                    VALUES (%s, %s, %s, %s, %s)
                    ON CONFLICT DO NOTHING
                    """,
                    (asset_id, stage, model_id, PIPELINE_VERSION, asset_fingerprint),
                )
                jobs_created += cursor.rowcount
    logger.info("reconcile assets_seen=%d jobs_created=%d", len(assets), jobs_created)
    return {"assetsSeen": len(assets), "jobsCreated": jobs_created}


@app.post("/v1/jobs/lease", dependencies=[Depends(require_token)])
def lease_jobs(request: LeaseRequest) -> dict[str, Any]:
    with pool.connection() as connection, connection.transaction():
        connection.execute(
            """
            UPDATE ai_jobs SET state = 'retry', lease_owner = NULL, lease_token = NULL,
                lease_until = NULL, next_attempt_at = now(), updated_at = now(),
                last_error = COALESCE(last_error, 'lease expired')
            WHERE state = 'processing' AND lease_until < now()
            """
        )
        stage_filter = request.stages or []
        rows = connection.execute(
            """
            WITH selected AS (
                SELECT id FROM ai_jobs
                WHERE state IN ('pending', 'retry') AND next_attempt_at <= now()
                  AND (%s::text[] = '{}'::text[] OR stage = ANY(%s::text[]))
                ORDER BY created_at, id
                FOR UPDATE SKIP LOCKED
                LIMIT %s
            )
            UPDATE ai_jobs AS job SET
                state = 'processing', lease_owner = %s, lease_token = gen_random_uuid(),
                lease_until = now() + make_interval(secs => %s), updated_at = now()
            FROM selected, ai_models AS model, ai_assets AS asset
            WHERE job.id = selected.id AND model.id = job.model_id AND asset.asset_id = job.asset_id
            RETURNING job.id, job.asset_id, job.stage, job.pipeline_version, job.input_fingerprint,
                      job.lease_token, job.lease_until, model.model_name, model.model_revision,
                      model.weights_sha256, model.config, asset.media_type, asset.original_filename
            """,
            (stage_filter, stage_filter, request.batch_size, request.worker_id, LEASE_SECONDS),
        ).fetchall()
    return {"jobs": rows}


@app.post("/v1/jobs/{job_id}/heartbeat", dependencies=[Depends(require_token)])
def heartbeat(job_id: UUID, request: HeartbeatRequest) -> dict[str, str]:
    with pool.connection() as connection, connection.transaction():
        row = connection.execute(
            """
            UPDATE ai_jobs SET lease_until = now() + make_interval(secs => %s), updated_at = now()
            WHERE id = %s AND state = 'processing' AND lease_token = %s
            RETURNING id
            """,
            (LEASE_SECONDS, job_id, request.lease_token),
        ).fetchone()
    if not row:
        raise HTTPException(status_code=409, detail="Lease is no longer valid")
    return {"status": "ok"}


def clean_tag(value: str) -> str | None:
    normalized = unicodedata.normalize("NFKC", value).strip().casefold()
    normalized = re.sub(r"[\\/]+", "-", normalized)
    normalized = re.sub(r"\s+", "-", normalized)
    normalized = re.sub(r"[^\w.-]+", "", normalized, flags=re.UNICODE).strip("-.")
    return normalized[:80] or None


def namespaced_tags(result: dict[str, Any]) -> list[tuple[str, str, float | None]]:
    output: list[tuple[str, str, float | None]] = []
    mapping = {"objects": "object", "scene": "scene", "scenes": "scene", "activities": "activity"}
    for source_key, category in mapping.items():
        values = result.get(source_key, [])
        if not isinstance(values, list):
            continue
        for item in values:
            confidence = None
            value = item
            if isinstance(item, dict):
                value = item.get("value") or item.get("name")
                confidence = item.get("confidence")
            if isinstance(value, str) and (cleaned := clean_tag(value)):
                output.append((category, cleaned, confidence))
    return list(dict.fromkeys(output))[:MAX_TAGS_PER_ASSET]


async def write_tags(asset_id: UUID, tags: list[tuple[str, str, float | None]]) -> None:
    if not tags:
        return
    values = [f"ai/{category}/{value}" for category, value, _ in tags]
    response = await immich_request("PUT", "/tags", json={"tags": values})
    tag_ids = [tag["id"] for tag in response.json()]
    await immich_request("PUT", "/tags/assets", json={"tagIds": tag_ids, "assetIds": [str(asset_id)]})


@app.post("/v1/jobs/{job_id}/complete", dependencies=[Depends(require_token)])
async def complete(job_id: UUID, request: CompleteRequest) -> dict[str, str]:
    tags = namespaced_tags(request.result)
    with pool.connection() as connection:
        job = connection.execute(
            "SELECT asset_id FROM ai_jobs WHERE id = %s AND state = 'processing' AND lease_token = %s",
            (job_id, request.lease_token),
        ).fetchone()
    if not job:
        raise HTTPException(status_code=409, detail="Lease is no longer valid")
    await write_tags(job["asset_id"], tags)
    with pool.connection() as connection, connection.transaction():
        result_row = connection.execute(
            """
            INSERT INTO ai_results (job_id, asset_id, model_id, pipeline_version, result)
            SELECT id, asset_id, model_id, pipeline_version, %s::jsonb FROM ai_jobs
            WHERE id = %s AND state = 'processing' AND lease_token = %s
            ON CONFLICT (job_id) DO UPDATE SET result = EXCLUDED.result
            RETURNING id, asset_id
            """,
            (json.dumps(request.result), job_id, request.lease_token),
        ).fetchone()
        if not result_row:
            raise HTTPException(status_code=409, detail="Lease is no longer valid")
        caption = request.result.get("caption")
        if isinstance(caption, str) and caption.strip():
            connection.execute(
                """
                INSERT INTO ai_captions (result_id, asset_id, caption, confidence, language)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (result_id) DO UPDATE SET caption = EXCLUDED.caption,
                    confidence = EXCLUDED.confidence, language = EXCLUDED.language
                """,
                (
                    result_row["id"], result_row["asset_id"], caption.strip(),
                    request.result.get("caption_confidence"), request.result.get("language"),
                ),
            )
        for category, value, confidence in tags:
            connection.execute(
                """
                INSERT INTO ai_tags (result_id, asset_id, category, value, confidence)
                VALUES (%s, %s, %s, %s, %s) ON CONFLICT DO NOTHING
                """,
                (result_row["id"], result_row["asset_id"], category, value, confidence),
            )
        embedding = request.result.get("embedding")
        if isinstance(embedding, list) and embedding and all(isinstance(value, (int, float)) for value in embedding):
            vector = "[" + ",".join(str(float(value)) for value in embedding) + "]"
            connection.execute(
                """
                INSERT INTO ai_embeddings (result_id, asset_id, model_id, dimensions, embedding)
                SELECT %s, asset_id, model_id, %s, %s::vector FROM ai_jobs WHERE id = %s
                ON CONFLICT (result_id) DO UPDATE SET dimensions = EXCLUDED.dimensions, embedding = EXCLUDED.embedding
                """,
                (result_row["id"], len(embedding), vector, job_id),
            )
        connection.execute(
            """
            UPDATE ai_jobs SET state = 'completed', completed_at = now(), updated_at = now(),
                lease_owner = NULL, lease_token = NULL, lease_until = NULL, last_error = NULL
            WHERE id = %s AND lease_token = %s
            """,
            (job_id, request.lease_token),
        )
    logger.info("completed job_id=%s asset_id=%s", job_id, result_row["asset_id"])
    return {"status": "completed"}


@app.post("/v1/jobs/{job_id}/fail", dependencies=[Depends(require_token)])
def fail(job_id: UUID, request: FailRequest) -> dict[str, str]:
    sanitized = re.sub(r"[\r\n\t]+", " ", request.error).strip()[:4000]
    with pool.connection() as connection, connection.transaction():
        row = connection.execute(
            """
            UPDATE ai_jobs SET
                retry_count = retry_count + 1,
                state = CASE WHEN %s AND retry_count + 1 < max_retries THEN 'retry' ELSE 'failed' END,
                next_attempt_at = now() + make_interval(secs => LEAST(3600, 30 * (2 ^ retry_count))),
                lease_owner = NULL, lease_token = NULL, lease_until = NULL,
                last_error = %s, updated_at = now()
            WHERE id = %s AND state = 'processing' AND lease_token = %s
            RETURNING state, asset_id, stage, pipeline_version, input_fingerprint
            """,
            (request.retryable, sanitized, job_id, request.lease_token),
        ).fetchone()
        fallback_enqueued = False
        if row and request.fallback_model_name:
            fallback = connection.execute(
                "SELECT id FROM ai_models WHERE stage = %s AND model_name = %s ORDER BY created_at DESC LIMIT 1",
                (row["stage"], request.fallback_model_name),
            ).fetchone()
            if fallback:
                cursor = connection.execute(
                    """
                    INSERT INTO ai_jobs (asset_id, stage, model_id, pipeline_version, input_fingerprint)
                    VALUES (%s, %s, %s, %s, %s) ON CONFLICT DO NOTHING
                    """,
                    (row["asset_id"], row["stage"], fallback["id"], row["pipeline_version"], row["input_fingerprint"]),
                )
                fallback_enqueued = cursor.rowcount > 0
    if not row:
        raise HTTPException(status_code=409, detail="Lease is no longer valid")
    logger.error("failed job_id=%s state=%s error=%s", job_id, row["state"], sanitized)
    return {"status": "fallback-enqueued" if fallback_enqueued else row["state"]}


@app.get("/v1/assets/{asset_id}/inference-image", dependencies=[Depends(require_token)])
async def inference_image(asset_id: UUID) -> Response:
    response = await immich_request("GET", f"/assets/{asset_id}/thumbnail", params={"size": "preview"})
    return Response(
        content=response.content,
        media_type=response.headers.get("content-type", "image/jpeg"),
        headers={"cache-control": "private, max-age=300"},
    )


@app.get("/v1/reports/status", dependencies=[Depends(require_token)])
def report_status() -> dict[str, Any]:
    with pool.connection() as connection:
        jobs = connection.execute("SELECT state, count(*) AS count FROM ai_jobs GROUP BY state ORDER BY state").fetchall()
        assets = connection.execute("SELECT count(*) AS count FROM ai_assets").fetchone()["count"]
        results = connection.execute("SELECT count(*) AS count FROM ai_results").fetchone()["count"]
    return {"assets": assets, "results": results, "jobs": jobs, "pipelineVersion": PIPELINE_VERSION}
