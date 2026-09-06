-- 五族金样的重放器(check.lua 调)。每个 fam(g, eq) 用镜像重放 golden 的输入, 逐字段 eq。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("tools%.$", ""))
local num = require(R .. "num")
local Rng = require(R .. "rng")
local Card = require(R .. "core.card")
local Deck = require(R .. "core.deck")
local Pattern = require(R .. "core.pattern")
local Settle = require(R .. "core.settle")
local Joker = require(R .. "core.joker")
local Economy = require(R .. "core.economy")
local SectionMod = require(R .. "core.modifier")
local Consumable = require(R .. "core.consumable")
local BlindBoon = require(R .. "core.blind_boon")
local GameConfig = require(R .. "core.config")
local Fx = require(R .. "core.fx")

local fams = {}
local fmt = string.format

local function mk_cards(pairs_)
	local out = {}
	for _, p in ipairs(pairs_) do out[#out + 1] = Card.new(p[1], p[2]) end
	return out
end

local function labels(arr)
	local out = {}
	for _, c in ipairs(arr) do out[#out + 1] = c:label() end
	return table.concat(out, " ")
end

-- 任意值 → 可比较的字符串(浮点走位串, 表按键排序)
local function canon(v)
	local t = type(v)
	if t == "number" then
		if math.floor(v) == v and math.abs(v) < 2 ^ 53 then return fmt("%d", v) end
		return "f:" .. num.f64hex(v)
	elseif t == "boolean" then
		return v and "T" or "F"
	elseif t == "string" then
		return "'" .. v .. "'"
	elseif t == "table" then
		if getmetatable(v) and v.digest then return v:digest() end
		local parts = {}
		if num.is_array(v) then
			for i = 1, #v do parts[#parts + 1] = canon(v[i]) end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		for _, k in ipairs(num.sorted_keys(v)) do
			parts[#parts + 1] = tostring(k) .. "=" .. canon(v[k])
		end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif v == nil then
		return "nil"
	end
	return tostring(v)
end
fams.canon = canon

local function mk_slots(spec)
	local slots = {}
	for i = 1, #spec do
		local s = spec[i]
		if s == false then
			slots[i] = false
		else
			local j = Joker.by_id(s.id)
			j.state = num.deep(s.state)
			slots[i] = j
		end
	end
	return slots
end

local function mk_extra(spec)
	local x = num.deep(spec)
	x.cache_cards = mk_cards(spec.cache_cards)
	return x
end

local function mk_result(case)
	local cards = mk_cards(case.cards)
	local res = Pattern.evaluate_best(cards, {})
	res.hidden_scoring = case.hidden
	return res
end

local function outcome_canon(o)
	return canon({
		score = o.score, coins = o.coins, base = o.base, mult = o.mult + 0.0, bonus = o.bonus,
		pattern_mult = o.pattern_mult + 0.0, joker_mult = o.joker_mult + 0.0, bonus_pct = o.bonus_pct + 0.0,
		target_hit = o.target_hit, face_bit = o.face_bit, popups = (function()
			local pp = {}
			for _, p in ipairs(o.popups) do pp[#pp + 1] = { p.slot, p.text } end
			return pp
		end)(),
	})
end

local function expected_canon(o)
	return canon({
		score = o.score, coins = o.coins, base = o.base, mult = o.mult + 0.0, bonus = o.bonus,
		pattern_mult = o.pattern_mult + 0.0, joker_mult = o.joker_mult + 0.0, bonus_pct = o.bonus_pct + 0.0,
		target_hit = o.target_hit, face_bit = o.face_bit, popups = o.popups,
	})
end

local function run_case(case, tag, eq)
	local res = mk_result(case)
	local slots = mk_slots(case.slots)
	local extra = mk_extra(case.extra)
	local out = Settle.run(res, slots, extra)
	local got, want = outcome_canon(out), expected_canon(case.out)
	if got ~= want then
		local ids = {}
		for _, s in ipairs(case.slots) do ids[#ids + 1] = s and s.id or "-" end
		tag = tag .. fmt(" [%s | %s | mod=%s]", labels(mk_cards(case.cards)), table.concat(ids, ","), tostring(case.extra.mod))
	end
	eq(got, want, tag)
end

-- ---------------------------------------------------------------- rng
function fams.rng(g, eq)
	for _, case in ipairs(g) do
		local rng = Rng.new():seed(case.seed)
		for i, op in ipairs(case.ops) do
			local k = op[1]
			local tag = fmt("rng seed=%d step=%d %s", case.seed, i, k)
			if k == "i" then
				eq(rng:randi(), op[2], tag)
			elseif k == "r" then
				eq(rng:randi_range(op[2], op[3]), op[4], tag .. fmt("(%d,%d)", op[2], op[3]))
			elseif k == "f" then
				eq(num.f64hex(rng:randf()), num.f64hex(op[2]), tag)
			elseif k == "s" then
				eq(rng:state_hex(), op[2], tag)
			elseif k == "S" then
				rng:set_state_hex(op[2])
			end
		end
	end
end

-- ---------------------------------------------------------------- pattern
function fams.pattern(g, eq)
	for i, case in ipairs(g) do
		local cards = mk_cards(case.cards)
		local rules = case.rules
		local res = Pattern.evaluate_best(cards, rules)
		local tag = fmt("pattern #%d [%s]", i - 1, labels(cards))
		eq(res.kind, case.kind, tag .. " kind")
		eq(res.name, case.name, tag .. " name")
		eq(res.chips, case.chips, tag .. " chips")
		eq(res.pmult, case.pmult, tag .. " pmult")
		eq(res.rank_sum, case.rank_sum, tag .. " rank_sum")
		eq(res.score, case.score, tag .. " score")
		eq(res.coins, case.coins, tag .. " coins")
		eq(labels(res.resolved), table.concat(case.resolved, " "), tag .. " resolved")
		eq(Pattern.best_score_of(cards, rules), case.best, tag .. " best_score_of")
		local five = { cards[1], cards[2], cards[3], cards[4], cards[5] }
		eq(Pattern.score_five(five, rules), case.five, tag .. " score_five")
		eq(Pattern.evaluate_best(five, rules).kind, case.five_kind, tag .. " five_kind")
	end
end

-- ---------------------------------------------------------------- settle
function fams.settle(g, eq)
	for i, case in ipairs(g) do
		run_case(case, fmt("settle #%d", i - 1), eq)
	end
end

-- ---------------------------------------------------------------- fx
function fams.fx(g, eq)
	-- ① 每张卡的电池
	for i, case in ipairs(g.battery) do
		run_case(case, fmt("fx battery #%d", i - 1), eq)
	end
	-- ② 钩子序列 + 元数据
	for _, h in ipairs(g.hooks) do
		local j = Joker.by_id(h.id)
		local tag = "fx hooks " .. h.id
		local trail = { canon(j.state) }
		j:on_discard(2); trail[#trail + 1] = canon(j.state)
		j:on_shop_event("reroll"); trail[#trail + 1] = canon(j.state)
		j:on_shop_event("buy"); trail[#trail + 1] = canon(j.state)
		j:on_shop_event("target_swap"); trail[#trail + 1] = canon(j.state)
		j:on_phrase_end({ early_finish = true }); trail[#trail + 1] = canon(j.state)
		j:on_phrase_end({ early_finish = false }); trail[#trail + 1] = canon(j.state)
		j:on_discard(0); trail[#trail + 1] = canon(j.state)
		local life1 = j:tick_section_life(); trail[#trail + 1] = canon(j.state)
		local life2 = j:tick_section_life(); trail[#trail + 1] = canon(j.state)
		local want = {}
		for k, st in ipairs(h.trail) do want[k] = canon(st) end
		eq(table.concat(trail, "|"), table.concat(want, "|"), tag .. " trail")
		eq(canon({ life1, life2 }), canon(h.life), tag .. " life")
		eq(j:trial_free(), h.trial_free, tag .. " trial_free")
		eq(j:chance_rolls_needed(), h.rolls, tag .. " rolls")
		eq(num.f64hex(j:swap_bonus_pct()), num.f64hex(h.swap_bonus), tag .. " swap_bonus")
		eq(j:is_rule_card(), h.rule, tag .. " rule")
		eq(j:has_effects(), h.has_fx, tag .. " has_fx")
		eq(num.f64hex(j:shelf_target_mult()), num.f64hex(h.shelf_mult), tag .. " shelf_mult")
		eq(j:shelf_target_guaranteed(), h.shelf_guar, tag .. " shelf_guar")
		eq(j.cn_name, h.cn, tag .. " cn"); eq(j.kind, h.kind, tag .. " kind"); eq(j.rarity, h.rarity, tag .. " rarity")
		local d2 = Deck.new(77)
		j:on_acquire(d2)
		eq(d2:total(), h.deck_total, tag .. " acquire total")
		eq(canon(d2.rules), canon(h.deck_rules), tag .. " acquire rules")
		eq(d2.trim_low, h.deck_trim, tag .. " acquire trim")
		eq(canon(d2.wild_extra), canon(h.deck_wildx), tag .. " acquire wildx")
		eq(canon(j:clone().state), canon(h.clone_state), tag .. " clone")
	end
	-- ③ 槽统计 + 经济
	for si, s in ipairs(g.statics) do
		local tag = fmt("fx statics #%d", si - 1)
		local slots = mk_slots(s.slots)
		local rng = Rng.new():seed(70000 + si - 1)
		-- rand_slots 在 Godot 侧消耗了 rng;这里不重建槽, 而是从金样里取 rng 消耗后的状态?
		-- 不:weighted_pick 的输入 rng 状态无法从槽反推 ⇒ 金样里 picked 只在 rng 状态可复现时比。
		-- Godot 侧 rand_slots 的消耗步数取决于池子, 镜像逐步复刻它(见 replay_rand_slots)。
		local pool = Joker.pool()
		eq(Joker.slots_shelf_size(slots, (si - 1) % 3), s.shelf_size, tag .. " shelf_size")
		eq(Joker.slots_buy_limit(slots), s.buy_limit, tag .. " buy_limit")
		eq(Joker.slots_price_delta(slots), s.price_delta, tag .. " price_delta")
		eq(Joker.slots_coin_cap(slots), s.coin_cap, tag .. " coin_cap")
		eq(num.f64hex(Joker.slots_odds_mult(slots)), num.f64hex(s.odds), tag .. " odds")
		eq(Joker.slots_cache_scoring(slots), s.cache_scoring, tag .. " cache_scoring")
		eq(num.f64hex(Joker.slots_target_mult(slots)), num.f64hex(s.target_mult), tag .. " target_mult")
		eq(Joker.slots_copy_consumable(slots), s.copy_cons, tag .. " copy_cons")
		eq(Joker.first_free_support(slots), s.free_support, tag .. " free_support")
		eq(Joker.has_room_for(slots, "target"), s.room_t, tag .. " room_t")
		eq(Joker.has_room_for(slots, "support"), s.room_s, tag .. " room_s")
		eq(Joker.slots_guarantee_target(slots), s.guar, tag .. " guar")
		eq(canon(Joker.slots_loan(slots)), canon(s.loan), tag .. " loan")
		eq(Joker.slots_rule_guaranteed(slots), s.rule_guar, tag .. " rule_guar")
		local prices = {}
		local weights = {}
		for k, pj in ipairs(pool) do
			prices[k] = { pj.id, Economy.joker_price(pj, false), Economy.joker_price(pj, true),
				Economy.sell_value(pj), Economy.shelf_price(pj, slots) }
			weights[k] = Economy.shelf_weight(pj, s.tm, s.rm)
		end
		eq(canon(prices), canon(s.prices), tag .. " prices")
		eq(canon(weights), canon(s.weights), tag .. " weights")
		eq(canon({ Economy.grant(3, 4, slots), Economy.grant(20, 4, slots), Economy.grant(20, -2, slots) }), canon(s.grant), tag .. " grant")
		eq(Economy.cap_held(30, slots), s.cap_held, tag .. " cap_held")
		eq(canon({ Economy.reroll_cost(0), Economy.reroll_cost(3), Economy.reroll_cost(1, -2), Economy.reroll_cost(0, -9) }), canon(s.reroll), tag .. " reroll")
		eq(canon({ Economy.discard_cost(0), Economy.discard_cost(3) }), canon(s.discard_cost), tag .. " discard_cost")
		-- weighted_pick:rng 状态由 golden 记的 picked 与镜像的 replay_rand_slots 对齐后比
		local rng2 = fams.replay_rand_slots(Rng.new():seed(70000 + si - 1), (si - 1) % 5)
		local picked = Economy.weighted_pick(pool, 3, s.tm, rng2, s.rm, s.boost)
		local pids = {}
		for _, pj in ipairs(picked) do pids[#pids + 1] = pj.id end
		eq(canon(pids), canon(s.picked), tag .. " weighted_pick")
	end
	-- ④ 脸
	local F = g.faces
	for _, f in ipairs(F.list) do
		local id = f.id
		local tag = "fx face " .. id
		local m = SectionMod.by_id(id)
		eq(m ~= nil, true, tag .. " by_id")
		if m then
			eq(m.cn_name, f.cn, tag .. " cn")
			eq(canon(m.params), canon(f.params), tag .. " params")
		end
		eq(canon(SectionMod.attack_axes(id)), canon(f.axes), tag .. " axes")
		eq(SectionMod.affects_settle(id), f.settle, tag .. " affects_settle")
		eq(canon(SectionMod.tiers_of(id)), canon(f.tiers), tag .. " tiers")
		eq(SectionMod.tier_of(id), f.tier, tag .. " tier")
		eq(SectionMod.base_of(id), f.base, tag .. " base")
		eq(canon(SectionMod.combo_of(id)), canon(f.combo), tag .. " combo")
		eq(SectionMod.proof(id), f.proof, tag .. " proof")
		eq(SectionMod.tape_required(id), f.tape, tag .. " tape")
		eq(canon({ SectionMod.unlocked_at(id, -1), SectionMod.unlocked_at(id, 1), SectionMod.unlocked_at(id, 9) }), canon(f.unlocked), tag .. " unlocked")
		local v = { SectionMod.time_penalty(id), SectionMod.phrase_toll(id), SectionMod.target_power(id),
			SectionMod.repeat_factor(id), SectionMod.zero_discard_factor(id), SectionMod.cache_evict(id),
			SectionMod.cache_cap(id), SectionMod.lock_first(id), SectionMod.target_mult(id),
			SectionMod.hide_refill(id), SectionMod.hide_faces(id), SectionMod.discard_lock_last(id),
			SectionMod.swap_lock_last(id), SectionMod.discard_action_limit(id), SectionMod.swap_action_limit(id),
			SectionMod.action_limit(id), SectionMod.discard_cards_max(id), SectionMod.action_cards_max(id),
			SectionMod.cache_blocks_red(id), SectionMod.refill_rank_min(id), SectionMod.refill_rank_max(id),
			SectionMod.cache_lock_phrases(id), SectionMod.seals_lowest_start(id), SectionMod.seals_oldest_cache(id),
			SectionMod.seals_random_start(id), SectionMod.seals_random_cache(id), SectionMod.hide_random(id),
			SectionMod.hide_suits(id), SectionMod.hide_ranks(id), SectionMod.roll_chance(id),
			SectionMod.roll_cache_extra(id), SectionMod.rolls_suit(id), SectionMod.suit_half(id),
			SectionMod.callout_factor(id), SectionMod.rolls_kind(id), SectionMod.required_kinds(id),
			SectionMod.variety_penalty(id), SectionMod.restores_with_initial_cache(id),
			SectionMod.section_discard_budget(id), SectionMod.exclusive_action_tracks(id),
			SectionMod.request_factor(id), SectionMod.joker_power(id), SectionMod.bonus_disabled(id),
			SectionMod.discard_open(id, 2.0), SectionMod.swap_open(id, 2.0), SectionMod.discard_open(id, 1.5) }
		eq(canon(v), canon(f.v), tag .. " params-v")
		local pf, tp = {}, {}
		for idx = 0, 5 do
			pf[#pf + 1] = SectionMod.phase_factor(id, idx)
			tp[#tp + 1] = SectionMod.time_penalty_at(id, idx)
		end
		eq(canon(pf), canon(f.pf), tag .. " phase_factor")
		eq(canon(tp), canon(f.tp), tag .. " time_penalty_at")
	end
	local pools = {}
	for sidx = 0, GameConfig.SECTIONS_PER_RUN - 1 do pools[#pools + 1] = SectionMod.pool_for(sidx) end
	eq(canon(pools), canon(F.pools), "fx faces pools")
	eq(canon(SectionMod.pooled_ids()), canon(F.pooled), "fx faces pooled")
	eq(canon(SectionMod.axis_ids()), canon(F.axes), "fx faces axes")
	eq(canon({ SectionMod.tier_is_fixed(1), SectionMod.tier_is_fixed(4) }), canon(F.fixed), "fx faces fixed")
	for _, r in ipairs(F.rolls) do
		local rng = Rng.new():seed(r.seed)
		local out = SectionMod.roll_run(rng, r.run_index)
		local arr = {}
		for _, w in ipairs(GameConfig.WALL_SECTIONS) do arr[#arr + 1] = tostring(num.get(out, w, "")) end
		local tag = fmt("fx roll_run seed=%d ri=%d", r.seed, r.run_index)
		eq(canon(arr), canon(r.faces), tag)
		eq(rng:randi(), r.after, tag .. " after")
		eq(SectionMod.roll((r.seed - 80000) % 4, rng, { arr[1] }, r.run_index), r.single, tag .. " single")
	end
	-- ⑤ 消耗牌
	local C = g.consumables
	local rows = {}
	for _, e in ipairs(require(R .. "core.db").consumables()) do rows[tostring(e.id)] = e end
	for _, cs in ipairs(C.list) do
		local c = Consumable.new(rows[cs.id])
		local tag = "fx consumable " .. cs.id
		eq(c:is_instant(), cs.instant, tag .. " instant")
		eq(c:is_rule_card(), cs.rule, tag .. " rule")
		eq(c:fire_label(), cs.label, tag .. " label")
		eq(c.price, cs.price, tag .. " price")
		eq(c:display_name(), cs.name, tag .. " name")
		eq(c:clone().queued_beats, cs.clone_q, tag .. " clone_q")
		local due = {}
		for beat = 1, 6 do
			for q = 0, 2 do due[#due + 1] = c:due_on(beat, q) end
		end
		eq(canon(due), canon(cs.due), tag .. " due")
	end
	for _, sh in ipairs(C.shelves) do
		local rng = Rng.new():seed(sh.seed)
		local out = Consumable.roll_shelf(sh.held, sh.rule_first, sh.n, function(n) return rng:randi_range(0, n - 1) end)
		local ids = {}
		for _, r in ipairs(out) do ids[#ids + 1] = r and tostring(r.id) or "" end
		eq(canon(ids), canon(sh.ids), fmt("fx roll_shelf seed=%d", sh.seed))
	end
	-- ⑥ 增益 + 配置
	local B = g.boons
	eq(canon(BlindBoon.ids()), canon(B.ids), "fx boons ids")
	for k, want in ipairs(B.rolls) do
		eq(BlindBoon.roll(Rng.new():seed(95000 + k - 1)), want, fmt("fx boon roll seed=%d", 95000 + k - 1))
	end
	local bp = {}
	for _, bid in ipairs(BlindBoon.ids()) do
		bp[#bp + 1] = { bid, BlindBoon.score_replay_factor(bid), BlindBoon.spotlight_cards(bid),
			BlindBoon.previous_raw_factor(bid), BlindBoon.ghost_first_discard(bid), BlindBoon.by_id(bid).cn_name }
	end
	eq(canon(bp), canon(B.params), "fx boon params")
	local cfg = g.config
	local mine = {
		pps = GameConfig.PHRASES_PER_SECTION, shop = GameConfig.PHRASES_PER_SHOP, sps = GameConfig.SHOPS_PER_SECTION,
		spg = GameConfig.SECTIONS_PER_GIG, gpr = GameConfig.GIGS_PER_RUN, spr = GameConfig.SECTIONS_PER_RUN,
		walls = GameConfig.WALL_SECTIONS, targets = GameConfig.SECTION_TARGETS, avg = GameConfig.avg_beat_target(),
		hand = GameConfig.HAND_SIZE, cache = GameConfig.CACHE_CAP, bd = GameConfig.BEAT_DISCARDS,
		bb = GameConfig.BEAT_DISCARD_BATCH, bs = GameConfig.BEAT_SWAPS, blind = GameConfig.BLIND_SAMPLES,
		coins = GameConfig.STARTING_COINS, dc = GameConfig.DISCARD_COST, wage = GameConfig.SECTION_CLEAR_REWARD,
		rb = GameConfig.DRAFT_REROLL_BASE, rs = GameConfig.DRAFT_REROLL_STEP,
		s1 = { GameConfig.S1_FACE_MIN_RUN, GameConfig.S1_EASY_CHANCE },
		windows = { GameConfig.LATE_ACT_WINDOW, GameConfig.FINAL_ACT_WINDOW, GameConfig.EARLY_DISCARD_WINDOW,
			GameConfig.EARLY_FINISH_LEFT, GameConfig.RESOLVE_FEEDBACK },
		per_section = {}, budget = {},
	}
	for sidx = 0, GameConfig.SECTIONS_PER_RUN - 1 do
		local d = GameConfig.phrase_duration(sidx)
		mine.per_section[#mine.per_section + 1] = { d, GameConfig.warning_time(d), GameConfig.lock_time(d),
			GameConfig.is_wall(sidx), GameConfig.gig_of(sidx), GameConfig.blind_name(sidx), GameConfig.gig_name(sidx),
			GameConfig.section_target(sidx) }
		for _, dur in ipairs({ 8.0, 6.0, 4.0 }) do
			mine.budget[#mine.budget + 1] = { sidx, dur, GameConfig.beat_discards(dur, sidx), GameConfig.discard_batch(dur, sidx) }
		end
	end
	for _, k in ipairs(num.sorted_keys(cfg)) do
		eq(canon(mine[k]), canon(cfg[k]), "fx config " .. k)
	end
	-- 覆盖报告:jokers.json 里的操作码有没有都被电池走到
	local uncovered = {}
	for _, e in ipairs(require(R .. "core.db").jokers()) do
		for _, ef in ipairs(e.effects or {}) do
			for k in pairs(ef.when or {}) do
				if not Fx._seen_when[k] then uncovered[#uncovered + 1] = "when." .. k end
			end
			for k in pairs(ef["do"] or {}) do
				if not Fx._seen_do[k] then uncovered[#uncovered + 1] = "do." .. k end
			end
		end
	end
	eq(#uncovered, 0, "fx opcode coverage: " .. table.concat(uncovered, " "))
end

-- Godot 侧 tools/golden.gd::rand_slots 的 RNG 消耗复刻(只为让 weighted_pick 的 rng 状态对齐)。
function fams.replay_rand_slots(rng, n)
	local DB = require(R .. "core.db")
	local targets, supports = {}, {}
	for _, e in ipairs(DB.jokers()) do
		if tostring(e.kind) == "target" then targets[#targets + 1] = tostring(e.id) else supports[#supports + 1] = tostring(e.id) end
	end
	local slots = { false, false, false, false }
	if n > 0 and rng:randi_range(0, 3) > 0 then
		slots[1] = Joker.by_id(targets[rng:randi_range(0, #targets - 1) + 1])
	end
	local k = 1
	while k <= 3 and k <= n do
		local sid = supports[rng:randi_range(0, #supports - 1) + 1]
		local dup = false
		for _, j in ipairs(slots) do
			if j and j.id == sid then dup = true end
		end
		if not dup then slots[k + 1] = Joker.by_id(sid) end
		k = k + 1
	end
	for _, j in ipairs(slots) do
		if j then
			for _, cname in ipairs(num.sorted_keys(j._counters)) do
				j.state[cname] = rng:randi_range(0, 12) + 0.0
			end
		end
	end
	return rng
end

return fams
