#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"

export TEST_CLIENT_ROLE=A
export IOS_STAGING_MODE="${IOS_STAGING_MODE:-profile}"

exec zsh "$script_dir/run-ios-field-staging-app.sh"
