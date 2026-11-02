#!/usr/bin/env bash
# kg_v4 标准上线脚本（bundle 版，改自正式服务的 deploy.sh）：用新版 project/ 目录同步数据目录。
#
#   bash scripts/deploy.sh [--dry-run] <新版project目录> [标签]
#
# 流程：停看门狗（按 watch.lock 找进程组，不用 pgrep -f）→ stop.sh → 数据目录整份备份到
#       backups/kg_v4_<时间>_before_<标签>（.auth_secret 只拷不读，按大小/权限/修改时间核对）
#       + diff/cmp 校验 → 同步约定目录（contracts entities queries routes scripts services ui
#       setup i18n + plan/top.zs；只覆盖/新增，不删数据目录里多出的文件；旧数据目录没有 i18n/
#       时 mkdir 补上——K180 起界面词表在这里，缺了顶栏不出现语言切换）→ start.sh → GET / 200
#       → 起看门狗（setsid -f：自己 fork 父进程立即返回；标准输入输出全部重定向到文件，
#         关掉 3 号以上描述符，不经 tee/管道，脚本立即返回）→ 打印停服秒数、备份路径。
# --dry-run：只核对源目录、列出要同步的差异、找到的看门狗/服务进程；不停服、不备份、不同步。
# 停服之后任何一步失败：先从本次备份还原约定目录，再拉起服务（确认 GET / 200 且 server.pid
#       就是监听端口的进程）之后才起看门狗，退出码 1。
#
# 可配置：环境变量 > bundle.conf > 默认。DATA_DIR RUN_DIR PORT BACKUPS
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[ -f "$HERE/bundle.conf" ] && . "$HERE/bundle.conf"
RUN=${RUN_DIR:-$HERE/run}
D=${DATA_DIR:-$HERE/data}
PORT=${PORT:-8119}
BK=${BACKUPS:-$HERE/backups}
DIRS="contracts entities queries routes scripts services ui setup i18n"   # i18n：K180 起的界面词表（旧数据目录没有，同步时 mkdir）
FILES="plan/top.zs"
mkdir -p "$RUN"

