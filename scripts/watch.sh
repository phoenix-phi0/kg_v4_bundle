#!/usr/bin/env bash
# 常驻看门狗：每 KG_INTERVAL（默认 60）秒跑一次 start.sh；flock 单实例。
# 起法（setsid -f 自己 fork、父进程立即返回；不要再加 &）：
#   cd <bundle>/run 2>/dev/null || mkdir -p <bundle>/run && cd <bundle>/run
#   for fd in $(seq 3 255); do eval "exec $fd>&-" 2>/dev/null; done
#   exec setsid -f nohup ../scripts/watch.sh >> watch.log 2>&1 < /dev/null
# （deploy.sh 会自动起/停看门狗，一般不用手动。）
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[ -f "$HERE/bundle.conf" ] && . "$HERE/bundle.conf"
RUN=${RUN_DIR:-$HERE/run}
mkdir -p "$RUN"
exec 8>"$RUN/watch.lock"; flock -n 8 || exit 0
D=$(dirname "$(readlink -f "$0")")
while :; do bash "$D/start.sh" >> "$RUN/watch.log" 2>&1 < /dev/null; sleep "${KG_INTERVAL:-60}"; done
