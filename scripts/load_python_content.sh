#!/usr/bin/env bash
# 导入「Python 编程」科目内容包（content/python_v1/，可选内容）：
#   建 Python 科目 → 知识图谱导入（知识点/条目/前置边/对照，走图谱管理 preview→confirm，先预检再写）
#   → 题库导入（POST /quiz/import，清空本科目题库重灌）→ 日文译文导入（project/scripts/import_content_ja.py，
#   先预检再 --apply）→ 中文课文 13 课（project/setup/import_lesson_rows.py，按条目/知识点挂接，所以在图谱之后）
#   → 课文译文 54 行（ja_lesson/lesson.tsv，要在课文之后）。最后按库里的行数自检：图谱 34/49/110/13、题库 99、
#   课文 13、挂接 110/34、译文 496（442+54）。
# 前提：install.sh、init_data.sh 已跑，服务已在跑（bash scripts/start.sh）。
# 可重复执行：图谱导入按编号「新增/更新」，题库重灌结果一致，译文 upsert；科目已存在则跳过建科目。
# 用法：KG_PASSWORD='管理员口令' bash scripts/load_python_content.sh
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[ -f "$HERE/bundle.conf" ] && . "$HERE/bundle.conf"
DATA=${DATA_DIR:-$HERE/data}
PORT=${PORT:-8119}
HOST=${HOST:-127.0.0.1}
BASE="http://$HOST:$PORT"
PY=$HERE/.venv/bin/python
C=$HERE/content/python_v1
DB=$DATA/app.db
say(){ echo "[load_python_content] $*"; }

for f in points.csv items.csv edges.csv contrasts.csv quiz_v2.txt; do
  [ -f "$C/$f" ] || { echo "!! 缺 $C/$f（内容包不全）"; exit 1; }
done
[ "$(ls "$C"/ja/*.tsv 2>/dev/null | wc -l)" -eq 4 ] || { echo "!! 缺 $C/ja/*.tsv（应 4 份译文）"; exit 1; }
[ -f "$C/lessons/lesson_rows.zh.json" ] && [ -f "$C/ja_lesson/lesson.tsv" ] || { echo "!! 缺课文 lessons/lesson_rows.zh.json 或译文 ja_lesson/lesson.tsv"; exit 1; }
[ -x "$PY" ] || { echo "!! 先跑 bash scripts/install.sh"; exit 1; }
[ -f "$DB" ] || { echo "!! 没找到 $DB：先 bash scripts/init_data.sh"; exit 1; }
[ -n "${KG_PASSWORD:-}" ] || { echo "!! 请用环境变量 KG_PASSWORD 给管理员口令（init_data.sh 用的那个）"; exit 1; }
curl -sf -o /dev/null "$BASE/" || { echo "!! 服务没在 $BASE 上跑：先 bash scripts/start.sh（端口不符时用 PORT=… 指定，别把口令发到别的服务）"; exit 1; }

JAR=$(mktemp); trap 'rm -f "$JAR"' EXIT
say "登录 ${KG_ADMIN:-admin}"
LG=$(curl -s -c "$JAR" -H 'Content-Type: application/json' \
  -d "{\"username\":\"${KG_ADMIN:-admin}\",\"password\":\"$KG_PASSWORD\"}" \
  -o /dev/null -w '%{http_code}' "$BASE/account/login")
