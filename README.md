# kg_v4 独立上线包（中文版）

自包含文件夹：拿到一台新机器，解压 → 装依赖 → 初始化（或迁移旧库）→ 启动，不依赖开发机上的任何东西。
默认假模型（回复带 [模拟回复]），页面全部可演示；配好密钥可切真模型。
**中文版**：界面/后端消息词表 `project/i18n/ja.tsv`（顶栏「中文 / 日本語」随时切换，跟随账号）；`init_data.sh` 建的账号默认中文（`DEFAULT_LANG=zh`）；`content/` 带 Python 科目内容包（知识图谱+题库+课文 13 课+496 条日文译文）。
引擎基线、打包时间、Python 版本见 `VERSION`；打包脚本在引擎仓库 `scripts/build_bundle.sh`，可重复打包。

## 目录
| 路径 | 内容 |
|---|---|
| `engine/` | 引擎最小运行集（`python -m gen run` 实际 import/读取的，经追踪分析验证）：`gen/`（不含 out/ 与编辑器 .pyw）、`tools/` 31 个运行时模块（含 cbatch/zcode_tool：--real 的 cli:claude/cli:zcode 后端懒加载，缺了请求直接断）、`templates/`（db+frontend 的 .j2）、`gen/templates/`、`verbs/` 全量（动词包懒加载，裁不动）、`app2/assets/vue.global.prod.js`（本地 Vue）、`models.json`（模型档位说明，无密钥） |
| `project/` | kg_v4 项目源：contracts entities queries routes scripts services setup ui **i18n**（ja.tsv 界面/消息词表 720 条） plan/top.zs req.md README.md。**不含** app.db、uploads、web 生成物；plan/ 只带 top.zs（设计 .md 不随包） |
| `content/` | 可选内容包 `python_v1/`：Python 科目知识图谱与题库源文件（points/items/edges/contrasts/quiz_v2）+ 中文课文 13 课 + 日文译文 496 条（`ja/` 442、`ja_lesson/` 课文 54）。不导入不影响其它功能；导入用 `scripts/load_python_content.sh` |
| `scripts/` | `install.sh`（装依赖）· `init_data.sh`（建库+建管理员，语言 DEFAULT_LANG=zh）· `add_teacher.py`（建账号，--lang）· `set_lang.py`（改账号界面语言 ja/zh）· `load_python_content.sh`（导入 Python 内容包）· `start.sh`（幂等启动）· `stop.sh` · `watch.sh`（看门狗）· `deploy.sh`（上线，同步清单含 i18n/）· `config.example.json`（真模型样板）· `bundle.conf.example`（配置样板） |
| `wheels/` | 离线依赖 wheel，平台见 `WHEELS.txt` |
| `requirements.txt` | 直接依赖，精确版本（传递依赖由 pip 按 wheels/ 解出） |
| `data/` | 数据目录（初始化或迁移后出现）：`app.db`、`uploads/`、`web/`（每次启动重新编译的生成物）、`.auth_secret`（首次启动自动生成，登录签名密钥） |
| `run/` | 运行时产生：server.pid、server.log（超 20MB 自动滚动留 3 份）、watch.log、starts.hist、各锁文件 |
| `backups/` | deploy.sh 每次上线的完整备份 |

**不会打进包的东西**：config.json、.auth_secret、任何密钥、*.db、uploads、web 生成物、日志。

## 要求
- Linux x86_64，Python >= 3.10。wheels/ 按 CPython 3.13 / manylinux 打的（markupsafe、pyyaml、charset_normalizer 是二进制 wheel，其余纯 Python）。换平台或 Python 版本：在联网机上 `pip download -r requirements.txt -d wheels/` 重打 wheels/。
- wheels/ 齐全时安装全程不用联网；`wheels/` 为空则 install.sh 退回从 PyPI 装。

## 新机器上线（完整步骤）
### 1. 安装
    tar xzf kg_v4_bundle.tar.gz && cd kg_v4_bundle
    bash scripts/install.sh          # 建 .venv，离线优先装依赖，导入自检

