-- core/modifier.gd 的镜像:Boss 脸(faces.json)的数据壳与参数访问器;复合脸在 _entry 合并。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("core%.$", ""))
local num = require(R .. "num")
local Rng = require(R .. "rng")
local DB = require(P .. "db")
local Lingo = require(P .. "lingo")
local GameConfig = require(P .. "config")

local SectionMod = {}
SectionMod.__index = SectionMod

local function faces()
	return DB.faces().faces or {}
end

function SectionMod._raw_entry(mod_id)
	for _, e in ipairs(faces()) do
		if tostring(e.id) == mod_id then return e end
	end
	return {}
end

-- 一条 faces 条目的生效参数:单机制脸 = 自己的 params;复合脸 = 两成分的并集。
function SectionMod._merged_params(e)
	if e.combo == nil then return e.params or {} end
	local out = {}
	for _, cid in ipairs(e.combo) do
		local cp = SectionMod._raw_entry(tostring(cid)).params or {}
		for k, v in pairs(cp) do out[k] = v end
	end
	return out
end

-- 复合脸的唯一合并点(返回副本, 不污染数据)
function SectionMod._entry(mod_id)
	local e = SectionMod._raw_entry(mod_id)
	if e.combo == nil then return e end
	local merged = num.shallow(e)
	merged.params = SectionMod._merged_params(e)
	return merged
end

function SectionMod.new(e)
	return setmetatable({
		id = tostring(e.id), name = tostring(e.name), cn_name = Lingo.pick(e),
		fx_text = tostring(e.fx), params = SectionMod._merged_params(e),
	}, SectionMod)
end

