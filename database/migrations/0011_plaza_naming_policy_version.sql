ALTER TABLE plaza_grids
  ADD COLUMN naming_policy_version integer NOT NULL DEFAULT 1,
  ADD CONSTRAINT plaza_grids_naming_policy_version_positive
    CHECK (naming_policy_version > 0);

CREATE INDEX plaza_grids_naming_policy_retry_idx
  ON plaza_grids (grid_version_id, naming_policy_version, naming_retry_after)
  WHERE status = 'active';

COMMENT ON COLUMN plaza_grids.naming_policy_version IS
  'Automatic display-name policy last applied. It never changes plaza or conversation identity.';
