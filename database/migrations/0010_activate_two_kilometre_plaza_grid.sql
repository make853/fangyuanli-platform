-- Product baseline change: use two-kilometre square plaza cells for the
-- initial rollout. Shared grid versions are immutable, so version 2 is
-- retired rather than rewritten. Existing plazas, conversations and messages
-- remain available for audit and rollback but are not returned by new geo
-- contexts.
UPDATE plaza_grid_versions
   SET status = 'retired'
 WHERE status = 'active';

INSERT INTO plaza_grid_versions (
  id,
  version,
  coordinate_system,
  projection_key,
  side_length_meters,
  projection_definition,
  status
) VALUES (
  '019f0b00-0000-7000-8000-000000000003',
  3,
  'gcj02',
  'gcj02-web-mercator-v1',
  2000,
  '{"productBaseline":"two-kilometre-v1","technicalValidation":"required-before-production"}'::jsonb,
  'active'
);
