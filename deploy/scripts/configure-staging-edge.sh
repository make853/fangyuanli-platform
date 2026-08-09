#!/bin/bash
set -euo pipefail

repo_root="${FANGYUANLI_REPO_ROOT:-/srv/fangyuanli}"
env_file="${FANGYUANLI_ENV_FILE:-${repo_root}/.env}"
host="${STAGING_PUBLIC_HOST:-}"
nginx_available="/etc/nginx/sites-available/fangyuanli-staging"
nginx_enabled="/etc/nginx/sites-enabled/fangyuanli-staging"
certbot_root="/var/www/fangyuanli-certbot"
certbot_bin="/snap/bin/certbot"

if [[ -z "$host" && -f "$env_file" ]]; then
  host="$(sed -n 's/^STAGING_PUBLIC_HOST=//p' "$env_file" | tail -n 1)"
  host="${host%\"}"
  host="${host#\"}"
fi

if [[ ! "$host" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]]; then
  echo "STAGING_PUBLIC_HOST 缺失或格式无效" >&2
  exit 1
fi

host_kind="dns"
if [[ "$host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  IFS='.' read -r octet1 octet2 octet3 octet4 <<<"$host"
  for octet in "$octet1" "$octet2" "$octet3" "$octet4"; do
    if (( 10#$octet > 255 )); then
      echo "STAGING_PUBLIC_HOST 包含无效的 IPv4 地址" >&2
      exit 1
    fi
  done
  host_kind="ip"
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
apt-get install -y --no-install-recommends nginx snapd

# Ubuntu 24.04 的 apt Certbot 版本不支持 IP 证书。统一使用官方 snap，
# DNS 域名和公网 IPv4 共用同一套签发、续期与部署钩子。
if ! snap list certbot >/dev/null 2>&1; then
  snap install certbot --classic
else
  snap refresh certbot
fi
ln -sfn "$certbot_bin" /usr/local/bin/certbot

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

  certbot_arguments=(
    certonly
    --webroot
    --webroot-path "$certbot_root"
    --cert-name "$host"
    --non-interactive
    --agree-tos
    --register-unsafely-without-email
  )
  if [[ "$host_kind" == "ip" ]]; then
    certbot_arguments+=(
      --preferred-profile shortlived
      --ip-address "$host"
    )
  else
    certbot_arguments+=(--domain "$host")
  fi
  "$certbot_bin" "${certbot_arguments[@]}"
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

# snap 自带的 renew timer 负责短期 IP 证书和普通 DNS 证书续期。
if systemctl list-unit-files snap.certbot.renew.timer >/dev/null 2>&1; then
  systemctl enable --now snap.certbot.renew.timer
fi

curl --fail --silent --show-error --max-time 10 \
  "https://${host}/health" >/dev/null

echo "方圆里 staging HTTPS 入口已就绪。"
