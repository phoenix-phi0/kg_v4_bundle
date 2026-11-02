#!/usr/bin/env python
"""建教师/学生账号（不灌内容）。等同 app/setup/init_data.py 的 make_teacher。
口令从环境变量读，不进命令行历史：
    KG_PASSWORD='口令' .venv/bin/python scripts/add_teacher.py 用户名 [显示名] [--role student] [--lang ja]
数据目录默认 <bundle>/data，可 --data 路径 指定。账号已存在则不动；库不存在先按 project/entities 建库。
界面语言 --lang ja|zh（默认取环境变量 DEFAULT_LANG，再默认 zh）；库里没有 lang 列（旧版数据）时
账号按服务默认语言（zh）建并提示，之后可用 scripts/set_lang.py 改。"""
import os, sqlite3, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent      # bundle 顶层
sys.path.insert(0, str(HERE / "engine"))
from gen.project import ensure_db          # noqa: E402
from tools.auth import hash_password       # noqa: E402

argv = sys.argv[1:]
data = HERE / "data"
if "--data" in argv:
    i = argv.index("--data")
    data = Path(argv[i + 1])
    del argv[i:i + 2]
role = "teacher"
if "--role" in argv:
    i = argv.index("--role")
    if i + 1 < len(argv):
        role = argv[i + 1]
        del argv[i:i + 2]
lang = os.environ.get("DEFAULT_LANG", "zh")
if "--lang" in argv:
    i = argv.index("--lang")
    if i + 1 < len(argv):
        lang = argv[i + 1]
        del argv[i:i + 2]
if lang not in ("zh", "ja"):
    sys.exit("!! --lang 只能是 zh 或 ja")
args = [a for a in argv if not a.startswith("--")]
if not args:
    sys.exit(__doc__)
user = args[0]
display = args[1] if len(args) > 1 else args[0]
pw = os.environ.get("KG_PASSWORD", "")
if not pw:
    sys.exit("!! 请用环境变量 KG_PASSWORD 给口令（不写进命令行）")
ensure_db(data.resolve())
con = sqlite3.connect(data / "app.db")
try:
    if con.execute("select 1 from account_user where username=?", (user,)).fetchone():
        print(f"账号 {user} 已存在，没动")
        sys.exit(0)
    cols = {r[1] for r in con.execute("PRAGMA table_info(account_user)")}
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    if "lang" in cols:
        con.execute("INSERT INTO account_user(username,password_hash,display_name,role,disabled,created_at,lang) "
                    "VALUES(?,?,?,?,0,?,?)",
                    (user, hash_password(pw), display, role, ts, lang))
        note = f"lang={lang}"
    else:
        if lang != "zh":
            print(f"注意：库里没有 lang 列（旧版数据），先跑 project/scripts/migrate_lang.py；"
                  f"账号先按服务默认语言（zh）建，之后可用 scripts/set_lang.py {lang} {user}")
        con.execute("INSERT INTO account_user(username,password_hash,display_name,role,disabled,created_at) "
                    "VALUES(?,?,?,?,0,?)",
                    (user, hash_password(pw), display, role, ts))
        note = "lang=服务默认(zh)"
    con.commit()
    print(f"建了{role}账号 {user}（{note}，{data/'app.db'}）")
finally:
    con.close()
