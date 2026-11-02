#!/usr/bin/env python
"""把指定账号（或全部账号）的界面语言设为 ja/zh。可重复执行。

    .venv/bin/python scripts/set_lang.py ja              # 全部账号 → ja
    .venv/bin/python scripts/set_lang.py ja 用户名        # 只改指定账号（可多个）
    .venv/bin/python scripts/set_lang.py zh 用户名

库默认 <bundle>/data/app.db，可 --db 路径 指定。lang 列不存在（旧版数据）时
先跑 project/scripts/migrate_lang.py。只改 account_user.lang，不动别的。
"""
import pathlib
import sqlite3
import sys

HERE = pathlib.Path(__file__).resolve().parent.parent
a = sys.argv[1:]
DB = HERE / "data" / "app.db"
if "--db" in a:
    i = a.index("--db")
    DB = pathlib.Path(a[i + 1])
    del a[i:i + 2]
if not a or a[0] not in ("ja", "zh"):
    sys.exit(__doc__)
lang, users = a[0], a[1:]
if not DB.is_file():
    sys.exit(f"!! 库不存在：{DB}")
con = sqlite3.connect(str(DB), isolation_level=None)
try:
    cols = {r[1] for r in con.execute("PRAGMA table_info(account_user)")}
    if "lang" not in cols:
        sys.exit(f"!! {DB} 没有 account_user.lang 列：先跑 project/scripts/migrate_lang.py")
    miss = []
    if users:
        ph = ",".join("?" * len(users))
        n = con.execute(f"UPDATE account_user SET lang=? WHERE username IN ({ph})",
                        (lang, *users)).rowcount
        miss = [u for u in users
                if not con.execute("select 1 from account_user where username=?", (u,)).fetchone()]
    else:
        n = con.execute("UPDATE account_user SET lang=?", (lang,)).rowcount
    print(f"已把 {n} 个账号的界面语言设为 {lang}"
          + (f"（库里没这个账号：{'、'.join(miss)}）" if miss else ""))
finally:
    con.close()
