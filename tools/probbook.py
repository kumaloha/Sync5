#!/usr/bin/env python3
"""概率账本生成器(design/numbers.md §1 的记录制度)。

    python3 tools/probbook.py [sim日志路径]

产出 design/probbook.md:每张支援卡三列概率(设计 p̂ / 仪器 p_bot / 真人 p_人)
+ 样本量 + 自动诊断。真人列扫全部合格 Tape;bot 列解析 sim 日志(可选,
没给路径就留空标注)。**probbook.md 是仪器读数,手改无效** —— 改这里。
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


def human_rates():
    beats, fired, runs = defaultdict(int), defaultdict(int), 0
    for f in glob.glob(TAPE + '/*.jsonl'):
        try:
            lines = [json.loads(l) for l in open(f)]
        except Exception:
            continue
        if not lines or lines[0].get('e') != 'run':
            continue
        evs = defaultdict(int)
        for l in lines:
            evs[l['e']] += 1
        if not (evs['intro'] > 0
                and max((l.get('ms', 0) for l in lines), default=0) > 60000
                and evs['pick'] + evs['swap'] + evs['disc'] >= 5):
            continue
        runs += 1
        held = set()
        for l in lines:
            if l['e'] in ('buy', 'repl') and 'id' in l:
                held.add(l['id'])
            elif l['e'] == 'settle':
                hit = set(l.get('fired', []))
                for j in held:
                    beats[j] += 1
                    if j in hit:
                        fired[j] += 1
    return beats, fired, runs


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


def main():
    sim_path = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('SYNC5_SIMLOG', '')
    h_beats, h_fired, runs = human_rates()
    b_sum, b_cnt, sim_used = bot_rates(sim_path)
    jokers = json.load(open(os.path.join(ROOT, 'data/jokers.json')))['jokers']

    out = []
    out.append('# 概率账本(仪器读数,手改无效 —— 重刷:`python3 tools/probbook.py <sim日志>`)\n')
    out.append('生成:%s · 真人样本:%d 局 · bot 来源:%s\n' % (
        datetime.now().strftime('%Y-%m-%d %H:%M'), runs,
        ('`%s`' % os.path.basename(sim_used)) if sim_used else '**未提供(缺 bot 列)**'))
    out.append('| id | 名 | 稀有 | 通道数额 | p̂ 设计 | p_bot (n拍) | p_人 (n拍) | 诊断 |')
    out.append('|---|---|---|---|---|---|---|---|')
    for j in jokers:
        if j.get('kind') == 'target':
            continue
        jid = j['id']
        chan = ''
        for e in j.get('effects', []):
            for k, v in e.get('do', {}).items():
                chan = '%s %s' % (k, v if not isinstance(v, dict) else '…')
        dp = DESIGN_P.get(jid)
        pb = b_sum[jid] / b_cnt[jid] / 100.0 if b_cnt[jid] else None
        ph = h_fired[jid] / h_beats[jid] if h_beats[jid] else None
        diag = []
        if ph is not None and h_beats[jid] < 30:
            diag.append('⚠人样本薄')
        if dp and pb is not None and pb > 0 and dp[0] / max(pb, 0.001) > 2:
            diag.append('p̂≫bot:教学/结构?')
        if pb is not None and ph is not None and ph > 0.01 and pb / max(ph, 0.001) > 2:
            diag.append('bot≫人:水平相关,锚真人')
        if (pb is not None and pb < 0.05) and (ph is None or ph < 0.05):
            diag.append('☠死档(<5%)')
        out.append('| %s | %s | %s | %s | %s | %s | %s | %s |' % (
            jid, j['cn'], j['rarity'], chan,
            ('%.2f(%s)' % dp if dp else '—'),
            ('%.0f%% (%d)' % (pb * 100, b_cnt[jid])) if pb is not None else '—',
            ('%.0f%% (%d)' % (ph * 100, h_beats[jid])) if ph is not None else '—',
            ' '.join(diag) or '·'))
    dst = os.path.join(ROOT, 'design/probbook.md')
    open(dst, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    print('→ %s(%d 局真人,bot=%s)' % (dst, runs, sim_used or '无'))


if __name__ == '__main__':
    main()
