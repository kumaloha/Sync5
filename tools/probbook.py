#!/usr/bin/env python3
"""概率账本生成器(docs/design/numbers.md §1 的记录制度)。

    python3 tools/probbook.py [sim日志路径]

产出 docs/design/probbook.md:每张支援卡三列概率(设计 p̂ / 仪器 p_bot / 真人 p_人)
+ 样本量 + 自动诊断。真人列扫全部合格 Tape;bot 列解析 sim 日志(可选,
没给路径就留空标注)。**probbook.md 是仪器读数,手改无效** —— 改这里。

2026-08-12 C9(numbers.md §1 修订):
- 真人列拆两态:持有规则牌 / 未持有 —— Δp = p_有 − p_无 是规则牌计价的输入;
- 附「规则牌 Δp 牌型频率表」:规则牌自己不入 fired(无 effects,proof:solver),
  它的读数是牌型频率的两态差,旧版把它们标 ☠死档 是量纲用错;
- 修 held 追踪:repl 事件是 in/out 键,旧版只认 id —— 换进的不计、换出的不删,
  有替换的局真人列全错;
- ⚠ bot 列尚未拆两态(sim 的 support trigger 表不分态,仪器债)。
"""
import glob
import json
import os
import re
import sys
from collections import defaultdict
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TAPE = os.path.expanduser(
    '~/Library/Application Support/Godot/app_userdata/Sync5 · Project Rhythm/tape')

# 改判定/改牌堆的四张(proof:solver,无 effects)。它们抬的是牌型概率,
# 不是自己的触发率 —— 见文件头与 numbers.md §2「概率放大器」。
RULES = ('shortcut', 'fourfingers', 'twotone', 'wildcard')

# settle.kind 是 Pattern.Kind 的 int(core/pattern.gd 枚举序)。
KIND_FAMS = [
    ('顺子族', {4, 8, 9}),          # STRAIGHT / STRAIGHT_FLUSH / ROYAL_FLUSH
    ('同花族', {5, 8, 9}),          # FLUSH / SF / RF
    ('大牌型族', {4, 5, 6, 8, 9}),  # fullcast 的牌型集(顺/同花/葫芦/SF/RF)
]

# ── 设计概率 p̂:策划手推,带一句推导。没推过的不填,表里留 "—"。──────────
# (条件在"玩家理解并愿意配合"时的达成率;高估教学效果是它的已知失真)
DESIGN_P = {
    'neonsign':  (1.00, '无条件'),
    'finale':    (0.65, '最后2秒有操作:节奏玩家多数拍会压秒'),
    'variation': (0.70, '换牌型:五张重抽下不同牌型是自然态'),
    'turnover':  (0.75, '弃过牌:免费弃牌下多数拍会弃'),
    'tipjar':    (0.35, '整拍零弃:与弃牌自由互斥,少数拍'),
    'encore':    (0.35, '重复上一拍:需刻意保型,且被禁回族脸打断'),
    'chord':     (0.70, '建成态:缓存三同花建好后可持续;建设期2-4拍'),
    'rainbow':   (0.28, '成牌四花色:C(4,4)分布+换牌可凑,偏彩票'),
    'nopair':    (0.40, '五张无对:高牌/顺/同花态,可刻意保持'),
    'fullcast':  (0.12, '顺/同花/葫芦成手:等价于打出大牌型'),
    'backup':    (0.05, '缓存三人头:建设成本极高,基本不会为它建'),
    'rehearsal': (0.08, '缓存三连号:同上'),
    'popup':     (0.10, 'S1 专属×商店最早段中开:窗口错位'),
    'chorus':    (0.17, '每段末拍:1/6 结构概率'),
    'opener':    (0.17, '每段首拍:1/6 结构概率'),
    'reprise':   (0.35, '同回响'),
    'superfan':  (0.90, '持币≥2◆ 几乎恒真'),
    'interest':  (0.85, '持币≥4◆ 多数拍为真'),
}


