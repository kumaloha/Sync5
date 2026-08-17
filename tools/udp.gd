extends SceneTree

## ⏸ **重构:本轮整块不动**(见 [TODO.md](../TODO.md) 的 R6)。
## 这五份(`formal`/`dp`/`dpcheck`/`dpdiag`/`udp`)的骨架与统计要收进 `Stat`/`Probe`,
## **解锁条件是 S3 结案** —— `dpdiag`/`dpcheck` 是 S3(通关率低估 8.4pp, 主因未定位)
## **正在用的**诊断仪器,而 S3 的下一步大概率还要改它们。
## **在仪器还在用的时候改仪器**是本项目吃过亏的形状 —— 别顺手「合并一下」。

## **`U` 表 —— 「还差 g 分、还剩 r 拍，能过的概率」**(docs/design/solving.md 第三部分)。
##   godot --headless --path . --script res://tools/udp.gd
##
## ## 这一步在验什么
##
## 新的求解目标是**最大化通过率**而不是最大化分数(用户 2026-08-08:
## 「有压力就要全力以赴, 如果没压力就可以留一些余力为未来的更难的盲注做准备」)。
## 那个目标函数的核心就是这张表:
##
##     U(g, r) = Σ_s  p(s) · U(g − s, r − 1)
##     边界: U(g ≤ 0, ·) = 1     U(g > 0, 0) = 0
##
## **它同时是生成器的全部** —— 目标分 T 只是初始的 g, 所以一次 DP 出整条曲线,
## 反解 T = U⁻¹(想要的通过率) **是查表, 免费**(docs/design/solver_roadmap.md 原本的理由)。
##
## ## ⚠⚠ 这个探针要暴露的是 DP 的核心近似
##
## 上面那个递推假设**每拍分数独立同分布**。而真实数据里同一局的各拍是**相关**的:
## 构筑相同、牌堆相关、脸相同。所以 DP 预测的通过率会和实测有偏差 ——
## **这个偏差的大小就是「能不能用 DP」的答案**, 不是可以假设的。
##
## 判据(本项目铁律:显著 **且** 量级够):
##   · |U 预测 − 实测| 的量级 —— 大到多少就说明独立同分布不成立
##   · 偏差的**方向** —— 正相关会让实际方差比 DP 以为的大, 即 DP **高估**中间档的通过率
##
## ⚠ 不许因为想要哪个结论就调离散化的档数。先跑, 再看。

