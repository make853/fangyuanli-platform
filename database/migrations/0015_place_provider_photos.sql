ALTER TABLE place_pois
  ADD COLUMN provider_photo_url text,
  ADD COLUMN provider_photo_title varchar(200),
  ADD COLUMN provider_photo_checked_at timestamptz;

COMMENT ON COLUMN place_pois.provider_photo_url IS
  'Refreshable external POI photo URL supplied by the map provider; never treated as a merchant-owned avatar.';
COMMENT ON COLUMN place_pois.provider_photo_checked_at IS
  'Last successful provider response time, including responses with no usable photo.';