# ── 基线概率 p_基线:**换分母**(2026-08-28)。────────────────────────────
#
# 上面那两列真人概率的分母是「**持有该卡**的拍」,于是行为类卡常年 n=3~6,
# 满屏「⚠人样本薄」,而 numbers.md 判它们「先验算不出来,必须等实测」——
# 两头堵死,结果是 64 条里 39 条**从来没有过任何概率输入**(谢幕 curtain 是其一)。
#
# ⚑ 但行为/牌面类条件的成立**只取决于玩家怎么打和发到什么牌,与有没有装那张卡无关**
# (装了会改打法是二阶效应,见下面的偏差说明)。⇒ 分母可以换成**全部合格拍**,
# 样本从 3~6 拍变成几百拍。这就是 numbers.md §1 说的「说『等更多数据』之前,
# 先问换个分母能不能答」。
#
# ⚠⚠ **判定是在这里手写的 = 第二份判定**,而「规则在游戏里不在模型里」是本项目
# 最贵的一类错。所以每一条都**由 `fired` 自证**:在玩家确实持有该卡的那些拍上,
# 这里算出来的条件必须与游戏记的 `fired` **逐拍相同**。一致率 <100% 的卡
# **不出基线值**,只在诊断列报「判定不同源」—— 宁可空着,也不要一个错的大样本。
#
# ⚠ 已知偏差(读数时要记得):① **行为适应** —— 装了谢幕的人会更爱压秒,所以基线
# 是「不特意配合」的下界,持有态那一列才是含配合的真实收益;两列并排看才完整。
# ② 只覆盖**能从 settle/beat 已记事实直接判定**的卡;需要更细事实的
# (串场/回收/盲奏 的 per 计数)不在表里,留 `—`。
KIND_PAIRPLUS = {1, 2, 3, 6, 7}      # 含对子:PAIR/TWO_PAIR/THREE/FULL/FOUR
KIND_TRIPLUS = {3, 6, 7}             # 三条或更好
KIND_BIG = {4, 5, 6, 8, 9}           # 顺/同花/葫芦/SF/RF(全员的牌型集)
KIND_MADE = set(range(1, 10))        # 成牌(高牌以外)


# 早弃窗口:活取 data/run.json,别抄第二份(见 BASELINE['earlyout'])。
EARLY_DISCARD_WINDOW = float(json.load(
    open(os.path.join(ROOT, 'data/run.json')))['early_discard_window'])


def _rank(c):
    """'10H' -> 10 · 'QD' -> 12 · 'AS' -> 14(Tape 的牌面串, core/card.gd 的写法)。"""
    r = c[:-1]
    return {'J': 11, 'Q': 12, 'K': 13, 'A': 14}.get(r, int(r) if r.isdigit() else 0)


def _suit(c):
    return c[-1]


def _reds(b):
    return sum(1 for c in b['cards'] if _suit(c) in 'HD')


BASELINE = {
    # 时机族 —— `late` 是**游戏自己写进 Tape 的字段**,零重写(自证必然 100%)
    'finale':     lambda b: bool(b['late']),
    'curtain':    lambda b: b['act'] >= b['dur'] - 1.0,
    # ~~stopwatch~~ **判定不了,故意留空**:它是 `per: second_left`,要的是「提前收工」
    # (玩家主动按收工键)。我一度写成 `act < dur-1`(最后一次操作早),那是**另一件事**
    # —— 什么都不做干等到自然结束也满足它。settle 事件里**没有 early 字段**
    # (2026-08-12 补的 `early` 只传给了结算链, 没进 Tape), 判不了就不判。
    # ⚠ 这条是「基线未自证」那个标注抓到的:stopwatch 没人买过 ⇒ 无 fired 可对,
    # 错的判定会一路走到表上。**没自证的判定要自己再读一遍谓词**。
    # 弃牌族
    'tipjar':     lambda b: b['disc'] == 0,
    'hush':       lambda b: b['disc'] == 0,
    'lonewolf':   lambda b: b['disc'] == 0,
    'turnover':   lambda b: b['disc'] >= 1,
    'wrecker':    lambda b: b['disc'] >= 4 and b['kind'] in KIND_MADE,
    # ⚠ 窗口**从 data/run.json 活取**(2026-08-28 把它从 4.0 抬到 6.0 时抓到的):
    # 这里写死一个 4.0 就是「规则在游戏里、模型里另有一份」—— 改了配置账本不跟,
    # 而且不报错。同一条纪律见 db.gd 的 discard_bias 交叉校验。
    'earlyout':   lambda b: b['disc'] > 0 and b['last_disc_at'] < EARLY_DISCARD_WINDOW,
    # 交换族
    'stilllife':  lambda b: b['swaps'] == 0,
    # 牌型族
    'fullcast':   lambda b: b['kind'] in KIND_BIG,
    'duo':        lambda b: b['kind'] in KIND_PAIRPLUS,
    'duet':       lambda b: b['kind'] in KIND_PAIRPLUS,
    'triad':      lambda b: b['kind'] in KIND_TRIPLUS,
    'triplebill': lambda b: b['kind'] in KIND_TRIPLUS,
    # 牌面族(per 类:触发 = 计数 > 0)
    'rainbow':    lambda b: len({_suit(c) for c in b['cards']}) == 4,
    'nopair':     lambda b: len({_rank(c) for c in b['cards']}) == len(b['cards']),
    'warmtone':   lambda b: _reds(b) > 0,
    'cooltone':   lambda b: len(b['cards']) - _reds(b) > 0,
    'undertone':  lambda b: any(_rank(c) <= 5 for c in b['cards']),
    'bassclef':   lambda b: any(2 <= _rank(c) <= 5 for c in b['cards']),
    'vip':        lambda b: any(11 <= _rank(c) <= 13 for c in b['cards']),
}


