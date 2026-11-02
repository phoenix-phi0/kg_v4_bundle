#!/usr/bin/env bash
# 新机器初始化数据目录（默认 <bundle>/data）：
#   - 没有 app.db 时按 project/entities 建空库；
#   - 建首个教师账号（口令走环境变量 KG_PASSWORD，不进命令行）。
# 用法：KG_PASSWORD='口令' bash scripts/init_data.sh [数据目录]
#       KG_ADMIN=名字 指定管理员用户名（默认 admin）。
# 注意：带旧库上线不要用本脚本建库——直接把现有 app.db（及 uploads/）拷进数据目录，
#       gen run 启动时会做增量迁移（见 README「迁移现有数据」）。
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[ -f "$HERE/bundle.conf" ] && . "$HERE/bundle.conf"
# 本包（中文版）建账号时的默认界面语言。只影响这里建的账号；改已有账号用 scripts/set_lang.py，
# 用户也可在页面顶栏随时切。新注册用户的默认语言是服务默认值 zh（没改服务代码，见 README「界面语言」）。
DEFAULT_LANG=${DEFAULT_LANG:-zh}
DATA=${1:-$HERE/data}
mkdir -p "$DATA"
if [ ! -x "$HERE/.venv/bin/python" ]; then echo "!! 先跑 bash scripts/install.sh"; exit 1; fi
# 引擎目录模型：数据目录 = 项目源 + 库（gen run 在同一目录读 entities/、写 app.db 和 web/）。
# 全新机器的数据目录是空的：先把 project/ 铺进去，再建库。
if [ -z "$(ls "$DATA/entities"/*.entity 2>/dev/null)" ]; then
  echo "== 数据目录是空的：先把 project/ 铺进 $DATA（数据目录=项目源+库）"
  cp -a "$HERE/project/." "$DATA/"
fi
if [ ! -f "$DATA/app.db" ]; then
  echo "== 建空库 $DATA/app.db（按 project/entities）"
  ( cd "$HERE/engine" && "$HERE/.venv/bin/python" -c \
    'import sys; from pathlib import Path; sys.path.insert(0, "."); from gen.project import ensure_db; print(ensure_db(Path(sys.argv[1]).resolve()))' "$DATA" )
else
  echo "== $DATA/app.db 已存在，不重建"
fi
if [ -z "${KG_PASSWORD:-}" ]; then
  echo "!! 没给 KG_PASSWORD：跳过建账号。之后：KG_PASSWORD='口令' .venv/bin/python scripts/add_teacher.py 管理员名"
else
  U=${KG_ADMIN:-admin}
  KG_PASSWORD="$KG_PASSWORD" "$HERE/.venv/bin/python" "$HERE/scripts/add_teacher.py" "$U" 管理员 --data "$DATA" --lang "$DEFAULT_LANG"
fi
echo "初始化完成（账号界面语言：$DEFAULT_LANG）。启动：bash scripts/start.sh（默认 127.0.0.1:8119）"
echo "可选：服务起来后 bash scripts/load_python_content.sh 导入 Python 科目内容包（图谱+题库+日文译文）"
