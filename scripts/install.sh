#!/usr/bin/env bash
# 安装：建 .venv、装依赖（离线优先 wheels/，没有再联网 PyPI）、导入自检。
# 用法：在本目录（解压出的 kg_v4_bundle/ 顶层）跑：bash scripts/install.sh
# PYTHON=python3.13 可指定解释器（wheels 是按 CPython 3.13 / linux x86_64 打的，见 wheels/WHEELS.txt）。
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$HERE"
PY=${PYTHON:-python3}
"$PY" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] >= (3,10) else 1)' \
  || { echo "!! 需要 Python >= 3.10（wheels 按 CPython 3.13 / linux x86_64 打的，见 wheels/WHEELS.txt）"; exit 1; }
if [ ! -x .venv/bin/python ]; then
  echo "== 建 .venv（$PY）"
  "$PY" -m venv .venv
fi
if [ -n "$(ls wheels/*.whl 2>/dev/null)" ]; then
  echo "== 离线安装依赖（wheels/）"
  .venv/bin/python -m pip install --no-index --find-links wheels -r requirements.txt
else
  echo "== wheels/ 为空，改联网安装（PyPI）"
  .venv/bin/python -m pip install -r requirements.txt
fi
echo "== 导入自检"
.venv/bin/python - <<'XPY'
import flask, jinja2, yaml, requests, pypdf
from importlib.metadata import version
print("依赖自检 OK，Flask", version("flask"))
XPY
echo "装好了。下一步："
echo "  新机器：KG_PASSWORD='口令' bash scripts/init_data.sh   # 建库 + 建管理员（中文版账号默认中文）"
echo "  内容包：bash scripts/start.sh 起服务后再跑 bash scripts/load_python_content.sh（Python 科目+日文译文）"
echo "  迁移旧库：把现有 app.db（及 uploads/）放进 data/，见 README.md「迁移现有数据」"
echo "          （从旧中文包/更早版本升到中文版：先跑 project/scripts/migrate_lang.py 等，见 README）"
# deploy.sh 的 wait_ready/deploy/watch 依赖这些命令；缺了提前报，免得上线中途走回滚
for c in curl flock setsid sha256sum ss ps stat; do
  command -v "$c" >/dev/null 2>&1 || { echo "!! 缺命令 $c（装 iproute2/coreutils/curl 后重跑）"; exit 1; }
done
echo "依赖命令检查 OK（curl/flock/setsid/sha256sum/ss/ps/stat）"