def _qualified(lines):
    if not lines or lines[0].get('e') != 'run':
        return False
    # 2026-08-21 审查:教学关(假局, 目标分 0)与探针会话(sess.id = -1)不算合格真人局
    head = lines[0]
    if head.get('tutorial'):
        return False
    if isinstance(head.get('sess'), dict) and head['sess'].get('id', 0) == -1:
        return False
    evs = defaultdict(int)
    for l in lines:
        evs[l['e']] += 1
    return (evs['intro'] > 0
            and max((l.get('ms', 0) for l in lines), default=0) > 60000
            and evs['pick'] + evs['swap'] + evs['disc'] >= 5)


def human_rates():
    """两态计数。beats/fired[jid] = [无规则牌, 有规则牌];
    rule_kinds[rule][态][kind] = 拍数(态 0=未持有该规则牌, 1=持有)。"""
    beats = defaultdict(lambda: [0, 0])
    fired = defaultdict(lambda: [0, 0])
    rule_kinds = {r: [defaultdict(int), defaultdict(int)] for r in RULES}
    runs = 0
    base_hit = defaultdict(int)          # 基线:条件成立的拍数(分母 = 全部合格拍)
    base_n = 0
    # ⚠⚠ 基线的分母**跨版本**:合格 Tape 从 2026-08-06 一直攒到今天,期间经济 v2
    # (弃牌收费)、动作粒度(多选 = 1 动作)、拍长都改过。混在一个分母里 = 拿三个版本
    # 的游戏平均。实证:「一次弃≥4 张」08-13 手算是 8.6%(同分母),今天 16.2% ——
    # **翻倍,而那正是 08-27 动作粒度改动的效果**。⇒ 按 mtime 分前后半各算一份,
    # 差得大的在诊断列报「⚠版本漂移」,提醒读数的人别把旧版本的拍当同一件事。
    late_hit = defaultdict(int)
    late_n = 0
    agree = defaultdict(lambda: [0, 0])  # 自证:[与 fired 一致的拍, 持有该卡的拍]
    # 回传成功的日志被 core/uplink.gd 搬进 sent/ —— 本地分析两处都要扫(2026-08-21 审查)
    # 按 mtime 排序:版本漂移那一列要「前半 / 后半」,顺序不能靠 glob 的随机结果。
    files = sorted(glob.glob(TAPE + '/*.jsonl') + glob.glob(TAPE + '/sent/*.jsonl'),
                   key=os.path.getmtime)
    ok_files = []
    for f in files:
        try:
            if _qualified([json.loads(l) for l in open(f)]):
                ok_files.append(f)
        except Exception:
            pass
    recent = set(ok_files[len(ok_files) // 2:])     # 后半 = 较新的那批局
    for f in ok_files:
        lines = [json.loads(l) for l in open(f)]
        is_recent = f in recent
        runs += 1
        held = set()
        # 拍内累计:换分母那一列要的事实(拍长 / 交换次数 / 最后一次弃牌的时刻)
        dur, swaps, last_disc_at = 8.0, 0, -1.0
        for l in lines:
            e = l['e']
            if e == 'buy' and 'id' in l:
                held.add(l['id'])
            elif e == 'repl':
                # 满槽替换:in 换进 / out 换出(core/tape.gd 事件表)
                held.discard(l.get('out', ''))
                if l.get('in'):
                    held.add(l['in'])
            elif e == 'beat':
                dur, swaps, last_disc_at = float(l.get('dur', 8.0)), 0, -1.0
            elif e == 'swap':
                swaps += 1
            elif e == 'disc':
                last_disc_at = max(last_disc_at, float(l.get('at', 0.0)))
            elif e == 'settle':
                st = 1 if any(r in held for r in RULES) else 0
                hit = set(l.get('fired', []))
                for j in held:
                    beats[j][st] += 1
                    if j in hit:
                        fired[j][st] += 1
                k = l.get('kind', -1)
                if isinstance(k, int) and k >= 0:
                    for r in RULES:
                        rule_kinds[r][1 if r in held else 0][k] += 1
                # ---- 基线列(换分母)+ 自证 ----
                b = {'dur': dur, 'swaps': swaps, 'last_disc_at': last_disc_at,
                     'act': float(l.get('act', 0.0)), 'late': l.get('late', False),
                     'disc': int(l.get('disc', 0)), 'cards': l.get('cards', []),
                     'kind': k if isinstance(k, int) else -1}
                base_n += 1
                if is_recent:
                    late_n += 1
                for jid, cond in BASELINE.items():
                    try:
                        ok = bool(cond(b))
                    except Exception:
                        continue
                    if ok:
                        base_hit[jid] += 1
                        if is_recent:
                            late_hit[jid] += 1
                    # 自证:只在**确实持有该卡**的拍上比对(那时 fired 才有意义)
                    if jid in held:
                        agree[jid][1] += 1
                        if ok == (jid in hit):
                            agree[jid][0] += 1
    return (beats, fired, rule_kinds, runs, base_hit, base_n, agree,
            late_hit, late_n)


def bot_rates(path):
    n_sum, n_cnt = defaultdict(float), defaultdict(int)
    if not path or not os.path.exists(path):
        return n_sum, n_cnt, None
    for line in open(path):
        if 'support trigger' in line:
            for m in re.finditer(r'(\w+):(\d+)%\((\d+)\)', line):
                jid, pct, n = m.group(1), int(m.group(2)), int(m.group(3))
                if n > 0:
                    n_sum[jid] += pct * n
                    n_cnt[jid] += n
    return n_sum, n_cnt, path


def _cell(f, b):
    return ('%.0f%% (%d)' % (f / b * 100, b)) if b else '—'


def main():
    sim_path = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('SYNC5_SIMLOG', '')
    (h_beats, h_fired, rule_kinds, runs, base_hit, base_n, agree,
     late_hit, late_n) = human_rates()
    b_sum, b_cnt, sim_used = bot_rates(sim_path)
    jokers = json.load(open(os.path.join(ROOT, 'data/jokers.json')))['jokers']

    out = []
    out.append('# 概率账本(仪器读数,手改无效 —— 重刷:`python3 tools/probbook.py <sim日志>`)\n')
    out.append('生成:%s · 真人样本:%d 局 · bot 来源:%s' % (
        datetime.now().strftime('%Y-%m-%d %H:%M'), runs,
        ('`%s`' % os.path.basename(sim_used)) if sim_used else '**未提供(缺 bot 列)**'))
    out.append('真人列两态:**无R** = 未持有任何规则牌(近道/四指/双色调/百搭)的拍,'
               '**有R** = 持有的拍。bot 列未拆态(仪器债)。')
    out.append('**`p_基线` = 换分母那一列(2026-08-28)**:分母是**全部合格拍**而不是「持有该卡的拍」,'
               '因为行为/牌面类条件成不成立与有没有装那张卡无关 —— 样本因此从 3~6 拍变成 '
               + str(base_n) + ' 拍。每一条判定都由 `fired` **逐拍自证**'
               '(持有该卡的拍上必须与游戏记录一致),一致率不足 100% 的**不出值**,'
               '只报「判定不同源」。')
    out.append('⚠ 读数时记得两条偏差:① **行为适应** —— 装了谢幕的人会更爱压秒,'
               '所以基线是「不特意配合」的**下界**,持有态那列才是含配合的真实收益,两列并排才完整;'
               '② 只覆盖能从已记事实直接判定的卡,其余留 `—`。\n')
    out.append('| id | 名 | 稀有 | 通道数额 | p̂ 设计 | p_bot (n拍) | p_人·无R (n拍) | p_人·有R (n拍) | **p_基线 (n拍)** | 诊断 |')
    out.append('|---|---|---|---|---|---|---|---|---|---|')
    for j in jokers:
        if j.get('kind') == 'target':
            continue
        jid = j['id']
        if not j.get('effects'):
            out.append('| %s | %s | %s | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | — | 概率放大器,不入 fired |'
                       % (jid, j['cn'], j['rarity']))
            continue
        chan = ''
        for e in j.get('effects', []):
            for k, v in e.get('do', {}).items():
                chan = '%s %s' % (k, v if not isinstance(v, dict) else '…')
        dp = DESIGN_P.get(jid)
        pb = b_sum[jid] / b_cnt[jid] / 100.0 if b_cnt[jid] else None
        b0, b1 = h_beats[jid]
        f0, f1 = h_fired[jid]
        ph = f0 / b0 if b0 else None            # 无R 态是基准概率
        diag = []
        if ph is not None and b0 < 30:
            diag.append('⚠人样本薄')
        if b1 and b1 < 30:
            diag.append('⚠有R态样本薄')
        if dp and pb is not None and pb > 0 and dp[0] / max(pb, 0.001) > 2:
            diag.append('p̂≫bot:教学/结构?')
        if pb is not None and ph is not None and ph > 0.01 and pb / max(ph, 0.001) > 2:
            diag.append('bot≫人:水平相关,锚真人')
        if (pb is not None and pb < 0.05) and (ph is None or ph < 0.05):
            diag.append('☠死档(<5%)')
        # 基线列:自证不过就不出值(宁可空着,也不要一个错的大样本)
        base_cell = '—'
        if jid in BASELINE and base_n:
            ok_n, seen_n = agree[jid]
            if seen_n and ok_n < seen_n:
                diag.append('⚠判定不同源(%d/%d)' % (ok_n, seen_n))
            else:
                pb_all = base_hit[jid] / base_n
                base_cell = '**%.0f%%** (%d)' % (pb_all * 100, base_n)
                # 版本漂移:后半(较新的局)与全体差 ≥10pt 就报 —— 规则改过, 别当同一件事
                if late_n:
                    pb_late = late_hit[jid] / late_n
                    if abs(pb_late - pb_all) >= 0.10:
                        base_cell += '<br>近期 %.0f%% (%d)' % (pb_late * 100, late_n)
                        diag.append('⚠版本漂移')
                if not seen_n:
                    diag.append('基线未自证(没持有过)')
                pbase = base_hit[jid] / base_n
                if dp and pbase > 0 and dp[0] / max(pbase, 0.001) > 2:
                    diag.append('p̂≫基线')
                # 方差轴的档位判断改由**大样本**说话(numbers.md §3.2:<5% = 死档)。
                # 旧判据只看 bot/持有态两列, 而行为类卡在那两列常年 n=3~6 —— 6 拍里
                # 中 0 次和中 1 次差 17 个百分点, 那种分母判不了档。
                if pbase < 0.05:
                    diag.append('☠基线死档(<5%)')
                elif pbase > 0.95:
                    diag.append('⚑基线≈无条件(>95%),按地板定价')
        out.append('| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |' % (
            jid, j['cn'], j['rarity'], chan,
            ('%.2f(%s)' % dp if dp else '—'),
            ('%.0f%% (%d)' % (pb * 100, b_cnt[jid])) if pb is not None else '—',
            _cell(f0, b0), _cell(f1, b1), base_cell,
            ' '.join(diag) or '·'))

    out.append('\n## 规则牌 Δp(真人牌型频率两态 —— numbers.md §2 概率放大器的计价输入)\n')
    out.append('「无该牌」池 = 全部合格局里未持有该牌的拍(跨局对照,混着构筑差异,样本大了才可用);')
    out.append('有态样本 < 30 拍 ⇒ **规则牌不定价**(numbers.md §1 的封锁纪律)。\n')
    out.append('| 规则牌 | 态 | n拍 | ' + ' | '.join(name for name, _ in KIND_FAMS) + ' |')
    out.append('|---|---|---|' + '---|' * len(KIND_FAMS))
    for r in RULES:
        for st, tag in ((1, '持有'), (0, '未持有')):
            cnt = rule_kinds[r][st]
            n = sum(cnt.values())
            cells = []
            for _, fam in KIND_FAMS:
                hitn = sum(v for k, v in cnt.items() if k in fam)
                cells.append(('%.1f%%' % (hitn / n * 100)) if n else '—')
            out.append('| %s | %s | %d | %s |' % (r if st else '', tag, n, ' | '.join(cells)))

    dst = os.path.join(ROOT, 'docs/design/probbook.md')
    open(dst, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    print('→ %s(%d 局真人,bot=%s)' % (dst, runs, sim_used or '无'))


if __name__ == '__main__':
    main()
