extends Probe

## 配对诊断:同一副牌、同一个策略, 数学侧的复刻 vs 真实游戏代码路径, **逐手对比**。
##   godot --headless --path . --script res://tools/pair.gd
##
## `agree.gd` 报出数学侧比真打高 6.3%, 而两边用的是同一批种子 —— 牌是配对的,
## 所以那不是抽样噪声。这个脚本把每一手的两个分数并排打出来, 定位分家点。
##
## 为了先排除采样带来的干扰, **默认关掉弃牌与前瞻**(d_max=0, lam=0):
## 那时两条路径都是**完全确定性**的, 分数必须逐位相同。不同 = 铁定是 bug。

const N := 2000


func _initialize() -> void:
	var slots: Array = [null, null, null, null]
	var rng := RandomNumberGenerator.new()
	var extra := {
		"prev_kind": -99, "acted_late": false, "discards": 0, "coins": 99,
		"phrase_idx": 0, "cache_cards": [], "mod": "", "character": null,
	}

	# ---- 第一关:确定性核心(不弃牌、不前瞻)。必须逐位相同 ----
	var diff0 := 0
	var shown := 0
	for r in range(N):
		var d1 := Deck.new(700000 + r)
		var vis: Array = []
		for _j in range(GameConfig.HAND_SIZE + GameConfig.CACHE_CAP):
			vis.append(d1.draw())
		var math_s := float(Solver.best_split(vis, slots, extra).score)

		var d2 := Deck.new(700000 + r)
		var cache: Array = []
		var ph := Phrase.new(d2, cache, 99)
		ph.start()
		rng.seed = 700000 + r
		var bot := Bot.new(rng, Report.new(1, 4))
		bot._play_perfect(ph, slots, "", 0.0, 0, 0)      # lam=0, samples=0
		var sim_s := float(Settle.run(ph.lock_and_settle(), slots, extra)["score"])

		if absf(math_s - sim_s) > 0.001:
			diff0 += 1
			if shown < 5:
				shown += 1
				print("  分家 seed=%d   数学 %.0f   真打 %.0f" % [700000 + r, math_s, sim_s])
				print("     可见 8 张: %s" % [_lbl(vis)])
				print("     真打手牌 : %s   缓存: %s" % [_lbl(ph.hand), _lbl(cache)])
	print("\n=== 第一关:确定性核心(不弃牌/不前瞻) ===")
	print("  %d/%d 手不一致" % [diff0, N])
	if diff0 == 0:
		print("  ✅ 切法逻辑两边一致 —— 分家点在弃牌或前瞻")
	else:
		print("  ❌ 连最基本的切法都对不上 —— bug 在 Solver 或 _play_perfect 的搬牌")

	# ---- 第二、三关:逐级打开弃牌与前瞻, 看哪一级引入差距 ----
	# 这两级都带采样, 所以不比"逐手相同", 比**配对均值差**(同种子同牌, 差应当近 0)。
	_trace(rng, slots, extra)
	_stage("第二关:开弃牌, 不前瞻", 2, 0.0, rng, slots, extra)
	_stage("第三关:弃牌 + 前瞻(实战配置)", 2, float(DB.sim()["solver"]["lam"]), rng, slots, extra)
	quit(0)


## 逐手打印弃牌前后的实际牌面 —— 推理到此为止, 让数据说话。
func _trace(rng: RandomNumberGenerator, slots: Array, extra: Dictionary) -> void:
	print("\n=== 逐手追踪(前 3 手) ===")
	var samples := int(DB.sim()["solver"]["lam_samples"])
	for r in range(3):
		var d1 := Deck.new(700000 + r)
		rng.seed = 700000 + r
		var vis: Array = []
		for _j in range(8):
			vis.append(d1.draw())
		var b0 = Solver.best_split(vis, slots, extra)
		var drop := Solver.best_discard(vis, slots, extra, d1, rng, 999, 2, 0.0, samples, 0.0)
		var ks := {}
		for di in drop:
			ks[b0.keep[di]] = true
		var rb: Array = []
		for c in vis:
			if not ks.has(c):
				rb.append(c)
		var newc := d1.peek_many(rng, ks.size())
		rb.append_array(newc)
		var m_after := Solver.best_split(rb, slots, extra)

		var d2 := Deck.new(700000 + r)
		var cache: Array = []
		var ph := Phrase.new(d2, cache, 99)
		ph.start()
		rng.seed = 700000 + r
		var bot := Bot.new(rng, Report.new(1, 4))
		bot._play_perfect(ph, slots, "", 0.0, samples, 0)
		var sim_after: Array = []
		sim_after.append_array(ph.hand)
		sim_after.append_array(ph.cache)

		print("  #%d 弃前 8 张 %s -> 最优 %d" % [r, _lbl(vis), b0.score])
		print("     弃掉 %s   数学补 %s -> 最优 %d" % [_lbl(ks.keys()), _lbl(newc), m_after.score])
		print("     真打弃后 8 张 %s -> 实得 %d"
			% [_lbl(sim_after), int(Settle.run(ph.lock_and_settle(), slots, extra)["score"])])


