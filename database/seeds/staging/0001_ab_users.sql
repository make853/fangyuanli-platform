INSERT INTO users (
  id,
  fangyuan_number,
  phone_ciphertext,
  phone_hash,
  status
)
VALUES
  (
    '019f0000-0000-7000-8000-00000000000a',
    'FYTESTA',
    'staging-test-only:no-real-phone:a',
    'staging-test-only:phone-hash-a',
    'active'
  ),
  (
    '019f0000-0000-7000-8000-00000000000b',
    'FYTESTB',
    'staging-test-only:no-real-phone:b',
    'staging-test-only:phone-hash-b',
    'active'
  )
ON CONFLICT (id) DO UPDATE SET
  fangyuan_number = EXCLUDED.fangyuan_number,
  phone_ciphertext = EXCLUDED.phone_ciphertext,
  phone_hash = EXCLUDED.phone_hash,
  status = EXCLUDED.status,
  updated_at = now();

INSERT INTO user_profiles (
  user_id,
  nickname,
  gender,
  signature
)
VALUES
  (
    '019f0000-0000-7000-8000-00000000000a',
    '测试用户A',
    'unspecified',
    '方圆里 staging A账号'
  ),
  (
    '019f0000-0000-7000-8000-00000000000b',
    '测试用户B',
    'unspecified',
    '方圆里 staging B账号'
  )
ON CONFLICT (user_id) DO UPDATE SET
  nickname = EXCLUDED.nickname,
  gender = EXCLUDED.gender,
  signature = EXCLUDED.signature,
  profile_version = user_profiles.profile_version + 1,
  updated_at = now();

INSERT INTO user_privacy_settings (user_id)
VALUES
  ('019f0000-0000-7000-8000-00000000000a'),
  ('019f0000-0000-7000-8000-00000000000b')
ON CONFLICT (user_id) DO NOTHING;
