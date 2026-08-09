#!/bin/bash
set -euo pipefail

repo_root="${FANGYUANLI_REPO_ROOT:-/srv/fangyuanli}"
env_file="${FANGYUANLI_ENV_FILE:-${repo_root}/.env}"
host="${STAGING_PUBLIC_HOST:-}"
nginx_available="/etc/nginx/sites-available/fangyuanli-staging"
nginx_enabled="/etc/nginx/sites-enabled/fangyuanli-staging"
certbot_root="/var/www/fangyuanli-certbot"

if [[ -z "$host" && -f "$env_file" ]]; then
  host="$(sed -n 's/^STAGING_PUBLIC_HOST=//p' "$env_file" | tail -n 1)"
  host="${host%\"}"
  host="${host#\"}"
fi

if [[ ! "$host" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]]; then
  echo "STAGING_PUBLIC_HOST 缺失或格式无效" >&2
  exit 1
fi

if [[ ! -f "$env_file" ]]; then
  echo "找不到环境文件：$env_file" >&2
  exit 1
fi

update_env_value() {
  local name="$1"
  local value="$2"
  local temporary
  temporary="$(mktemp)"
  awk -v name="$name" -v value="$value" '
    BEGIN { replaced = 0 }
    $0 ~ "^" name "=" {
      if (!replaced) print name "=" value
      replaced = 1
      next
    }
    { print }
    END { if (!replaced) print name "=" value }
  ' "$env_file" >"$temporary"
  install -o root -g root -m 0600 "$temporary" "$env_file"
  rm -f "$temporary"
}

render_config() {
  local template="$1"
  local output="$2"
  local temporary
  temporary="$(mktemp)"
  sed "s/__STAGING_PUBLIC_HOST__/${host}/g" "$template" >"$temporary"
  install -o root -g root -m 0644 "$temporary" "$output"
  rm -f "$temporary"
}

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends nginx certbot

install -d -o www-data -g www-data -m 0755 "$certbot_root"
rm -f /etc/nginx/sites-enabled/default

if [[ ! -s "/etc/letsencrypt/live/${host}/fullchain.pem" ]]; then
  render_config \
    "$repo_root/deploy/nginx/fangyuanli-staging-bootstrap.conf.template" \
    "$nginx_available"
  ln -sfn "$nginx_available" "$nginx_enabled"
  nginx -t
  systemctl enable --now nginx.service
  systemctl reload nginx.service

  certbot certonly \
    --webroot \
    --webroot-path "$certbot_root" \
    --domain "$host" \
    --cert-name "$host" \
    --non-interactive \
    --agree-tos \
    --register-unsafely-without-email
fi

render_config \
  "$repo_root/deploy/nginx/fangyuanli-staging.conf.template" \
  "$nginx_available"
ln -sfn "$nginx_available" "$nginx_enabled"
install -o root -g root -m 0755 \
  "$repo_root/deploy/nginx/reload-nginx.sh" \
  /etc/letsencrypt/renewal-hooks/deploy/reload-nginx

update_env_value STAGING_PUBLIC_HOST "$host"

nginx -t
systemctl enable --now nginx.service
systemctl reload nginx.service
systemctl enable --now certbot.timer

curl --fail --silent --show-error --max-time 10 \
  "https://${host}/health" >/dev/null

echo "方圆里 staging HTTPS 入口已就绪。"