func _stage(label: String, d_max: int, lam: float, rng: RandomNumberGenerator,
		slots: Array, extra: Dictionary) -> void:
	var samples := int(DB.sim()["solver"]["lam_samples"])
	var dm := 0.0
	var ds := 0.0
	var nm := 0      # 数学侧弃了几张
	var ns := 0      # 真打弃了几张
	var dsum := 0.0  # 配对差之和
	var dsq := 0.0   # 配对差平方和 —— **没有标准误的差值等于没有结论**
	for r in range(N):
		# ---- 数学侧复刻 ----
		var d1 := Deck.new(700000 + r)
		rng.seed = 700000 + r
		var vis: Array = []
		for _j in range(GameConfig.HAND_SIZE + GameConfig.CACHE_CAP):
			vis.append(d1.draw())
		if d_max > 0:
			var b0 = Solver.best_split(vis, slots, extra)
			if b0 != null:
				var drop := Solver.best_discard(vis, slots, extra, d1, rng, 999, d_max,
					0.0, samples, 0.0)
				if not drop.is_empty():
					var ks := {}
					for di in drop:
						if di >= 0 and di < b0.keep.size():
							ks[b0.keep[di]] = true
					var rb: Array = []
					for c in vis:
						if not ks.has(c):
							rb.append(c)
					for _k in range(ks.size()):
						rb.append(d1.draw())   # ⭐ 与真打同一种抽法(消耗牌堆), 原为 peek_many
					if rb.size() == vis.size():
						vis = rb
						nm += ks.size()
		var mb = Solver.best_split_lookahead(vis, slots, extra, d1, rng, lam, samples)
		var m_one := float(mb.score) if mb != null else 0.0
		dm += m_one

		# ---- 真实代码路径 ----
		var d2 := Deck.new(700000 + r)
		var cache: Array = []
		var ph := Phrase.new(d2, cache, 99)
		ph.start()
		rng.seed = 700000 + r
		var bot := Bot.new(rng, Report.new(1, 4))
		bot._play_perfect(ph, slots, "", lam, samples if d_max > 0 or lam > 0.0 else 0, 0)
		var s_one := float(Settle.run(ph.lock_and_settle(), slots, extra)["score"])
		ds += s_one
		ns += ph.discards_used
		var dd := m_one - s_one
		dsum += dd
		dsq += dd * dd
	print("\n=== %s ===" % label)
	print("  数学侧 %.1f   真打 %.1f   配对差 %+.1f (%+.1f%%)"
		% [dm / N, ds / N, (dm - ds) / N, 100.0 * (dm - ds) / maxf(1.0, ds)])
	print("  弃牌张数/手:  数学侧 %.2f   真打 %.2f" % [float(nm) / N, float(ns) / N])
	var mean_d := dsum / N
	var var_d: float = (dsq - dsum * dsum / N) / float(N - 1)
	var se := sqrt(var_d / N)
	print("  ⭐ 配对差 %+.1f ± %.1f   z = %+.2f   %s"
		% [mean_d, se, mean_d / maxf(0.001, se),
			"显著" if absf(mean_d) > 2.0 * se else "**不显著 —— 之前那个 6.7% 是噪声**"])


func _lbl(cards: Array) -> String:
	var s := ""
	for c in cards:
		s += c.label() + " "
	return s