DRY=0
[ "${1:-}" = "--dry-run" ] && { DRY=1; shift; }
SRC=${1:-}; [ -n "$SRC" ] || { echo "用法：bash scripts/deploy.sh [--dry-run] <新版project目录> [标签]"; exit 2; }
SRC=$(cd "$SRC" && pwd) || { echo "!! 源目录不存在：$SRC"; exit 2; }
for d in $DIRS; do [ -d "$SRC/$d" ] || { echo "!! 源目录里没有 $d：传的应是新版包的 project/ 目录"; exit 2; }; done
for f in $FILES; do [ -f "$SRC/$f" ] || { echo "!! 源目录里没有 $f"; exit 2; }; done
[ -x "$HERE/.venv/bin/python" ] || { echo "!! 先 bash scripts/install.sh"; exit 1; }
[ -f "$D/app.db" ] || { echo "!! 数据目录 $D 没有 app.db（先 bash scripts/init_data.sh 或迁移现有库）"; exit 1; }
TAG=${2:-$(date +%Y%m%d-%H%M%S)}
[[ $TAG =~ ^[A-Za-z0-9._-]+$ ]] || { echo "!! 标签只能是字母数字和 . _ -：$TAG"; exit 2; }
TS=$(date +%Y%m%d-%H%M%S); B=$BK/kg_v4_${TS}_before_${TAG}
say(){ echo "[$(date '+%T')] $*"; }
STAGE=pre      # pre：还没停服；stopped：已停服、正式目录没动；syncing：开始改正式目录；up：已起服
die(){
  echo "!! $*"
  case $STAGE in
    stopped|syncing)
      if [ $STAGE = syncing ]; then
        echo "!! 从备份 $B 还原约定目录"
        for d in $DIRS; do rm -rf "${D:?}/$d" && cp -a "$B/$d" "$D/$d" || echo "!! 还原 $d 失败"; done
        for f in $FILES; do cp -a "$B/$f" "$D/$f" || echo "!! 还原 $f 失败"; done
      fi
      echo "!! 拉起原服务（确认就绪之后才起看门狗，避免两者同一秒各拉一个）"
      start_server
      if wait_ready 120; then say "恢复：server.pid $(cat "$RUN/server.pid") 就是监听 $PORT 的进程，GET / 200"
      else
        echo "!! 恢复：服务 120 秒内没就绪（server.pid=$(cat "$RUN/server.pid" 2>/dev/null)，监听 $PORT 的是 $(port_pid || echo 没有进程)）；看 $RUN/server.log、watch.log"
        tail -3 "$RUN/watch.log" 2>/dev/null | grep -q '退避' && echo "!! watch.log 里是「退避」：start.sh 的 10 分钟 3 次拉起上限被触发（部署+恢复连续拉起会撞上），不是服务坏；窗口过去后看门狗自动恢复，不要手动清 starts.hist"
      fi
      start_watch || echo "!! 恢复：看门狗没起来" ;;
  esac
  exit 1
}
# 关掉 3–255 号描述符再跑：否则服务会继承 deploy.lock（7 号）和调用方的管道
start_server(){ ( for fd in $(seq 3 255); do eval "exec $fd>&-" 2>/dev/null; done; exec bash "$HERE/scripts/start.sh" ); }
# 子 shell 里关描述符、全部重定向到文件，再 exec setsid -f：fork 出新会话后父进程立即退出，
# 不留任何握着调用方管道的进程
start_watch(){
  ( cd "$RUN" || exit 1
    for fd in $(seq 3 255); do eval "exec $fd>&-" 2>/dev/null; done
    exec setsid -f nohup "$HERE/scripts/watch.sh" >> "$RUN/watch.log" 2>&1 < /dev/null )
  for i in $(seq 1 10); do lock_free || return 0; sleep 0.3; done
  return 1
}
# 看门狗 = 握着 watch.lock 的进程（watch.sh 本身和它正在 sleep/跑 start.sh 的子进程）。
# 不用 pgrep -f（会匹配到自己）；按 /proc/*/fd 找，返回它们的进程组号（去重，排除服务和本脚本的组）。
watch_pgids(){
  local lock p fd pg sp me
  lock=$(readlink -f "$RUN/watch.lock"); sp=$(cat "$RUN/server.pid" 2>/dev/null); me=$(ps -o pgid= $$ | tr -d ' ')
  for p in /proc/[0-9]*; do
    for fd in "$p"/fd/*; do
      [ "$(readlink "$fd" 2>/dev/null)" = "$lock" ] || continue
      pg=$(ps -o pgid= "${p#/proc/}" 2>/dev/null | tr -d ' ')
      [ -n "$pg" ] && [ "$pg" != "$sp" ] && [ "$pg" != "$me" ] && echo "$pg"
      break
    done
  done | sort -u
}
lock_free(){ flock -n "$RUN/watch.lock" -c true; }
# 监听 $PORT 的进程号（ss 拿不到就是空串）
port_pid(){ ss -ltnp "sport = :$PORT" 2>/dev/null | grep -o 'pid=[0-9]\+' | head -1 | cut -d= -f2; }
# 服务就绪 = server.pid 里的进程活着、就是监听 $PORT 的进程、GET / 200。
# 只看 GET 200 不行：孤儿服务占着端口时新服务起不来，200 是孤儿答的（正式部署踩过）。参数=轮询次数（0.5 秒一次）。
wait_ready(){
  local i p c
  for i in $(seq 1 "${1:-120}"); do
    p=$(cat "$RUN/server.pid" 2>/dev/null)
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null && [ "$(port_pid)" = "$p" ]; then
      c=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/" 2>/dev/null)
      [ "$c" = 200 ] && return 0
    fi
    sleep 0.5
  done
  return 1
}

# 单实例：两个人同时上线会互相停对方起的服务
exec 7>"$RUN/deploy.lock"; flock -n 7 || die "另一个 deploy.sh 正在跑（$RUN/deploy.lock）"

echo "== 要同步的差异（源 $SRC vs 数据目录 $D）"
n=0
for d in $DIRS; do
  while IFS= read -r l; do echo "  $l"; n=$((n+1)); done < <(diff -rq "$SRC/$d" "$D/$d" 2>&1 | grep -v "^Only in $D/")
done
for f in $FILES; do cmp -s "$SRC/$f" "$D/$f" || { echo "  $f 不同"; n=$((n+1)); }; done
echo "  共 $n 处"
extra=$(for d in $DIRS; do diff -rq "$SRC/$d" "$D/$d" 2>&1 | grep "^Only in $D/"; done)
[ -n "$extra" ] && { echo "  （数据目录里有、源里没有的文件，不删，只列出）"; echo "$extra" | sed 's/^/    /'; }

WP=$(watch_pgids | tr '\n' ' '); SP=$(cat "$RUN/server.pid" 2>/dev/null)
say "看门狗进程组：${WP:-（没找到）}；服务 PID：${SP:-（没有）}；监听 $PORT：$(port_pid || echo 无)"
if [ $DRY = 1 ]; then
  echo "== --dry-run：不停服、不备份、不同步。真跑时备份到 $B"
  exit 0
fi

# 1 停看门狗（进程组）
for g in $WP; do kill -TERM -- "-$g" 2>/dev/null; done
for i in $(seq 1 20); do lock_free && break; sleep 0.5; done
lock_free && say "看门狗已停（watch.lock 可拿到）" || die "watch.lock 仍被占，看门狗没停，未停服"

# 2 停服
T0=$(date +%s.%N); say "停服开始"
bash "$HERE/scripts/stop.sh"
if [ -n "$SP" ] && kill -0 "$SP" 2>/dev/null; then
  start_watch; die "服务 $SP 没停（服务仍在原样运行，已重新起看门狗）"
fi
STAGE=stopped
Q=$(port_pid); [ -z "$Q" ] || die "停服后端口 $PORT 仍被 PID $Q 占着（不是本服务，先处理它；服务和看门狗即将拉回）"

# 3 完整备份（cp -a；.auth_secret 只拷不读，不进 diff，按 大小/权限/修改时间 核对）
mkdir -p "$BK"; cp -a "$D" "$B" || die "备份失败（数据目录没动）"
(cd "$D" && sha256sum app.db) > "$B.app.db.sha256"
diff -rq --exclude=.auth_secret "$D" "$B" > /dev/null && say "备份与原目录一致（diff -rq，除 .auth_secret）" || die "备份不一致 $B（数据目录没动）"
cmp -s "$D/app.db" "$B/app.db" && say "app.db 字节一致" || die "app.db 备份不一致（数据目录没动）"
if [ -e "$D/.auth_secret" ]; then
  [ "$(stat -c '%s %a %Y' "$D/.auth_secret")" = "$(stat -c '%s %a %Y' "$B/.auth_secret")" ] \
    && say ".auth_secret 已拷（大小/权限/修改时间一致，未读内容）" || die ".auth_secret 备份不一致（数据目录没动）"
fi

# 4 同步约定目录（只覆盖/新增，不删数据目录里多出的文件）
STAGE=syncing
for d in $DIRS; do mkdir -p "$D/$d" && cp -a "$SRC/$d/." "$D/$d/" || die "同步 $d 失败"; done
for f in $FILES; do cp -a "$SRC/$f" "$D/$f" || die "同步 $f 失败"; done
bad=0
for d in $DIRS; do diff -rq "$SRC/$d" "$D/$d" | grep -v "^Only in $D/" && bad=1; done
for f in $FILES; do cmp -s "$SRC/$f" "$D/$f" || { echo "  $f 不一致"; bad=1; }; done
[ $bad = 0 ] && say "同步后逐目录与源一致" || die "同步不一致"

# 5 起服
STAGE=up
LOG0=$(stat -c %s "$RUN/server.log" 2>/dev/null || echo 0)
start_server
P=$(cat "$RUN/server.pid" 2>/dev/null); say "新 PID $P"
if wait_ready 120; then c=200
else c=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/" 2>/dev/null); fi
T1=$(date +%s.%N)
DOWN=$(awk -v a="$T0" -v b="$T1" 'BEGIN{printf "%.1f", b-a}')
RC=0
if [ "$c" = 200 ]; then say "GET / 200（$P 就是监听 $PORT 的进程）"
else
  Q=$(port_pid)
  if [ -n "$Q" ] && [ "$Q" != "$P" ]; then echo "!! 端口 $PORT 被 PID $Q 占着（不是新服务 $P）：GET $c 不可信，新服务可能没起来"
  elif ! kill -0 "$P" 2>/dev/null; then echo "!! 新服务 $P 已退出（看 server.log；回滚：从 $B 拷回约定目录后 bash scripts/start.sh）"
  else echo "!! 新版本 120 秒内 GET / 不是 200（看 server.log；回滚：从 $B 拷回约定目录后 bash scripts/start.sh）"; fi
  RC=1
fi

# 6 起看门狗（新版本没起来也照样起：它每 60 秒重试 start.sh，有退避）
if start_watch; then say "看门狗已在跑（watch.lock 被占用），进程组 $(watch_pgids | tr '\n' ' ')"
else echo "!! watch.lock 空闲，看门狗没起来（手动起法见 scripts/watch.sh 头注）"; RC=1; fi

# 7 启动日志里的警告
NEW=$(tail -c +$((LOG0+1)) "$RUN/server.log" 2>/dev/null)
echo "== 本次启动日志：[迁移警告] $(grep -c '迁移警告' <<<"$NEW") 行，Traceback $(grep -c 'Traceback' <<<"$NEW") 处"
grep -E '迁移|Traceback' <<<"$NEW" | head -5 | sed 's/^/  /'

echo "== 结果：源 $SRC，GET / $c，停服秒数 $DOWN，备份 $B"
exit $RC
