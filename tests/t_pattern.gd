extends RefCounted

# --- Pattern ---
func run(t) -> void:
	_t_memo(t)
	# Royal flush
	var royal := [t._c(10, 3), t._c(11, 3), t._c(12, 3), t._c(13, 3), t._c(14, 3)]
	var r := Pattern.evaluate_best(royal)
	t.eq(r["kind"], Pattern.Kind.ROYAL_FLUSH, "royal flush kind")
	t.eq(r["score"], (140 + 60) * int(Pattern.BASE_MULT[Pattern.Kind.ROYAL_FLUSH]),
		"royal flush score = chips × mult")

	# Straight flush 5-9 hearts
	var sf := [t._c(5, 2), t._c(6, 2), t._c(7, 2), t._c(8, 2), t._c(9, 2)]
	t.eq(Pattern.evaluate_best(sf)["kind"], Pattern.Kind.STRAIGHT_FLUSH, "straight flush kind")

	# Wheel straight (A2345 mixed suits)
	var wheel := [t._c(14, 3), t._c(2, 2), t._c(3, 1), t._c(4, 0), t._c(5, 3)]
	var w := Pattern.evaluate_best(wheel)
	t.eq(w["kind"], Pattern.Kind.STRAIGHT, "wheel is a straight")
	t.eq(w["score"], (30 + 28) * int(Pattern.BASE_MULT[Pattern.Kind.STRAIGHT]),
		"wheel score uses A=14")

	# Four of a kind
	var quad := [t._c(7, 0), t._c(7, 1), t._c(7, 2), t._c(7, 3), t._c(2, 0)]
	t.eq(Pattern.evaluate_best(quad)["kind"], Pattern.Kind.FOUR_KIND, "four of a kind")

	# Full house 999 22
	var fh := [t._c(9, 0), t._c(9, 1), t._c(9, 2), t._c(2, 0), t._c(2, 1)]
	var fhr := Pattern.evaluate_best(fh)
	t.eq(fhr["kind"], Pattern.Kind.FULL_HOUSE, "full house kind")
	t.eq(fhr["score"], (40 + 31) * int(Pattern.BASE_MULT[Pattern.Kind.FULL_HOUSE]),
		"full house score = chips × mult")

	# Flush (non-straight)
	var fl := [t._c(2, 0), t._c(5, 0), t._c(8, 0), t._c(11, 0), t._c(13, 0)]
	t.eq(Pattern.evaluate_best(fl)["kind"], Pattern.Kind.FLUSH, "flush kind")

	# Two pair
	var tp := [t._c(5, 0), t._c(5, 1), t._c(6, 2), t._c(6, 3), t._c(13, 0)]
	t.eq(Pattern.evaluate_best(tp)["kind"], Pattern.Kind.TWO_PAIR, "two pair kind")

	# Best-five from 7: quad hidden among noise
	var seven := [t._c(7, 0), t._c(7, 1), t._c(7, 2), t._c(7, 3), t._c(2, 0), t._c(3, 1), t._c(9, 2)]
	t.eq(Pattern.evaluate_best(seven)["kind"], Pattern.Kind.FOUR_KIND, "best-five finds quad in 7 cards")

	# Fewer than 5 cards -> empty
	t.check(Pattern.evaluate_best([t._c(2, 0), t._c(3, 0)]).is_empty(), "less than 5 cards -> empty")

	# ≥3 张万能的解析捷径(2026-08-26 超级百搭引擎前提)。
	# 旧暴力分支只处理 ≤2 张;k≥3 曾会漏替换 → rank 15 直达计数数组越界。
	var w0 := Card.new(Card.JOKER_RANK, 2)
	var w1 := Card.new(Card.JOKER_RANK, 3)
	var w2 := Card.new(Card.JOKER_RANK, Card.JOKER_BIG)
	var w3 := Card.new(Card.JOKER_RANK, Card.JOKER_LITTLE)
	var five_w := [w0, w1, w2, w3, Card.new(Card.JOKER_RANK, 2)]
	t.eq(Pattern.evaluate_best(five_w)["kind"], Pattern.Kind.ROYAL_FLUSH, "5 wilds = royal flush")
	t.eq(Pattern.evaluate_best([w0, w1, w2, w3, t._c(12, 1)])["kind"],
		Pattern.Kind.ROYAL_FLUSH, "4 wilds + Q = royal flush")
	t.eq(Pattern.evaluate_best([w0, w1, w2, w3, t._c(4, 1)])["kind"],
		Pattern.Kind.STRAIGHT_FLUSH, "4 wilds + 4 = straight flush(窗含实牌)")
	t.eq(Pattern.evaluate_best([w0, w1, w2, t._c(11, 0), t._c(13, 0)])["kind"],
		Pattern.Kind.ROYAL_FLUSH, "3 wilds + 同花 J K = royal flush")
	t.eq(Pattern.evaluate_best([w0, w1, w2, t._c(9, 0), t._c(9, 1)])["kind"],
		Pattern.Kind.FOUR_KIND, "3 wilds + 对 9 = four of a kind(对子进不了顺子窗)")
	# 红调:红桃 + 方块异花同色, 3 万能补窗 → 颜色同花顺(规则不开第二份的证据)
	t.eq(Pattern._score_five([w0, w1, w2, t._c(10, 1), t._c(12, 2)],
		{"redtone": true})["kind"], Pattern.Kind.ROYAL_FLUSH,
		"redtone: 红桃+方块 + 3 wilds = 颜色皇家(规则牌在捷径下自动生效)")
	# 对拍:候选构造 vs 缩减域暴力(每张万能试 3 花色 × 13 点 —— 花色只有
	# 「等于哪张实牌的花色 / 都不等于」三个等价类, 39 张即覆盖 52 张的全部结果)。
	var prng := RandomNumberGenerator.new()
	prng.seed = 20260826
	for case_i in range(8):
		var r1 := prng.randi_range(2, 14)
		var r2 := prng.randi_range(2, 14)
		var s1 := prng.randi_range(0, 3)
		var s2 := prng.randi_range(0, 3)
		var rules: Dictionary = {}
		if case_i == 6:
			rules = {"redtone": true}
		elif case_i == 7:
			rules = {"fourfingers": true}
		var hand5 := [w0, w1, w2, Card.new(r1, s1), Card.new(r2, s2)]
		var got := Pattern.score_five(hand5, rules)
		var sx := 0
		while sx == s1 or sx == s2:
			sx += 1
		var subs: Array = []
		for ss in [s1, s2, sx]:
			for rr in range(2, 15):
				subs.append(Card.new(rr, ss))
		var want := -1
		for a in subs:
			for b in subs:
				for c in subs:
					var sc := Pattern.score_five([a, b, c, hand5[3], hand5[4]], rules)
					if sc > want:
						want = sc
		t.eq(got, want, "3-wild 候选构造 = 缩减域暴力 (case %d: r%d s%d / r%d s%d %s)"
			% [case_i, r1, s1, r2, s2, str(rules)])

	# ⚑ 2026-08-27 全域候选构造:k=1,2 也走 _score_many_wilds(52^k 暴力退役为测试参照
	# _score_five_brute)。对拍 = 全域暴力(每张万能试全 52 张, **允许与实牌重复** ——
	# 万能可以变成你已有的那张, 这是万能语义的权威口径)。
	var prng2 := RandomNumberGenerator.new()
	prng2.seed = 20260827
	for kk in [1, 2]:
		for case_i in range(12):
			var rules2: Dictionary = {}
			if kk == 1 and case_i == 10:
				rules2 = {"redtone": true}
			if kk == 1 and case_i == 11:
				rules2 = {"fourfingers": true, "shortcut": true}
			if kk == 2 and case_i == 10:
				rules2 = {"shortcut": true}
			if kk == 2 and case_i == 11:
				rules2 = {"fourfingers": true}
			var hand: Array = []
			for i in range(kk):
				hand.append(Card.new(Card.JOKER_RANK, i))
			for i in range(5 - kk):
				hand.append(Card.new(prng2.randi_range(2, 14), prng2.randi_range(0, 3)))
			var got2 := Pattern.score_five(hand, rules2)
			var want2 := int(Pattern._score_five_brute(hand, rules2)["score"])
			t.eq(got2, want2, "k=%d 候选构造 = 52^k 全域暴力 (case %d %s)"
				% [kk, case_i, str(rules2)])

	# 定向角落(每个都是候选族容易漏的形态), 锁形态 + 与暴力对拍:
	# ① 带对的同花:k=2 四条配不齐时, wild 变 A♠(与实牌 A 重 rank)是同花最优 ——
	#    「避开实牌 rank 往下取」在这里是错的(A,A,A,K,9 同花 495 > A,K,Q,J,9 同花 470)。
	var pf := [w0, w1, t._c(14, 3), t._c(13, 3), t._c(9, 3)]
	var pfr: Dictionary = Pattern._score_five(pf, {})
	t.eq(pfr["kind"], Pattern.Kind.FLUSH, "2 wilds + A♠K♠9♠ = 三 A 同花(重复 rank 合法)")
	t.eq(int(pfr["score"]), int(Pattern._score_five_brute(pf, {})["score"]),
		"带对同花 = 全域暴力")
	# ② 三条族:k=2 + 实牌三异 rank(四条 need=3 配不齐, 满堂盖不住)→ 双 wild 变最大实牌 rank。
	var tk := [w0, w1, t._c(2, 3), t._c(7, 2), t._c(12, 1)]
	var tkr: Dictionary = Pattern._score_five(tk, {})
	t.eq(tkr["kind"], Pattern.Kind.THREE_KIND, "2 wilds + 2/7/Q 异花 = 三条 Q")
	t.eq(int(tkr["score"]), int(Pattern._score_five_brute(tk, {})["score"]), "三条族 = 全域暴力")
	# ③ 四指 + 实牌带对:重 rank 实牌进旁观位, 4 连窗同花顺仍可达。
	var ff := [w0, w1, t._c(7, 3), t._c(7, 2), t._c(8, 3)]
	var ffr: Dictionary = Pattern._score_five(ff, {"fourfingers": true})
	t.eq(ffr["kind"], Pattern.Kind.STRAIGHT_FLUSH, "四指: 2 wilds + 7♠7♥8♠ = 同花顺(对 7 一张旁观)")
	t.eq(int(ffr["score"]), int(Pattern._score_five_brute(ff, {"fourfingers": true})["score"]),
		"四指旁观位 = 全域暴力")
	# ④ 近道跳位窗:9,J,Q,K + wild→A(6 宽窗去 10), 比补 10 的普通顺子分高。
	var sc := [w0, t._c(9, 0), t._c(11, 1), t._c(12, 2), t._c(13, 3)]
	var scr: Dictionary = Pattern._score_five(sc, {"shortcut": true})
	t.eq(scr["kind"], Pattern.Kind.STRAIGHT, "近道: wild 变 A 走跳位窗(9JQKA)")
	t.eq(int(scr["score"]), int(Pattern._score_five_brute(sc, {"shortcut": true})["score"]),
		"近道跳位窗 = 全域暴力")
	# ⑤ k=1 点数提升:两对在手, wild 配实牌 rank 升三条(不是变 A 做高牌)。
	var up := [w0, t._c(5, 3), t._c(5, 2), t._c(9, 1), t._c(13, 0)]
	var upr: Dictionary = Pattern._score_five(up, {})
	t.eq(upr["kind"], Pattern.Kind.THREE_KIND, "1 wild + 5,5,9,K = 三条 5")
	t.eq(int(upr["score"]), int(Pattern._score_five_brute(up, {})["score"]), "点数提升 = 全域暴力")


