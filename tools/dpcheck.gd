extends SceneTree

## ⏸ **重构:本轮整块不动**(见 [TODO.md](../TODO.md) 的 R6)。
## 这五份(`formal`/`dp`/`dpcheck`/`dpdiag`/`udp`)的骨架与统计要收进 `Stat`/`Probe`,
## **解锁条件是 S3 结案** —— 本文件与 `dpdiag` 是 S3(通关率低估 8.4pp, 主因未定位)
## **正在用的**诊断仪器,而 S3 的下一步大概率还要改它们。
## **在仪器还在用的时候改仪器**是本项目吃过亏的形状 —— 别顺手「合并一下」。

## **DP 表的样本外验证**(规格 = `design/solving.md` 第三部分)。
##   godot --headless --path . --script res://tools/dpcheck.gd
##
## 两批数据, **不同种子**:
##   批 A(不死局, 打满 24 拍)→ 录分数分布 + 段间构筑转移 → 建 DP 表
##   批 B(**真判生死**)      → 实测通关率与期望总分
##
## ⚠ **必须样本外**。拿同一批数据既建表又验证, 得到的是「表能不能记住自己」,
## 不是「表能不能预测」。这个项目栽过的同型错误:用「这一段的平均分」当分档依据
## (段总分 = 6 × 平均每拍分, 拿答案预测答案)。
##
## ⚠ 批 A 是**不死局**而批 B **判生死** —— 这不是口径不一致, 那正是要验的东西:
## DP 要从**无条件**的分数分布, 通过路径算出**幸存者条件**下的通关率。
## 两者对得上, 才说明 §3 那套链式转移是对的。

