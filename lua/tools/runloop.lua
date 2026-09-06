-- 整局金样的重放器:按 tools/golden.gd::_play_run 记录的动作驱动镜像, 逐拍比摘要。
-- 也是「一局的循环」的 Lua 参照实现(探针口径:不死局);游戏侧编排在 app/phrase.lua。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("tools%.$", ""))
local num = require(R .. "num")
local Rng = require(R .. "rng")
local Deck = require(R .. "core.deck")
local Run = require(R .. "core.run")
local Beat = require(R .. "core.beat")
local Economy = require(R .. "core.economy")
local GameConfig = require(R .. "core.config")
local SectionMod = require(R .. "core.modifier")
local BlindBoon = require(R .. "core.blind_boon")
local Tutorial = require(R .. "core.tutorial")
local Shop = require(R .. "app.shop")

local M = {}

-- 与 tools/golden.gd::canon 逐字相同
local function canon(v)
	local t = type(v)
	if v == nil then return "nil" end
	if t == "boolean" then return v and "T" or "F" end
	if t == "number" then
		if math.floor(v) == v and math.abs(v) < 2 ^ 53 then return string.format("%d", v) end
		return "f:" .. num.f64hex(v)
	end
	if t == "string" then return "'" .. v .. "'" end
	if t == "table" then
		if next(v) == nil then return "{}" end   -- 摘要里的空表都是字典(mod_roll / wild_extra), 与 Godot 同
		if num.is_array(v) then
			local parts = {}
			for i = 1, #v do parts[i] = canon(v[i]) end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = tostring(k) end
		table.sort(keys)
		local parts = {}
		for _, k in ipairs(keys) do
			local val = v[k]
			if val == nil then val = v[tonumber(k)] end
			parts[#parts + 1] = k .. "=" .. canon(val)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "'" .. tostring(v) .. "'"
end
M.canon = canon

local function joker_digest(j)
	if not j then return "-" end
	local parts = {}
	for _, k in ipairs(num.sorted_keys(j.state)) do parts[#parts + 1] = k .. "=" .. canon(j.state[k]) end
	return j.id .. "{" .. table.concat(parts, ",") .. "}"
end

local function lbl(arr)
	local out = {}
	for _, c in ipairs(arr) do out[#out + 1] = c and c:label() or "?" end
	return table.concat(out, " ")
end

-- RunLoop.roll_boon 的镜像:从 deck_seed 派生的独立流
function M.roll_boon(deck_seed)
	return BlindBoon.roll(Rng.new():seed(deck_seed * 53 + 11))
end

function M.digest(run)
	local slots_s = {}
	for i = 1, #run.joker_slots do slots_s[i] = joker_digest(run.joker_slots[i]) end
	local cons = {}
	for _, c in ipairs(run.consumables) do cons[#cons + 1] = string.format("%s:%d", c.id, num.int(c.queued_beats)) end
	local kinds = {}
	for k in pairs(run.section_kinds) do kinds[#kinds + 1] = num.int(k) end
	table.sort(kinds)
	local ks = {}
	for i, k in ipairs(kinds) do ks[i] = string.format("%d", k) end
	local rules = {}
	for k, v in pairs(run.deck.rules) do
		if v then rules[#rules + 1] = tostring(k) end
	end
	table.sort(rules)
	return table.concat({
		string.format("sec=%d", run.section_idx), string.format("pis=%d", run.phrase_in_section),
		string.format("pi=%d", run.phrase_index), string.format("score=%d", run.section_score),
		string.format("coins=%d", run.coins), string.format("debt=%d", run.debt), string.format("stage=%d", run.stage),
		"rng=" .. run.deck._rng:state_hex(),
		"draw=" .. lbl(run.deck.draw_pile), "disc=" .. lbl(run.deck.discard_pile), "cache=" .. lbl(run.cache),
		"slots=" .. table.concat(slots_s, ";"), "cons=" .. table.concat(cons, ","),
		string.format("boost=%d", #run.phrase_boosts),
		"face=" .. run:face(), "boon=" .. run.run_boon, "mr=" .. canon(run.mod_roll),
		string.format("pk=%d", run.prev_kind), "pth=" .. (run.prev_target_hit and "T" or "F"),
		string.format("fk=%d", run.first_kind), "kinds=" .. table.concat(ks, ","),
		string.format("sdu=%d", run.section_discards_used), string.format("sb=%d", run.shelf_bonus),
		"rl=" .. run.request_last, string.format("prs=%d", run.previous_raw_score),
		"brng=" .. run._blind_rng:state_hex(), string.format("rs=%d", run._roll_seed),
		"trim=" .. (run.deck.trim_low and "T" or "F"), "rules=" .. table.concat(rules, ","),
		"wildx=" .. canon(run.deck.wild_extra),
		string.format("tut=%s/%d", run.tutorial and "T" or "F", run.tutorial_step),
	}, "|")
end

-- 按脚本重放一局;eq(got, want, tag) 逐条比。返回比过的摘要条数。
function M.replay(case, eq)
	local seed = case.seed
	local run = Run.new()
	run.deck = Deck.new(seed)
	run.cache = {}
	run.joker_slots = { false, false, false, false }
	run.coins = GameConfig.STARTING_COINS
	run.tutorial = case.tutorial and true or false
	run._blind_rng:seed(seed * 31 + 7)
	run._roll_seed = seed * 97 + 13
	if run.tutorial then
		run.run_faces = {}
		run.run_boon = ""
	else
		run.run_faces = SectionMod.roll_run(Rng.new():seed(seed * 13 + 3))
		run.run_boon = M.roll_boon(seed)
	end
	local shop = Shop.new({ run = run, rng = Rng.new():seed(seed * 5 + 2) })
	local rule_next = false
	local p = nil
	local nd = 0
	local tag = string.format("run seed=%d%s", seed, run.tutorial and " (tutorial)" or "")
	local pending_out = nil       -- 上一拍 advance() 的结果
	local section_started = false
	local section_over = false    -- 段末摘要已记、next_section() 待做(在段末商店开门那一刻做)
	local function begin_beat()
		p = Beat.begin(run)
		run:age_consumables()
		for _, used in ipairs(run:due_consumables(run.phrase_in_section + 1)) do
			shop:apply_consumable(used, "due")
		end
	end
	local i = 1
	local ops = case.ops
	while i <= #ops do
		local op = ops[i]
		local k = op[1]
		if k == "beat" then
			if not section_started then
				run:reset_section_state()
				section_started = true
			end
			begin_beat()
		elseif k == "discard" then
			p:discard_selected(op[2], op[3])
		elseif k == "swap" then
			p:swap_with_cache(op[2], op[3])
		elseif k == "sort" then
			p:sort_hand()
		elseif k == "settle" then
			local flags = op[2]
			Beat.settle(run, p, flags)
			Beat.phrase_end(run, p, flags)
			run:tutorial_note("play")
			run:tutorial_try_advance()
			pending_out = run:advance()
		elseif k == "D" then
			nd = nd + 1
			local got = M.digest(run)
			if got ~= op[2] then
				-- 定位第一处不同的字段
				local ga, wa = {}, {}
				for f in got:gmatch("[^|]+") do ga[#ga + 1] = f end
				for f in op[2]:gmatch("[^|]+") do wa[#wa + 1] = f end
				local diff = {}
				for n = 1, math.max(#ga, #wa) do
					if ga[n] ~= wa[n] then diff[#diff + 1] = string.format("%s ≠ %s", tostring(ga[n]), tostring(wa[n])) end
				end
				eq(table.concat(diff, " || "), "", string.format("%s digest #%d", tag, nd))
			else
				eq(true, true, string.format("%s digest #%d", tag, nd))
			end
		elseif k == "tutorial_done" then
			run.tutorial = false
			run:roll_faces(seed * 11 + 5, -1)
		elseif k == "sec_end" then
			run.coins = Economy.grant(run.coins, GameConfig.SECTION_CLEAR_REWARD, run.joker_slots)
			if run.debt > 0 then
				local rp = run:repay_debt(run.coins)
				if rp.ok then run.coins = rp.coins else run.coins = 0; run.debt = 0 end
			end
			-- 段边界的 next_section() 在段末摘要之后、段末商店之前(与生成器同序)
			section_over = not pending_out.finale
		elseif k == "shop" then
			if section_over then
				run:next_section()
				section_over = false
			end
			shop:open(rule_next)
			rule_next = false
		elseif k == "buy" then
			shop:buy(op[2])
		elseif k == "replace" then
			shop:replace(op[2], op[3])
		elseif k == "cbuy" then
			shop:buy_consumable(op[2])
		elseif k == "reroll" then
			shop:reroll()
		elseif k == "leave" then
			shop:leave()
		elseif k == "shop_end" then
			eq(shop.closed, true, tag .. " shop closed at shop_end")
			if shop.rule_next then rule_next = true; shop.rule_next = false end
		elseif k == "end" then
			break
		end
		i = i + 1
	end
	return nd
end

return M