### 2. 数据（二选一）
**全新机器**（空库）：
    KG_PASSWORD='管理员口令' bash scripts/init_data.sh     # 建空库 + 建管理员（用户名默认 admin，KG_ADMIN=名字 可改；账号界面语言=DEFAULT_LANG，默认 zh）
    bash scripts/start.sh                                  # 起服务（内容包导入要走接口）
    KG_PASSWORD='管理员口令' bash scripts/load_python_content.sh   # 可选：导入 Python 科目内容包（建科目→图谱→题库→日文译文，先预检再写，可重复执行）
    KG_PASSWORD='口令' .venv/bin/python scripts/add_teacher.py 学生名 --role student   # 需要时再建学生/教师（--lang 可指定界面语言）

**迁移现有数据**：停掉旧服务 → 把旧数据目录里的 `app.db`（及 `app.db-wal`/`-shm` 若有）拷进 `data/` → 要上传文件就拷 `uploads/` → 想沿用登录会话再拷 `.auth_secret`（不拷则所有人重新登录）→ 启动时自动做增量迁移（加列），迁移不了的结构变化看启动日志的「迁移警告」。

**从旧版（K178 中文包或更早的 kg_v4）升到本中文版**，先备份数据目录，再在启动前跑两步迁移（脚本可重复执行，已迁过会自己跳过）：
    cp -a data backups/data_before_ja_$(date +%F_%H%M)                                            # 备份（整份拷，含 app.db/uploads）
    .venv/bin/python project/scripts/migrate_lang.py data/app.db                                  # account_user 加 lang 列
    .venv/bin/python project/scripts/migrate_subject_content_translation.py --db data/app.db      # 建译文表 subject_content_translation
启动后导入日文译文（upsert，可重复；已导入过就只是覆盖同样的值）：
    .venv/bin/python project/scripts/import_content_ja.py --db data/app.db --dir content/python_v1/ja           # 先预检
    .venv/bin/python project/scripts/import_content_ja.py --db data/app.db --dir content/python_v1/ja --apply   # 再写入
再跑一次 `bash scripts/deploy.sh <新版project目录> 标签` 同步代码（旧数据目录缺 i18n/ 会自动补上）。旧账号界面语言默认 zh：批量切日语用 `.venv/bin/python scripts/set_lang.py ja`（单个：`set_lang.py ja 用户名`）。旧库里没有 Python 科目的话，照上面「全新机器」跑 `load_python_content.sh`。

### 3. 配置（可选）
默认假模型。要真模型：`cp scripts/config.example.json engine/config.json` 填 `api_key`（字段说明在样板文件里），然后 `REAL=1 bash scripts/start.sh`；或用环境变量 `ZHIPU_API_KEY / ZHIPU_MODEL / ZHIPU_BASE_URL`（不用建文件）。
注意档位：引擎 models.json 里 快/平衡/强 默认走本机 claude CLI（cli:claude，需 PATH 上有 claude，start.sh 已把 ~/.local/bin 加进 PATH），没有 claude 时自动落到 api:zhipu（需要上面配好的 key）；纯 zhipu 用法在 config.json 写 `model` 即可。
界面语言：`DEFAULT_LANG`（默认 zh，环境变量或 bundle.conf 可改）只影响 `init_data.sh` 建的账号；改已有账号用 `scripts/set_lang.py`；用户自己在页面顶栏「中文 / 日本語」随时切换。**新注册用户默认仍是中文**——本包不改服务代码与默认值；想让新注册也默认日语，可在注册后执行一次 `.venv/bin/python scripts/set_lang.py ja 新用户名`（文档说明的做法）。
端口、数据目录等：拷 `scripts/bundle.conf.example` 到顶层改名 `bundle.conf` 改注释掉的行，或用同名环境变量（环境变量优先）。

### 4. 启动 / 停止
    bash scripts/start.sh                 # 幂等后台启动，默认 127.0.0.1:8119，日志 run/server.log
    FOREGROUND=1 bash scripts/start.sh    # 前台跑（调试用，Ctrl+C 停）
    bash scripts/stop.sh                  # 停（进程组 TERM，kill -0 确认，10 秒不退 KILL）

