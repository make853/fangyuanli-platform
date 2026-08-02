ALTER TABLE plaza_grids
  ADD COLUMN naming_kind varchar(32),
  ADD CONSTRAINT plaza_grids_naming_kind_supported
    CHECK (
      naming_kind IS NULL OR naming_kind IN (
        'public_square',
        'transit',
        'culture_scenic',
        'public_service',
        'commercial_landmark',
        'community',
        'village',
        'area',
        'road'
      )
    );

COMMENT ON COLUMN plaza_grids.naming_kind IS
  'Semantic class selected by the automatic naming policy for audit and future policy upgrades.';
