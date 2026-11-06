CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS ai_assets (
    asset_id uuid PRIMARY KEY,
    checksum text NOT NULL,
    input_fingerprint text NOT NULL,
    original_filename text,
    media_type text NOT NULL,
    file_created_at timestamptz,
    immich_updated_at timestamptz,
    discovered_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ai_models (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    stage text NOT NULL,
    model_name text NOT NULL,
    model_revision text NOT NULL,
    weights_sha256 text NOT NULL,
    config jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (stage, model_name, model_revision, weights_sha256)
);

CREATE TABLE IF NOT EXISTS ai_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id uuid NOT NULL REFERENCES ai_assets(asset_id) ON DELETE CASCADE,
    stage text NOT NULL,
    model_id uuid NOT NULL REFERENCES ai_models(id),
    pipeline_version text NOT NULL,
    input_fingerprint text NOT NULL,
    state text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending', 'processing', 'completed', 'failed', 'retry')),
    retry_count integer NOT NULL DEFAULT 0,
    max_retries integer NOT NULL DEFAULT 5,
    next_attempt_at timestamptz NOT NULL DEFAULT now(),
    lease_owner text,
    lease_token uuid,
    lease_until timestamptz,
    last_error text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    UNIQUE (asset_id, stage, model_id, pipeline_version, input_fingerprint)
);
CREATE INDEX IF NOT EXISTS ai_jobs_ready_idx ON ai_jobs (state, next_attempt_at, created_at);
CREATE INDEX IF NOT EXISTS ai_jobs_asset_idx ON ai_jobs (asset_id);

CREATE TABLE IF NOT EXISTS ai_results (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id uuid NOT NULL UNIQUE REFERENCES ai_jobs(id) ON DELETE CASCADE,
    asset_id uuid NOT NULL REFERENCES ai_assets(asset_id) ON DELETE CASCADE,
    model_id uuid NOT NULL REFERENCES ai_models(id),
    pipeline_version text NOT NULL,
    result jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ai_captions (
    result_id uuid PRIMARY KEY REFERENCES ai_results(id) ON DELETE CASCADE,
    asset_id uuid NOT NULL REFERENCES ai_assets(asset_id) ON DELETE CASCADE,
    caption text NOT NULL,
    confidence real,
    language text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ai_tags (
    result_id uuid NOT NULL REFERENCES ai_results(id) ON DELETE CASCADE,
    asset_id uuid NOT NULL REFERENCES ai_assets(asset_id) ON DELETE CASCADE,
    category text NOT NULL,
    value text NOT NULL,
    confidence real,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (result_id, category, value)
);
CREATE INDEX IF NOT EXISTS ai_tags_asset_idx ON ai_tags (asset_id);
CREATE INDEX IF NOT EXISTS ai_tags_value_idx ON ai_tags (category, value);

CREATE TABLE IF NOT EXISTS ai_embeddings (
    result_id uuid PRIMARY KEY REFERENCES ai_results(id) ON DELETE CASCADE,
    asset_id uuid NOT NULL REFERENCES ai_assets(asset_id) ON DELETE CASCADE,
    model_id uuid NOT NULL REFERENCES ai_models(id),
    dimensions integer NOT NULL,
    embedding vector NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ai_embeddings_asset_idx ON ai_embeddings (asset_id, model_id);

CREATE TABLE IF NOT EXISTS ai_duplicate_groups (
    group_id uuid NOT NULL DEFAULT gen_random_uuid(),
    asset_id uuid NOT NULL REFERENCES ai_assets(asset_id) ON DELETE CASCADE,
    method text NOT NULL,
    score real,
    model_id uuid REFERENCES ai_models(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (group_id, asset_id)
);
