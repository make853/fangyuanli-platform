ALTER TABLE friend_requests
  ADD COLUMN create_idempotency_key_hash char(64);

CREATE UNIQUE INDEX friend_requests_create_idempotency_idx
  ON friend_requests (sender_user_id, create_idempotency_key_hash)
  WHERE create_idempotency_key_hash IS NOT NULL;

ALTER TABLE friend_settings
  ADD COLUMN pinned boolean NOT NULL DEFAULT false;

CREATE TABLE relationship_audit_logs (
  id uuid PRIMARY KEY,
  actor_user_id uuid NOT NULL REFERENCES users(id),
  target_user_id uuid NOT NULL REFERENCES users(id),
  action varchar(40) NOT NULL,
  friend_request_id uuid REFERENCES friend_requests(id),
  friendship_id uuid REFERENCES friendships(id),
  metadata jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT relationship_audit_logs_distinct_users
    CHECK (actor_user_id <> target_user_id)
);

CREATE INDEX relationship_audit_logs_actor_created_idx
  ON relationship_audit_logs (actor_user_id, created_at DESC);

CREATE INDEX relationship_audit_logs_target_created_idx
  ON relationship_audit_logs (target_user_id, created_at DESC);
