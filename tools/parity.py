#!/usr/bin/env python3
"""游戏侧 / bot 侧的**规则对齐**扫描 —— 「规则在游戏里、不在模型里」的机械检查。

⚑ 这个形状本项目栽过**七次**(最近一次:2026-08-30 帕奇欧只接了游戏侧,
   sim 里它是纯废卡, bot 永不购买 ⇒ 这张牌进不了任何读数)。
   `core/joker.gd` 早就写着方法:「让调用形式统一到一行, grep 就能数清两侧是否对齐」——
   **有尺没用**, 所以把它做成可执行的。

判据:一个「由动作触发的规则入口」, 如果只在 view/ 出现而 tools/ 为零, 就是漏了。
     ⚠ 反过来(只在 tools/)也报 —— 那是 bot 自作主张, 同样是不一致。

   python3 tools/parity.py            # 扫描
   python3 tools/parity.py --check    # 只报异常(CI/门用)
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent

# 需要两侧对齐的规则入口。⚠ 加新钩子时**同时加到这里** —— 这张表本身就是那条纪律。
ENTRIES = [
    "notify_shop", "slots_copy_consumable", "slots_target_guaranteed",
    "slots_rule_guaranteed", "slots_shelf_size", "slots_buy_limit",
    "slots_coin_cap", "slots_loan", "slots_odds_mult", "use_consumable",
    "take_consumable", "add_wilds", "trim_low_ranks",
]
# 这些只属于一侧, 有充分理由 —— 写清理由, 否则就是给例外开后门
# ⚠ 空的。**别急着往里加** —— 2026-08-30 首版我凭记忆给 `slots_loan` 写了条豁免,
# 而它 view 3 / tools 3 本来就对齐, 那条例外纯属多余。一条不需要的豁免 =
# 下一块遮羞布(同日 LESSONS「过期的豁免是遮羞布」)。**加之前先跑一次确认它真的不齐。**
EXEMPT = {}

def sides(name):
    def count(sub):
        n = 0
        for f in (ROOT / sub).rglob("*.gd"):
            txt = f.read_text(encoding="utf-8", errors="ignore")
            # 不数定义行, 只数调用
            n += len([l for l in txt.splitlines()
                      if name in l and not l.strip().startswith(("func ", "static func ", "#", "##"))])
        return n
    return count("view"), count("tools"), count("core")

def action_keys():
    """数据驱动的第二层:消耗牌 `action` 的每个键, 两侧是否都实现。

    ⚑ 2026-08-30 手工核对发现 **6/9 的键 bot 侧没实现** —— bot 会买、会「用掉」,
    但用了什么都不发生, 而我正是用那份读数给它们定的价。核对花 30 秒,
    推翻的是半小时前刚落的价格 ⇒ 值得自动化。
    ⚠ `parity.py` 上半部分扫的是**规则入口**(函数名), 扫不到这一层 ——
    这些键写在 JSON 里, 是数据驱动的。
    """
    import json
    acts = set()
    for c in json.loads((ROOT / "data/consumables.json").read_text(encoding="utf-8"))["consumables"]:
        acts |= set(c.get("action", {}))
    game = "".join((ROOT / f).read_text(encoding="utf-8") for f in ("view/phrase.gd", "view/shop.gd"))
    bot = (ROOT / "tools/bot.gd").read_text(encoding="utf-8")
    bad = []
    for a in sorted(acts):
        g, b = ('"%s"' % a) in game, ('"%s"' % a) in bot
        if not (g and b):
            bad.append("%s(%s)" % (a, "bot 侧缺" if g else "游戏侧缺"))
    return sorted(acts), bad


def write_only():
    """第三层:**写了但没人读**的成员变量。

    ⚑ 2026-08-30 code review 抓到三张消耗牌在游戏里是**空白卡** ——
    `_grant_buy_limit` / `_grant_min_rarity` / `consume_free_reroll()`
    全都只被写入和清零, **从没被读过**。⚠ 上面两层查不出这个:
    它们查「两侧都有没有实现」, 而这三个**两侧都写了变量**, 只是没人消费。
    """
    import re
    bad = []
    for sub in ("view", "core"):
        for f in sorted((ROOT / sub).glob("*.gd")):
            txt = f.read_text(encoding="utf-8", errors="ignore")
            for m in re.finditer(r"^var (_g?rant?_\w+|_g_\w+)\s*(?::=|:|=)", txt, re.M):
                n = m.group(1)
                uses = len(re.findall(r"\b" + re.escape(n) + r"\b", txt))
                writes = len(re.findall(re.escape(n) + r"\s*(?:=|\+=|-=|\*=)", txt))
                if uses - writes - 1 <= 0:
                    bad.append("%s:%s" % (f.relative_to(ROOT), n))
    return bad


def main():
    quiet = "--check" in sys.argv
    bad = []
    if not quiet:
        print("%-26s %6s %6s %6s" % ("规则入口", "view", "tools", "core"))
    for e in ENTRIES:
        v, t, c = sides(e)
        flag = ""
        if e in EXEMPT:
            flag = "豁免: " + EXEMPT[e]
        elif v > 0 and t == 0:
            flag = "✗ 只在游戏侧 —— bot 看不见这条规则"; bad.append(e)
        elif t > 0 and v == 0 and c == 0:
            flag = "✗ 只在 bot 侧 —— 模型里有游戏里没有"; bad.append(e)
        if not quiet:
            print("%-26s %6d %6d %6d  %s" % (e, v, t, c, flag))
    wbad = write_only()
    if wbad:
        print("✗ %d 个授予变量**写了但没人读**(那张卡在游戏里是空白的):%s" % (len(wbad), " ".join(wbad)))
    acts, abad = action_keys()
    if not quiet:
        print("\n消耗牌 action 键:%d 个, 两侧齐 %d 个" % (len(acts), len(acts) - len(abad)))
    if abad:
        print("✗ %d 个 action 键两侧不齐:%s" % (len(abad), " ".join(abad)))
        print("  ⚠ 后果不止低估 —— 用这种读数定的价**无效**(见 LESSONS 同名条)")
    if bad or abad or wbad:
        if bad:
            print("✗ %d 个入口两侧不对齐:%s" % (len(bad), " ".join(bad)))
        return 1
    if not quiet:
        print("\n✓ 所有规则入口两侧对齐")
    return 0

if __name__ == "__main__":
    sys.exit(main())
