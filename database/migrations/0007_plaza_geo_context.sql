CREATE TABLE plaza_grid_versions (
  id uuid PRIMARY KEY,
  version integer NOT NULL UNIQUE,
  coordinate_system varchar(16) NOT NULL DEFAULT 'gcj02',
  projection_key varchar(64) NOT NULL,
  side_length_meters integer NOT NULL,
  projection_definition jsonb NOT NULL DEFAULT '{}'::jsonb,
  status varchar(16) NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT plaza_grid_versions_version_positive CHECK (version > 0),
  CONSTRAINT plaza_grid_versions_coordinate_system_gcj02
    CHECK (coordinate_system = 'gcj02'),
  CONSTRAINT plaza_grid_versions_side_length_valid
    CHECK (side_length_meters BETWEEN 200 AND 3000),
  CONSTRAINT plaza_grid_versions_status_supported
    CHECK (status IN ('active', 'retired'))
);

CREATE UNIQUE INDEX plaza_grid_versions_one_active_idx
  ON plaza_grid_versions ((status))
  WHERE status = 'active';

CREATE TABLE plaza_grids (
  id uuid PRIMARY KEY,
  grid_version_id uuid NOT NULL REFERENCES plaza_grid_versions(id),
  grid_x bigint NOT NULL,
  grid_y bigint NOT NULL,
  conversation_id uuid NOT NULL UNIQUE REFERENCES conversations(id),
  display_name varchar(96) NOT NULL,
  naming_source varchar(24) NOT NULL DEFAULT 'neutral',
  center_longitude_gcj02 numeric(10, 7) NOT NULL,
  center_latitude_gcj02 numeric(10, 7) NOT NULL,
  status varchar(16) NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT plaza_grids_cell_unique
    UNIQUE (grid_version_id, grid_x, grid_y),
  CONSTRAINT plaza_grids_name_not_blank CHECK (btrim(display_name) <> ''),
  CONSTRAINT plaza_grids_naming_source_supported
    CHECK (naming_source IN ('landmark', 'venue', 'road', 'community', 'neutral')),
  CONSTRAINT plaza_grids_longitude_valid
    CHECK (center_longitude_gcj02 BETWEEN -180 AND 180),
  CONSTRAINT plaza_grids_latitude_valid
    CHECK (center_latitude_gcj02 BETWEEN -90 AND 90),
  CONSTRAINT plaza_grids_status_supported
    CHECK (status IN ('active', 'hidden', 'retired'))
);

CREATE INDEX plaza_grids_active_version_idx
  ON plaza_grids (grid_version_id, status, grid_x, grid_y);

COMMENT ON COLUMN plaza_grids.center_longitude_gcj02 IS
  'GCJ-02 grid center used only by the geo domain; never expose as a user location.';
COMMENT ON COLUMN plaza_grids.center_latitude_gcj02 IS
  'GCJ-02 grid center used only by the geo domain; never expose as a user location.';

CREATE TABLE user_plaza_anchors (
  user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  grid_version_id uuid NOT NULL REFERENCES plaza_grid_versions(id),
  anchor_longitude_gcj02 numeric(10, 7) NOT NULL,
  anchor_latitude_gcj02 numeric(10, 7) NOT NULL,
  plaza_ids uuid[] NOT NULL,
  pending_plaza_ids uuid[],
  pending_confirmation_count integer NOT NULL DEFAULT 0,
  pending_first_seen_at timestamptz,
  last_accuracy_meters numeric(8, 2) NOT NULL,
  anchor_policy_version integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_confirmed_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_plaza_anchors_longitude_valid
    CHECK (anchor_longitude_gcj02 BETWEEN -180 AND 180),
  CONSTRAINT user_plaza_anchors_latitude_valid
    CHECK (anchor_latitude_gcj02 BETWEEN -90 AND 90),
  CONSTRAINT user_plaza_anchors_four_plazas CHECK (cardinality(plaza_ids) = 4),
  CONSTRAINT user_plaza_anchors_pending_four_plazas
    CHECK (pending_plaza_ids IS NULL OR cardinality(pending_plaza_ids) = 4),
  CONSTRAINT user_plaza_anchors_confirmation_nonnegative
    CHECK (pending_confirmation_count >= 0),
  CONSTRAINT user_plaza_anchors_policy_version_positive
    CHECK (anchor_policy_version > 0)
);

CREATE INDEX user_plaza_anchors_grid_version_idx
  ON user_plaza_anchors (grid_version_id, updated_at DESC);

-- Staging/MVP default. A different side length must be introduced as a new
-- version instead of mutating this row so existing plaza IDs remain stable.
INSERT INTO plaza_grid_versions (
  id,
  version,
  coordinate_system,
  projection_key,
  side_length_meters,
  projection_definition,
  status
) VALUES (
  '019f0b00-0000-7000-8000-000000000001',
  1,
  'gcj02',
  'gcj02-web-mercator-v1',
  500,
  '{"technicalValidation":"required-before-production"}'::jsonb,
  'active'
);
