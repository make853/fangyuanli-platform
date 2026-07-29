CREATE TABLE sms_verifications (
  id uuid PRIMARY KEY,
  country_code varchar(8) NOT NULL,
  phone_ciphertext text NOT NULL,
  phone_hash varchar(128) NOT NULL,
  phone_last_four varchar(4) NOT NULL,
  purpose varchar(24) NOT NULL,
  code_hash char(64) NOT NULL,
  attempts integer NOT NULL DEFAULT 0,
  expires_at timestamptz NOT NULL,
  resend_after timestamptz NOT NULL,
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT sms_verifications_country_code
    CHECK (country_code = '+86'),
  CONSTRAINT sms_verifications_purpose
    CHECK (purpose = 'login'),
  CONSTRAINT sms_verifications_attempts_nonnegative
    CHECK (attempts >= 0)
);

CREATE INDEX sms_verifications_phone_created_idx
  ON sms_verifications (phone_hash, created_at DESC);

CREATE INDEX sms_verifications_expiry_idx
  ON sms_verifications (expires_at)
  WHERE consumed_at IS NULL;

ALTER TABLE auth_sessions
  ADD COLUMN source_verification_id uuid
    REFERENCES sms_verifications(id),
  ADD COLUMN login_idempotency_key_hash char(64),
  ADD COLUMN login_created_user boolean NOT NULL DEFAULT false;

CREATE UNIQUE INDEX auth_sessions_source_verification_idx
  ON auth_sessions (source_verification_id)
  WHERE source_verification_id IS NOT NULL;
