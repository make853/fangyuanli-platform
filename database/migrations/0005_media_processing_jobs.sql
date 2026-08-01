ALTER TABLE media_assets
  ADD COLUMN display_object_key text,
  ADD COLUMN processing_failure_code varchar(64),
  ADD COLUMN processing_completed_at timestamptz,
  ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();

CREATE UNIQUE INDEX media_assets_display_object_key_unique
  ON media_assets (display_object_key)
  WHERE display_object_key IS NOT NULL;

CREATE UNIQUE INDEX media_assets_thumbnail_object_key_unique
  ON media_assets (thumbnail_object_key)
  WHERE thumbnail_object_key IS NOT NULL;

CREATE TABLE media_processing_jobs (
  id uuid PRIMARY KEY,
  media_asset_id uuid NOT NULL UNIQUE REFERENCES media_assets(id) ON DELETE CASCADE,
  status varchar(24) NOT NULL DEFAULT 'pending',
  attempt_count integer NOT NULL DEFAULT 0,
  available_at timestamptz NOT NULL DEFAULT now(),
  lease_owner varchar(128),
  lease_expires_at timestamptz,
  last_error_code varchar(64),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  CONSTRAINT media_processing_jobs_status_valid
    CHECK (status IN ('pending', 'processing', 'retry', 'completed', 'failed')),
  CONSTRAINT media_processing_jobs_attempt_count_valid
    CHECK (attempt_count >= 0),
  CONSTRAINT media_processing_jobs_lease_consistency
    CHECK (
      (status = 'processing' AND lease_owner IS NOT NULL AND lease_expires_at IS NOT NULL)
      OR
      (status <> 'processing' AND lease_owner IS NULL AND lease_expires_at IS NULL)
    ),
  CONSTRAINT media_processing_jobs_completion_consistency
    CHECK (
      (status = 'completed' AND completed_at IS NOT NULL)
      OR status <> 'completed'
    )
);

CREATE INDEX media_processing_jobs_available_idx
  ON media_processing_jobs (status, available_at, created_at)
  WHERE status IN ('pending', 'retry');

CREATE INDEX media_processing_jobs_expired_lease_idx
  ON media_processing_jobs (lease_expires_at)
  WHERE status = 'processing';

INSERT INTO media_processing_jobs (
  id,
  media_asset_id,
  status,
  available_at,
  created_at,
  updated_at
)
SELECT gen_random_uuid(), id, 'pending', now(), now(), now()
  FROM media_assets
 WHERE processing_status = 'processing'
   AND deleted_at IS NULL
ON CONFLICT (media_asset_id) DO NOTHING;
