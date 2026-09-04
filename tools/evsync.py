#!/usr/bin/env python3
"""evbook.md 的实测 EV → data/sim.json 的 ev.measured(bot 估值地板)。

⚑ 为什么要有这个脚本:两处存同一份数, 就是「两个家」。
   evbook 由 `tools/cf.gd` 重刷, 而 bot 读 sim.json —— 手工同步一次就会漂一次,
   而且漂了**不报错**(bot 只是估值偏低, 而估值偏低正是这个地板要修的病)。
   ⇒ 改数据的唯一路径:跑 cf.gd 刷 evbook → 跑本脚本同步 → 跑 sim。

   python3 tools/evsync.py [kit日志]         # 同步(evbook → ev.measured;kit 日志 → ev.measured_kit, 缺省 /tmp/sync5-gate/gate_cards.log)
   python3 tools/evsync.py --check [kit日志] # 只检查是否已同步(CI/门用, 不写文件;kit 日志不在时只查 evbook)
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

KIT_LOG_DEFAULT = "/tmp/sync5-gate/gate_cards.log"

def measured_kit(path=None):
    """kit 单卡门(score 通路)的**总分效应 → 分/拍**(Δ总分 / 24 拍)。

    ⚑ 2026-09-04:重放估值修好了效果卡那 39 张, lift 显示剩下的「低用高值」全在 17 张手写臂的卡上
    (ensemble +42.9pt 装机 3% · skint +13.3pt 装机 2% · vinyl · curtain · tipjar)—— 它们的先验是手写的,
    而 cf.gd 量不到成长/持有/概率卡(state 跨拍 / luck_rolls)。**kit 量得到**:它把卡钉进规则 bot 打满 24 拍,
    Δ总分就是「装着一整局值多少」= §3.3 说的到达值口径。⇒ 拿它给手写臂当第二块地板(与 evbook 同权重)。
    ⚠ 只收 score 通路的行(`    id  +Δ  ±SE  z = …`)与成长卡的「总分(参考)」行;z < 3 的不收(噪声不进地板)。
    日志不在时返回 None(与 evbook 同款:跳过, 不炸)。"""
    path = pathlib.Path(path or KIT_LOG_DEFAULT)
    if not path.exists():
        return None
    beats = 24
    ev = {}
    in_score = False
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.strip().startswith("---- ①"):
            in_score = True
        elif line.strip().startswith("---- ②") or line.strip().startswith("---- ③"):
            in_score = False
        if not in_score:
            continue
        m = re.match(r"^\s{4}(\w+)(?:: 总分\(参考\))?\s+([+-]\d+(?:\.\d+)?)\s+±(\d+(?:\.\d+)?)\s+z =\s*([+-]?[\d.>]+)", line)
        if not m:
            continue
        jid, delta, se, z = m.group(1), float(m.group(2)), float(m.group(3)), m.group(4)
        zval = 99.0 if ">" in z else float(z)
        if delta <= 0 or zval < 3.0:
            continue
        ev[jid] = round(delta / beats, 1)
    pool = {j["id"] for j in json.loads((ROOT / "data/jokers.json").read_text(encoding="utf-8"))["jokers"]}
    return {k: v for k, v in ev.items() if k in pool}

def main():
    kit_path = next((a for a in sys.argv[1:] if not a.startswith("--")), None)
    want_kit = measured_kit(kit_path)
    want = measured()
    if want is None:
        print("⚠ docs/design/evbook.md 不存在(cf.gd 的产物)—— 跳过同步检查。"
              "要生成:godot --headless --path . --script res://tools/cf.gd")
        return 0
    p = ROOT / "data/sim.json"
    d = json.loads(p.read_text(encoding="utf-8"))
    have = d["ev"].get("measured", {})
    have_kit = d["ev"].get("measured_kit", {})
    if "--check" in sys.argv:
        kit_ok = want_kit is None or have_kit == want_kit
        if not kit_ok:
            print("✗ ev.measured_kit 与 kit 日志不同步(%s)—— 跑 `python3 tools/evsync.py [kit日志]`" % (kit_path or KIT_LOG_DEFAULT))
            only_log = sorted(set(want_kit) - set(have_kit)); only_sim = sorted(set(have_kit) - set(want_kit))
            drift = [k for k in want_kit if k in have_kit and have_kit[k] != want_kit[k]]
            if only_log: print("  日志有 sim 没有:", " ".join(only_log))
            if only_sim: print("  sim 有日志没有:", " ".join(only_sim))
            if drift: print("  值不同:", " ".join("%s(%s→%s)" % (k, have_kit[k], want_kit[k]) for k in drift))
        if have == want and kit_ok:
            print("ev.measured 已同步(%d 张)%s" % (len(want), "" if want_kit is None else " · ev.measured_kit 已同步(%d 张)" % len(want_kit))); return 0
        if have == want:
            return 1
        only_book = sorted(set(want) - set(have)); only_sim = sorted(set(have) - set(want))
        drift = [k for k in want if k in have and have[k] != want[k]]
        print("✗ ev.measured 与 evbook 不同步 —— 跑 `python3 tools/evsync.py`")
        if only_book: print("  evbook 有 sim 没有:", " ".join(only_book))
        if only_sim:  print("  sim 有 evbook 没有:", " ".join(only_sim))
        if drift:     print("  值不同:", " ".join("%s(%s→%s)" % (k, have[k], want[k]) for k in drift))
        return 1
    d["ev"]["measured"] = want
    if want_kit is not None:
        d["ev"]["_comment_measured_kit"] = ("kit 单卡门 score 通路的总分效应 ÷ 24 拍(分/拍), 由 evsync.py 从 %s 同步;"
            "手写臂那 17 张卡的第二块地板(cf 量不到成长/持有/概率卡, kit 量得到)。**手改无效**。" % (kit_path or KIT_LOG_DEFAULT))
        d["ev"]["measured_kit"] = want_kit
    p.write_text(json.dumps(d, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print("ev.measured 已同步 %d 张%s" % (len(want), "" if want_kit is None else " · ev.measured_kit 已同步 %d 张" % len(want_kit)))
    return 0

if __name__ == "__main__":
    sys.exit(main())
