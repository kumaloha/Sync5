-- core/settle.gd 的镜像:结算链 牌型 → target → support → 分数/金币。
-- score = (chips + Σ改基) × 牌型mult × target × (1 + Σ%) + Σ奖励;脸的四种扭曲在这里生效。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("core%.$", ""))
local num = require(R .. "num")
local Pattern = require(P .. "pattern")
local GameConfig = require(P .. "config")
local SectionMod = require(P .. "modifier")

local Settle = {}

-- slots: {Joker | false} × 4(0 号 = target);extra: 见 core/beat.gd 拼的 ctx
function Settle.run(result, slots, extra)
	if result == nil or next(result) == nil then
		return { score = 0, coins = 0, popups = {}, base = 0, mult = 1.0 }
	end
	extra = extra or {}
	local ctx = {
		kind = num.get(result, "kind", -1),
		base_score = num.int(num.get(result, "score", 0)),
		chips = num.int(num.get(result, "chips", 0)),
		additive = 0,
		bonus = 0,
		mult = num.get(result, "pmult", 1) + 0.0,
		bonus_pct = 0.0,
		coins_bonus = 0,
		prev_kind = num.get(extra, "prev_kind", -99),
		acted_late = num.get(extra, "acted_late", false),
		discards = num.get(extra, "discards", 0),
		coins = num.get(extra, "coins", 0),
		phrase_idx = num.get(extra, "phrase_idx", -1),
		cache_cards = num.get(extra, "cache_cards", {}),
		early_finish = num.get(extra, "early_finish", false),
		section_idx = num.get(extra, "section_idx", -1),
		scoring_cards = num.get(result, "resolved", {}),
		target_factor = 1.0,
		acted_final = num.get(extra, "acted_final", false),
		seconds_left = num.get(extra, "seconds_left", 0.0),
		early_discards = num.get(extra, "early_discards", false),
		swaps = num.get(extra, "swaps", 0),
		discard_batch_max = num.get(extra, "discard_batch_max", 0),
		faces_discarded = num.get(extra, "faces_discarded", 0),
		swapped_scoring = num.get(extra, "swapped_scoring", 0),
		section_score = num.get(extra, "section_score", 0),
		section_target = num.get(extra, "section_target", 0),
		prev_target_hit = num.get(extra, "prev_target_hit", false),
		rolled_suit = num.get(extra, "rolled_suit", -1),
		callout_unsolved = num.get(extra, "callout_unsolved", false),
		luck_rolls = num.get(extra, "luck_rolls", {}),
		odds_mult = num.get(extra, "odds_mult", 1.0),
		cache_rank_sum = num.get(extra, "cache_rank_sum", 0),
		hidden_scoring = num.get(result, "hidden_scoring", 0),
		coins_factor = 1.0,
	}
	local mod = tostring(num.get(extra, "mod", ""))
	local face_bit = false
	-- 变色灯:中签花色的牌点数减半计分(砍在 chips 层)
	local sh = SectionMod.suit_half(mod)
	local rolled_suit = num.int(num.get(ctx, "rolled_suit", -1))
	if sh < 1.0 and rolled_suit >= 0 then
		local suit_cut = 0
		for _, sc in ipairs(ctx.scoring_cards) do
			if sc ~= nil and not sc:is_wild() and num.int(sc.suit) == rolled_suit then
				suit_cut = suit_cut + num.round(sc.rank * (1.0 - sh))
			end
		end
		ctx.chips = num.maxi(0, num.int(ctx.chips) - suit_cut)
		if suit_cut > 0 then face_bit = true end
	end
	local patch_power = SectionMod.joker_power(mod)
	local patch_restored = num.get(extra, "patch_restored", false) and true or false
	-- 消耗牌的当拍加成:在小丑牌之前并进 ctx(同处一条乘法链)
	for _, b in ipairs(num.get(extra, "phrase_boosts", {})) do
		local fires = true
		if b.chance ~= nil then
			local rolls = num.get(ctx, "luck_rolls", {})
			if #rolls == 0 then
				fires = false
			else
				local rv = table.remove(rolls, 1) + 0.0
				fires = rv < num.minf(1.0, (b.chance + 0.0) * (num.get(ctx, "odds_mult", 1.0) + 0.0))
			end
		end
		if fires then
			if b.bonus_pct ~= nil then ctx.bonus_pct = ctx.bonus_pct + b.bonus_pct end
			if b.mult ~= nil then ctx.mult = ctx.mult * b.mult end
			if b.bonus ~= nil then ctx.bonus = num.int(ctx.bonus) + num.int(b.bonus) end
			if b.bonus_target_pct ~= nil then
				ctx.bonus = num.int(ctx.bonus) + num.round((b.bonus_target_pct + 0.0)
					* (num.get(extra, "section_target", 0) + 0.0) / GameConfig.PHRASES_PER_SECTION)
			end
			if b.additive ~= nil then ctx.additive = num.int(ctx.additive) + num.int(b.additive) end
		end
	end
	local pre_joker_mult = ctx.mult
	local pre_joker_additive = num.int(ctx.additive)
	local pre_joker_bonus = num.int(ctx.bonus)
	local pre_joker_bonus_pct = ctx.bonus_pct + 0.0
	local popups = {}
	for i = 1, #slots do
		local j = slots[i]
		if j then
			local pre_mult = ctx.mult
			local text = j:apply(ctx)
			if i == 1 and pre_mult > 0.0 then
				ctx.target_factor = ctx.mult / pre_mult
				local tp = SectionMod.target_power(mod)
				if tp < 1.0 and ctx.target_factor > 1.0 then
					local hf = 1.0 + (ctx.target_factor - 1.0) * tp
					ctx.mult = pre_mult * hf
					ctx.target_factor = hf
					face_bit = true
				end
			end
			if text ~= "" then
				popups[#popups + 1] = { slot = i - 1, text = text }
			end
		end
	end
	-- 补丁脸:小丑牌的合计增量按 patch_power 缩放(链末一次取整)
	if patch_power < 1.0 and not patch_restored then
		if num.int(ctx.additive) ~= pre_joker_additive or num.int(ctx.bonus) ~= pre_joker_bonus
				or (ctx.bonus_pct + 0.0) ~= pre_joker_bonus_pct
				or (pre_joker_mult > 0.0 and (ctx.mult + 0.0) ~= pre_joker_mult) then
			face_bit = true
		end
		ctx.additive = pre_joker_additive + num.round((num.int(ctx.additive) - pre_joker_additive) * patch_power)
		ctx.bonus = pre_joker_bonus + num.round((num.int(ctx.bonus) - pre_joker_bonus) * patch_power)
		ctx.bonus_pct = pre_joker_bonus_pct + ((ctx.bonus_pct + 0.0) - pre_joker_bonus_pct) * patch_power
		if pre_joker_mult > 0.0 then
			local joker_factor = (ctx.mult + 0.0) / pre_joker_mult
			ctx.mult = pre_joker_mult * (1.0 + (joker_factor - 1.0) * patch_power)
		end
		for _, popup in ipairs(popups) do
			popup.text = "½ " .. popup.text
		end
	end
	local eff_chips = num.int(ctx.chips) + num.int(ctx.additive)
	local total_mult = ctx.mult * (1.0 + ctx.bonus_pct)
	if SectionMod.bonus_disabled(mod) then
		if num.int(ctx.bonus) ~= 0 then face_bit = true end
		ctx.bonus = 0
	end
	local score = num.round(eff_chips * total_mult + ctx.bonus)
	local rf = SectionMod.repeat_factor(mod)
	if rf < 1.0 and ctx.prev_kind == ctx.kind and num.int(ctx.kind) > Pattern.Kind.HIGH_CARD then
		score = num.int(score * rf)
		face_bit = true
	end
	local zf = SectionMod.zero_discard_factor(mod)
	if zf < 1.0 and num.int(ctx.discards) == 0 then
		score = num.int(score * zf)
		face_bit = true
	end
	local lf = SectionMod.lock_first(mod)
	local fk = num.int(num.get(extra, "first_kind", -99))
	if lf < 1.0 and fk ~= -99 and num.int(ctx.kind) ~= fk then
		score = num.int(score * lf)
		face_bit = true
	end
	local qf = SectionMod.request_factor(mod)
	if qf < 1.0 and not num.get(extra, "request_met", true) then
		score = num.int(score * qf)
		face_bit = true
	end
	local phf = SectionMod.phase_factor(mod, num.int(ctx.phrase_idx))
	if phf ~= 1.0 then
		score = num.int(score * phf)
		if phf < 1.0 then face_bit = true end
	end
	local cof = SectionMod.callout_factor(mod)
	if cof < 1.0 and ctx.callout_unsolved then
		score = num.int(score * cof)
		face_bit = true
	end
	local coins = num.round(num.int(num.get(result, "coins", 0)) * (num.get(ctx, "coins_factor", 1.0) + 0.0))
		+ num.int(ctx.coins_bonus)
	if face_bit then
		for _, fj in ipairs(slots) do
			if fj then coins = coins + num.int(num.get(fj._hold, "face_coins", 0)) end
		end
	end
	local pat_mult = num.get(result, "pmult", 1) + 0.0
	local joker_mult = 1.0
	if pat_mult > 0.0 then joker_mult = (ctx.mult + 0.0) / pat_mult end
	return {
		score = score, coins = coins, popups = popups,
		base = eff_chips, mult = total_mult, bonus = num.int(ctx.bonus),
		pattern_mult = pat_mult, joker_mult = joker_mult,
		bonus_pct = ctx.bonus_pct + 0.0,
		target_hit = (ctx.target_factor + 0.0) > 1.0,
		face_bit = face_bit,
	}
end

return Settle
