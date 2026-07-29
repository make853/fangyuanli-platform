ALTER TABLE media_assets
  ADD COLUMN content_type varchar(100),
  ADD COLUMN sha256 char(64),
  ADD COLUMN original_file_name varchar(200);

CREATE TABLE media_upload_sessions (
  id uuid PRIMARY KEY,
  owner_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  purpose varchar(32) NOT NULL,
  media_type varchar(16) NOT NULL,
  original_file_name varchar(200) NOT NULL,
  content_type varchar(100) NOT NULL,
  expected_bytes bigint NOT NULL,
  expected_sha256 char(64) NOT NULL,
  duration_ms integer,
  width integer,
  height integer,
  object_key text NOT NULL UNIQUE,
  status varchar(24) NOT NULL DEFAULT 'pending',
  create_idempotency_hash char(64) NOT NULL,
  create_request_hash char(64) NOT NULL,
  complete_idempotency_hash char(64),
  complete_request_hash char(64),
  media_asset_id uuid REFERENCES media_assets(id),
  etag varchar(256),
  failure_code varchar(64),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT media_upload_sessions_owner_idempotency_unique
    UNIQUE (owner_user_id, create_idempotency_hash),
  CONSTRAINT media_upload_sessions_expected_values_valid
    CHECK (
      expected_bytes > 0
      AND expected_sha256 ~ '^[0-9a-f]{64}$'
      AND (duration_ms IS NULL OR duration_ms >= 0)
      AND (width IS NULL OR width > 0)
      AND (height IS NULL OR height > 0)
    ),
  CONSTRAINT media_upload_sessions_status_valid
    CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'expired')),
  CONSTRAINT media_upload_sessions_completion_consistency
    CHECK (
      (status = 'completed' AND media_asset_id IS NOT NULL)
      OR status <> 'completed'
    )
);

CREATE INDEX media_upload_sessions_owner_status_idx
  ON media_upload_sessions (owner_user_id, status, created_at DESC);

CREATE INDEX media_upload_sessions_expiry_idx
  ON media_upload_sessions (status, expires_at);
