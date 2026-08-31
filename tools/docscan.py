# -*- coding: utf-8 -*-
"""文档漂移扫描 —— 设计文档里反引号写着、而代码/数据里根本不存在的标识符。

⚑ 起因(2026-08-31 用户):「之前消耗牌在文档里列了但没做的, 找找这种是不是还有没做的」。
   凭印象翻文档不可靠, 做成扫描。

⚠⚠ **它扫不到最毒的那一类** —— kit.gd 的抬头曾三天印着「不死局**打满 24 拍**」而实际
   只打 4 拍, 那句话里**没有标识符**。散文里的行为声明只能靠**把声明变成断言**来守
   (见 `tests/t_run.gd::_t_probe_runs_full`)。这把尺守的是另一半:名字层面的漂移。

   python3 tools/docscan.py
"""
import io, re, pathlib, collections
ROOT = pathlib.Path(".")
# 代码与数据的全文(标识符的唯一真相)
hay = []
for sub in ("core", "view", "tools", "tests", "data"):
    for f in ROOT.joinpath(sub).rglob("*"):
        if f.suffix in (".gd", ".json", ".py", ".sh", ".cfg"):
            hay.append(f.read_text(encoding="utf-8", errors="ignore"))
# ⚠ 盲区补丁:文档之间会互相引用文件名(README 引 `research_balatro_jokers`),
# 那不是漂移。把 docs/ 下的文件名也算作"存在"。
for f in ROOT.joinpath("docs").rglob("*.md"):
    hay.append(f.stem)
hay = "\n".join(hay)

ident = re.compile(r"^[a-z][a-z0-9_]{3,}(\.[a-z][a-z0-9_]*)*$")
ghosts = collections.defaultdict(list)
SKIP = ("_review", "_history", "research_")   # 评审/历史/调研篇本来就在讲不存在的东西
for md in sorted(ROOT.joinpath("docs/design").glob("*.md")):
    if any(k in md.name for k in SKIP):
        continue
    txt = md.read_text(encoding="utf-8", errors="ignore")
    # ⚠ **逐行看, 并跳过「自己写着已经没了」的行** —— 文档明确记着「已删除 / 退役 /
    # 不再有」时, 那个标识符出现在文里是**正确的历史记录**, 不是漂移。
    # (不加这条, 扫描会把「诚实地记下删除」当成问题, 而那正是我们要鼓励的写法。)
    GONE = re.compile(r"(已删|删除|退役|不再有|曾在|已随|~~|提案|未实装|未实现|未采纳|冲突)")
    for line in txt.splitlines():
        if GONE.search(line):
            continue
        for m in re.finditer(r"`([^`\n]{4,60})`", line):
            tok = m.group(1).strip()
        # 只看像标识符的:全小写 + 下划线/点, 不含空格中文括号
            if not ident.match(tok):
                continue
            base = tok.split(".")[-1]
            if base in hay or tok in hay:
                continue
            ghosts[tok].append(md.name)
print("文档里写着、代码/数据里找不到的标识符:%d 个\n" % len(ghosts))
for tok, files in sorted(ghosts.items(), key=lambda kv: -len(kv[1])):
    print("  %-34s %s" % (tok, " ".join(sorted(set(files)))[:70]))
