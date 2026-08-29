class_name Settle
extends RefCounted

## Settlement pipeline: pattern result → target joker → support jokers →
## final score & coins.
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
## extra: {prev_kind, acted_late, discards, coins, phrase_idx, cache_cards, mod}
## `mod` is the section's boss-face modifier id ("" = none, see
## core/modifier.gd). Settle enforces the four scoring-side twists here:
## unplugged halves the target factor (the mirror copies the weakened one),
## static zeroes the
## flat-bonus channel, norepeat / rotation halve the final score.
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
		"prev_target_hit": extra.get("prev_target_hit", false),
		"rolled_suit": extra.get("rolled_suit", -1),
		"callout_unsolved": extra.get("callout_unsolved", false),
		"luck_rolls": extra.get("luck_rolls", []),
		"odds_mult": extra.get("odds_mult", 1.0),
		"cache_rank_sum": extra.get("cache_rank_sum", 0),
		"hidden_scoring": result.get("hidden_scoring", 0),
		"coins_factor": 1.0,
	}
	var mod := String(extra.get("mod", ""))
	# 斗牛士(2026-08-25):「脸的规则这拍咬到你没有」—— 每个税/削的应用点登记一次,
	# 链末按它给持有 face_coins 的卡发钱。只记事实(真的扣了), 不记假设。
	var face_bit := false
	# 变色灯(掷色税, 2026-08-25):中签花色的牌点数减半计分 —— 砍在 chips 层,
	# 让后面整条倍率链吃的是打过折的底(与「改基牌加在 chips 上」同层语义)。
	var sh := SectionMod.suit_half(mod)
	var rolled_suit := int(ctx.get("rolled_suit", -1))
	if sh < 1.0 and rolled_suit >= 0:
		var suit_cut := 0
		for sc in ctx.scoring_cards:
			if sc != null and not sc.is_wild() and int(sc.suit) == rolled_suit:
				suit_cut += int(round(float(sc.rank) * (1.0 - sh)))
		ctx.chips = maxi(0, int(ctx.chips) - suit_cut)
		if suit_cut > 0:
			face_bit = true
	var patch_power := SectionMod.joker_power(mod)
	var patch_restored := bool(extra.get("patch_restored", false))
	# ⚑ 消耗牌的当拍加成(2026-08-29):在小丑牌**之前**并进 ctx。
	# ⚠ 位置有讲究 —— 放在小丑牌之前, 意味着它和小丑牌**同处一条乘法链**、
	# 会被后面的 target/support 一起放大;放在之后则只是末尾平加。
	# 选前者的理由:玩家是「看到这手牌、判断这拍能打大」才烧的牌
	# (实时可点的设计意图), 它该吃到这一拍的全部倍率, 否则烧牌的时机判断就不值钱了。
	for b in extra.get("phrase_boosts", []):
		var continue_next := false
		# ⚠ 概率类加成(彩头「半概率 ×3」)走**与小丑牌同一条随机源** `luck_rolls`,
		# 灌铅骰的 `odds_mult` 因此对它一样生效 —— 不许各摇各的。
		# ⚑ 2026-08-30 补:`chance` 键此前**从没被读过**, 彩头实际是 100% 触发的 ×3,
		# 卡面在说谎, 而它的定价(724.6 分)也是按 100% 量的。
		# ⚠ **不用 `continue`** —— Godot 4 的 GDScript 在这个 for 里 continue 会
		# `Stack underflow! (Engine Bug)`(2026-08-30 实测刷了 311 万条)。改成显式 gate。
		var fires := true
		if b.has("chance"):
			var rolls: Array = ctx.get("luck_rolls", [])
			if rolls.is_empty():
				fires = false                 # 没有预掷 = 这一拍不判概率(与 fx 同)
			else:
				var rv: float = float(rolls.pop_front())
				fires = rv < minf(1.0, float(b["chance"])
					* float(ctx.get("odds_mult", 1.0)))
		# ⚠ `b = {}` 会改循环变量, 语义危险(GDScript 里字典是引用) —— 用显式分支。
		if not fires:
			continue_next = true
		if not continue_next and b.has("bonus_pct"):
			ctx.bonus_pct = float(ctx.bonus_pct) + float(b["bonus_pct"])
		if not continue_next and b.has("mult"):
			ctx.mult = float(ctx.mult) * float(b["mult"])
		if not continue_next and b.has("bonus"):
			ctx.bonus = int(ctx.bonus) + int(b["bonus"])
		if not continue_next and b.has("bonus_target_pct"):
			ctx.bonus = int(ctx.bonus) + int(round(float(b["bonus_target_pct"])
				* float(extra.get("section_target", 0))))
		if not continue_next and b.has("additive"):
			ctx.additive = int(ctx.additive) + int(b["additive"])
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
				face_bit = true
		if text != "":
			popups.append({"slot": i, "text": text})
	# Scale one aggregate Joker delta after the complete chain. Per-Joker
	# rounding makes two +3 effects become +4 at half power; aggregate rounding
	# correctly makes their combined +6 become +3.
	if patch_power < 1.0 and not patch_restored:
		face_bit = true
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
	# (主角被动曾在这里收链, slot = -1;2026-08-24 主角系统整体删除, 链到 support 为止)
	var eff_chips: int = int(ctx.chips) + int(ctx.additive)
	var total_mult: float = ctx.mult * (1.0 + ctx.bonus_pct)
	if SectionMod.bonus_disabled(mod):
		if int(ctx.bonus) != 0:
			face_bit = true
		ctx.bonus = 0
	var score := int(round(float(eff_chips) * total_mult + float(ctx.bonus)))
	# a repeated HIGH CARD is exempt — an unmade hand is nobody's routine,
	# and taxing it executed the Lone Wolf archetype outright (round 17)
	var rf := SectionMod.repeat_factor(mod)
	if rf < 1.0 and ctx.prev_kind == ctx.kind and int(ctx.kind) > Pattern.Kind.HIGH_CARD:
		score = int(score * rf)
		face_bit = true
	var zf := SectionMod.zero_discard_factor(mod)
	if zf < 1.0 and int(ctx.discards) == 0:
		score = int(score * zf)
		face_bit = true
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
		face_bit = true
	var qf := SectionMod.request_factor(mod)
	if qf < 1.0 and not bool(extra.get("request_met", true)):
		score = int(score * qf)
		face_bit = true
	# 渐强(2026-08-25):按拍序的得分因子, 前轻后重 —— 惩罚与奖励都写在曲线里。
	# ⚠ 挂在「拍级目标」上是做不出来的(判生死只在段末对总分), 所以挂得分侧。
	var phf := SectionMod.phase_factor(mod, int(ctx.phrase_idx))
	if phf != 1.0:
		score = int(score * phf)
		if phf < 1.0:
			face_bit = true   # 渐强的后半是奖励, 只有打折段算「咬」
	# 点名(2026-08-25):指定牌型未打出前, 全场按系数计分;解除判定在 Beat 里,
	# 解除的那一拍 callout_unsolved 已是 false ⇒ 立即恢复全额。
	var cof := SectionMod.callout_factor(mod)
	if cof < 1.0 and bool(ctx.callout_unsolved):
		score = int(score * cof)
		face_bit = true
	var coins := int(round(float(int(result.get("coins", 0)))
		* float(ctx.get("coins_factor", 1.0)))) + int(ctx.coins_bonus)
	# 斗牛士:被脸咬到的拍, 持有 face_coins 的卡发钱(与穷开心同族的持有期读法;
	# 金币通道不挂升级, 规则照旧)。
	if face_bit:
		for fj in slots:
			if fj != null:
				coins += int(fj._hold.get("face_coins", 0))
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
		# 本拍旗条件是否触发(镜面的连击谓词读它;Run 存成 prev_target_hit)。
		"target_hit": float(ctx.target_factor) > 1.0,
		# 脸的规则这拍是否真的咬了(斗牛士的口径;记事实不记假设)。
		"face_bit": face_bit,
	}