const N_BUILD := 400
const N_TEST := 250
## ⚠ 档数被**样本量**卡死:N/BANDS/拍位 = 每格样本数。150 局 3 档时 S3 的档 0 只有 8 个。
## 400 局 4 档 → 每格 ~17 个。**要更细的档必须先加样本, 不是调参能绕过的。**
const BANDS := 4

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var k: int = GameConfig.PHRASES_PER_SECTION
	var nsec: int = GameConfig.SECTIONS_PER_RUN
	var targets: Array = []
	for n in range(nsec):
		targets.append(float(Run.section_target_for(GameConfig.SECTION_TARGETS, n, "")))
	print("=== DP 表样本外验证(design/solving.md) ===")
	print("建表 %d 局(不死局) / 验证 %d 局(真判生死) · 构筑 %d 档 · 缺口 %d 档"
		% [N_BUILD, N_TEST, BANDS, DP.BINS])
	print("目标分 %s" % str(targets))

	# ── 批 A:录分 ────────────────────────────────────────
	var a := _collect(N_BUILD, 41000, false, targets)
	var cuts := _band_cuts(a["strength"], BANDS)
	var suffix := _make_suffix(a, cuts, nsec, k, targets)
	var trans := _make_trans(a, cuts, nsec, targets)
	print("\n  构筑档分界 %s" % str(cuts))
	for n in range(nsec):
		var row: Array = []
		for b in range(BANDS):
			row.append((suffix[n][b][k] as Array).size())
		print("  S%d 各档样本数(r=%d) %s" % [n + 1, k, str(row)])

	var table := DP.build(suffix, trans, targets, k)

	# ── 批 B:真判生死 ────────────────────────────────────
	var bres := _collect(N_TEST, 88000, true, targets)
	var obs_clear: float = float(bres["cleared"]) / float(N_TEST)
	var obs_score: float = _mean(bres["totals"])

	# 预测:开局空槽 ⇒ 构筑档 0, 缺口满(= T_1), 剩 K 拍
	var pred_clear: float = table.p(0, targets[0], k, 0)
	var pred_score: float = table.v(0, targets[0], k, 0)

	print("\n  ── 通关率 ──")
	print("    DP 预测 %.4f   实测 %.4f   偏差 %+.4f" % [pred_clear, obs_clear, pred_clear - obs_clear])
	var se: float = sqrt(maxf(0.0001, obs_clear * (1.0 - obs_clear)) / float(N_TEST))
	print("    实测标准误 ±%.4f  ⇒  z = %+.2f" % [se, (pred_clear - obs_clear) / maxf(0.0001, se)])
	print("  ── 期望总分 ──")
	print("    DP 预测 %.0f   实测 %.0f   相对偏差 %+.1f%%"
		% [pred_score, obs_score, (pred_score - obs_score) / maxf(1.0, obs_score) * 100.0])

	# ⚠ 语义要对齐:`table.p(n, T_n, K, b)` 是「**从第 n 段开局出发, 后面全过**」的概率,
	# 不是「到达第 n 段」的比例。拿后者去比是错的(第一版就错在这)。
	# 实测的对应量 = 「到达了第 n 段的局里, 最终通关的比例」。
	print("\n  ── 从第 n 段起的条件通关率(验**路径**, 不是验总数) ──")
	print("    段   DP 预测    实测      偏差    (实测样本数)")
	for n in range(nsec):
		# ⚠⚠ 必须按**到达第 n 段时的实际构筑档分布**加权。
		# 第一版恒用 b=0(最弱档)去查 S2-S4, 而到达 S4 的人 56% 在最强档 ——
		# 拿最弱档预测最强人群, 那一栏的数字整个无效。
		var mix := _band_mix(bres["strength"][n], cuts)
		var pr := 0.0
		for b in range(BANDS):
			pr += float(mix[b]) * table.p(n, targets[n], k, b)
		var reached: int = int((bres["reach"] as Array)[n])
		var ob: float = float((bres["clear_from"] as Array)[n]) / float(maxi(1, reached))
		print("    S%d   %.4f   %.4f   %+.4f   (n=%d, 档分布 %s)"
			% [n + 1, pr, ob, pr - ob, reached, str(mix).substr(0, 34)])
	print("\n  判据:通关率 |z| < 2 且 总分相对偏差 < 10% ⇒ 表可用;")
	print("        逐段到达率同时对上, 才说明**路径**对(不是碰巧总数对)。")
	print("\n耗时 %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()


## 跑一批。mortal=false 时打满 24 拍(建表用), true 时真判生死(验证用)。
func _collect(n_runs: int, seed_base: int, mortal: bool, targets: Array) -> Dictionary:
	var nsec: int = GameConfig.SECTIONS_PER_RUN
	var beats: Array = []        # [段][局][拍]
	var strength: Array = []     # [段][局] 段首构筑强度(事前可知)
	var reach: Array = []        # [段] 到达该段的局数
	for _s in range(nsec):
		beats.append([])
		strength.append([])
		reach.append(0)
	var totals: Array = []
	var clear_from: Array = []       # [段] 到达该段**且最终通关**的局数
	for _s in range(nsec):
		clear_from.append(0)
	var cleared := 0
	var bot := Bot.new(_rng, Report.new(n_runs, nsec))
	var lam: float = float(DB.sim()["solver"]["lam"])
	var lsamp: int = int(DB.sim()["solver"]["lam_samples"])
	var faces := {}
	for w in range(nsec):
		faces[w] = ""            # ⚠ 先无脸 —— 一次只加一个变量。脸的效应单独再验。
	for r in range(n_runs):
		_rng.seed = seed_base + r
		var per: Array = []
		var stg: Array = []
		for _s in range(nsec):
			per.append([])
			stg.append(-1.0)
		var o := RunLoop.Opts.new()
		o.rng = _rng
		o.deck_seed = r * 17 + 5
		o.faces = faces
		o.player = "perfect"
		o.lam = lam
		o.lam_samples = lsamp
		o.cfg = {"bot": "perfect", "target": "", "pivot": false}
		o.shop = true            # 开商店 —— 构筑会变, 那正是构筑档存在的理由
		o.mortal = mortal
		o.targets = targets
		o.on_begin = func(run: Run, _p: Phrase) -> void:
			if run.phrase_in_section == 0:
				stg[run.section_idx] = Draft._forward(run, null, -1, 660000 + r, 6, lam, lsamp)
		o.on_beat = func(run: Run, _p: Phrase, outcome: Dictionary, _c: Dictionary) -> void:
			(per[run.section_idx] as Array).append(float(outcome["score"]))
		var res := RunLoop.play(o, bot)
		totals.append(float(res["total"]))
		var died: int = int(res["died_at"])
		if died < 0:
			cleared += 1
		for s in range(nsec):
			if not (per[s] as Array).is_empty():
				reach[s] += 1
				if died < 0:
					clear_from[s] += 1
				beats[s].append(per[s])
				strength[s].append(float(stg[s]))
	return {"beats": beats, "strength": strength, "totals": totals,
		"cleared": cleared, "reach": reach, "clear_from": clear_from}


## 构筑强度的分档边界(在**批 A** 上定, 用到批 B —— 训练/测试分离)。
func _band_cuts(strength: Array, q: int) -> Array:
	var all: Array = []
	for col in strength:
		all.append_array(col)
	all.sort()
	var cuts: Array = []
	for i in range(1, q):
		cuts.append(float(all[clampi(int(float(i) * float(all.size()) / float(q)), 0, all.size() - 1)]))
	return cuts


func _band_of(v: float, cuts: Array) -> int:
	for i in range(cuts.size()):
		if v < float(cuts[i]):
			return i
	return cuts.size()


## suffix[n][b][r] = 「还剩 r 拍时, **后续 r 拍的总分**」的样本。
##
## ⚠⚠ **这是这次改动的全部** —— 不再从单拍分布卷积。卷积等于假设各拍独立,
## 而实测那个假设是错的(通关率系统性低估 8.5 个百分点, 加样本加档数都修不掉)。
## 直接录后缀和, 拍间的一切相关(负相关、构筑漂移)都天然包含在里面。
##
## ⚑ 顺带一个好处:**一局一段能贡献 K 个观测**(每个 r 一个), 不是 1 个 ——
## 样本量直接多一个量级, 而这正是分更多构筑档所需要的。
func _make_suffix(a: Dictionary, cuts: Array, nsec: int, k: int, targets: Array) -> Array:
	var out: Array = []
	for n in range(nsec):
		var per_b: Array = []
		for _b in range(BANDS):
			var per_r: Array = []
			for _r in range(k + 1):
				per_r.append([])
			per_b.append(per_r)
		out.append(per_b)
	for n in range(nsec):
		var runs: Array = a["beats"][n]
		var stg: Array = a["strength"][n]
		for i in range(runs.size()):
			if not _alive(a, i, n, targets):
				continue          # ⚠ 这局本该在前面某段就死了, 它在这一段的数据是幻影
			var b: int = _band_of(float(stg[i]), cuts)
			var rb: Array = runs[i]
			# 后缀和:剩 r 拍 ⇒ 从第 (len−r) 拍加到末尾
			var acc := 0.0
			for r in range(1, mini(rb.size(), k) + 1):
				acc += float(rb[rb.size() - r])
				(out[n][b][r] as Array).append(acc)
	return out


## trans[n][b] = 段末从档 b 转到各档的概率。⚠ 这一段的档 → 下一段的档, 逐局配对。
func _make_trans(a: Dictionary, cuts: Array, nsec: int, targets: Array) -> Array:
	var out: Array = []
	for n in range(nsec):
		var rows: Array = []
		for _b in range(BANDS):
			var row: Array = []
			for _b2 in range(BANDS):
				row.append(0.0)
			rows.append(row)
		out.append(rows)
	for n in range(nsec - 1):
		var s0: Array = a["strength"][n]
		var s1: Array = a["strength"][n + 1]
		var cnt: Array = []
		for _b in range(BANDS):
			cnt.append(0.0)
		for i in range(mini(s0.size(), s1.size())):
			# ⚠ 转移必须**条件于「活到第 n 段且本段达标」** —— 只有达标的人才走得到下一段。
			# 无条件统计会把「没达标的局的构筑变化」也算进去, 而它们根本不该有下一段。
			if not _alive(a, i, n + 1, targets):
				continue
			var b0: int = _band_of(float(s0[i]), cuts)
			var b1: int = _band_of(float(s1[i]), cuts)
			out[n][b0][b1] += 1.0
			cnt[b0] += 1.0
		for b in range(BANDS):
			if cnt[b] > 0.0:
				for b2 in range(BANDS):
					out[n][b][b2] = float(out[n][b][b2]) / float(cnt[b])
			else:
				# 这一档没样本 —— 退化成"留在原档", 并且这件事本身值得看见
				out[n][b][b] = 1.0
	return out


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())


