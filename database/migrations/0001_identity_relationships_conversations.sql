CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TYPE account_status AS ENUM (
  'active',
  'suspended',
  'deactivated',
  'deleted'
);

CREATE TYPE gender_type AS ENUM (
  'unspecified',
  'male',
  'female',
  'custom'
);

CREATE TYPE request_status AS ENUM (
  'pending',
  'accepted',
  'rejected',
  'cancelled',
  'expired'
);

CREATE TYPE friendship_status AS ENUM (
  'active',
  'deleted'
);

CREATE TYPE conversation_type AS ENUM (
  'plaza',
  'place',
  'activity',
  'direct',
  'system'
);

CREATE TYPE message_type AS ENUM (
  'text',
  'image',
  'voice',
  'video',
  'sticker',
  'location',
  'live_location',
  'activity_card',
  'system_event'
);

CREATE TYPE notification_override_mode AS ENUM (
  'inherit',
  'normal',
  'muted'
);

CREATE TABLE users (
  id uuid PRIMARY KEY,
  fangyuan_number varchar(32) NOT NULL UNIQUE,
  phone_ciphertext text NOT NULL,
  phone_hash varchar(128) NOT NULL UNIQUE,
  password_hash text,
  status account_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  CONSTRAINT users_fangyuan_number_not_blank
    CHECK (btrim(fangyuan_number) <> '')
);

CREATE TABLE media_assets (
  id uuid PRIMARY KEY,
  owner_user_id uuid REFERENCES users(id),
  purpose varchar(32) NOT NULL,
  media_type varchar(16) NOT NULL,
  object_key text NOT NULL UNIQUE,
  thumbnail_object_key text,
  cover_object_key text,
  width integer,
  height integer,
  duration_ms integer,
  bytes bigint,
  processing_status varchar(24) NOT NULL,
  expires_at timestamptz,
  compliance_hold boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  CONSTRAINT media_assets_dimensions_nonnegative
    CHECK (
      (width IS NULL OR width >= 0)
      AND (height IS NULL OR height >= 0)
      AND (duration_ms IS NULL OR duration_ms >= 0)
      AND (bytes IS NULL OR bytes >= 0)
    )
);

CREATE INDEX media_assets_expiry_idx
  ON media_assets (expires_at, compliance_hold);

CREATE TABLE user_profiles (
  user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  nickname varchar(64) NOT NULL,
  gender gender_type NOT NULL DEFAULT 'unspecified',
  custom_gender varchar(32),
  avatar_media_id uuid REFERENCES media_assets(id),
  background_media_id uuid REFERENCES media_assets(id),
  signature varchar(160),
  profile_version integer NOT NULL DEFAULT 1,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_profiles_nickname_not_blank CHECK (btrim(nickname) <> ''),
  CONSTRAINT user_profiles_custom_gender_consistency
    CHECK (
      (gender = 'custom' AND custom_gender IS NOT NULL)
      OR (gender <> 'custom' AND custom_gender IS NULL)
    )
);

