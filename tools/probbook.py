#!/usr/bin/env python3
"""概率账本生成器(design/numbers.md §1 的记录制度)。

    python3 tools/probbook.py [sim日志路径]

产出 design/probbook.md:每张支援卡三列概率(设计 p̂ / 仪器 p_bot / 真人 p_人)
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


def _qualified(lines):
    if not lines or lines[0].get('e') != 'run':
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
    for f in glob.glob(TAPE + '/*.jsonl'):
        try:
            lines = [json.loads(l) for l in open(f)]
        except Exception:
            continue
        if not _qualified(lines):
            continue
        runs += 1
        held = set()
        for l in lines:
            e = l['e']
            if e == 'buy' and 'id' in l:
                held.add(l['id'])
            elif e == 'repl':
                # 满槽替换:in 换进 / out 换出(core/tape.gd 事件表)
                held.discard(l.get('out', ''))
                if l.get('in'):
                    held.add(l['in'])
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
    return beats, fired, rule_kinds, runs


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
    h_beats, h_fired, rule_kinds, runs = human_rates()
    b_sum, b_cnt, sim_used = bot_rates(sim_path)
    jokers = json.load(open(os.path.join(ROOT, 'data/jokers.json')))['jokers']

    out = []
    out.append('# 概率账本(仪器读数,手改无效 —— 重刷:`python3 tools/probbook.py <sim日志>`)\n')
    out.append('生成:%s · 真人样本:%d 局 · bot 来源:%s' % (
        datetime.now().strftime('%Y-%m-%d %H:%M'), runs,
        ('`%s`' % os.path.basename(sim_used)) if sim_used else '**未提供(缺 bot 列)**'))
    out.append('真人列两态:**无R** = 未持有任何规则牌(近道/四指/双色调/百搭)的拍,'
               '**有R** = 持有的拍。bot 列未拆态(仪器债)。\n')
    out.append('| id | 名 | 稀有 | 通道数额 | p̂ 设计 | p_bot (n拍) | p_人·无R (n拍) | p_人·有R (n拍) | 诊断 |')
    out.append('|---|---|---|---|---|---|---|---|---|')
    for j in jokers:
        if j.get('kind') == 'target':
            continue
        jid = j['id']
        if not j.get('effects'):
            out.append('| %s | %s | %s | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |'
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
        out.append('| %s | %s | %s | %s | %s | %s | %s | %s | %s |' % (
            jid, j['cn'], j['rarity'], chan,
            ('%.2f(%s)' % dp if dp else '—'),
            ('%.0f%% (%d)' % (pb * 100, b_cnt[jid])) if pb is not None else '—',
            _cell(f0, b0), _cell(f1, b1),
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

    dst = os.path.join(ROOT, 'design/probbook.md')
    open(dst, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    print('→ %s(%d 局真人,bot=%s)' % (dst, runs, sim_used or '无'))


if __name__ == '__main__':
    main()
