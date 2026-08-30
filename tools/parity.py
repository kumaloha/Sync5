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
    # ⚠ `slots_rule_guaranteed` 已移出:2026-08-30 规则牌整体转生为消耗牌之后
    # 它没有真值来源, 两侧都只剩定义 —— 留在这张表里会让「0 vs 0」被读成「对齐」。
    "slots_shelf_size", "slots_buy_limit",
    # ⚠ `slots_loan` 已移出:2026-08-30 预支转生为消耗牌之后它没有真值来源,
    # 两侧都只剩定义 —— 留着会让「0 vs 0」被读成「对齐」(同 slots_rule_guaranteed)。
    "slots_coin_cap", "slots_odds_mult", "use_consumable",
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


def card_face():
    """第四层:**卡面上的数字与数据里的值对不上**。

    ⚑ 2026-08-30 一天撞三次:彩头的 `chance` 从没被读过(卡面「半概率」实为 100%)·
    挑高的「必出 8 以上」在货架上没有对应物 · 拍内四张改了数值但中文卡面还是旧的。
    ⇒ **改数值时卡面是最容易漏的一环**, 而漏了玩家会按错的规则做决策。

    做法:把卡面里出现的数字抠出来, 与该卡 boost/action 的值比对。
    ⚠ 只查**能机械对上**的形状(百分比 / 倍率 / 整数加分), 对不上的形状跳过 ——
    宁可漏报, 不可误报(一把爱喊狼来了的尺会被无视)。
    """
    import json, re
    cons = json.loads((ROOT / "data/consumables.json").read_text(encoding="utf-8"))["consumables"]
    ui = json.loads((ROOT / "data/ui.json").read_text(encoding="utf-8")).get("consumablecard", {})
    bad = []
    for c in cons:
        face = ui.get(c["id"], {}).get("trigger", "")
        nums = [float(x) for x in re.findall(r"(\d+(?:\.\d+)?)", face)]
        if not nums:
            continue
        vals = []
        for k, v in list(c.get("boost", {}).items()) + list(c.get("action", {}).items()):
            if isinstance(v, bool) or not isinstance(v, (int, float)):
                continue
            # 原值 / 百分比 / 绝对值(卡面写「−2◆」而数据是 -2, 符号在文案里)
            vals += [float(v), float(v) * 100.0, abs(float(v)), abs(float(v)) * 100.0]
        if not vals:
            continue
        for n in nums:
            if not any(abs(n - v) < 0.51 for v in vals):
                bad.append("%s: 卡面「%s」里的 %g 在数据里找不到 %s"
                           % (c["id"], face, n, {**c.get("boost", {}), **c.get("action", {})}))
                break
    return bad


def amount_channels():
    """第 ⑤ 层:jokers.json 里的每个 `do` 键, `tools/bot.gd::_amt` 认不认识。

    ⚑ 2026-08-30:`coins_factor` 不在 `_amt` 的白名单里(全池只有版税用它)⇒
       `_amt` 落到末尾 `return 0.0`, 而版税的臂写的是 `(_amt(id) - 1.0)` ⇒ **EV 变成负数**
       ⇒ 买牌的 `best_gain` 从 0.0 起比, **这张卡永远不可能被选中**。
       实测装机率 **0.0%**(全池唯一一张一次都没被买过的), 而单卡门量出来它值
       **+1191.7 分/局**, 是一张 common 的两倍。**一个白名单漏了一个键, 判了一张卡死刑。**
    判据:每个 `do` 键要么在 `_amt` 的通道白名单里, 要么在 `NON_AMOUNT_KEYS` 里(显式声明「它不是数额」)。
    """
    import json
    bot = (ROOT / "tools/bot.gd").read_text(encoding="utf-8")
    known = set()
    m = re.search(r'for ch in \[([^\]]+)\]', bot)
    if m:
        known |= set(re.findall(r'"([a-z_]+)"', m.group(1)))
    # 特判分支(各自 return 的通道)+ 显式声明的非数额键
    known |= set(re.findall(r'fx\.get\("do", \{\}\)\.has\("([a-z_]+)"\)', bot))
    m2 = re.search(r'const NON_AMOUNT_KEYS := \[([^\]]+)\]', bot, re.S)
    if m2:
        known |= set(re.findall(r'"([a-z_]+)"', m2.group(1)))
    used = {}
    for j in json.loads((ROOT / "data/jokers.json").read_text(encoding="utf-8"))["jokers"]:
        for fx in (j.get("effects") or []):
            for k in (fx.get("do") or {}):
                used.setdefault(k, []).append(j["id"])
    bad = [(k, used[k]) for k in sorted(used) if k not in known]
    return len(used), bad


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
    fbad = card_face()
    if fbad:
        print("✗ %d 张卡的**卡面与数据对不上**(玩家会按错的规则做决策):" % len(fbad))
        for b in fbad:
            print("   " + b)
    wbad = write_only()
    if wbad:
        print("✗ %d 个授予变量**写了但没人读**(那张卡在游戏里是空白的):%s" % (len(wbad), " ".join(wbad)))
    nch, chbad = amount_channels()
    if not quiet:
        print("\njokers.json 的 do 通道:%d 个, _amt 认识 %d 个" % (nch, nch - len(chbad)))
    if chbad:
        print("✗ %d 个 do 通道 `_amt` 不认识(那些卡的数额会被推导成 0):" % len(chbad))
        for k, ids in chbad:
            print("   %-22s %d 张: %s" % (k, len(ids), " ".join(ids[:8])))
        print("  ⚠ 数额 0 不只是「少算一点」—— 臂里写 `(_amt-1)` 的会变成**负 EV = 永不购买**")
    acts, abad = action_keys()
    if not quiet:
        print("\n消耗牌 action 键:%d 个, 两侧齐 %d 个" % (len(acts), len(acts) - len(abad)))
    if abad:
        print("✗ %d 个 action 键两侧不齐:%s" % (len(abad), " ".join(abad)))
        print("  ⚠ 后果不止低估 —— 用这种读数定的价**无效**(见 LESSONS 同名条)")
    if bad or abad or wbad or fbad or chbad:
        if bad:
            print("✗ %d 个入口两侧不对齐:%s" % (len(bad), " ".join(bad)))
        return 1
    if not quiet:
        print("\n✓ 所有规则入口两侧对齐")
    return 0

if __name__ == "__main__":
    sys.exit(main())
