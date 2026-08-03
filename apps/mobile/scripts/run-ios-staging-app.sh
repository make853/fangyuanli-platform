#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
mobile_dir="${script_dir:h}"
flutter_bin="${FLUTTER_BIN:-flutter}"
ios_device_id="${IOS_STAGING_DEVICE_ID:-}"
client_role="${TEST_CLIENT_ROLE:-}"
run_mode="${IOS_STAGING_MODE:-debug}"
build_identity="${BUILD_IDENTITY:-$($script_dir/staging-source-identity.sh)}"

: "${ios_device_id:?IOS_STAGING_DEVICE_ID 必须填写 flutter devices 显示的精确设备 ID}"
: "${client_role:?TEST_CLIENT_ROLE 必须填写 A 或 B}"
: "${API_BASE_URL:?缺少 API_BASE_URL}"
: "${REALTIME_URL:?缺少 REALTIME_URL}"
: "${STAGING_TEST_PHONE_A:?缺少 STAGING_TEST_PHONE_A}"
: "${STAGING_TEST_PHONE_B:?缺少 STAGING_TEST_PHONE_B}"
: "${STAGING_TEST_CODE:?缺少 STAGING_TEST_CODE}"

if [[ "$client_role" != A && "$client_role" != B ]]; then
  print -u2 -- "TEST_CLIENT_ROLE 仅支持 A 或 B"
  exit 1
fi

case "$run_mode" in
  debug) flutter_mode_args=() ;;
  profile) flutter_mode_args=(--profile) ;;
  release) flutter_mode_args=(--release) ;;
  *)
    print -u2 -- "IOS_STAGING_MODE 仅支持 debug、profile 或 release"
    exit 1
    ;;
esac

devices_json="$($flutter_bin devices --machine --device-timeout 30)"
DEVICE_JSON="$devices_json" DEVICE_ID="$ios_device_id" CLIENT_ROLE="$client_role" \
  /usr/bin/python3 - <<'PY'
import json
import os
import sys

devices = json.loads(os.environ['DEVICE_JSON'])
device_id = os.environ['DEVICE_ID']
role = os.environ['CLIENT_ROLE']
matches = [item for item in devices if item.get('id') == device_id]
if len(matches) != 1:
    available = ', '.join(f"{item.get('name')} [{item.get('id')}]" for item in devices)
    print(f"找不到精确设备 ID {device_id}。当前设备：{available}", file=sys.stderr)
    raise SystemExit(1)
device = matches[0]
is_emulator = bool(device.get('emulator'))
if role == 'A' and is_emulator:
    print('测试端 A 必须是真机，当前目标是模拟器', file=sys.stderr)
    raise SystemExit(1)
if role == 'B' and not is_emulator:
    print('测试端 B 必须是模拟器，当前目标是真机', file=sys.stderr)
    raise SystemExit(1)
print(f"设备校验通过：{role} = {device.get('name')} [{device_id}]")
PY

cd "$mobile_dir"
print -r -- "构建身份：staging · ${client_role} · ${build_identity}"
"$flutter_bin" run \
  -d "$ios_device_id" \
  "${flutter_mode_args[@]}" \
  --dart-define=APP_FLAVOR=staging \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=REALTIME_URL="$REALTIME_URL" \
  --dart-define=STAGING_TEST_PHONE_A="$STAGING_TEST_PHONE_A" \
  --dart-define=STAGING_TEST_PHONE_B="$STAGING_TEST_PHONE_B" \
  --dart-define=STAGING_TEST_CODE="$STAGING_TEST_CODE" \
  --dart-define=BUILD_IDENTITY="$build_identity" \
  --dart-define=TEST_CLIENT_ROLE="$client_role"
