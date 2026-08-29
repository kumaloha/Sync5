#!/usr/bin/env python3
"""τ 读数器 —— 真人 Tape 里的**时间**(2026-08-28 用户「小丑牌的条件没有考虑时间问题」)。

    python3 tools/tau.py

`docs/design/solving.md §3` 的玩家参数 θ=⟨λ, τ, ε, d⟩ 里,`τ`(动作耗时向量)一直写着
「默认 0 · 待 Tape 量」,于是**所有倍率的概率口径都是 τ=0(无手速限制)下算的**。
它其实一直能量:Tape 的每个动作事件都带 `at` = **拍内经过秒数**(view/phrase.gd 打的),
不用自己算 ms 差。本工具只读 Tape、只出读数,**不碰任何定价**。

四张表,各回答一个问题:
  ① τ 分量与认知时间 —— 8 秒到底被什么吃掉了
  ② 熟练度趋势 —— ⚑ **判据**:随熟练下降 = 可读性/教学问题;不下降 = 结构性难度,该进定价
                   (CLAUDE.md 那条「实测远低于组合概率 ⇒ 倍率治不了它」针对的是前者)
  ③ 每拍动作构成 —— 实际弃牌张数 vs 定价用的 b
  ④ 按持有 Target 分组的命中率 —— **干净口径**:按「装了哪张 Target」分组 = 玩家有动机
     追那个型。按结算牌型分组会有选择偏差(追砸的拍算进低牌型),不要那样比。

合格局判据与 `tools/probbook.py::_qualified` **同一份**(教学关与探针会话不算)。
⚠ 样本薄的族要看标准误再下结论 —— 阶梯常年只有十几拍。
"""
import glob
import json
import math
import os
import statistics as st
import time
from collections import defaultdict

TAPE = os.path.expanduser(
    '~/Library/Application Support/Godot/app_userdata/Sync5 · Project Rhythm/tape')

# 动作事件(core/tape.gd 事件表)。sort=理牌 / pick=点选 / disc=弃牌 / swap=对调。
ACTIONS = ('pick', 'disc', 'swap', 'sort')

# Target → (显示名, 它覆盖的 Pattern.Kind)。改 jokers.json 的覆盖面要同步这里。
TARGETS = {
    'twin': ('双子', {1, 2}),
    'triplet': ('三连音', {3, 6, 7}),
    'mono': ('单色', {5, 8, 9}),
    'stair': ('阶梯', {4, 8, 9}),
}
KINDS = ['高牌', '对子', '两对', '三条', '顺子', '同花', '葫芦', '四条', '同花顺', '皇家']


def qualified(lines):
    """与 probbook.py 同一份合格判据 —— 两个工具的分母必须一样。"""
    if not lines or lines[0].get('e') != 'run':
        return False
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


def load_runs():
    out = []
    for f in glob.glob(TAPE + '/*.jsonl') + glob.glob(TAPE + '/sent/*.jsonl'):
        try:
            lines = [json.loads(l) for l in open(f)]
        except Exception:
            continue
        if qualified(lines):
            out.append((os.path.getmtime(f), f, lines))
    out.sort()
    return out


def beats_of(lines):
    """切拍。每拍 → {'dur', 'acts': [(事件名, at)], 'kind', 'held': set}。

    `held` 是**结算那一刻**持有的小丑牌(buy 加 / repl 换),与 probbook 同口径。
    """
    held = set()
    cur = None
    for l in lines:
        e = l['e']
        if e == 'buy' and 'id' in l:
            held.add(l['id'])
        elif e == 'repl':
            held.discard(l.get('out', ''))
            if l.get('in'):
                held.add(l['in'])
        elif e == 'beat':
            cur = {'dur': float(l.get('dur', 8.0)), 'acts': [], 'discn': 0}
        elif e in ACTIONS and cur is not None and 'at' in l:
            cur['acts'].append((e, float(l['at'])))
            if e == 'disc':
                cur['discn'] += int(l.get('k', 1))
        elif e == 'settle' and cur is not None:
            k = l.get('kind', -1)
            cur['kind'] = k if isinstance(k, int) and 0 <= k < 10 else -1
            cur['held'] = set(held)
            yield cur
            cur = None


def se(xs):
    return st.stdev(xs) / math.sqrt(len(xs)) if len(xs) > 1 else float('nan')


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(p * len(xs)))] if xs else float('nan')


