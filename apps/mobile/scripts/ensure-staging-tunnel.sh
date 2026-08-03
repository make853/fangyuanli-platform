#!/bin/zsh
set -euo pipefail

simulator_port="${STAGING_SIMULATOR_PORT:-3000}"
physical_port="${STAGING_PHYSICAL_PORT:-33000}"
runtime_dir="${TMPDIR:-/tmp}/fangyuanli-staging-${UID}"
pid_file="$runtime_dir/tunnel.pid"
log_file="$runtime_dir/tunnel.log"
lock_dir="$runtime_dir/start.lock"

health() {
  curl --noproxy '*' --silent --fail --max-time 2 \
    "http://127.0.0.1:${1}/health" >/dev/null
}

listener_exists() {
  lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

if health "$simulator_port" && health "$physical_port"; then
  print -r -- "staging 隧道已就绪：${simulator_port} / ${physical_port}"
  exit 0
fi

: "${STAGING_SSH_KEY:?请通过 STAGING_SSH_KEY 提供本机私钥路径}"
: "${STAGING_REMOTE_HOST:?请通过 STAGING_REMOTE_HOST 提供 SSH 目标}"

mkdir -p "$runtime_dir"
if ! mkdir "$lock_dir" 2>/dev/null; then
  for _ in {1..20}; do
    if health "$simulator_port" && health "$physical_port"; then
      print -r -- "staging 隧道已由另一进程建立"
      exit 0
    fi
    sleep 0.25
  done
  print -u2 -- "另一个隧道启动任务没有按时完成"
  exit 1
fi
trap 'rmdir "$lock_dir" >/dev/null 2>&1 || true' EXIT INT TERM

forward_args=()
for port in "$simulator_port" "$physical_port"; do
  if health "$port"; then
    continue
  fi
  if listener_exists "$port"; then
    print -u2 -- "端口 $port 已被非健康服务占用，已停止以避免误杀其他进程"
    exit 1
  fi
  if [[ "$port" == "$physical_port" ]]; then
    forward_args+=(-L "0.0.0.0:${port}:127.0.0.1:3000")
  else
    forward_args+=(-L "127.0.0.1:${port}:127.0.0.1:3000")
  fi
done

if (( ${#forward_args[@]} > 0 )); then
  nohup ssh -N "${forward_args[@]}" \
    -o BatchMode=yes \
    -o IdentitiesOnly=yes \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -i "$STAGING_SSH_KEY" \
    "$STAGING_REMOTE_HOST" </dev/null >>"$log_file" 2>&1 &
  tunnel_pid="$!"
  print -r -- "$tunnel_pid" >"$pid_file"
fi

for _ in {1..30}; do
  if health "$simulator_port" && health "$physical_port"; then
    print -r -- "staging 隧道已独立启动：${simulator_port} / ${physical_port}"
    exit 0
  fi
  sleep 0.25
done

if [[ -n "${tunnel_pid:-}" ]]; then
  kill "$tunnel_pid" >/dev/null 2>&1 || true
fi
print -u2 -- "staging 隧道启动失败，日志：$log_file"
exit 1
