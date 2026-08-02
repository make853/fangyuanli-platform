CREATE TYPE place_certification_status AS ENUM (
  'unverified',
  'review_pending',
  'verified',
  'rejected',
  'revoked'
);

CREATE TYPE place_visibility_status AS ENUM (
  'active',
  'hidden_inactive',
  'hidden_by_platform'
);

CREATE TYPE group_role AS ENUM (
  'owner',
  'admin',
  'resident',
  'member'
);

CREATE TYPE speak_policy AS ENUM (
  'nearby_and_members',
  'members_only',
  'admins_only'
);

CREATE TABLE place_categories (
  key varchar(64) PRIMARY KEY,
  parent_key varchar(64) REFERENCES place_categories(key),
  display_name varchar(64) NOT NULL,
  sort_order integer NOT NULL,
  active boolean NOT NULL DEFAULT true,
  CONSTRAINT place_categories_key_not_blank CHECK (btrim(key) <> ''),
  CONSTRAINT place_categories_display_name_not_blank
    CHECK (btrim(display_name) <> '')
);

INSERT INTO place_categories (key, display_name, sort_order) VALUES
  ('food_retail', '餐饮与商铺', 10),
  ('community', '住宅与社区', 20),
  ('sports_fitness', '运动与健身', 30),
  ('culture_entertainment', '文化与娱乐', 40),
  ('nightlife', '酒吧与夜生活', 50),
  ('parks_scenic', '景区与公园', 60),
  ('education_public', '学校与公共服务', 70),
  ('shopping_district', '商场与商业街', 80),
  ('transport_other', '交通与其他地点', 90);

CREATE TABLE place_pois (
  id uuid PRIMARY KEY,
  amap_poi_id varchar(128) NOT NULL UNIQUE,
  name varchar(160) NOT NULL,
  address varchar(300),
  longitude_gcj02 numeric(10, 7) NOT NULL,
  latitude_gcj02 numeric(10, 7) NOT NULL,
  coordinate_system varchar(16) NOT NULL DEFAULT 'gcj02',
  amap_category_code varchar(64),
  amap_category_name varchar(160),
  display_category_key varchar(64) NOT NULL REFERENCES place_categories(key),
  source_updated_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT place_pois_name_not_blank CHECK (btrim(name) <> ''),
  CONSTRAINT place_pois_longitude_valid
    CHECK (longitude_gcj02 BETWEEN -180 AND 180),
  CONSTRAINT place_pois_latitude_valid
    CHECK (latitude_gcj02 BETWEEN -90 AND 90),
  CONSTRAINT place_pois_coordinate_system_gcj02
    CHECK (coordinate_system = 'gcj02')
);

COMMENT ON COLUMN place_pois.longitude_gcj02 IS
  'Raw Amap GCJ-02 longitude. Do not relabel as WGS84/PostGIS SRID 4326.';
COMMENT ON COLUMN place_pois.latitude_gcj02 IS
  'Raw Amap GCJ-02 latitude. Spatial projection remains a validation item.';

CREATE INDEX place_pois_discovery_bounds_idx
  ON place_pois (latitude_gcj02, longitude_gcj02);
CREATE INDEX place_pois_category_name_idx
  ON place_pois (display_category_key, name);

CREATE TABLE place_groups (
  id uuid PRIMARY KEY,
  poi_id uuid NOT NULL UNIQUE REFERENCES place_pois(id),
  conversation_id uuid NOT NULL UNIQUE REFERENCES conversations(id),
  certification_status place_certification_status NOT NULL DEFAULT 'unverified',
  visibility_status place_visibility_status NOT NULL DEFAULT 'active',
  visibility_radius_meters integer NOT NULL DEFAULT 500,
  speak_policy speak_policy NOT NULL DEFAULT 'nearby_and_members',
  last_effective_activity_at timestamptz,
  version integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT place_groups_visibility_radius_valid
    CHECK (visibility_radius_meters BETWEEN 100 AND 30000),
  CONSTRAINT place_groups_version_positive CHECK (version > 0)
);

CREATE INDEX place_groups_visibility_activity_idx
  ON place_groups (visibility_status, last_effective_activity_at DESC);

CREATE TABLE place_group_members (
  place_group_id uuid NOT NULL REFERENCES place_groups(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role group_role NOT NULL,
  status varchar(16) NOT NULL DEFAULT 'active',
  appointed_by_user_id uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (place_group_id, user_id),
  CONSTRAINT place_group_members_status_supported
    CHECK (status IN ('active', 'removed'))
);

CREATE INDEX place_group_members_user_role_idx
  ON place_group_members (user_id, role, status);

CREATE TABLE place_heat_snapshots (
  place_group_id uuid NOT NULL REFERENCES place_groups(id) ON DELETE CASCADE,
  calculated_at timestamptz NOT NULL,
  score numeric(10, 4) NOT NULL,
  level varchar(16) NOT NULL,
  unique_speakers integer NOT NULL,
  effective_messages integer NOT NULL,
  interaction_score numeric(10, 4) NOT NULL,
  decay_factor numeric(10, 6) NOT NULL,
  formula_version integer NOT NULL,
  PRIMARY KEY (place_group_id, calculated_at),
  CONSTRAINT place_heat_level_supported
    CHECK (level IN ('quiet', 'neutral', 'active', 'very_active', 'hot')),
  CONSTRAINT place_heat_counts_nonnegative
    CHECK (unique_speakers >= 0 AND effective_messages >= 0),
  CONSTRAINT place_heat_formula_version_positive CHECK (formula_version > 0)
);

CREATE INDEX place_heat_level_calculated_idx
  ON place_heat_snapshots (level, calculated_at DESC);
