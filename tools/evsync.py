#!/usr/bin/env python3
"""evbook.md 的实测 EV → data/sim.json 的 ev.measured(bot 估值地板)。

⚑ 为什么要有这个脚本:两处存同一份数, 就是「两个家」。
   evbook 由 `tools/cf.gd` 重刷, 而 bot 读 sim.json —— 手工同步一次就会漂一次,
   而且漂了**不报错**(bot 只是估值偏低, 而估值偏低正是这个地板要修的病)。
   ⇒ 改数据的唯一路径:跑 cf.gd 刷 evbook → 跑本脚本同步 → 跑 sim。

   python3 tools/evsync.py           # 同步
   python3 tools/evsync.py --check   # 只检查是否已同步(CI/门用, 不写文件)
"""
import json, re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent

def measured():
    ev = {}
    for line in (ROOT / "docs/design/evbook.md").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\| *(\w+) *\|[^|]*\| *(\w+) *\| *([\d.-]+) *\|[^|]*\| *\*\*([\d.-]+)\*\*", line)
        if m and float(m.group(4)) > 0:
            ev[m.group(1)] = round(float(m.group(4)), 1)
    pool = {j["id"] for j in json.loads((ROOT / "data/jokers.json").read_text(encoding="utf-8"))["jokers"]}
    return {k: v for k, v in ev.items() if k in pool}

def main():
    want = measured()
    p = ROOT / "data/sim.json"
    d = json.loads(p.read_text(encoding="utf-8"))
    have = d["ev"].get("measured", {})
    if "--check" in sys.argv:
        if have == want:
            print("ev.measured 已同步(%d 张)" % len(want)); return 0
        only_book = sorted(set(want) - set(have)); only_sim = sorted(set(have) - set(want))
        drift = [k for k in want if k in have and have[k] != want[k]]
        print("✗ ev.measured 与 evbook 不同步 —— 跑 `python3 tools/evsync.py`")
        if only_book: print("  evbook 有 sim 没有:", " ".join(only_book))
        if only_sim:  print("  sim 有 evbook 没有:", " ".join(only_sim))
        if drift:     print("  值不同:", " ".join("%s(%s→%s)" % (k, have[k], want[k]) for k in drift))
        return 1
    d["ev"]["measured"] = want
    p.write_text(json.dumps(d, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print("ev.measured 已同步 %d 张" % len(want))
    return 0

if __name__ == "__main__":
    sys.exit(main())
