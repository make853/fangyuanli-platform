#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
mobile_dir="${script_dir:h}"
acceptance_wrapper="${STAGING_ACCEPTANCE_WRAPPER:-$mobile_dir/build/run-ios-media-acceptance.sh}"
ssh_bin="${SSH_BIN:-ssh}"
client_role="${TEST_CLIENT_ROLE:-A}"
run_mode="${IOS_STAGING_MODE:-profile}"
ios_device_id="${IOS_STAGING_DEVICE_ID:-}"

if [[ ! -f "$acceptance_wrapper" ]]; then
  print -u2 -- "找不到本机 staging 私有配置脚本。"
  exit 1
fi

# 只读取被 gitignore 保护的本机配置；密钥路径和服务器地址不会进入仓库。
eval "$(sed -n -E '/^(flutter_bin|ssh_key|remote_host)=/p' "$acceptance_wrapper")"

remote_env() {
  local name="$1"
  local value
  value="$($ssh_bin -o BatchMode=yes -o IdentitiesOnly=yes -i "$ssh_key" "$remote_host" \
    "sudo sed -n 's/^${name}=//p' /srv/fangyuanli/.env | head -n 1")"
  value="${value%\"}"
  value="${value#\"}"
  print -r -- "$value"
}

if [[ -z "$ios_device_id" ]]; then
  devices_json="$($flutter_bin devices --machine --device-timeout 30)"
  ios_device_id="$(DEVICE_JSON="$devices_json" /usr/bin/python3 - <<'PY'
import json
import os
import sys

devices = json.loads(os.environ['DEVICE_JSON'])
matches = [
    item for item in devices
    if item.get('targetPlatform') == 'ios' and not bool(item.get('emulator'))
]
if len(matches) != 1:
    print('场外测试要求恰好连接一台 iPhone 真机', file=sys.stderr)
    raise SystemExit(1)
print(matches[0]['id'])
PY
)"
fi

staging_public_host="$(remote_env STAGING_PUBLIC_HOST)"
STAGING_TEST_PHONE_A="$(remote_env STAGING_TEST_PHONE_A)"
STAGING_TEST_PHONE_B="$(remote_env STAGING_TEST_PHONE_B)"
STAGING_TEST_CODE="$(remote_env STAGING_SMS_TEST_CODE)"

if [[ ! "$staging_public_host" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]]; then
  print -u2 -- "服务器未配置有效的 STAGING_PUBLIC_HOST"
  exit 1
fi

unset ssh_key remote_host ssh_bin

FLUTTER_BIN="$flutter_bin" \
IOS_STAGING_DEVICE_ID="$ios_device_id" \
IOS_STAGING_MODE="$run_mode" \
TEST_CLIENT_ROLE="$client_role" \
API_BASE_URL="https://${staging_public_host}" \
REALTIME_URL="wss://${staging_public_host}/ws/v1" \
STAGING_TEST_PHONE_A="$STAGING_TEST_PHONE_A" \
STAGING_TEST_PHONE_B="$STAGING_TEST_PHONE_B" \
STAGING_TEST_CODE="$STAGING_TEST_CODE" \
  zsh "$script_dir/run-ios-staging-app.sh"
