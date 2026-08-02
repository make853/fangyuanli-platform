ALTER TABLE plaza_grids
  ADD COLUMN naming_provider varchar(24),
  ADD COLUMN naming_provider_place_id varchar(128),
  ADD COLUMN naming_longitude_gcj02 decimal(10,7),
  ADD COLUMN naming_latitude_gcj02 decimal(10,7),
  ADD CONSTRAINT plaza_grids_naming_coordinate_pair
    CHECK (
      (naming_longitude_gcj02 IS NULL AND naming_latitude_gcj02 IS NULL)
      OR
      (naming_longitude_gcj02 IS NOT NULL AND naming_latitude_gcj02 IS NOT NULL)
    ),
  ADD CONSTRAINT plaza_grids_naming_provider_supported
    CHECK (naming_provider IS NULL OR naming_provider IN ('amap'));

COMMENT ON COLUMN plaza_grids.naming_provider IS
  'External discovery provider for the selected automatic name; never plaza identity.';
COMMENT ON COLUMN plaza_grids.naming_provider_place_id IS
  'Opaque provider POI identifier retained only for naming audit and refresh.';
COMMENT ON COLUMN plaza_grids.naming_longitude_gcj02 IS
  'Selected naming landmark longitude, required to audit that the landmark is inside the plaza region.';
COMMENT ON COLUMN plaza_grids.naming_latitude_gcj02 IS
  'Selected naming landmark latitude, required to audit that the landmark is inside the plaza region.';
