extends RefCounted

## 数学 D 的单拍求解器 (docs/design/solver_roadmap.md)。这是新地基, 契约要锁住:
## 它是**一致性测试的一半** —— 数学侧和模拟器共用它, 它错了两边会一起错、
## 而且 agree.gd 会一致地不报警(共模误差探针抓不到)。
func run(t) -> void:
	var slots: Array = [null, null, null, null]
	var extra := {
		"prev_kind": -99, "acted_late": false, "discards": 0, "coins": 99,
		"phrase_idx": 0, "cache_cards": [], "mod": "",
	}
	var visible: Array = []
	for i in range(GameConfig.HAND_SIZE + GameConfig.CACHE_CAP):
		visible.append(Card.new(2 + i, i % 4))

	var all := Solver.splits(visible, slots, extra)
	# C(8,5) = 56 —— 一个都不能少:少了就是有持法够不到, 上界会被工具限制而不是被游戏
	t.eq(all.size(), 56, "solver enumerates every 5-of-8 hold")

	# ⚠ 循环内不逐条 check —— 56 次会把测试基线灌水几百条, 那个数字就不再有参考价值。
	# 循环里计数, 循环外断言一次。
	var seen := {}
	var bad_size := 0
	var bad_partition := 0
	var dup := 0
	for s in all:
		if s.hold.size() != GameConfig.HAND_SIZE or s.keep.size() != GameConfig.CACHE_CAP:
			bad_size += 1
		# hold 与 keep 必须是原 8 张的一个**划分**:不重不漏。
		# 漏了 = 凭空少牌, 重了 = 同一张牌既计分又留缓存(白赚一张)。
		var union := {}
		for c in s.hold:
			union[c] = true
		for c in s.keep:
			union[c] = true
		if union.size() != visible.size():
			bad_partition += 1
		var key := ""
		for c in s.hold:
			key += "%d-%d," % [c.rank, c.suit]
		if seen.has(key):
			dup += 1
		seen[key] = true
	t.eq(bad_size, 0, "every split is hand-size hold + cache-size keep")
	t.eq(bad_partition, 0, "hold + keep always partition the visible cards (no overlap, no loss)")
	t.eq(dup, 0, "no duplicate hold enumerated")

	# best_split 必须真的是这 56 个里的最大值(它是"上界"这个词的全部含义)
	var best = Solver.best_split(visible, slots, extra)
	t.check(best != null, "best_split returns something")
	var mx := -1
	for s in all:
		mx = maxi(mx, s.score)
	t.eq(best.score, mx, "best_split really is the max over all splits")

	# λ = 0 时前瞻必须退化成单拍贪心 —— 否则"λ=0 是基准"这个读数就不成立
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var deck := Deck.new(11)
	var lz = Solver.best_split_lookahead(visible, slots, extra, deck, rng, 0.0, 2)
	t.eq(lz.score, mx, "lookahead with lambda=0 degenerates to the greedy split")

	# --- 快慢路径对拍 (性能优化的安全网) ---
	# `best_score` 跳过了 Settle 和 56 个 Split 对象的分配, 快 5-10 倍。
	# **优化改结果是最坏的一种 bug:它不报错, 只让所有读数悄悄偏掉。**
	# 所以随机对拍两条路径 —— 空槽(走恒等快路径)和带小丑牌+Boss脸(走完整结算)各一批。
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 4242
	var mism_plain := 0
	var mism_full := 0
	var jslots: Array = [Joker.by_id("mono"), Joker.by_id("neonsign"), null, null]
	for _t in range(40):
		var d3 := Deck.new(rng2.randi_range(1, 99999))
		var vis: Array = []
		for _j in range(GameConfig.HAND_SIZE + GameConfig.CACHE_CAP):
			vis.append(d3.draw())
		var e_plain := {"prev_kind": -99, "acted_late": false, "discards": 0,
			"coins": 9, "phrase_idx": 0, "mod": ""}
		if Solver.best_score(vis, slots, e_plain) != float(Solver.best_split(vis, slots, e_plain).score):
			mism_plain += 1
		# 带小丑牌 + Boss 脸:必须走完整 Settle, 快路径不许在这里生效
		var e_full := {"prev_kind": Pattern.Kind.FLUSH, "acted_late": true, "discards": 1,
			"coins": 9, "phrase_idx": 0, "mod": "norepeat"}
		if Solver.best_score(vis, jslots, e_full) != float(Solver.best_split(vis, jslots, e_full).score):
			mism_full += 1
		# ⚠ 2026-08-07:恒等快路径的判据从「有没有脸」改成「这张脸进不进 Settle」
		# (`mod == ""` 时任何脸都关掉它, 实测 8.4 → 36 ms/拍)。这是一条**会改结果**
		# 的优化, 所以**每一张脸**都逐位对拍, 不是抽两张代表。
		for m in SectionMod.roster():
			var e_m := {"prev_kind": Pattern.Kind.FLUSH, "acted_late": true, "discards": 0,
				"coins": 9, "phrase_idx": 0, "mod": m.id,
				"first_kind": Pattern.Kind.PAIR}
			if Solver.best_score(vis, slots, e_m) != float(Solver.best_split(vis, slots, e_m).score):
				mism_full += 1
	# `_classify` 的位运算快路径 vs 原实现:大样本随机对拍。
	# 它占探针 63% 的时间, 但**它是真游戏的计分核心** —— 改错了不是探针慢, 是分数全错。
	var mism_cls := 0
	var seen_kinds := {}
	var d5 := Deck.new(31337)
	var pool5: Array = []
	while d5.remaining() > 0:
		pool5.append(d5.draw())
	for _t in range(3000):
		var five: Array = []
		var idxs := {}
		while five.size() < 5:
			var j := rng2.randi_range(0, pool5.size() - 1)
			if idxs.has(j):
				continue
			idxs[j] = true
			five.append(pool5[j])
		var kf: int = Pattern._classify_fast(five)
		if kf != Pattern._classify_ref(five, {}):
			mism_cls += 1
		seen_kinds[kf] = true
	t.eq(mism_cls, 0, "bitmask classify matches the reference over 3000 random hands")
	# 覆盖率兜底:随机样本必须真的踩到过高牌型, 否则「全对」只是没测到
	t.check(seen_kinds.size() >= 7, "the random sample actually reached most hand kinds")
	# 边角:轮子 A2345、皇家、四条、葫芦 —— 随机样本很难稳定命中
	t.eq(Pattern._classify_fast([t._c(14,0), t._c(2,1), t._c(3,2), t._c(4,3), t._c(5,0)]),
		Pattern.Kind.STRAIGHT, "wheel A2345 is a straight on the fast path")
	t.eq(Pattern._classify_fast([t._c(10,3), t._c(11,3), t._c(12,3), t._c(13,3), t._c(14,3)]),
		Pattern.Kind.ROYAL_FLUSH, "royal flush on the fast path")
	t.eq(Pattern._classify_fast([t._c(14,0), t._c(2,0), t._c(3,0), t._c(4,0), t._c(5,0)]),
		Pattern.Kind.STRAIGHT_FLUSH, "wheel in one suit is a straight flush")
	t.eq(Pattern._classify_fast([t._c(7,0), t._c(7,1), t._c(7,2), t._c(7,3), t._c(2,0)]),
		Pattern.Kind.FOUR_KIND, "quads on the fast path")
	t.eq(Pattern._classify_fast([t._c(9,0), t._c(9,1), t._c(9,2), t._c(2,0), t._c(2,1)]),
		Pattern.Kind.FULL_HOUSE, "full house on the fast path")

	# Pattern 的无字典快路径也要对拍(含万能牌 —— 它走的是另一条分支)
	var mism_pat := 0
	for _t in range(60):
		var d4 := Deck.new(rng2.randi_range(1, 99999))
		var five: Array = []
		for _j in range(5):
			five.append(d4.draw())
		if _t % 5 == 0:
			five[0] = Card.new(Card.JOKER_RANK, Card.JOKER_BIG)   # 万能牌分支
		if Pattern.score_five(five) != int(Pattern.evaluate_best(five)["score"]):
			mism_pat += 1
	t.eq(mism_pat, 0, "Pattern.score_five matches evaluate_best (wilds included)")

	t.eq(mism_plain, 0, "fast path matches the full path with empty slots")
	t.eq(mism_full, 0, "fast path matches the full path with jokers and a boss face")

	# peek_many: 设想抽牌**不能**消耗牌堆, 且一次调用内不放回
	var d2 := Deck.new(5)
	var before := d2.remaining()
	var peek := d2.peek_many(rng, 5)
	t.eq(peek.size(), 5, "peek_many returns what was asked")
	t.eq(d2.remaining(), before, "peek_many does not consume the deck")
	var uniq := {}
	for c in peek:
		uniq[c] = true
	t.eq(uniq.size(), 5, "peek_many draws without replacement within one call")

	# ── ε(决策噪声, docs/design/solving.md)──────────────────────────────
	# ⚠ 这两条是本次改动最重要的断言。ε=0 时若消耗了随机数, 全部历史读数会
	# 整体漂移**而且不报错** —— `peek_many` 那次就是这个形状, 已撤回。
	var rng_e := RandomNumberGenerator.new()
	rng_e.seed = 12345
	var st_before := rng_e.state
	var s_eps0 = Solver.best_split(visible, slots, extra, {}, [], [], 0.0, rng_e)
	t.eq(rng_e.state, st_before, "eps=0 consumes no randomness (否则历史读数整体漂移且不报错)")
	var s_ref = Solver.best_split(visible, slots, extra)
	t.check(s_eps0 != null and s_ref != null, "both eps=0 and no-eps paths return a split")
	t.eq(s_eps0.score, s_ref.score, "eps=0 is bit-identical to the no-eps path")

	# ε 很大时必须真的偏离 argmax —— 否则它是个装饰品参数, 和「最多弃 2 张」
	# 同一个形状(一条写了等于没写的约束, 而那次骗了我们整整一轮)。
	# ⚠ 循环内计数, 循环外断言一次 —— 逐条 check 会把测试基线灌水。
	var mx_e := -1
	for s in all:
		mx_e = maxi(mx_e, s.score)
	var rng_e2 := RandomNumberGenerator.new()
	rng_e2.seed = 777
	var off_argmax := 0
	for _t in range(50):
		var pick = Solver.best_split(visible, slots, extra, {}, [], [], 3.0, rng_e2)
		if pick != null and pick.score < mx_e:
			off_argmax += 1
	t.check(off_argmax > 0, "eps>0 actually deviates from argmax (否则 ε 是装饰品参数)")

	# ── 前瞻的真实跨拍转移(docs/design/solving.md 第三部分 / docs/design/capability.md 缺口 2)──
	# 现在的 cache_value 假设留下的 3 张会原样留到下一拍, 而 cache_evict 族
	# 正好拿走它们。判据两条, 缺一不可:
	#   ① 无脸(evict=0)时**逐位不变** —— 否则历史读数全部漂移;
	#   ② 有脸(evict>0)时**必须变** —— 否则这条修复是空气(和「最多弃 2 张」同形状)。
	var deck_cv := Deck.new(4242)
	var rng_cv := RandomNumberGenerator.new()
	rng_cv.seed = 99
	var futures_cv: Array = []
	for _i in range(3):
		futures_cv.append(deck_cv.peek_many(rng_cv, GameConfig.HAND_SIZE))
	var keep_cv: Array = [visible[0], visible[1], visible[2]]

	var extra_none := extra.duplicate()
	extra_none["mod"] = ""
	var v_none := Solver.cache_value(keep_cv, slots, extra_none, futures_cv, {})
	var v_none2 := Solver.cache_value(keep_cv, slots, extra_none, futures_cv, {})
	t.eq(v_none, v_none2, "cache_value is deterministic given shared futures")

	# ⚠ **判据不能用「驱逐越多分越低」的单调性** —— 驱逐之后下一拍 `Phrase.start()`
	# 会把缓存**补满**, 补进来的随机牌完全可能比留下的牌好, 所以单调性在
	# 结构上**不成立**。(第一版判据就写错在这里, 而它当时能过纯属侥幸。)
	# 结构性的东西改测 `_survivor_sets` 本身;集成侧只断言「读了 mod」。
	t.eq(Solver._survivor_sets(keep_cv, 0).size(), 1,
		"evict=0 -> 恰好一种幸存集合(= keep 本身, 老路径逐位不变的根据)")
	t.eq(Solver._survivor_sets(keep_cv, 1).size(), 3,
		"evict=1 -> C(3,2)=3 种幸存集合")
	t.eq(Solver._survivor_sets(keep_cv, 2).size(), 3,
		"evict=2 -> C(3,1)=3 种幸存集合")
	t.eq(Solver._survivor_sets(keep_cv, 3).size(), 1,
		"evict=3 -> 恰好一种(空集)")
	t.eq(Solver._survivor_sets(keep_cv, 0)[0], keep_cv,
		"evict=0 的那一种就是 keep 原样(顺序也一样)")

	# 集成:cache_value 必须**读** mod。三个值全等 = 根本没读(那正是修复前的状态)。
	# ⚠ futures 的长度必须跟着 evict 走 —— 驱逐 n 张就要多补 n 张, 否则下一拍
	# 只有 7 张可见, 那是个静默的悲观偏置。
	var extra_lost := extra.duplicate()
	extra_lost["mod"] = "lostpage"      # cache_evict 1
	var extra_fresh := extra.duplicate()
	extra_fresh["mod"] = "freshsheet"   # cache_evict 3 —— 缓存整个换掉
	var fut_lost: Array = []
	var fut_fresh: Array = []
	var deck_cv2 := Deck.new(4242)
	var rng_cv2 := RandomNumberGenerator.new()
	rng_cv2.seed = 99
	for _i in range(3):
		fut_lost.append(deck_cv2.peek_many(rng_cv2, GameConfig.HAND_SIZE + 1))
		fut_fresh.append(deck_cv2.peek_many(rng_cv2, GameConfig.HAND_SIZE + 3))
	var v_lost := Solver.cache_value(keep_cv, slots, extra_lost, fut_lost, {})
	var v_fresh := Solver.cache_value(keep_cv, slots, extra_fresh, fut_fresh, {})
	t.check(v_none != v_lost or v_none != v_fresh,
		"cache_value 必须读 mod (三值全等 = 缺口2 的修复是空气: %.1f / %.1f / %.1f)"
			% [v_none, v_lost, v_fresh])
	t.eq(int(SectionMod.cache_evict("freshsheet")), 3,
		"freshsheet 的 cache_evict 仍是 3 (这条测试的前提)")
	t.eq(int(SectionMod.cache_evict("lostpage")), 1,
		"lostpage 的 cache_evict 仍是 1 (这条测试的前提)")
