#!/usr/bin/env python3
"""文档里的卡数 vs `data/*.json` 的真值 —— 手抄的数字会漂,而且漂了不报错。

⚑ 2026-08-30 立:`STATUS.md` 那一行历史上写过 23 / 61 / 63 / 76,**没有一个是对的**
   (真值 69)。它自己的注释都写着「以 data/*.json 计数为准」—— 有尺没用, 所以做成机械。

   python3 tools/counts.py           # 报告
   python3 tools/counts.py --check   # 只报不一致(gate 用)
"""
import json, re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent

def main():
    quiet = "--check" in sys.argv
    truth = {
        "小丑牌": len(json.loads((ROOT / "data/jokers.json").read_text(encoding="utf-8"))["jokers"]),
        "消耗牌": len(json.loads((ROOT / "data/consumables.json").read_text(encoding="utf-8"))["consumables"]),
    }
    if not quiet:
        print("真值:", " · ".join("%s %d 张" % kv for kv in truth.items()))
    bad = []
    # 扫 md 里形如「小丑牌 … NN 张」「消耗牌 … NN 张」的断言(同一行内, 允许中间有格式符)
    for md in list((ROOT / "docs/design").glob("*.md")) + [ROOT / "STATUS.md", ROOT / "CLAUDE.md"]:
        for ln, line in enumerate(md.read_text(encoding="utf-8").splitlines(), 1):
            for name, n in truth.items():
                # ⚠ 只查**指向现状**的断言。历史记录写的是**当时**的数, 改了反而是篡改证据
                # (2026-08-30 首扫 4 处, 3 处是 08-13 的日志与「批 3 口径」的图谱标题)。
                # 判据:同一行里出现日期、「口径」、「冻结」、「当时」这类词 ⇒ 是历史。
                if re.search(r"20\d\d-\d\d-\d\d|口径|冻结|当时|历史|曾", line):
                    continue
                for m in re.finditer(name + r"[^\n]{0,24}?\*{0,2}(\d{2,3})\*{0,2}\s*张", line):
                    got = int(m.group(1))
                    if got != n and got not in (4,):     # 4 槽位那种无关数字
                        bad.append((md.relative_to(ROOT), ln, name, got, n, line.strip()[:70]))
    for b in bad:
        print("✗ %s:%d  %s 写着 %d 张, 真值 %d\n    %s" % b)
    if bad:
        print("\n⚠ %d 处卡数与 data/ 不符 —— 手抄的数字会漂, 且漂了不报错" % len(bad))
        return 1
    if not quiet:
        print("✓ 文档里的卡数与 data/ 一致")
    return 0

if __name__ == "__main__":
    sys.exit(main())
