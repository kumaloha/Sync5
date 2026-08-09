class_name Settle
extends RefCounted

## Settlement pipeline: pattern result → target joker → support jokers →
## protagonist → final score & coins.
##
## Formula (2026-08-05 用户拍板 chips×mult, supersedes design/jokers.md B1):
##   score = (chips + Σ chip-mods) × 牌型mult × target mult × (1 + Σ%) + Σ bonus
## `chips` = pattern base chips + rank sum (from Pattern); the pattern's own
## MULT seeds the multiplier chain, target jokers stack onto it 符合条件时.
## `additive` (chip-mods: VIP, Vinyl) lands on chips — rides every multiplier,
## draft早了才值钱; `bonus` (flat rewards: Neon Sign, Encore, Finale, Turnover,
## Chord) lands AFTER the multiplier, so it is huge in S1 and pocket change by
## S10 — the Balatro mechanism that kills universal filler cards. Channels
## merge at the end, so slot order stays meaningless (B4).
##
## slots: Array of Joker-or-null, index 0 = target, 1..3 = supports.
## extra: {prev_kind, acted_late, discards, coins, phrase_idx, cache_cards,
##         character, mod}
## `mod` is the section's boss-face modifier id ("" = none, see
## core/modifier.gd). Settle enforces the four scoring-side twists here:
## unplugged halves the target factor (the mirror copies the weakened one),
## static zeroes the
## flat-bonus channel, norepeat / rotation halve the final score.
## `character` is the run's protagonist (Character or null). It applies AFTER
## every joker, so it reads the totals the jokers built. Its popup uses slot -1.
## Returns {score, coins, popups: [{slot, text}], base, mult} where `base`
## already includes the additive channel — the settle animation's
## 基础分 × 乘数 = 分数 stays a true equation.

static func run(result: Dictionary, slots: Array, extra: Dictionary) -> Dictionary:
	if result.is_empty():
		return {"score": 0, "coins": 0, "popups": [], "base": 0, "mult": 1.0}
	var ctx := {
		"kind": result.get("kind", -1),
		"base_score": int(result.get("score", 0)),   # pre-joker pattern score (base_gte reads this)
		"chips": int(result.get("chips", 0)),
		"additive": 0,
		"bonus": 0,
		"mult": float(result.get("pmult", 1)),        # the pattern mult seeds the chain
		"bonus_pct": 0.0,
		"coins_bonus": 0,
		"prev_kind": extra.get("prev_kind", -99),
		"acted_late": extra.get("acted_late", false),
		"discards": extra.get("discards", 0),
		"coins": extra.get("coins", 0),
		"phrase_idx": extra.get("phrase_idx", -1),
		"cache_cards": extra.get("cache_cards", []),
		"scoring_cards": result.get("resolved", []),
		"target_factor": 1.0,
	}
	var mod := String(extra.get("mod", ""))
	var popups: Array = []
	for i in range(slots.size()):
		var j = slots[i]
		if j == null:
			continue
		var pre_mult: float = ctx.mult
		var text: String = j.apply(ctx)
		# record how hard the target hit, so the copy card can re-apply it
		if i == 0 and pre_mult > 0.0:
			ctx.target_factor = ctx.mult / pre_mult
			var tp := SectionMod.target_power(mod)
			if tp < 1.0 and ctx.target_factor > 1.0:
				# reduced power: ×6 plays as ×3.5, and the mirror copies the
				# weakened factor
				var hf: float = 1.0 + (ctx.target_factor - 1.0) * tp
				ctx.mult = pre_mult * hf
				ctx.target_factor = hf
		if text != "":
			popups.append({"slot": i, "text": text})
	# the protagonist closes the chain
	var ch = extra.get("character")
	if ch != null:
		var ch_text: String = ch.apply(ctx)
		if ch_text != "":
			popups.append({"slot": -1, "text": ch_text})
	var eff_chips: int = int(ctx.chips) + int(ctx.additive)
	var total_mult: float = ctx.mult * (1.0 + ctx.bonus_pct)
	if SectionMod.bonus_disabled(mod):
		ctx.bonus = 0
	var score := int(round(float(eff_chips) * total_mult + float(ctx.bonus)))
	# a repeated HIGH CARD is exempt — an unmade hand is nobody's routine,
	# and taxing it executed the Lone Wolf archetype outright (round 17)
	var rf := SectionMod.repeat_factor(mod)
	if rf < 1.0 and ctx.prev_kind == ctx.kind and int(ctx.kind) > Pattern.Kind.HIGH_CARD:
		score = int(score * rf)
	var zf := SectionMod.zero_discard_factor(mod)
	if zf < 1.0 and int(ctx.discards) == 0:
		score = int(score * zf)
	# setlist: whatever hand type opened the SECTION locks it; anything else
	# scores at `lock_first`. `first_kind` is maintained by the caller exactly
	# the way prev_kind is, and is -99 on the section's own opening phrase —
	# nothing to lock against yet, because THAT phrase is what sets the lock.
	# ⚠ No HIGH_CARD exemption here, unlike norepeat: opening on a high card and
	# being locked to it IS the punishment this face is made of.
	var lf := SectionMod.lock_first(mod)
	var fk: int = int(extra.get("first_kind", -99))
	if lf < 1.0 and fk != -99 and int(ctx.kind) != fk:
		score = int(score * lf)
	var coins := int(result.get("coins", 0)) + int(ctx.coins_bonus)
	return {
		"score": score, "coins": coins, "popups": popups,
		"base": eff_chips, "mult": total_mult, "bonus": int(ctx.bonus),
	}