CREATE TABLE user_privacy_settings (
  user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  strangers_can_view_profile boolean NOT NULL DEFAULT true,
  searchable_by_fangyuan_number boolean NOT NULL DEFAULT true,
  global_group_muted boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE user_devices (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform varchar(16) NOT NULL,
  device_name varchar(128),
  push_token_ciphertext text,
  last_active_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_devices_id_user_unique UNIQUE (id, user_id),
  CONSTRAINT user_devices_platform_supported
    CHECK (platform IN ('ios', 'android'))
);

CREATE INDEX user_devices_user_activity_idx
  ON user_devices (user_id, last_active_at DESC);

CREATE TABLE auth_sessions (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL,
  device_id uuid NOT NULL,
  refresh_token_hash varchar(128) NOT NULL UNIQUE,
  token_version integer NOT NULL DEFAULT 1,
  expires_at timestamptz NOT NULL,
  last_refreshed_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT auth_sessions_token_version_positive CHECK (token_version > 0),
  CONSTRAINT auth_sessions_device_owner_fk
    FOREIGN KEY (device_id, user_id)
    REFERENCES user_devices(id, user_id)
    ON DELETE CASCADE
);

CREATE INDEX auth_sessions_user_active_idx
  ON auth_sessions (user_id, revoked_at);

CREATE INDEX auth_sessions_device_active_idx
  ON auth_sessions (device_id, revoked_at);

CREATE TABLE friend_requests (
  id uuid PRIMARY KEY,
  sender_user_id uuid NOT NULL REFERENCES users(id),
  receiver_user_id uuid NOT NULL REFERENCES users(id),
  application_note varchar(200) NOT NULL,
  status request_status NOT NULL DEFAULT 'pending',
  decided_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT friend_requests_distinct_users
    CHECK (sender_user_id <> receiver_user_id),
  CONSTRAINT friend_requests_note_not_blank
    CHECK (btrim(application_note) <> ''),
  CONSTRAINT friend_requests_decision_consistency
    CHECK (
      (status = 'pending' AND decided_at IS NULL)
      OR (status <> 'pending' AND decided_at IS NOT NULL)
    )
);

CREATE INDEX friend_requests_receiver_status_idx
  ON friend_requests (receiver_user_id, status, created_at DESC);

CREATE INDEX friend_requests_sender_receiver_status_idx
  ON friend_requests (sender_user_id, receiver_user_id, status);

CREATE UNIQUE INDEX friend_requests_one_pending_direction_idx
  ON friend_requests (sender_user_id, receiver_user_id)
  WHERE status = 'pending';

CREATE TABLE friendships (
  id uuid PRIMARY KEY,
  user_low_id uuid NOT NULL REFERENCES users(id),
  user_high_id uuid NOT NULL REFERENCES users(id),
  status friendship_status NOT NULL DEFAULT 'active',
  established_from_request_id uuid REFERENCES friend_requests(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT friendships_canonical_order CHECK (user_low_id < user_high_id),
  CONSTRAINT friendships_unique_pair UNIQUE (user_low_id, user_high_id),
  CONSTRAINT friendships_id_pair_unique
    UNIQUE (id, user_low_id, user_high_id)
);

CREATE INDEX friendships_high_status_idx
  ON friendships (user_high_id, status);

CREATE TABLE friend_settings (
  friendship_id uuid NOT NULL REFERENCES friendships(id) ON DELETE CASCADE,
  owner_user_id uuid NOT NULL REFERENCES users(id),
  remark_name varchar(64),
  can_view_owner_posts boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (friendship_id, owner_user_id)
);

CREATE TABLE block_relations (
  blocker_user_id uuid NOT NULL REFERENCES users(id),
  blocked_user_id uuid NOT NULL REFERENCES users(id),
  prior_relation varchar(24) NOT NULL,
  prior_friendship_id uuid REFERENCES friendships(id),
  reason_code varchar(32),
  created_at timestamptz NOT NULL DEFAULT now(),
  removed_at timestamptz,
  PRIMARY KEY (blocker_user_id, blocked_user_id),
  CONSTRAINT block_relations_distinct_users
    CHECK (blocker_user_id <> blocked_user_id),
  CONSTRAINT block_relations_prior_relation
    CHECK (prior_relation IN ('friend', 'stranger')),
  CONSTRAINT block_relations_prior_friendship_consistency
    CHECK (
      (prior_relation = 'friend' AND prior_friendship_id IS NOT NULL)
      OR (prior_relation = 'stranger' AND prior_friendship_id IS NULL)
    )
);

CREATE INDEX block_relations_blocked_active_idx
  ON block_relations (blocked_user_id, removed_at);

CREATE TABLE conversations (
  id uuid PRIMARY KEY,
  type conversation_type NOT NULL,
  latest_sequence bigint NOT NULL DEFAULT 0,
  status varchar(24) NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT conversations_sequence_nonnegative CHECK (latest_sequence >= 0)
);

CREATE TABLE direct_conversations (
  conversation_id uuid PRIMARY KEY
    REFERENCES conversations(id) ON DELETE CASCADE,
  friendship_id uuid NOT NULL UNIQUE,
  user_low_id uuid NOT NULL,
  user_high_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT direct_conversations_canonical_order
    CHECK (user_low_id < user_high_id),
  CONSTRAINT direct_conversations_friendship_pair_fk
    FOREIGN KEY (friendship_id, user_low_id, user_high_id)
    REFERENCES friendships(id, user_low_id, user_high_id)
);

CREATE TABLE messages (
  id uuid PRIMARY KEY,
  conversation_id uuid NOT NULL
    REFERENCES conversations(id) ON DELETE CASCADE,
  sequence bigint NOT NULL,
  sender_user_id uuid REFERENCES users(id),
  client_message_id uuid,
  type message_type NOT NULL,
  body_text text,
  payload jsonb,
  reply_to_message_id uuid REFERENCES messages(id),
  retention_policy varchar(32) NOT NULL,
  expires_at timestamptz,
  send_status varchar(24) NOT NULL DEFAULT 'sent',
  created_at timestamptz NOT NULL DEFAULT now(),
  edited_at timestamptz,
  deleted_at timestamptz,
  CONSTRAINT messages_sequence_positive CHECK (sequence > 0),
  CONSTRAINT messages_content_present
    CHECK (
      body_text IS NOT NULL
      OR payload IS NOT NULL
      OR type IN ('image', 'voice', 'video', 'sticker')
    ),
  CONSTRAINT messages_conversation_sequence_unique
    UNIQUE (conversation_id, sequence),
  CONSTRAINT messages_sender_client_unique
    UNIQUE (sender_user_id, client_message_id)
);

CREATE INDEX messages_expiry_idx ON messages (expires_at);

CREATE TABLE conversation_read_cursors (
  conversation_id uuid NOT NULL
    REFERENCES conversations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  last_read_sequence bigint NOT NULL DEFAULT 0,
  first_unread_sequence bigint,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (conversation_id, user_id),
  CONSTRAINT conversation_read_cursors_nonnegative
    CHECK (last_read_sequence >= 0),
  CONSTRAINT conversation_read_cursors_first_unread_positive
    CHECK (first_unread_sequence IS NULL OR first_unread_sequence > 0)
);

CREATE INDEX conversation_read_cursors_user_updated_idx
  ON conversation_read_cursors (user_id, updated_at DESC);

CREATE TABLE conversation_notification_settings (
  conversation_id uuid NOT NULL
    REFERENCES conversations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  notification_override notification_override_mode
    NOT NULL DEFAULT 'inherit',
  pinned boolean NOT NULL DEFAULT false,
  announcement_dismissed_version integer,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (conversation_id, user_id)
);

CREATE INDEX conversation_notification_settings_user_pinned_idx
  ON conversation_notification_settings (user_id, pinned);