## 一批局在某段的构筑档分布(用于按档加权查表)。
func _band_mix(strength: Array, cuts: Array) -> Array:
	var m: Array = []
	for _b in range(BANDS):
		m.append(0.0)
	if strength.is_empty():
		m[0] = 1.0
		return m
	for v in strength:
		m[_band_of(float(v), cuts)] += 1.0
	for b in range(BANDS):
		m[b] = float(m[b]) / float(strength.size())
	return m

## ⚑ **第 i 局活到第 n 段了吗** —— 前 n 段全部达标。
##
## ⚠⚠ 这是修「幸存者偏差」的核心。批 A 是**不死局**(打满 24 拍), 里面包含了那些
## **在 S1 就该死**的局在 S2/S3/S4 的表现。而真判生死时它们早已出局, 不该贡献数据。
## 不过滤 = 拿「含弱者」的分布去预测「只剩强者」的情形 ⇒ **系统性低估通关率**。
##
## 实测证据(400 局 4 档): 逐段偏差 −0.090 / −0.086 / −0.075 / −0.047 **单调递减**,
## 而 S4 是唯一没有段间转移的段 —— **偏差随段间转移次数累积**, 正是幸存者偏差的签名。
func _alive(a: Dictionary, i: int, n: int, targets: Array) -> bool:
	for m in range(n):
		var runs: Array = a["beats"][m]
		if i >= runs.size():
			return false
		var sec := 0.0
		for v in (runs[i] as Array):
			sec += float(v)
		if sec < float(targets[m]):
			return false
	return true