def main():
    runs = load_runs()
    if not runs:
        print('没有合格的真人 Tape(%s)' % TAPE)
        return
    all_beats = [(mt, b) for mt, _f, ls in runs for b in beats_of(ls)]
    print('合格真人局 %d · 拍 %d\n' % (len(runs), len(all_beats)))

    # ---- ① τ 分量与认知时间 ----
    gaps = defaultdict(list)
    first, last, nact = [], [], []
    for _mt, b in all_beats:
        ats = [a[1] for a in b['acts']]
        if not ats:
            continue
        first.append(ats[0])
        last.append(ats[-1])
        nact.append(len(ats))
        for i in range(1, len(ats)):
            gaps[b['acts'][i][0]].append(ats[i] - ats[i - 1])
    print('① τ 分量与认知时间(%d 个有动作的拍)' % len(first))
    print('   认知(开拍→首个动作)  中位 %.2fs · 均值 %.2fs · p90 %.2fs'
          % (st.median(first), st.mean(first), pct(first, 0.9)))
    print('   末动作时刻            中位 %.2fs · p90 %.2fs'
          % (st.median(last), pct(last, 0.9)))
    for k in ACTIONS:
        if gaps[k]:
            print('   τ_%-5s n=%-4d 中位 %.2fs · 均值 %.2fs · p90 %.2fs'
                  % (k, len(gaps[k]), st.median(gaps[k]), st.mean(gaps[k]), pct(gaps[k], 0.9)))

    # ---- ② 熟练度趋势(判据) ----
    half = len(runs) // 2
    print('\n② 熟练度趋势 —— ⚑ 认知时间随熟练**下降 = 教学问题;不降 = 结构性难度**')
    for label, grp in (('前半', runs[:half]), ('后半', runs[half:])):
        F, N = [], []
        for mt, _f, ls in grp:
            for b in beats_of(ls):
                ats = [a[1] for a in b['acts']]
                if ats:
                    F.append(ats[0])
                    N.append(len(ats))
        if not F:
            continue
        d0 = time.strftime('%m-%d', time.localtime(grp[0][0]))
        d1 = time.strftime('%m-%d', time.localtime(grp[-1][0]))
        print('   %s %s~%s  %2d 局 %3d 拍   认知 %.2f ±%.2fs   动作数 %.1f'
              % (label, d0, d1, len(grp), len(F), st.mean(F), se(F), st.mean(N)))

    # ---- ③ 每拍动作构成 vs 定价用的 b ----
    comp = defaultdict(float)
    disc_cards = 0
    tau = {k: st.median(gaps[k]) for k in ACTIONS if gaps[k]}
    for _mt, b in all_beats:
        for e, _at in b['acts']:
            comp[e] += 1
        disc_cards += b['discn']
    n = len(all_beats)
    spent = sum(comp[e] / n * tau.get(e, 0.0) for e in ACTIONS)
    print('\n③ 每拍动作构成(次/拍)')
    print('   ' + ' · '.join('%s %.1f' % (e, comp[e] / n) for e in ACTIONS))
    print('   动作耗时 %.2fs + 认知 %.2fs = **%.2fs / 8s**'
          % (spent, st.median(first), spent + st.median(first)))
    print('   ⚑ 每拍实际弃牌 **%.2f 张** —— 先验层定价用的 b 要和这个数对得上'
          % (disc_cards / n))

    # ---- ④ 按持有 Target 分组的命中率(干净口径) ----
    print('\n④ 按持有 Target 分组的命中率(⚑ 干净口径:按意图分组,不按结算牌型分组)')
    print('   %-8s %6s %14s %10s' % ('Target', '拍数', '命中率', '认知(s)'))
    for tid, (cn, cov) in TARGETS.items():
        held_beats = [b for _mt, b in all_beats if tid in b.get('held', ())]
        if not held_beats:
            print('   %-8s %6d %14s %10s' % (cn, 0, '—', '—'))
            continue
        hit = sum(1 for b in held_beats if b['kind'] in cov)
        p = hit / len(held_beats)
        sep = math.sqrt(p * (1 - p) / len(held_beats))
        F = [b['acts'][0][1] for b in held_beats if b['acts']]
        print('   %-8s %6d %7.0f%% ±%-4.0f%% %10.2f'
              % (cn, len(held_beats), 100 * p, 100 * sep,
                 st.mean(F) if F else float('nan')))

    # 结算牌型分布(P(≥k) 那一列是先验层对账用的)
    kc = defaultdict(int)
    for _mt, b in all_beats:
        if b['kind'] >= 0:
            kc[b['kind']] += 1
    tot = sum(kc.values())
    if tot:
        print('\n   全局结算牌型(n=%d) —— ⚠ 与先验层对账要注意口径:' % tot)
        print('   先验层按「8 张选 5」算,而 core/phrase.gd::_scoring_cards() 默认只有手牌 5 张')
        cum = 0
        for k in range(9, -1, -1):
            cum += kc[k]
            if kc[k] or cum:
                print('     %-5s %4d 拍  P(=)%5.1f%%  P(≥)%5.1f%%'
                      % (KINDS[k], kc[k], 100 * kc[k] / tot, 100 * cum / tot))


if __name__ == '__main__':
    main()