[ "$LG" = 200 ] || { echo "!! 登录失败（HTTP $LG）：KG_PASSWORD 对吗？PORT=$PORT 指向的是不是你要灌内容的服务？（口令只发给自己的服务）"; exit 1; }
# 从响应 JSON 里按点路径取值；缺键/非 JSON 都报错退出，不会拿着空串往下走
jget(){ "$PY" -c 'import json,sys
v = json.load(sys.stdin)
for x in sys.argv[1].split("."):
    v = v[int(x)] if isinstance(v, list) else v[x]
print(v)' "$1"; }

get_sid(){ "$PY" - "$DB" <<'XPY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
r = con.execute("select id from subject_info where code='python'").fetchone()
print(r[0] if r else "", end="")
XPY
}
SID=$(get_sid)
if [ -z "$SID" ]; then
  say "建 Python 科目（通用，等级 入门,基础,进阶）"
  CG=$(curl -s -b "$JAR" -H 'Content-Type: application/json' \
    -d '{"subj_name":"Python 编程","subj_code":"python","subj_kind":"通用","subj_levels":"入门,基础,进阶","subj_intro":"Python 入门知识图谱与题库"}' \
    -o /dev/null -w '%{http_code}' "$BASE/subject/manage/save")
  [ "$CG" = 200 ] || { echo "!! 建科目失败（HTTP $CG）"; exit 1; }
  SID=$(get_sid)
  [ -n "$SID" ] || { echo "!! 建科目后查不到 code=python"; exit 1; }
else
  say "Python 科目已存在（id=$SID），跳过建科目"
fi
say "科目 id=$SID"
say "启用科目（新料科目默认 draft，不启用学生切不进来——验证时发现的）"
CE=$(curl -s -b "$JAR" -H 'Content-Type: application/json' -d "{\"subj_id\":\"$SID\"}" \
  -o /dev/null -w '%{http_code}' "$BASE/subject/manage/enable")
[ "$CE" = 200 ] || { echo "!! 启用科目失败（HTTP $CE）"; exit 1; }

imp(){ # imp <中文类型> <文件>：图谱管理 preview（先预检，一行不写）→ confirm（写入）
  local kind=$1 file=$2 pv pf ok
  pv=$(curl -s -b "$JAR" -F "imp_kind=$kind" -F "imp_upload=@$C/$file" "$BASE/kg/manage/import/preview?subject=$SID")
  ok=$(printf '%s' "$pv" | jget state.imp_ok) || { echo "!! $file 预检响应不对：$pv"; exit 1; }
  [ "$ok" = "1" ] || { echo "!! $file 预检没过：$(printf '%s' "$pv" | jget state.imp_head 2>/dev/null || echo "$pv")"; exit 1; }
  pf=$(printf '%s' "$pv" | jget form.imp_file)
  say "$file 预检通过（$kind）→ 确认导入 $pf"
  CF=$(curl -s -b "$JAR" -H 'Content-Type: application/json' \
    -d "{\"imp_kind\":\"$kind\",\"imp_file\":\"$pf\"}" \
    -o /dev/null -w '%{http_code}' "$BASE/kg/manage/import/confirm?subject=$SID")
  [ "$CF" = 200 ] || { echo "!! $kind 确认导入失败（HTTP $CF）"; exit 1; }
}
imp 知识点 points.csv
imp 条目 items.csv
imp 前置边 edges.csv
imp 对照 contrasts.csv

say "导入题库 quiz_v2.txt（清空本科目重灌，99 题）"
QPRE=$(grep -c '^python\.' "$C/quiz_v2.txt")
[ "$QPRE" -eq 99 ] || { echo "!! quiz_v2.txt 预检不过：题号行 ${QPRE} 行，应 99（导入是清空重灌，文件不对会毁题库，停下）"; exit 1; }
QZ=$(curl -s -b "$JAR" -F "file=@$C/quiz_v2.txt" "$BASE/quiz/import?subject=$SID")
echo "$QZ" | grep -q '"ok": *[1]' || { echo "!! 题库导入失败：$QZ"; exit 1; }
say "题库：$(printf '%s' "$QZ" | head -c 160)"

say "日文译文预检"
"$PY" "$HERE/project/scripts/import_content_ja.py" --db "$DB" --dir "$C/ja"
say "日文译文写入"
"$PY" "$HERE/project/scripts/import_content_ja.py" --db "$DB" --dir "$C/ja" --apply

say "导入中文课文 13 课（按系列重灌，可重复执行）"
# import_lesson_rows.py 按当前目录找引擎（gen/project.py），所以要在 engine/ 里跑；有拒收则退出码非 0、在这里停下
( cd "$HERE/engine" && "$PY" "$HERE/project/setup/import_lesson_rows.py" "$DATA" "$C/lessons/lesson_rows.zh.json" \
    --subject "$SID" --series-code python.core_v1 --series-name 'Python 从零入门' \
    --intro "$(cat "$C/lessons/series_intro.zh.txt")" --yes )
say "课文译文预检"
"$PY" "$HERE/project/scripts/import_content_ja.py" --db "$DB" --dir "$C/ja_lesson"
say "课文译文写入"
"$PY" "$HERE/project/scripts/import_content_ja.py" --db "$DB" --dir "$C/ja_lesson" --apply

say "自检行数（期望 图 34/49/110/13、题 99、课文 13、挂接 110/34、译文 496）"
"$PY" - "$DB" "$SID" <<'XPY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1]); sid = sys.argv[2]
def n(sql):
    return con.execute(sql, (sid,)).fetchone()[0]
got = [n("select count(*) from kg_point where subject_id=?"),
       n("select count(*) from kg_edge where subject_id=?"),
       n("select count(*) from kg_item where subject_id=?"),
       n("select count(*) from kg_contrast where subject_id=?"),
       n("select count(*) from quiz_question where subject_id=?"),
       n("select count(*) from lesson_text where subject_id=?"),
       n("select count(*) from lesson_item_link where subject_id=?"),
       n("select count(*) from lesson_point_link where subject_id=?"),
       con.execute("select count(*) from subject_content_translation where lang='ja'").fetchone()[0]]
exp = [34, 49, 110, 13, 99, 13, 110, 34, 496]
print("实际:", "/".join(map(str, got)))
if got != exp:
    print("!! 行数和期望不符：期望 " + "/".join(map(str, exp)))
    raise SystemExit(1)
if not con.execute("select intro from lesson_series where code='python.core_v1'").fetchone()[0]:
    print("!! 系列 python.core_v1 的中文简介为空")
    raise SystemExit(1)
print("内容包导入完成")
XPY
