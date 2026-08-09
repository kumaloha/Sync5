extends RefCounted

# --- Settle pipeline (formula: (chips + additive) × 牌型mult × joker mult × (1 + pct) + bonus) ---
func run(t) -> void:
	var flush_res := Pattern.evaluate_best([t._c(2, 0), t._c(5, 0), t._c(8, 0), t._c(11, 0), t._c(13, 0)])
	var base: int = flush_res["score"]

	# no jokers: passthrough
	var plain := Settle.run(flush_res, [null, null, null, null], {})
	t.eq(plain["score"], base, "no jokers -> base score")
	t.eq(plain["coins"], 4, "no jokers -> pattern coins")

	# mono target: flush x4
	var mono := Joker.by_id("mono")
	var r1 := Settle.run(flush_res, [mono, null, null, null], {})
	var mf: float = t._tmult("mono", "FLUSH")
	t.eq(r1["score"], int(round(float(base) * mf)), "mono multiplies flush by its data mult")
	t.eq(r1["popups"].size(), 1, "mono emits a popup")
	t.eq(r1["popups"][0]["slot"], 0, "popup anchored to target slot")

	# mono does not trigger on a pair
	var pair_res := Pattern.evaluate_best([t._c(5, 0), t._c(5, 1), t._c(7, 2), t._c(9, 3), t._c(13, 0)])
	var r2 := Settle.run(pair_res, [mono, null, null, null], {})
	t.eq(r2["score"], int(pair_res["score"]), "mono ignores non-flush")

	# encore support: +80 base on repeating previous kind
	var encore := Joker.by_id("encore")
	var r3 := Settle.run(flush_res, [null, encore, null, null], {"prev_kind": Pattern.Kind.FLUSH})
	t.eq(r3["score"], base + 80, "encore +80 on repeat")
	var r4 := Settle.run(flush_res, [null, encore, null, null], {"prev_kind": Pattern.Kind.PAIR})
	t.eq(r4["score"], base, "encore silent when kind differs")

	# flat bonuses land AFTER the multiplier (they must expire, 2026-08)
	var r5 := Settle.run(flush_res, [mono, encore, null, null], {"prev_kind": Pattern.Kind.FLUSH})
	t.eq(r5["score"], int(round(float(base) * mf)) + 80, "flat bonus lands after the target mult")

	# chorus pct and mono mult stack multiplicatively
	var chorus := Joker.by_id("chorus")
	var r6 := Settle.run(flush_res, [mono, chorus, null, null],
		{"phrase_idx": GameConfig.PHRASES_PER_SECTION - 1})
	t.eq(r6["score"], int(round(float(base) * mf * 1.75)), "target mult and support pct stack")

	# base / mult are exposed for the settle animation; base includes additive
	# so the shown 基础分 × 乘数 = 分数 stays a true equation
	var rm := Settle.run(flush_res, [mono, encore, null, null], {"prev_kind": Pattern.Kind.FLUSH})
	t.eq(rm["base"], int(flush_res["chips"]), "reported base = chips, flat bonuses stay out")
	t.eq(rm["bonus"], 80, "settle reports the flat bonus for the show")
	t.check(absf(float(rm["mult"]) - float(Pattern.BASE_MULT[Pattern.Kind.FLUSH]) * mf) < 0.001,
		"reported mult carries the pattern mult and the target mult")

	# empty result guard
	var r9 := Settle.run({}, [mono], {})
	t.eq(r9["score"], 0, "empty result settles to zero")
