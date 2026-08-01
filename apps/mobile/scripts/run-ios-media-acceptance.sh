#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
mobile_dir="${script_dir:h}"
ios_device="${IOS_ACCEPTANCE_DEVICE:-iPhone 17}"
api_base_url="${API_BASE_URL:-http://127.0.0.1:3000}"
flutter_bin="${FLUTTER_BIN:-}"

if [[ -z "$flutter_bin" ]]; then
  flutter_bin="$(command -v flutter || true)"
fi

if [[ -z "$flutter_bin" || ! -x "$flutter_bin" ]]; then
  echo "找不到 Flutter，请通过 FLUTTER_BIN 指定可执行文件。" >&2
  exit 1
fi

if [[ -z "${STAGING_TEST_PHONE_A:-}" || -z "${STAGING_TEST_PHONE_B:-}" || ! "${STAGING_TEST_CODE:-}" =~ '^[0-9]{6}$' ]]; then
  echo "请提供 STAGING_TEST_PHONE_A、STAGING_TEST_PHONE_B 和6位 STAGING_TEST_CODE。" >&2
  exit 1
fi

cd "$mobile_dir"
"$flutter_bin" test integration_test/media_upload_staging_test.dart \
  -d "$ios_device" \
  --dart-define=API_BASE_URL="$api_base_url" \
  --dart-define=STAGING_TEST_PHONE_A="$STAGING_TEST_PHONE_A" \
  --dart-define=STAGING_TEST_PHONE_B="$STAGING_TEST_PHONE_B" \
  --dart-define=STAGING_TEST_CODE="$STAGING_TEST_CODE"
