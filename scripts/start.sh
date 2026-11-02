#!/usr/bin/env bash
# 幂等启动 kg_v4 服务：已在跑就什么都不做；掉线则拉起（带退避、日志轮转）。
# 前台调试：FOREGROUND=1 bash scripts/start.sh（Ctrl+C 停，不写看门狗日志）。
# 可配置：环境变量 > bundle.conf（拷 scripts/bundle.conf.example 到顶层改名）> 默认值。
#   DATA_DIR（默认 <bundle>/data）  PORT（8119）  HOST（127.0.0.1）  RUN_DIR（<bundle>/run）
#   REAL=1 真模型（需 engine/config.json 或环境变量 ZHIPU_API_KEY；两者都没有就按假模型起并记日志）
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[ -f "$HERE/bundle.conf" ] && . "$HERE/bundle.conf"
DATA=${DATA_DIR:-$HERE/data}
PORT=${PORT:-8119}
HOST=${HOST:-127.0.0.1}
RUN=${RUN_DIR:-$HERE/run}
ENGINE=$HERE/engine
PY=$HERE/.venv/bin/python
PIDF=$RUN/server.pid; LOG=$RUN/server.log; WLOG=$RUN/watch.log; HIST=$RUN/starts.hist
MAXSTART=3; WINDOW=600; MAXLOG=$((20*1024*1024)); KEEP=3
export TZ=${TZ:-Asia/Tokyo}
# 供 cli:claude / cli:zcode 后端找本机 claude/zcode 可执行文件（同正式 start.sh 的做法）
export PATH="/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin:$PATH"
say(){ echo "$(date '+%F %T') [start.sh] $*" >> "$WLOG"; }
mkdir -p "$RUN"
exec 9>"$RUN/start.lock"; flock -n 9 || exit 0
[ -x "$PY" ] || { echo "!! 没找到 $PY：先 bash scripts/install.sh"; exit 1; }
[ -f "$DATA/app.db" ] || { echo "!! 没找到 $DATA/app.db：先 bash scripts/init_data.sh，或把现有库放进数据目录（README「迁移现有数据」）"; exit 1; }

alive(){ # PID 文件里的进程还活，且命令行是 gen run <DATA>
  local p; p=$(cat "$PIDF" 2>/dev/null) || return 1
  [[ $p =~ ^[0-9]+$ ]] && kill -0 "$p" 2>/dev/null || return 1
  local c; c=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null) || return 1
  [[ $c == *" -m gen run $DATA "* ]]
}

rotate(){ # server.log 超 20MB：.1 .2 .3 滚动，保留 3 份（copytruncate，运行中的服务仍持有同一 fd）
  local sz; sz=$(stat -c %s "$LOG" 2>/dev/null || echo 0)
  [ "$sz" -gt "$MAXLOG" ] || return 0
  rm -f "$LOG.$KEEP"
  for ((i=KEEP-1;i>=1;i--)); do [ -e "$LOG.$i" ] && mv "$LOG.$i" "$LOG.$((i+1))"; done
  cp "$LOG" "$LOG.1" && : > "$LOG"
  say "日志轮转（$sz 字节）"
}

if alive; then rotate; exit 0; fi

now=$(date +%s)
recent=$( { awk -v n="$now" -v w="$WINDOW" 'n-$1<w' "$HIST" 2>/dev/null || true; } | wc -l )
if [ "$recent" -ge "$MAXSTART" ]; then
  say "退避：最近 $((WINDOW/60)) 分钟已拉起 $recent 次（上限 $MAXSTART），暂停拉起；窗口过去后自动恢复，或排查后清空 $HIST 再手动 start.sh"
  exit 0
fi
awk -v n="$now" -v w="$WINDOW" 'n-$1<w' "$HIST" 2>/dev/null > "$HIST.tmp" || true; echo "$now" >> "$HIST.tmp"; mv "$HIST.tmp" "$HIST"
rotate

ARGS=(-m gen run "$DATA" --登录 --port "$PORT" --host "$HOST" --不开浏览器)
# 附加参数（bundle.conf 的 EXTRA_ARGS，如 --安全cookie；有意不加引号让多参数分词）
[ -n "${EXTRA_ARGS:-}" ] && ARGS+=(${EXTRA_ARGS})
if [ -n "${REAL:-}" ]; then
  if [ -f "$ENGINE/config.json" ] || [ -n "${ZHIPU_API_KEY:-}" ]; then
    ARGS+=(--real)
  else
    say "REAL=1 但既没有 $ENGINE/config.json 也没有 ZHIPU_API_KEY：按假模型起（要真模型：拷 scripts/config.example.json 为 engine/config.json 填好再重启）"
  fi
fi

cd "$ENGINE"
if [ -n "${FOREGROUND:-}" ]; then
  exec "$PY" "${ARGS[@]}"
fi
# 后台：关掉 3–255 号描述符再 setsid 起新会话（不经调用方的管道/锁；PID 文件记 setsid exec 后的同一 PID）
setsid bash -c 'for fd in $(seq 3 255); do eval "exec $fd>&-" 2>/dev/null; done; exec "$0" "$@"' \
  "$PY" "${ARGS[@]}" >> "$LOG" 2>&1 < /dev/null 8>&- 9>&- &
echo $! > "$PIDF"
say "已拉起 PID $(cat "$PIDF")（最近窗口内第 $((recent+1)) 次）http://$HOST:$PORT/"
