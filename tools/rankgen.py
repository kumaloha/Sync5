#!/usr/bin/env python3
"""data/ranking.json 生成器(Director 的脸难度排序, 2026-08-18)。

    python3 tools/rankgen.py <price.log 路径>

从 tools/price.gd 的输出日志里取那行 JSON(键 = 脸@段号, 0 起), 每段按「由易到难」排序
(sec 口径:0 附近 = 温和, 越负越狠), 写 data/ranking.json。**手改无效, 重跑本脚本刷新。**

两处设计性覆盖(与 docs/design/blinds.md 的仪器盲区一致, 不是数据造假):
1. **时间族**(weak_upper_bound 里 time_penalty>0 或纯时窗的脸):求解器没有手速,
   价格恒 ≈0 会被误排成「最温和」—— 而它们对真人是硬压力。按设计放到该段**最狠端**。
2. **raisedbar**:改目标分不改分数, 价格表里没有它。难度 = 目标 ×1.5, 放最狠端。
"""
import json, re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
log = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8', errors='replace')

m = None
for line in log.splitlines():
    line = line.strip()
    if line.startswith('{') and '@' in line:
        try:
            m = json.loads(line)
        except Exception:
            pass
if m is None:
    # 退路(2026-08-19):price.gd 全表在 S10 税下要 10h 级, 第一版排序改吃
    # **全量门的脸覆盖读数**(同一把完美玩家尺子, 每脸一行分差)。
    # 行形如:`  lowend   -332.3  ±100.2  z = -3.31  4.0%  ✓ 量到了`
    # 段号用 faces.json 的 tier(现役全部单轮, 1 起 → 0 起)。精修版以后用 price 重刷。
    faces_tmp = json.loads((ROOT / 'data' / 'faces.json').read_text())
    tier_of = {f['id']: int(f.get('tier', 0)) - 1 for f in faces_tmp['faces']}
    m = {}
    pat = re.compile(r'^\s{4}(\w+)(?::[^|]*)?\s+([+-]?\d+(?:\.\d+)?)\s+±')
    for line in log.splitlines():
        mm = pat.match(line)
        if not mm:
            continue
        fid, delta = mm.group(1), float(mm.group(2))
        if fid not in tier_of or tier_of[fid] < 0:
            continue
        key = '%s@%d' % (fid, tier_of[fid])
        if key not in m:      # 同脸多行(证物率/分差)只取第一条分差行
            m[key] = delta
assert m, '日志里既没有价格 JSON 也没有门的脸覆盖行'

faces = json.loads((ROOT / 'data' / 'faces.json').read_text())
wub = set(faces.get('weak_upper_bound', []))
time_family = set()
by_id = {}
for f in faces['faces']:
    by_id[f['id']] = f
    p = f.get('params', {})
    if f['id'] in wub and (float(p.get('time_penalty', 0)) > 0
            or any(k in p for k in ('discard_lock_last', 'swap_lock_last'))):
        time_family.add(f['id'])

# 每段收集 (id, price)。价格值可能是数或 {sec, run} 字典 —— 排序用 sec 口径。
secs = {0: [], 1: [], 2: [], 3: []}
for key, val in m.items():
    fid, sec = key.rsplit('@', 1)
    sec = int(sec)
    v = val
    if isinstance(val, dict):
        v = val.get('sec', val.get('run', 0))
    secs[sec].append((fid, float(v)))

out = {}
for sec, rows in secs.items():
    # raisedbar 无论仪器给了什么数都剔除 —— 它不改分数, 在分差尺上恒 ≈0,
    # 会被误排成温和;真实难度 = 目标 ×1.5(另一个量纲), 按设计压最狠端。
    rows = [(f, v) for f, v in rows if f != 'raisedbar']
    normal = [(f, v) for f, v in rows if f not in time_family]
    harsh_override = [f for f, _ in rows if f in time_family]
    # 由易到难:损失少(接近 0)在前, 越负越后
    ordered = [f for f, _ in sorted(normal, key=lambda t: -t[1])]
    ordered += harsh_override                     # 时间族压最狠端(盲区覆盖①)
    # ⚠ faces.json 的 tier 是 1 起, 段号 0 起 —— 差一位就把脸塞进邻段(踩过当场修)
    tier_pool = [f['id'] for f in faces['faces']
                 if (sec + 1) in ([f.get('tier')] if 'tier' in f else f.get('tiers', []))]
    if 'raisedbar' in tier_pool:
        ordered.append('raisedbar')               # 覆盖②:改目标分, 最狠端
    # ⚠⚠ 兜底(2026-08-20 补, trilogy 事故):**池里有、表里没的脸一律压最狠端**。
    # 起因 = trilogy 与 raisedbar 同族(改目标分, 仪器盲区), 但覆盖②只点了 raisedbar 的名,
    # trilogy 被静默丢出排序表 —— Director 取交后这张脸**永不登场且不报错**。
    # 点名规则改成结构规则:凡是仪器没给数的池脸, 按「仪器量不到 = 该族的已知形状 =
    # 真实难度在另一个量纲」处理, 压最狠端并打印出来;db::validate_ranking 同时加了
    # 反向完备性校验, 这类丢脸从此是测试期红灯。
    for fid in tier_pool:
        if fid not in ordered:
            ordered.append(fid)
            print(f'  ⚠ {fid}@S{sec + 1} 仪器无读数 → 设计性压最狠端(盲区兜底)')
    out[str(sec)] = ordered

doc = {'_comment': '⚑ 仪器输出(tools/price.gd → tools/rankgen.py), 手改无效。'
       '每段由易到难;时间族与 raisedbar 是设计性覆盖(理由在本脚本头与 blinds.md 仪器盲区节)。'
       'core/db.gd::validate_ranking 守四段齐全 + id 都是活脸 + **池脸都在表里**(反向完备性, trilogy 事故后加)—— 脸池一变这里就红。',
       **{k: out[k] for k in sorted(out)}}
(ROOT / 'data' / 'ranking.json').write_text(
    json.dumps(doc, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
print('data/ranking.json written:')
for k in sorted(out):
    print(' ', k, out[k])
