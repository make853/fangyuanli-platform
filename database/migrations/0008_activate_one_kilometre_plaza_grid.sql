-- Product baseline change: use one-kilometre square plaza cells for the
-- initial rollout. Grid versions are immutable after reaching a shared
-- environment, so the 500 metre staging version is retired instead of edited.
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
  '019f0b00-0000-7000-8000-000000000002',
  2,
  'gcj02',
  'gcj02-web-mercator-v1',
  1000,
  '{"productBaseline":"one-kilometre-v1","technicalValidation":"required-before-production"}'::jsonb,
  'active'
);
