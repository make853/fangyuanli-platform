CREATE TABLE user_chat_history_entries (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  last_entered_at timestamptz NOT NULL,
  entry_count integer NOT NULL DEFAULT 1,
  PRIMARY KEY (user_id, conversation_id),
  CONSTRAINT user_chat_history_entries_count_positive CHECK (entry_count > 0)
);

CREATE INDEX user_chat_history_entries_user_recent_idx
  ON user_chat_history_entries (user_id, last_entered_at DESC);
