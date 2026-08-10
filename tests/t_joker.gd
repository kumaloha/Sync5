extends RefCounted

# --- v0.1 joker roster ---
func run(t) -> void:
	# roster shape (2026-08-10 批3首波): Target 6 + Support 22, 终态 60 见 design/jokers_atlas.md §5
	var pool := Joker.pool()
	t.eq(pool.size(), 28, "pool holds 28 jokers")
	var targets := 0
	var rarities := {"common": 0, "uncommon": 0, "rare": 0}
	for j in pool:
		if j.kind == "target":
			targets += 1
			# 回池后 Target 真的参与货架抽取, 所以**必须**有档 ——
			# 空字符串会让权重静默退到 1(比 rare 的 5 还低), 换旗率变成没人写下的数。
			t.check(j.rarity != "", "target %s carries a rarity tier" % j.id)
		else:
			rarities[j.rarity] = int(rarities.get(j.rarity, 0)) + 1
		# principle D2: EN card text, ≤7 words
		t.check(j.fx_text.split(" ").size() <= 7, "%s card text within 7 words" % j.id)
	t.eq(targets, 6, "six targets (wrecker 待 bot 弃牌策略后 +1)")
	t.eq(rarities["common"], 9, "nine common supports")
	t.eq(rarities["uncommon"], 8, "eight uncommon supports")
	t.eq(rarities["rare"], 5, "five rare supports")
	t.check(Joker.by_id("nope") == null, "by_id on unknown id -> null")

	var flush_res := Pattern.evaluate_best([t._c(2, 0), t._c(5, 0), t._c(8, 0), t._c(11, 0), t._c(13, 0)])
	var base: int = flush_res["score"]
	var pair_res := Pattern.evaluate_best([t._c(5, 0), t._c(5, 1), t._c(7, 2), t._c(9, 3), t._c(13, 0)])
	var high_res := Pattern.evaluate_best([t._c(2, 0), t._c(5, 1), t._c(8, 2), t._c(11, 3), t._c(13, 0)])
	var fh_res := Pattern.evaluate_best([t._c(9, 0), t._c(9, 1), t._c(9, 2), t._c(2, 0), t._c(2, 1)])

	# targets
	# ⚠ 倍率一律从 data/jokers.json 推导。2026-08-06 拍板「难度只在牌型层收一次费,
	# Target 层各流派统一」后, 这批硬抄的断言一次红 5 条 —— 平衡要反复调, 别再抄死。
	t.eq(Settle.run(pair_res, [Joker.by_id("twin"), null, null, null], {})["score"],
		int(round(float(pair_res["score"]) * t._tmult("twin", "PAIR"))), "twin lifts the pair family")
	t.eq(Settle.run(fh_res, [Joker.by_id("twin"), null, null, null], {})["score"],
		int(fh_res["score"]), "twin: full house moved out of pair family")
	t.eq(Settle.run(fh_res, [Joker.by_id("triplet"), null, null, null], {})["score"],
		int(round(float(fh_res["score"]) * t._tmult("triplet", "FULL_HOUSE"))), "triplet lifts full house")
	var trips_res := Pattern.evaluate_best([t._c(9, 0), t._c(9, 1), t._c(9, 2), t._c(2, 0), t._c(5, 1)])
	t.eq(Settle.run(trips_res, [Joker.by_id("triplet"), null, null, null], {})["score"],
		int(round(float(trips_res["score"]) * t._tmult("triplet", "THREE_KIND"))), "triplet lifts trips")
	var tp_res := Pattern.evaluate_best([t._c(5, 0), t._c(5, 1), t._c(6, 2), t._c(6, 3), t._c(13, 0)])
	t.eq(Settle.run(tp_res, [Joker.by_id("twin"), null, null, null], {})["score"],
		int(round(float(tp_res["score"]) * t._tmult("twin", "TWO_PAIR"))), "twin lifts two pair")
	# 拍板后的**结构**契约:同一张 Target 内部各档必须一致(难度由牌型层承担, 不重复计价)
	t.eq(t._tmult("twin", "PAIR"), t._tmult("twin", "TWO_PAIR"), "twin tiers are uniform")
	t.eq(t._tmult("triplet", "THREE_KIND"), t._tmult("triplet", "FULL_HOUSE"), "triplet tiers are uniform")
	t.eq(t._tmult("stair", "STRAIGHT"), t._tmult("stair", "STRAIGHT_FLUSH"), "stair tiers are uniform")
	t.eq(t._tmult("mono", "FLUSH"), t._tmult("mono", "STRAIGHT_FLUSH"), "mono tiers are uniform")
	t.eq(Settle.run(flush_res, [Joker.by_id("triplet"), null, null, null], {})["score"],
		base, "triplet silent on a flush")
	# 独狼 2026-08-07 重做:从「得分卡」改成「经济/节奏卡」(用户拍板)。
	# 旧的「高牌 ×4」在弃牌免费后**一百拍才触发一次**(高牌频率 6.1%→1.6%),
	# 而它原本的交易「不弃牌=省钱」也随弃牌免费一起没了 —— 三根柱子倒了两根。
	# 新形态:不弃牌 → 给金币, 且 Target 出现率 ×3(卡面写着) —— 前期拖着攒钱换构筑。
	var wolf := Joker.by_id("lonewolf")
	t.eq(Settle.run(high_res, [wolf, null, null, null], {"discards": 0})["score"],
		int(high_res["score"]), "lone wolf no longer multiplies score")
	t.check(Settle.run(high_res, [wolf, null, null, null], {"discards": 0})["coins"]
		> Settle.run(high_res, [null, null, null, null], {"discards": 0})["coins"],
		"lone wolf pays coins when nothing was discarded")
	t.eq(Settle.run(high_res, [wolf, null, null, null], {"discards": 2})["coins"],
		Settle.run(high_res, [null, null, null, null], {"discards": 2})["coins"],
		"the vow is broken by any discard — no coins")
	var low_high := Pattern.evaluate_best([t._c(2, 0), t._c(4, 1), t._c(6, 2), t._c(9, 3), t._c(11, 0)])
	t.eq(Settle.run(low_high, [Joker.by_id("lonewolf"), null, null, null], {})["score"],
		int(low_high["score"]), "lonewolf: J-high does not count")
	t.eq(Settle.run(high_res, [Joker.by_id("lonewolf"), null, null, null], {"discards": 1})["score"],
		int(high_res["score"]), "lonewolf broken by a discard")
	t.eq(Settle.run(pair_res, [Joker.by_id("lonewolf"), null, null, null], {})["score"],
		int(pair_res["score"]), "lonewolf: made hands get no bonus")

	# finale / turnover / tipjar
	t.eq(Settle.run(flush_res, [null, Joker.by_id("finale"), null, null], {"acted_late": true})["score"],
		base + 70, "finale +70 on a late action")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("turnover"), null, null], {"discards": 3})["score"],
		base + 60, "turnover +20 per discard")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("tipjar"), null, null], {"discards": 0})["coins"],
		4 + 2, "tipjar +2 coins on zero discards")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("tipjar"), null, null], {"discards": 1})["coins"],
		4, "tipjar silent after a discard")

	# chord: cache all one suit (wilds match anything)
	var same_suit := [t._c(3, 1), t._c(9, 1), t._c(12, 1)]
	var mixed := [t._c(3, 1), t._c(9, 2), t._c(12, 1)]
	var with_wild := [t._c(3, 1), Card.new(Card.JOKER_RANK, Card.JOKER_BIG), t._c(12, 1)]
	t.eq(Settle.run(flush_res, [null, Joker.by_id("chord"), null, null], {"cache_cards": same_suit})["score"],
		base + 120, "chord +120 on a one-suit cache")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("chord"), null, null], {"cache_cards": mixed})["score"],
		base, "chord silent on a mixed cache")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("chord"), null, null], {"cache_cards": with_wild})["score"],
		base + 120, "a wild in the cache matches any suit")

	# neonsign: unconditional, flat — does NOT ride the multiplier
	t.eq(Settle.run(flush_res, [null, Joker.by_id("neonsign"), null, null], {})["score"],
		base + 80, "neonsign always +80")
	t.eq(Settle.run(flush_res, [Joker.by_id("mono"), Joker.by_id("neonsign"), null, null], {})["score"],
		int(round(float(base) * t._tmult("mono", "FLUSH"))) + 80, "neonsign stays flat under a target")

	# vinyl: permanent growth per discarded card, and it RIDES the multiplier —
	# the draft-early sleeper (user rule)
	var vinyl := Joker.by_id("vinyl")
	t.eq(Settle.run(flush_res, [null, vinyl, null, null], {})["score"], base, "vinyl starts silent")
	vinyl.on_discard(2)
	vinyl.on_discard(4)
	var fm: int = int(Pattern.BASE_MULT[Pattern.Kind.FLUSH])
	t.eq(Settle.run(flush_res, [null, vinyl, null, null], {})["score"],
		(int(flush_res["chips"]) + 18) * fm, "vinyl chips ride the pattern mult")
	t.eq(Settle.run(flush_res, [Joker.by_id("mono"), vinyl, null, null], {})["score"],
		int(round(float(int(flush_res["chips"]) + 18) * float(fm) * t._tmult("mono", "FLUSH"))),
		"vinyl growth rides every multiplier")

	# chorus: only on the section's last phrase
	t.eq(Settle.run(flush_res, [null, Joker.by_id("chorus"), null, null],
		{"phrase_idx": GameConfig.PHRASES_PER_SECTION - 2})["score"],
		base, "chorus silent mid-section")

	# momentum: grows only on early finishes with at least one action
	var mom := Joker.by_id("momentum")
	mom.on_phrase_end({"early_finish": true})
	mom.on_phrase_end({"early_finish": false})
	mom.on_phrase_end({"early_finish": true})
	t.eq(Settle.run(flush_res, [null, mom, null, null], {})["score"],
		int(round(base * 1.2)), "momentum +10% per early finish")

	# vip: J/Q/K count as 15 via the additive channel
	var vip_res := Pattern.evaluate_best([t._c(2, 0), t._c(5, 0), t._c(8, 0), t._c(11, 0), t._c(13, 0)])
	t.eq(Settle.run(vip_res, [null, Joker.by_id("vip"), null, null], {})["score"],
		(int(vip_res["chips"]) + 6) * int(Pattern.BASE_MULT[Pattern.Kind.FLUSH]),
		"vip: J +4 and K +2, on the chips side")

	# glowstick: rented power, fades 6% per phrase
	var glow := Joker.by_id("glowstick")
	t.eq(Settle.run(flush_res, [null, glow, null, null], {})["score"],
		int(round(base * 1.6)), "glowstick starts at +60%")
	for i in range(5):
		glow.on_phrase_end({})
	t.eq(Settle.run(flush_res, [null, glow, null, null], {})["score"],
		int(round(base * 1.3)), "glowstick down to +30% after 5 phrases")
	for i in range(5):
		glow.on_phrase_end({})
	t.eq(Settle.run(flush_res, [null, glow, null, null], {})["score"],
		base, "glowstick burnt out after 10 phrases")

	# bassline: ×0.25 per 12 discards
	var bass := Joker.by_id("bassline")
	bass.on_discard(11)
	t.eq(Settle.run(flush_res, [null, bass, null, null], {})["score"],
		base, "bassline silent below 12 discards")
	bass.on_discard(1)
	t.eq(Settle.run(flush_res, [null, bass, null, null], {})["score"],
		int(round(base * 1.25)), "bassline ×1.25 at 12 discards")
	bass.on_discard(12)
	t.eq(Settle.run(flush_res, [null, bass, null, null], {})["score"],
		int(round(base * 1.5)), "bassline ×1.5 at 24 discards")

	# mirror: re-applies the target at half power
	var mirror := Joker.by_id("mirror")
	t.eq(Settle.run(flush_res, [Joker.by_id("mono"), mirror, null, null], {})["score"],
		int(round(float(base) * t._tmult("mono", "FLUSH") * (1.0 + (t._tmult("mono", "FLUSH") - 1.0) * 0.5))),
		"mirror copies the target at half power")
	t.eq(Settle.run(flush_res, [null, mirror, null, null], {})["score"],
		base, "mirror silent without a target")
	t.eq(Settle.run(pair_res, [Joker.by_id("mono"), mirror, null, null], {})["score"],
		int(pair_res["score"]), "mirror silent when the target missed")

	# interest: cap at +5
	t.eq(Settle.run(flush_res, [null, Joker.by_id("interest"), null, null], {"coins": 40})["coins"],
		4 + 5, "interest caps at +5")