## ---- score_five 的分数记忆(2026-09-04):逐位精确 + 规则进键 + 满了清空 ----
func _t_memo(t) -> void:
	var w := Card.new(Card.JOKER_RANK, Card.JOKER_BIG)
	# 四指:4 连 + 万能 —— 有无规则分数不同, 记忆必须按规则分开(同一手牌先无规则再有规则)。
	var h4 := [t._c(4, 0), t._c(5, 1), t._c(6, 2), t._c(11, 3), w]
	var plain := Pattern.score_five(h4, {})
	var four := Pattern.score_five(h4, {"fourfingers": true})
	t.eq(plain, int(Pattern._score_five(h4, {})["score"]), "记忆命中 = 直算(无规则)")
	t.eq(four, int(Pattern._score_five(h4, {"fourfingers": true})["score"]), "记忆命中 = 直算(四指)")
	t.check(Pattern._rules_key({"fourfingers": true, "shortcut": false}) == 2, "规则键只计打开的规则")
	t.check(Pattern._rules_key({"unknown": true}) == -1, "未知规则键不进记忆")
	# 顺序无关:同 5 张任意排列同一个键。
	var perm := [w, t._c(11, 3), t._c(6, 2), t._c(4, 0), t._c(5, 1)]
	t.eq(Pattern._key5(perm), Pattern._key5(h4), "5 张牌的键与顺序无关")
	# 两遍相同, 且与不走记忆的 _score_five 逐位相同(含万能牌手)。
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var hands: Array = []
	for i in range(60):
		var d := Deck.new(500 + i)
		var h: Array = [d.draw(), d.draw(), d.draw(), d.draw()]
		h.append(w if i % 2 == 0 else d.draw())
		hands.append(h)
	var first: Array = []
	for h in hands:
		first.append(Pattern.score_five(h))
	var same := true
	for i in range(hands.size()):
		if Pattern.score_five(hands[i]) != first[i] \
				or first[i] != int(Pattern._score_five(hands[i], {})["score"]):
			same = false
	t.check(same, "记忆第二遍 = 第一遍 = 直算(60 手, 半数含万能)")
	Pattern._memo.clear()
	t.eq(Pattern.score_five(h4, {"fourfingers": true}), four, "清空后重算不变")
