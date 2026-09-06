-- core/beat.gd 的镜像:一拍的三次转移(开拍 / 结算 / 收尾), 游戏与探针共用;漏步拒绝执行。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("core%.$", ""))
local num = require(R .. "num")
local Run = require(P .. "run")
local Phrase = require(P .. "phrase")
local Joker = require(P .. "joker")
local SectionMod = require(P .. "modifier")
local Settle = require(P .. "settle")
local Economy = require(P .. "economy")
local BlindBoon = require(P .. "blind_boon")

local Beat = {}

local function warn(msg) io.stderr:write("[Beat] " .. msg .. "\n") end

function Beat._expect(run, want, who)
	if run.stage == want then return true end
	warn(string.format("%s() 在 stage=%d 时被调用, 期望 %d —— 有一步被跳过了, 本次调用已拒绝", who, run.stage, want))
	return false
end

-- 开一拍:解析脸 → 发牌 → 收入场费
function Beat.begin(run)
	local mod = run:face()
	run:ensure_mod_roll()
	local p = Phrase.new(run.deck, run.cache, run.coins)
	p.mod = mod
	p.phrase_idx = run.phrase_in_section
	p.mod_roll = run.mod_roll
	p.cache_scoring = Joker.slots_cache_scoring(run.joker_slots)
	p.boon = run:boon()
	p.cache_meta = run.cache_meta
	local section_budget = SectionMod.section_discard_budget(mod)
	if section_budget >= 0 then
		p.discard_budget = num.maxi(0, section_budget - run.section_discards_used)
	end
	if SectionMod.request_factor(mod) < 1.0 then
		p.request_prev_kind = run.prev_kind
	end
	p:start()
	if SectionMod.request_factor(mod) < 1.0 then
		p.request_goal = run:next_request_goal(p)
		p.request_met = p.request_goal == ""
	end
	local toll = SectionMod.phrase_toll(mod)
	if toll > 0 then p.coins = num.maxi(0, p.coins - toll) end
	run.coins = p.coins
	run.phrase_index = run.phrase_index + 1
	run.stage = Run.Stage.DECISION
	return p
end

-- 结算:锁定 → 组 ctx → Settle.run → 记 first/prev 牌型 → 金币与段分入账
function Beat.settle(run, p, flags)
	flags = flags or {}
	if not Beat._expect(run, Run.Stage.DECISION, "settle") then return {} end
	local res = p:lock_and_settle()
	run.section_kinds[num.int(num.get(res, "kind", -99))] = true
	local luck_rolls = {}
	for _, lj in ipairs(run.joker_slots) do
		if lj then
			for _ = 1, lj:chance_rolls_needed() do
				luck_rolls[#luck_rolls + 1] = run.deck:pick_index(10000) / 10000.0
			end
		end
	end
	for _, cb in ipairs(run.phrase_boosts) do
		if cb.chance ~= nil then
			luck_rolls[#luck_rolls + 1] = run.deck:pick_index(10000) / 10000.0
		end
	end
	local callout_unsolved = false
	if run.mod_roll.kind ~= nil and SectionMod.callout_factor(run:face()) < 1.0 then
		if num.get(run.mod_roll, "solved", false) then
			-- 已解除
		elseif num.int(num.get(res, "kind", -99)) == num.int(run.mod_roll.kind) then
			run.mod_roll.solved = true
			run.shelf_bonus = run.shelf_bonus + 1
		else
			callout_unsolved = true
		end
	end
	local ctx = {
		prev_kind = run.prev_kind,
		prev_target_hit = run.prev_target_hit,
		phrase_boosts = num.shallow(run.phrase_boosts),
		rolled_suit = num.int(num.get(run.mod_roll, "suit", -1)),
		callout_unsolved = callout_unsolved,
		luck_rolls = luck_rolls,
		odds_mult = Joker.slots_odds_mult(run.joker_slots),
		cache_rank_sum = p.cache_discard_rank_sum,
		acted_late = num.get(flags, "late", false) and true or false,
		discards = p.discards_used,
		coins = p.coins,
		phrase_idx = run.phrase_in_section,
		cache_cards = num.shallow(run.cache),
		early_finish = num.get(flags, "early", false) and true or false,
		acted_final = num.get(flags, "final", false) and true or false,
		seconds_left = num.get(flags, "secs_left", 0.0) + 0.0,
		early_discards = num.get(flags, "early_discards", false) and true or false,
		section_idx = run.section_idx,
		swaps = p.swap_actions_used,
		discard_batch_max = p.discard_batch_max,
		faces_discarded = p.faces_discarded,
		swapped_scoring = p:swapped_scoring_count(num.get(res, "resolved", {})),
		section_score = run.section_score,
		section_target = run:target(),
		mod = run:face(),
		first_kind = run.first_kind,
		request_met = p.request_met,
		patch_restored = SectionMod.restores_with_initial_cache(run:face()) and p:has_initial_cache_in_hand(),
	}
	local outcome = Settle.run(res, run.joker_slots, ctx)
	local raw_score = num.int(outcome.score)
	local boon_bonus = 0
	local replay_factor = BlindBoon.score_replay_factor(run:boon())
	if replay_factor > 0.0 then boon_bonus = boon_bonus + num.round(raw_score * replay_factor) end
	local previous_factor = BlindBoon.previous_raw_factor(run:boon())
	if previous_factor > 0.0 then boon_bonus = boon_bonus + num.round(run.previous_raw_score * previous_factor) end
	outcome.raw_score = raw_score
	outcome.boon_bonus = boon_bonus
	outcome.score = raw_score + boon_bonus
	run.previous_raw_score = raw_score
	if run.phrase_in_section == 0 then run.first_kind = num.int(num.get(res, "kind", -99)) end
	run.prev_kind = num.int(num.get(res, "kind", -99))
	run.prev_target_hit = num.get(outcome, "target_hit", false) and true or false
	run.phrase_boosts = {}
	p.coins = Economy.grant(p.coins, num.int(outcome.coins), run.joker_slots)
	run.coins = p.coins
	if SectionMod.section_discard_budget(run:face()) >= 0 then
		run.section_discards_used = run.section_discards_used + p.discards_used
	end
	run.section_score = run.section_score + num.int(outcome.score)
	run.stage = Run.Stage.SETTLED
	outcome.res = res
	outcome.ctx = ctx
	return outcome
end

-- 一拍收尾:缓存驱逐 + 成长钩子(顺序不能换)
function Beat.phrase_end(run, p, flags)
	flags = flags or {}
	if not Beat._expect(run, Run.Stage.SETTLED, "phrase_end") then return end
	p:cleanup()
	for _, j in ipairs(run.joker_slots) do
		if j then j:on_phrase_end({ early_finish = num.get(flags, "early", false) and true or false }) end
	end
	run.stage = Run.Stage.ENDED
end

return Beat
