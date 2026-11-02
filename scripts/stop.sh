#!/usr/bin/env bash
# 按 PID 文件停服务（进程组 TERM，kill -0 确认；10 秒没退则 KILL）。
# 注意：看门狗（watch.sh）在跑的话 ≤KG_INTERVAL 秒会拉回来；要真停先停看门狗（见 README）。
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[ -f "$HERE/bundle.conf" ] && . "$HERE/bundle.conf"
RUN=${RUN_DIR:-$HERE/run}
PIDF=$RUN/server.pid
p=$(cat "$PIDF" 2>/dev/null)
[[ $p =~ ^[0-9]+$ ]] || { echo "没有有效 PID 文件"; exit 0; }
kill -0 "$p" 2>/dev/null || { echo "进程 $p 已不在"; rm -f "$PIDF"; exit 0; }
kill -TERM -- "-$p" 2>/dev/null || kill -TERM "$p" 2>/dev/null || true
for i in $(seq 1 20); do kill -0 "$p" 2>/dev/null || { echo "已停止 $p"; rm -f "$PIDF"; exit 0; }; sleep 0.5; done
kill -KILL -- "-$p" 2>/dev/null || kill -KILL "$p" 2>/dev/null || true
sleep 1
kill -0 "$p" 2>/dev/null && { echo "!! 仍未退出 $p"; exit 1; } || { echo "已强制停止 $p"; rm -f "$PIDF"; }