### 5. 看门狗（掉线自动拉起，可选但建议）
    mkdir -p run && cd run
    for fd in $(seq 3 255); do eval "exec $fd>&-" 2>/dev/null; done
    exec setsid -f nohup ../scripts/watch.sh >> watch.log 2>&1 < /dev/null
每 KG_INTERVAL（默认 60）秒跑一次 start.sh，flock 单实例；start.sh 自带退避（10 分钟内最多拉起 3 次，防崩溃循环，watch.log 写「退避」）。
**要真停服务**：先停看门狗——按 `run/watch.lock` 找握着它的进程（`ls -l /proc/*/fd/* 2>/dev/null | grep watch.lock`）kill 其进程组，再 `bash scripts/stop.sh`；只 stop.sh 会被看门狗拉回来。

### 6. 更新上线
新版包在开发机用 `bash scripts/build_bundle.sh` 打出后，拷到目标机解压，然后：
    bash scripts/deploy.sh --dry-run /解压路径/kg_v4_bundle/project 某标签    # 先看差异，不停服
    bash scripts/deploy.sh /解压路径/kg_v4_bundle/project 某标签
流程：停看门狗 → 停服 → 数据目录整份备份到 backups/（校验后才开始改）→ 同步 contracts entities queries routes scripts services ui setup + plan/top.zs（只覆盖/新增，数据目录多出的文件只列出不删）→ 起服等 GET / 200（且确认 server.pid 就是监听端口的进程）→ 起看门狗 → 打印迁移警告/Traceback 数、停服秒数、备份路径。停服后任何一步失败自动从本次备份还原并拉回原服务。

### 7. 备份 / 回滚
- 手工备份：`bash scripts/stop.sh` 后 `cp -a data backups/data_$(date +%F_%H%M)`；热备可用 sqlite backup API：`python -c "import sqlite3; s=sqlite3.connect('data/app.db'); d=sqlite3.connect('backups/bak.db'); s.backup(d)"`。
- 回滚某次上线：`bash scripts/stop.sh` → `cp -a backups/kg_v4_<时间>_before_<标签>/. data/` → `bash scripts/start.sh`。

## 对外服务：只监听 127.0.0.1 + 反向代理
默认 `HOST=127.0.0.1`，服务不出网。给外面人用：用 nginx/caddy 反代到 `127.0.0.1:8119`，配 HTTPS；走 HTTPS 时把 `bundle.conf` 里的 `EXTRA_ARGS` 设为 `--安全cookie`（cookie 只经 https 传）。**不要**直接 `HOST=0.0.0.0` 裸奔：这是 Flask 开发服务器，且 `--real` 模式下接口会花模型额度。反向代理层建议加访问控制（如基本认证/IP 白名单）。

## 已知限制
1. 知识图谱节点图要联网加载 3 个 CDN（unpkg 的 vue-flow 两个、cdnjs 的 dagre），断网时该块留空（页面有降级），其余功能正常；Vue 本体已本地（engine/app2/assets/）。
2. Flask 开发服务器，适合小范围（一个班/一个学校）使用，扛不了大并发。
3. wheels/ 绑定 CPython 3.13 / linux x86_64；换平台要重新 pip download（见 wheels/WHEELS.txt）。
4. 退出登录只是删 cookie：签发的令牌在过期（7 天）前一直有效，服务器无法吊销单个会话；删除/换 `data/.auth_secret` 等于让所有人重新登录。
5. 登录限流：同一用户名或同一来源连续失败 5 次锁 5 分钟（内存计数，重启清零）。
6. 本机不是 systemd 时，看门狗是 setsid 常驻进程：机器重启后要重新起（放进开机脚本或手动按第 5 步起）。
7. deploy.sh 的同步不删除数据目录里多出的文件（防误删），确认不要的文件要手动删。
8. deploy.sh 的备份是数据目录整份拷（含 app.db、uploads、web），但只在上线时做：平时请自行定期备份 data/app.db 与 data/uploads/。
9. 中文版限制：①带插值参数的消息与「共 3 条，第 1 页」这类混排文字仍显示中文——词表只做整串替换；②AI 生成的草稿/材料等给学生看的内容按科目内容语言保持中文；③日语科目（语法课）本身的内容是中文的——本中文版面向学日语的中国学生，只有 Python 科目带日文译文。
