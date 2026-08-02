ALTER TABLE plaza_grids
  ADD COLUMN naming_last_attempted_at timestamptz,
  ADD COLUMN naming_retry_after timestamptz;

CREATE INDEX plaza_grids_neutral_naming_retry_idx
  ON plaza_grids (naming_retry_after, grid_version_id)
  WHERE naming_source = 'neutral' AND status = 'active';

COMMENT ON COLUMN plaza_grids.naming_last_attempted_at IS
  'Last server-side stable-name lookup. Never contains a user location.';
COMMENT ON COLUMN plaza_grids.naming_retry_after IS
  'Cross-process retry lease that prevents repeated external map requests.';
