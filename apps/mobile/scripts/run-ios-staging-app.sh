#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
mobile_dir="${script_dir:h}"
flutter_bin="${FLUTTER_BIN:-flutter}"
ios_device_id="${IOS_STAGING_DEVICE_ID:-}"
client_role="${TEST_CLIENT_ROLE:-}"
run_mode="${IOS_STAGING_MODE:-debug}"
build_identity="${BUILD_IDENTITY:-$($script_dir/staging-source-identity.sh)}"
build_root="${IOS_STAGING_BUILD_ROOT:-$mobile_dir/build/ios}"
devicectl_bin="${DEVICECTL_BIN:-xcrun}"

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
  debug)
    flutter_mode_args=()
    xcode_configuration="Debug"
    ;;
  profile)
    flutter_mode_args=(--profile)
    xcode_configuration="Profile"
    ;;
  release)
    flutter_mode_args=(--release)
    xcode_configuration="Release"
    ;;
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
fallback_app="$build_root/${xcode_configuration}-iphoneos/Runner.app"
legacy_app="$build_root/iphoneos/Runner.app"
fallback_mtime_before=0
if [[ -d "$fallback_app" ]]; then
  fallback_mtime_before="$(stat -f '%m' "$fallback_app")"
fi

# Flutter occasionally looks in the legacy `iphoneos` directory after Xcode
# wrote the current flavor to `<Configuration>-iphoneos`. A bundle left there
# by an earlier run can otherwise be reported as a successful installation.
# This is generated output only; removing it forces this invocation to either
# install its fresh standard artifact or enter the timestamp-checked fallback.
if [[ -d "$legacy_app" ]]; then
  rm -rf -- "$legacy_app"
fi

if "$flutter_bin" run \
  -d "$ios_device_id" \
  "${flutter_mode_args[@]}" \
  --dart-define=APP_FLAVOR=staging \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=REALTIME_URL="$REALTIME_URL" \
  --dart-define=STAGING_TEST_PHONE_A="$STAGING_TEST_PHONE_A" \
  --dart-define=STAGING_TEST_PHONE_B="$STAGING_TEST_PHONE_B" \
  --dart-define=STAGING_TEST_CODE="$STAGING_TEST_CODE" \
  --dart-define=BUILD_IDENTITY="$build_identity" \
  --dart-define=TEST_CLIENT_ROLE="$client_role"; then
  exit 0
fi

# Some Flutter/Xcode combinations successfully produce a signed physical-iOS
# app in `<Configuration>-iphoneos`, but Flutter still looks only in the legacy
# `iphoneos` directory and exits before installation. Fall back only for A,
# only when this invocation produced a newer signed app, so a stale bundle can
# never be installed by accident.
if [[ "$client_role" != A || ! -d "$fallback_app" ]]; then
  exit 1
fi
fallback_mtime_after="$(stat -f '%m' "$fallback_app")"
if (( fallback_mtime_after <= fallback_mtime_before )); then
  print -u2 -- "Flutter 启动失败，且没有生成新的真机 App，拒绝安装旧产物。"
  exit 1
fi

bundle_identifier="${IOS_STAGING_APP_BUNDLE_ID:-$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$fallback_app/Info.plist"
)}"
print -r -- "检测到 Flutter 产物路径兼容问题，改用 Xcode 官方设备工具安装本次构建。"
"$devicectl_bin" devicectl device install app \
  --device "$ios_device_id" \
  "$fallback_app"
"$devicectl_bin" devicectl device process launch \
  --device "$ios_device_id" \
  --terminate-existing \
  "$bundle_identifier"
print -r -- "staging App 已通过备用通道安装并启动。"
