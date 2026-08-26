extends RefCounted

# --- Pattern ---
func run(t) -> void:
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