const N_RUNS := 200        # 录分的局数
const BINS := 240          # 缺口 g 的离散档数
## ⚠ 3 档不是 5 档:D 要在**档内再按拍位**切, 样本会被切两次
## (200 局 / 3 档 / 6 拍位 ≈ 67 个样本/格)。档太多会让直方图变尖、DP 失真。
const QBANDS := 3      # 构筑强度分几档
const PROBE_QS: Array[float] = [0.1, 0.25, 0.5, 0.75, 0.9]   # 拿分数分位数当候选目标分

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	print("=== U 表:DP 预测 vs 实测(docs/design/solving.md 第三部分) ===")
	print("N=%d 局(不死局), 缺口离散 %d 档" % [N_RUNS, BINS])
	# 三个场景, 风险从低到高。**一次只加一个变量** —— 混着加就分不清偏差是谁造成的。
	# ①② 已验过(偏差均值 +0.002, 在噪声内)。这一轮只打 ③ —— 唯一破掉的那个。
	_scenario("③ 有脸有商店", true, true)
	print("\n耗时 %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()


func _scenario(name: String, with_faces: bool, with_shop: bool) -> void:
	print("\n────────── %s ──────────" % name)

	# ── 录分:每段、每局、每拍 ────────────────────────────────
	var beat_scores: Array = []      # [段][局][拍]
	var sec_totals: Array = []       # [段][局]
	var strength: Array = []          # [段][局] 段首的构筑强度(事前可知)
	for _s in range(GameConfig.SECTIONS_PER_RUN):
		beat_scores.append([])
		sec_totals.append([])
		strength.append([])
	var faces := {}
	for w in range(GameConfig.SECTIONS_PER_RUN):
		# ⚠ 一次只加一个变量:先无脸验 DP 本身, 再加脸, 最后加商店。
		faces[w] = "" if not with_faces else String(SectionMod.pool_for(w)[0])
	var bot := Bot.new(_rng, Report.new(N_RUNS, GameConfig.SECTIONS_PER_RUN))
	for r in range(N_RUNS):
		_rng.seed = 31000 + r
		var per_sec: Array = []
		for _s in range(GameConfig.SECTIONS_PER_RUN):
			per_sec.append([])
		var o := RunLoop.Opts.new()
		o.rng = _rng
		o.deck_seed = r * 17 + 5
		o.faces = faces
		o.player = "perfect"
		o.lam = float(DB.sim()["solver"]["lam"])
		o.lam_samples = int(DB.sim()["solver"]["lam_samples"])
		o.cfg = {"bot": "perfect", "target": "", "pivot": false}
		o.shop = with_shop           # 开了商店构筑就会中途变 —— 那正是 iid 会破的地方
		o.mortal = false             # 不死局:每段都要有分数, 否则后面的段没数据
		o.on_beat = func(run: Run, _p: Phrase, outcome: Dictionary, _ctx: Dictionary) -> void:
			(per_sec[run.section_idx] as Array).append(float(outcome["score"]))
		# ⚑ **事前可知**的构筑强度:段首推演几拍看这个局面能打多少。
		# ⚠ 绝不能用「这一段的平均分」当分档依据 —— 段总分 = 6 × 平均每拍分,
		# 那是**拿答案预测答案**, 偏差当然归零, 但表对新配置毫无预测力。
		# 这里用的是段首状态 + 独立随机数, 中间还隔着 6 拍的随机性, 不构成泄露。
		o.on_begin = func(run: Run, _p: Phrase) -> void:
			if run.phrase_in_section == 0:
				(strength[run.section_idx] as Array).append(
					Draft._forward(run, null, -1, 770000 + r, 6,
						float(DB.sim()["solver"]["lam"]),
						int(DB.sim()["solver"]["lam_samples"])))
		var res := RunLoop.play(o, bot)
		for s in range(GameConfig.SECTIONS_PER_RUN):
			beat_scores[s].append(per_sec[s])
			sec_totals[s].append(float(res["sec_scores"][s]))

	# ── 逐段:建 U 表, 和实测对账 ──────────────────────────
	print("")
	print("  段  候选目标分   A混合  偏差      B按拍位 偏差       实测")
	var worst := 0.0
	var worst_pos := 0.0
	var worst_c := 0.0
	var worst_d := 0.0
	var sum_mix := 0.0
	var sum_pos := 0.0
	var sum_c := 0.0
	var sum_d := 0.0
	var rows := 0
	for s in range(GameConfig.SECTIONS_PER_RUN):
		var flat: Array = []
		for run_beats in beat_scores[s]:
			flat.append_array(run_beats)
		if flat.is_empty():
			continue
		var hi: float = _quantile(sec_totals[s], 0.99)
		var step: float = maxf(1.0, hi / float(BINS))
		# 建表法 A(mixed):全段的拍混在一起 —— 假设**同分布**
		var u_mix := _build_u(flat, step, GameConfig.PHRASES_PER_SECTION)
		# 建表法 B(bypos):**按拍位**建分布 —— 不假设同分布, 自动吸收
		# 「构筑随拍位增强」(段中商店买了牌, 后几拍就更强)。
		var by_pos: Array = []
		for k in range(GameConfig.PHRASES_PER_SECTION):
			var col: Array = []
			for run_beats in beat_scores[s]:
				if k < (run_beats as Array).size():
					col.append(float((run_beats as Array)[k]))
			by_pos.append(col)
		var u_pos := _build_u_bypos(by_pos, step)
		# 建表法 C:**按构筑强度分档**, 每档一张表, 再对档次取期望。
		# 这是 E_J[U(g|J)] 而不是 U(g|混合分布) —— 两者不等(Jensen), 实测那 +0.026 就是这个差。
		var bands := _band_by_strength(strength[s], beat_scores[s], QBANDS)
		for q in PROBE_QS:
			var tgt: float = _quantile(sec_totals[s], q)
			var obs: float = _rate_ge(sec_totals[s], tgt)
			var pm: float = _lookup(u_mix, tgt, step)
			var pp: float = _lookup(u_pos, tgt, step)
			var pc := 0.0
			var pd := 0.0
			for band in bands:
				pc += float(band["w"]) * _lookup(
					_build_u(band["scores"], step, GameConfig.PHRASES_PER_SECTION), tgt, step)
				# D = C × B:档内再按拍位。两种相关是**不同的东西**, 各修各的:
				#   拍位效应 —— 段中商店买了牌, 后几拍变强(S1 最明显, 开局空槽)
				#   局间效应 —— 这一局整体构筑强弱(S2-S4 最明显)
				pd += float(band["w"]) * _lookup(
					_build_u_bypos(band["bypos"], step), tgt, step)
			print("  S%d %8.0f  A%+6.3f  B%+6.3f  C%+6.3f  D%+6.3f   实测 %.3f"
				% [s + 1, tgt, pm - obs, pp - obs, pc - obs, pd - obs, obs])
			worst = maxf(worst, absf(pm - obs))
			worst_pos = maxf(worst_pos, absf(pp - obs))
			worst_c = maxf(worst_c, absf(pc - obs))
			worst_d = maxf(worst_d, absf(pd - obs))
			sum_mix += pm - obs
			sum_pos += pp - obs
			sum_c += pc - obs
			sum_d += pd - obs
			rows += 1
	print("  ── A混合  最大|偏差| %.3f  偏差均值 %+.4f" % [worst, sum_mix / maxf(1.0, float(rows))])
	print("  ── B按拍位   最大|偏差| %.3f  偏差均值 %+.4f" % [worst_pos, sum_pos / maxf(1.0, float(rows))])
	print("  ── C按构筑分档   最大|偏差| %.3f  偏差均值 %+.4f" % [worst_c, sum_c / maxf(1.0, float(rows))])
	print("  ── D构筑×拍位    最大|偏差| %.3f  偏差均值 %+.4f  ← 判据:能不能回到 ~0.003"
		% [worst_d, sum_d / maxf(1.0, float(rows))])


## DP:U[r][i] = 还差 i 档、还剩 r 拍时的过关概率。
## ⚠ 分数分布直接用**录到的经验分布**(不拟合任何参数形式)——
## 拟合会引入一个我们无法验证的假设, 而经验分布是事实。
func _build_u(scores: Array, step: float, max_r: int) -> Array:
	# 分数也离散到同一把尺子上
	var hist := {}
	for v in scores:
		var b: int = int(round(float(v) / step))
		hist[b] = float(hist.get(b, 0.0)) + 1.0
	var n := float(scores.size())
	for k in hist:
		hist[k] = hist[k] / n
	var u: Array = []
	var zero: Array = []
	zero.resize(BINS + 1)
	for i in range(BINS + 1):
		zero[i] = 0.0          # 还剩 0 拍且缺口 > 0 → 过不去
	u.append(zero)
	for r in range(1, max_r + 1):
		var prev: Array = u[r - 1]
		var cur: Array = []
		cur.resize(BINS + 1)
		for i in range(BINS + 1):
			var acc := 0.0
			for b in hist:
				var j: int = i - int(b)
				# 缺口 ≤ 0 → 已经过了, 概率 1
				acc += float(hist[b]) * (1.0 if j <= 0 else float(prev[mini(j, BINS)]))
			cur[i] = acc
		u.append(cur)
	return u


## 按拍位建表:第 r 步用的是**倒数第 r 拍**的分数分布, 不是全段混合。
## 这样不需要「同分布」这个假设, 只需要「不同拍之间独立」。
## ⚠ 商店开着时构筑会中途变强, 后几拍的分布明显不同 —— A 混合会因此失真。
func _build_u_bypos(by_pos: Array, step: float) -> Array:
	var hists: Array = []
	for col in by_pos:
		var h := {}
		for v in col:
			var b: int = int(round(float(v) / step))
			h[b] = float(h.get(b, 0.0)) + 1.0
		var n := float(maxi(1, (col as Array).size()))
		for k in h:
			h[k] = h[k] / n
		hists.append(h)
	var u: Array = []
	var zero: Array = []
	zero.resize(BINS + 1)
	for i in range(BINS + 1):
		zero[i] = 0.0
	u.append(zero)
	var kk: int = by_pos.size()
	for r in range(1, kk + 1):
		# 还剩 r 拍 → 现在打的是第 (kk - r) 拍(0-based)
		var hist: Dictionary = hists[kk - r]
		var prev: Array = u[r - 1]
		var cur: Array = []
		cur.resize(BINS + 1)
		for i in range(BINS + 1):
			var acc := 0.0
			for b in hist:
				var j: int = i - int(b)
				acc += float(hist[b]) * (1.0 if j <= 0 else float(prev[mini(j, BINS)]))
			cur[i] = acc
		u.append(cur)
	return u


func _lookup(u: Array, gap: float, step: float) -> float:
	var i: int = clampi(int(round(gap / step)), 0, BINS)
	return float((u[u.size() - 1] as Array)[i])


func _rate_ge(vals: Array, t: float) -> float:
	var c := 0.0
	for v in vals:
		if float(v) >= t:
			c += 1.0
	return c / float(maxi(1, vals.size()))


func _quantile(vals: Array, q: float) -> float:
	var a: Array = vals.duplicate()
	a.sort()
	var i: int = clampi(int(floor(q * float(a.size() - 1))), 0, a.size() - 1)
	return float(a[i])


## 按**事前可知**的构筑强度把局分档, 每档给出该档的全部拍分数 + 权重。
func _band_by_strength(strengths: Array, per_run_beats: Array, q: int) -> Array:
	var idx: Array = []
	for i in range(strengths.size()):
		idx.append(i)
	idx.sort_custom(func(a, b): return float(strengths[a]) < float(strengths[b]))
	var out: Array = []
	var n := idx.size()
	for k in range(q):
		var lo: int = int(floor(float(k) * float(n) / float(q)))
		var hi: int = int(floor(float(k + 1) * float(n) / float(q)))
		var sc: Array = []
		var bp: Array = []
		for _k in range(GameConfig.PHRASES_PER_SECTION):
			bp.append([])
		for t in range(lo, hi):
			if idx[t] < per_run_beats.size():
				var rb: Array = per_run_beats[idx[t]]
				sc.append_array(rb)
				for kk2 in range(rb.size()):
					if kk2 < bp.size():
						(bp[kk2] as Array).append(float(rb[kk2]))
		if sc.is_empty():
			continue
		out.append({"w": float(hi - lo) / float(maxi(1, n)), "scores": sc, "bypos": bp})
	return out
