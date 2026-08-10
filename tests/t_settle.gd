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

	# Request is a transparent final-score factor, applied only when the public
	# goal was missed.
	var request_hit := Settle.run(flush_res, [null, null, null, null],
		{"mod": "request", "request_met": true})
	var request_miss := Settle.run(flush_res, [null, null, null, null],
		{"mod": "request", "request_met": false})
	t.eq(request_hit["score"], base, "a completed request leaves score untouched")
	t.eq(request_miss["score"], int(base * SectionMod.request_factor("request")),
		"a missed request applies the configured ten-percent loss")

	# Patch In scales the aggregate settlement contribution after every Joker has
	# applied. Bringing a phrase-start cache object into the final hand restores
	# the exact full chain.
	var neon := Joker.by_id("neonsign")
	var patch_full := Settle.run(flush_res, [mono, neon, null, null], {})
	var patch_half := Settle.run(flush_res, [mono, neon, null, null],
		{"mod": "patchin", "patch_restored": false})
	var patch_restored := Settle.run(flush_res, [mono, neon, null, null],
		{"mod": "patchin", "patch_restored": true})
	var pattern_mult := float(flush_res["pmult"])
	var want_half_mult := pattern_mult + (float(patch_full["mult"]) - pattern_mult) * 0.5
	t.check(absf(float(patch_half["mult"]) - want_half_mult) < 0.001,
		"Patch In halves the Joker multiplier contribution")
	t.eq(patch_half["bonus"], int(round(float(patch_full["bonus"]) * 0.5)),
		"Patch In halves flat score rewards")
	t.eq(patch_restored["score"], patch_full["score"],
		"using an initial cache card restores full Joker power")
	# Two odd +3 contributions expose the rounding boundary: aggregate 6 × 50%
	# is 3, while incorrectly rounding each Joker separately would become 4.
	var vinyl_a := Joker.by_id("vinyl")
	var vinyl_b := Joker.by_id("vinyl")
	vinyl_a.on_discard(1)
	vinyl_b.on_discard(1)
	var aggregate_full := Settle.run(flush_res, [null, vinyl_a, vinyl_b, null], {})
	var aggregate_half := Settle.run(flush_res, [null, vinyl_a, vinyl_b, null],
		{"mod": "patchin", "patch_restored": false})
	var base_chips := int(flush_res["chips"])
	t.eq(aggregate_half["base"], base_chips + int(round(
		float(int(aggregate_full["base"]) - base_chips) * 0.5)),
		"Patch In rounds one aggregate Joker delta, not each Joker separately")
