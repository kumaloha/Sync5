extends RefCounted

# --- Protagonist passives ---
func run(t) -> void:
	var roster := Character.roster()
	t.eq(roster.size(), 8, "eight protagonists")
	for i in range(roster.size()):
		t.eq(roster[i].idx, i, "character %d indexes itself" % i)

	var flush_res := Pattern.evaluate_best([t._c(2, 0), t._c(5, 0), t._c(8, 0), t._c(11, 0), t._c(13, 0)])
	var base: int = flush_res["score"]
	var none: Array = [null, null, null, null]

	# 0 DJ: same pattern as last phrase
	var dj: Character = roster[0]
	t.eq(Settle.run(flush_res, none, {"prev_kind": Pattern.Kind.FLUSH, "character": dj})["score"],
		int(round(base * 1.3)), "DJ +30% on a repeated pattern")
	t.eq(Settle.run(flush_res, none, {"prev_kind": Pattern.Kind.PAIR, "character": dj})["score"],
		base, "DJ silent on a different pattern")

	# 1 magician: +12% per discard, capped at 36%
	var mag: Character = roster[1]
	t.eq(Settle.run(flush_res, none, {"discards": 2, "character": mag})["score"],
		int(round(base * 1.24)), "magician +24% for 2 discards")
	t.eq(Settle.run(flush_res, none, {"discards": 7, "character": mag})["score"],
		int(round(base * 1.36)), "magician caps at +36%")

	# 2 boxer: only heavy hands (a five-card flush scores well above 60)
	var box: Character = roster[2]
	t.check(base >= 60, "flush base clears the boxer threshold")
	t.eq(Settle.run(flush_res, none, {"character": box})["score"],
		int(round(base * 1.25)), "boxer +25% on a heavy hand")
	var pair_res := Pattern.evaluate_best([t._c(4, 0), t._c(4, 1), t._c(7, 2), t._c(9, 3), t._c(11, 0)])
	if int(pair_res["score"]) < 60:
		t.eq(Settle.run(pair_res, none, {"character": box})["score"],
			int(pair_res["score"]), "boxer silent below 60 base")

	# 3 bartender: coin threshold
	var bar: Character = roster[3]
	t.eq(Settle.run(flush_res, none, {"coins": 8, "character": bar})["score"],
		int(round(base * 1.2)), "bartender +20% at 8 coins")
	t.eq(Settle.run(flush_res, none, {"coins": 7, "character": bar})["score"],
		base, "bartender silent at 7 coins")

	# 4 seer: the mirror of DJ, and silent on the very first phrase
	var seer: Character = roster[4]
	t.eq(Settle.run(flush_res, none, {"prev_kind": Pattern.Kind.PAIR, "character": seer})["score"],
		int(round(base * 1.2)), "seer +20% on a changed pattern")
	t.eq(Settle.run(flush_res, none, {"prev_kind": -99, "character": seer})["score"],
		base, "seer silent when there is no previous phrase")

	# 5 drummer: acting inside the final beats
	var drum: Character = roster[5]
	t.eq(Settle.run(flush_res, none, {"acted_late": true, "character": drum})["score"],
		int(round(base * 1.25)), "drummer +25% when acting late")

	# 6 rapper: rewarded for not discarding
	var rap: Character = roster[6]
	t.eq(Settle.run(flush_res, none, {"discards": 0, "character": rap})["score"],
		int(round(base * 1.18)), "rapper +18% with no discards")
	t.eq(Settle.run(flush_res, none, {"discards": 1, "character": rap})["score"],
		base, "rapper silent once a card is discarded")

	# 7 tattooist: flat coin income, and it stacks on top of the jokers
	var tat: Character = roster[7]
	t.eq(Settle.run(flush_res, none, {"character": tat})["coins"], 4 + 1,
		"tattooist adds a coin every phrase")
	var intr := Joker.by_id("interest")
	t.eq(Settle.run(flush_res, [null, intr, null, null], {"coins": 9, "character": tat})["coins"],
		4 + 2 + 1, "character income stacks with joker income")

	# the character runs after the jokers, so both feed one multiplier
	var mono := Joker.by_id("mono")
	var combo := Settle.run(flush_res, [mono, null, null, null],
		{"prev_kind": Pattern.Kind.FLUSH, "character": dj})
	t.eq(combo["score"], int(round(float(base) * t._tmult("mono", "FLUSH") * 1.3)),
		"joker mult and character bonus combine")
	t.check(combo["popups"].size() == 2, "both the joker and the character report a popup")
	var slots: Array = []
	for p in combo["popups"]:
		slots.append(int(p["slot"]))
	t.check(slots.has(-1), "the character popup uses slot -1")