function SectionMod.roster()
	local out = {}
	for _, e in ipairs(faces()) do out[#out + 1] = SectionMod.new(e) end
	return out
end

function SectionMod.by_id(p_id)
	for _, m in ipairs(SectionMod.roster()) do
		if m.id == p_id then return m end
	end
	return nil
end

function SectionMod.tiers_of_entry(e)
	if e.tiers ~= nil then
		local out = {}
		for _, v in ipairs(e.tiers) do out[#out + 1] = num.int(v) end
		return out
	end
	if e.tier ~= nil then return { num.int(e.tier) } end
	return {}
end

function SectionMod.pool_for(section_idx)
	local out = {}
	for _, e in ipairs(faces()) do
		if num.has(SectionMod.tiers_of_entry(e), section_idx + 1) then out[#out + 1] = tostring(e.id) end
	end
	return out
end

function SectionMod.tier_of(mod_id)
	for _, e in ipairs(faces()) do
		if tostring(e.id) == mod_id then return num.int(num.get(e, "tier", 0)) end
	end
	return 0
end

function SectionMod.combo_of(mod_id)
	local out = {}
	for _, cid in ipairs(SectionMod._raw_entry(mod_id).combo or {}) do out[#out + 1] = tostring(cid) end
	return out
end

function SectionMod.base_of(mod_id)
	local e = SectionMod._raw_entry(mod_id)
	if e.base ~= nil then return tostring(e.base) end
	local comps = SectionMod.combo_of(mod_id)
	if #comps > 0 then return comps[1] end
	return ""
end

function SectionMod.tiers_of(mod_id)
	for _, e in ipairs(faces()) do
		if tostring(e.id) == mod_id then return SectionMod.tiers_of_entry(e) end
	end
	return {}
end

function SectionMod.tier_is_fixed(tier)
	for _, v in ipairs(DB.faces().fixed_tiers or {}) do
		if num.int(v) == tier then return true end
	end
	return false
end

function SectionMod.proof(mod_id)
	for _, e in ipairs(faces()) do
		if tostring(e.id) == mod_id then return tostring(num.get(e, "proof", "")) end
	end
	return ""
end

function SectionMod.pooled_ids()
	local out = {}
	for _, idx in ipairs(GameConfig.WALL_SECTIONS) do
		for _, fid in ipairs(SectionMod.pool_for(idx)) do
			if not num.has(out, fid) then out[#out + 1] = fid end
		end
	end
	return out
end

function SectionMod.unlocked_at(id, run_index)
	if run_index <= 0 then return true end
	return run_index >= num.int(num.get(SectionMod._entry(id), "min_run", 0))
end

-- 掷这一段的脸("" = 无);exclude = 本局已掷到的脸;池被排空时退回全池。
function SectionMod.roll(section_idx, rng, exclude, run_index)
	exclude = exclude or {}
	if run_index == nil then run_index = -1 end
	local pool_all = SectionMod.pool_for(section_idx)
	local pool = {}
	for _, id in ipairs(pool_all) do
		if SectionMod.unlocked_at(tostring(id), run_index) then pool[#pool + 1] = id end
	end
	if #pool == 0 then pool = pool_all end
	if #pool == 0 then return "" end
	local fresh = {}
	for _, id in ipairs(pool) do
		if not num.has(exclude, id) then fresh[#fresh + 1] = id end
	end
	if #fresh == 0 then fresh = pool end
	return fresh[rng:randi_range(0, #fresh - 1) + 1]
end

function SectionMod.wall_face_unlocked(section_idx, run_index)
	if section_idx ~= 0 or run_index < 1 then return true end
	return run_index >= GameConfig.S1_FACE_MIN_RUN
end

-- 一局的四张脸(探针掷法);返回 {段号: face_id}
function SectionMod.roll_run(rng, run_index)
	if run_index == nil then run_index = -1 end
	local out = {}
	local drawn = {}
	for _, w in ipairs(GameConfig.WALL_SECTIONS) do
		if not SectionMod.wall_face_unlocked(w, run_index) then
			out[w] = ""
		else
			local f = SectionMod.roll(w, rng, drawn, run_index)
			out[w] = f
			if f ~= "" then drawn[#drawn + 1] = f end
		end
	end
	return SectionMod.enforce_axis_budget(out, rng, run_index)
end

-- 攻击轴从脸参数自动推导。⚠ 轴的顺序 = Godot 字典插入序, 这里显式列出。
SectionMod._AXIS_ORDER = { "discard", "swap", "cache", "time", "info", "tempo", "quality" }
SectionMod._AXIS_PARAMS = {
	discard = { "discard_cards_max", "discard_actions", "section_discard_budget", "discard_lock_last" },
	swap = { "swap_actions", "swap_lock_last" },
	cache = { "cache_evict", "cache_cap_delta", "cache_block_red", "cache_lock_phrases",
		"seal_oldest_cache", "seal_random_cache" },
	time = { "time_penalty", "time_curve" },
	info = { "hide_faces", "hide_refill", "hide_random", "hide_suits", "hide_ranks" },
	tempo = { "repeat_factor", "lock_first", "required_kinds", "request_factor", "callout_factor" },
	quality = { "refill_rank_min", "refill_rank_max" },
}

function SectionMod.axis_ids()
	return num.shallow(SectionMod._AXIS_ORDER)
end

function SectionMod.attack_axes(mod_id)
	if mod_id == "" then return {} end
	return SectionMod.axes_of_params(SectionMod._entry(mod_id).params or {})
end

function SectionMod.axes_of_params(params)
	local out = {}
	if params.action_cards_max ~= nil or params.action_limit ~= nil or params.exclusive_action_tracks ~= nil then
		out[#out + 1] = "discard"
		out[#out + 1] = "swap"
	end
	for _, axis in ipairs(SectionMod._AXIS_ORDER) do
		if not num.has(out, axis) then
			for _, k in ipairs(SectionMod._AXIS_PARAMS[axis]) do
				if params[k] ~= nil then
					out[#out + 1] = axis
					break
				end
			end
		end
	end
	return out
end

-- 预算修复:某轴被 ≥3 张脸压时重掷该轴最后一张(派生流上掷, 主流恒只消耗一掷)。
function SectionMod.enforce_axis_budget(out, rng, run_index)
	if run_index == nil then run_index = -1 end
	local fix_rng = Rng.new():seed(rng:randi())
	for _, axis in ipairs(SectionMod.axis_ids()) do
		for _ = 1, #GameConfig.WALL_SECTIONS do
			local hits = {}
			for _, w in ipairs(GameConfig.WALL_SECTIONS) do
				local f = tostring(num.get(out, w, ""))
				if f ~= "" and num.has(SectionMod.attack_axes(f), axis) then hits[#hits + 1] = w end
			end
			if #hits < 3 then break end
			local fix_idx = hits[#hits]
			local banned = {}
			for _, e in ipairs(faces()) do
				local fid = tostring(e.id)
				if num.has(SectionMod.attack_axes(fid), axis) then banned[#banned + 1] = fid end
			end
			for _, w2 in ipairs(GameConfig.WALL_SECTIONS) do
				local f2 = tostring(num.get(out, w2, ""))
				if f2 ~= "" and not num.has(banned, f2) then banned[#banned + 1] = f2 end
			end
			local repl = SectionMod.roll(fix_idx, fix_rng, banned, run_index)
			if repl == "" then break end
			out[fix_idx] = repl
		end
	end
	return out
end

function SectionMod.affects_settle(mod_id)
	if mod_id == "" then return false end
	for k in pairs(SectionMod._entry(mod_id).params or {}) do
		if num.has(DB._FACE_PARAMS_SETTLE, tostring(k)) then return true end
	end
	return false
end

-- float(params.get(key, dflt));布尔按 1/0
local function as_float(v)
	if v == true then return 1.0 end
	if v == false then return 0.0 end
	return v + 0.0
end

function SectionMod._param(mod_id, key, dflt)
	local v = (SectionMod._entry(mod_id).params or {})[key]
	if v == nil then return dflt end
	return as_float(v)
end

function SectionMod._param_array(mod_id, key)
	local v = (SectionMod._entry(mod_id).params or {})[key]
	if type(v) == "table" then return v end
	return {}
end

function SectionMod.time_penalty(mod_id) return SectionMod._param(mod_id, "time_penalty", 0.0) end

function SectionMod.time_penalty_at(mod_id, phrase_idx)
	if phrase_idx >= 0 then
		local curve = SectionMod._param_array(mod_id, "time_curve")
		if #curve > 0 then
			return curve[num.clampi(phrase_idx, 0, #curve - 1) + 1] + 0.0
		end
	end
	return SectionMod.time_penalty(mod_id)
end

function SectionMod.phrase_toll(mod_id) return num.int(SectionMod._param(mod_id, "phrase_toll", 0.0)) end
function SectionMod.target_power(mod_id) return SectionMod._param(mod_id, "target_power", 1.0) end
function SectionMod.repeat_factor(mod_id) return SectionMod._param(mod_id, "repeat_factor", 1.0) end
function SectionMod.zero_discard_factor(mod_id) return SectionMod._param(mod_id, "zero_discard_factor", 1.0) end
function SectionMod.cache_evict(mod_id) return num.int(SectionMod._param(mod_id, "cache_evict", 0.0)) end
function SectionMod.cache_cap(mod_id)
	return num.maxi(0, GameConfig.CACHE_CAP + num.int(SectionMod._param(mod_id, "cache_cap_delta", 0.0)))
end
function SectionMod.lock_first(mod_id) return SectionMod._param(mod_id, "lock_first", 1.0) end
function SectionMod.target_mult(mod_id) return SectionMod._param(mod_id, "target_mult", 1.0) end
function SectionMod.hide_refill(mod_id) return SectionMod._param(mod_id, "hide_refill", 0.0) > 0.0 end
function SectionMod.hide_faces(mod_id) return SectionMod._param(mod_id, "hide_faces", 0.0) > 0.0 end
function SectionMod.discard_lock_last(mod_id) return SectionMod._param(mod_id, "discard_lock_last", 0.0) end
function SectionMod.swap_lock_last(mod_id) return SectionMod._param(mod_id, "swap_lock_last", 0.0) end

function SectionMod.discard_open(mod_id, seconds_left)
	local close_last = SectionMod.discard_lock_last(mod_id)
	return close_last <= 0.0 or seconds_left > close_last
end

function SectionMod.swap_open(mod_id, seconds_left)
	local close_last = SectionMod.swap_lock_last(mod_id)
	return close_last <= 0.0 or seconds_left > close_last
end

function SectionMod.discard_action_limit(mod_id) return num.int(SectionMod._param(mod_id, "discard_actions", -1.0)) end
function SectionMod.swap_action_limit(mod_id) return num.int(SectionMod._param(mod_id, "swap_actions", -1.0)) end
function SectionMod.action_limit(mod_id) return num.int(SectionMod._param(mod_id, "action_limit", -1.0)) end
function SectionMod.discard_cards_max(mod_id) return num.int(SectionMod._param(mod_id, "discard_cards_max", -1.0)) end
function SectionMod.action_cards_max(mod_id) return num.int(SectionMod._param(mod_id, "action_cards_max", -1.0)) end
function SectionMod.cache_blocks_red(mod_id) return SectionMod._param(mod_id, "cache_block_red", 0.0) > 0.0 end
function SectionMod.refill_rank_min(mod_id) return num.int(SectionMod._param(mod_id, "refill_rank_min", 2.0)) end
function SectionMod.refill_rank_max(mod_id) return num.int(SectionMod._param(mod_id, "refill_rank_max", 15.0)) end
function SectionMod.cache_lock_phrases(mod_id) return num.int(SectionMod._param(mod_id, "cache_lock_phrases", 0.0)) end
function SectionMod.seals_lowest_start(mod_id) return SectionMod._param(mod_id, "seal_lowest_start", 0.0) > 0.0 end
function SectionMod.seals_oldest_cache(mod_id) return SectionMod._param(mod_id, "seal_oldest_cache", 0.0) > 0.0 end
function SectionMod.seals_random_start(mod_id) return SectionMod._param(mod_id, "seal_random_start", 0.0) > 0.0 end
function SectionMod.seals_random_cache(mod_id) return SectionMod._param(mod_id, "seal_random_cache", 0.0) > 0.0 end

function SectionMod.phase_factor(mod_id, phrase_idx)
	if phrase_idx < 0 then return 1.0 end
	local curve = SectionMod._param_array(mod_id, "phase_factors")
	if #curve == 0 then return 1.0 end
	return curve[num.clampi(phrase_idx, 0, #curve - 1) + 1] + 0.0
end

function SectionMod.hide_random(mod_id) return num.int(SectionMod._param(mod_id, "hide_random", 0.0)) end
function SectionMod.hide_suits(mod_id) return SectionMod._param(mod_id, "hide_suits", 0.0) > 0.0 end
function SectionMod.hide_ranks(mod_id) return SectionMod._param(mod_id, "hide_ranks", 0.0) > 0.0 end
function SectionMod.roll_chance(mod_id) return SectionMod._param(mod_id, "roll_chance", 0.0) end
function SectionMod.roll_cache_extra(mod_id) return num.int(SectionMod._param(mod_id, "roll_cache_extra", 0.0)) end
function SectionMod.rolls_suit(mod_id) return SectionMod._param(mod_id, "roll_suit", 0.0) > 0.0 end
function SectionMod.suit_half(mod_id) return SectionMod._param(mod_id, "suit_half", 1.0) end
function SectionMod.callout_factor(mod_id) return SectionMod._param(mod_id, "callout_factor", 1.0) end
function SectionMod.rolls_kind(mod_id) return SectionMod._param(mod_id, "roll_kind", 0.0) > 0.0 end
function SectionMod.required_kinds(mod_id) return num.int(SectionMod._param(mod_id, "required_kinds", 0.0)) end
function SectionMod.variety_penalty(mod_id) return SectionMod._param(mod_id, "variety_penalty", 0.0) end
function SectionMod.restores_with_initial_cache(mod_id) return SectionMod._param(mod_id, "restore_with_initial_cache", 0.0) > 0.0 end
function SectionMod.section_discard_budget(mod_id) return num.int(SectionMod._param(mod_id, "section_discard_budget", -1.0)) end
function SectionMod.exclusive_action_tracks(mod_id) return SectionMod._param(mod_id, "exclusive_action_tracks", 0.0) > 0.0 end
function SectionMod.request_factor(mod_id) return SectionMod._param(mod_id, "request_factor", 1.0) end
function SectionMod.joker_power(mod_id) return SectionMod._param(mod_id, "joker_power", 1.0) end

function SectionMod.tape_required(mod_id)
	for _, cid in ipairs(SectionMod.combo_of(mod_id)) do
		if SectionMod._raw_entry(cid).tape_required then return true end
	end
	return SectionMod._raw_entry(mod_id).tape_required and true or false
end

function SectionMod.bonus_disabled(mod_id)
	local v = (SectionMod._entry(mod_id).params or {}).bonus_disabled
	if v == nil or v == false or v == 0 then return false end
	return true
end

return SectionMod
