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
    """⚠ evbook.md 是 `cf.gd` 的**生成产物**, 可能不存在(新克隆 / 没跑过 cf)。
    缺文件不算错 —— 返回空表, 让调用方按「还没量过」处理, 而不是让门在
    一个不相干的地方炸(2026-08-30 code review:此前直接 FileNotFoundError,
    而这个脚本**已经进了 gate.sh**)。"""
    book = ROOT / "docs/design/evbook.md"
    if not book.exists():
        return None
    ev = {}
    for line in book.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\| *(\w+) *\|[^|]*\| *(\w+) *\| *([\d.-]+) *\|[^|]*\| *\*\*([\d.-]+)\*\*", line)
        if not m or float(m.group(4)) <= 0:
            continue
        # ⚠ 备注列说「本尺不适用 / 读数无效」的行**不进地板**(2026-09-04):穷开心(hold, 金币上限
        # 的代价不在结算链里)曾以 112.4 进了 ev.measured ⇒ 地板 56 盖过它手写臂的负 EV ⇒
        # bot 装机率 43% 而 lift 实测 −13pt。cf.gd 已经在备注里说了「不适用」, 这里没听。
        note = line.rstrip().rstrip("|").rsplit("|", 1)[-1]
        if "不适用" in note or "无效" in note:
            continue
        ev[m.group(1)] = round(float(m.group(4)), 1)
    pool = {j["id"] for j in json.loads((ROOT / "data/jokers.json").read_text(encoding="utf-8"))["jokers"]}
    return {k: v for k, v in ev.items() if k in pool}

def main():
    want = measured()
    if want is None:
        print("⚠ docs/design/evbook.md 不存在(cf.gd 的产物)—— 跳过同步检查。"
              "要生成:godot --headless --path . --script res://tools/cf.gd")
        return 0
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
