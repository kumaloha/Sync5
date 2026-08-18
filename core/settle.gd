class_name Settle
extends RefCounted

## Settlement pipeline: pattern result → target joker → support jokers →
## protagonist → final score & coins.
##
## Formula (2026-08-05 用户拍板 chips×mult, supersedes docs/design/jokers.md B1):
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
		"early_finish": extra.get("early_finish", false),
		"section_idx": extra.get("section_idx", -1),
		"scoring_cards": result.get("resolved", []),
		"target_factor": 1.0,
		# ---- 2026-08-13 子波1 ----
		"acted_final": extra.get("acted_final", false),
		"seconds_left": extra.get("seconds_left", 0.0),
		"early_discards": extra.get("early_discards", false),
		"swaps": extra.get("swaps", 0),
		"discard_batch_max": extra.get("discard_batch_max", 0),
		"faces_discarded": extra.get("faces_discarded", 0),
		"swapped_scoring": extra.get("swapped_scoring", 0),
		"section_score": extra.get("section_score", 0),
		"section_target": extra.get("section_target", 0),
		"coins_factor": 1.0,
	}
	var mod := String(extra.get("mod", ""))
	var patch_power := SectionMod.joker_power(mod)
	var patch_restored := bool(extra.get("patch_restored", false))
	var pre_joker_mult: float = ctx.mult
	var pre_joker_additive: int = int(ctx.additive)
	var pre_joker_bonus: int = int(ctx.bonus)
	var pre_joker_bonus_pct: float = float(ctx.bonus_pct)
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
	# Scale one aggregate Joker delta after the complete chain. Per-Joker
	# rounding makes two +3 effects become +4 at half power; aggregate rounding
	# correctly makes their combined +6 become +3.
	if patch_power < 1.0 and not patch_restored:
		ctx.additive = pre_joker_additive + int(round(
			float(int(ctx.additive) - pre_joker_additive) * patch_power))
		ctx.bonus = pre_joker_bonus + int(round(
			float(int(ctx.bonus) - pre_joker_bonus) * patch_power))
		ctx.bonus_pct = pre_joker_bonus_pct + (
			float(ctx.bonus_pct) - pre_joker_bonus_pct) * patch_power
		if pre_joker_mult > 0.0:
			var joker_factor: float = float(ctx.mult) / pre_joker_mult
			ctx.mult = pre_joker_mult * (1.0 + (joker_factor - 1.0) * patch_power)
		for popup in popups:
			popup["text"] = "½ " + String(popup["text"])
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
	var qf := SectionMod.request_factor(mod)
	if qf < 1.0 and not bool(extra.get("request_met", true)):
		score = int(score * qf)
	var coins := int(round(float(int(result.get("coins", 0)))
		* float(ctx.get("coins_factor", 1.0)))) + int(ctx.coins_bonus)
	# ---- 乘区分解(2026-08-18 用户:「我打了 8 万分但不能理解 …… 得了解规则」)----
	# 展示层要把等式拆开念:基础 × 牌型 × 小丑 × (1+加成%) + 奖励 = 分。
	# `pattern_mult` = 牌型种子;`joker_mult` = 链上其余乘子合并(Target 条件倍率 +
	# 乘子类 support + patch 半效后的实效);两者相乘恰好 = ctx.mult(等式必须真)。
	var pat_mult: float = float(result.get("pmult", 1))
	var joker_mult: float = (float(ctx.mult) / pat_mult) if pat_mult > 0.0 else 1.0
	return {
		"score": score, "coins": coins, "popups": popups,
		"base": eff_chips, "mult": total_mult, "bonus": int(ctx.bonus),
		"pattern_mult": pat_mult, "joker_mult": joker_mult,
		"bonus_pct": float(ctx.bonus_pct),
	}
