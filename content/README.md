# content/python_v1 ——「Python 编程」科目内容包（可选）

Python 科目（code=python）的知识图谱与题库源文件，附 ja/ 日文译文。导入：服务起来后跑
`bash scripts/load_python_content.sh`（建科目 → 图谱 preview/confirm 导入 → 题库导入 → 译文导入，
先预检再写，可重复执行；图谱按编号新增/更新，题库清空重灌，译文 upsert）。不导入不影响其它功能。

| 文件 | 内容 | 行数 |
|---|---|---|
| points.csv | 知识点（code,title） | 34 |
| items.csv | 条目（code,name,point_code,after_form,prev_code） | 110 |
| edges.csv | 前置边（pre_code,point_code，无环） | 49 |
| contrasts.csv | 对照（a_code,b_code） | 13 |
| quiz_v2.txt | 选择题（等级 入门38/基础34/进阶27；题干换行是字面 \n） | 99 |
| ja/*.tsv | 日文译文 442 条（kg_point 34 / kg_item 110 / quiz_question 297 / subject_info 1） | 442 |
| lessons/lesson_rows.zh.json | 中文课文 13 课（挂接条目 110、知识点 34） | 13 |
| ja_lesson/lesson.tsv | 课文译文（lesson_text 52 / lesson_series 2），文件用 JSON 字符串转义；必须在课文导入后导入 | 54 |

译文格式：tbl、row_key、field、text 四列；代码与程序输出保留原文，自然语言译日语；换行写成字面 \n。
等级约定：通用科目的题要能出，等级用科目自定义等级（这里是 入门/基础/进阶）。
