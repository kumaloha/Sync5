-- core/director.gd 的镜像:跨局序列(data/director.json)—— 第 r 局走哪个状态 · 脸怎么挑 · 货架怎么偏。
-- 铁律:Director 不许调目标分。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("core%.$", ""))
local num = require(R .. "num")
local DB = require(P .. "db")
local GameConfig = require(P .. "config")
local SectionMod = require(P .. "modifier")

local Director = {}
Director.BIASES = { "mild", "median", "harsh" }
Director.CYCLE_LEN = 10
Director.EXAM_KINDS = { "wall", "combo" }

local function cfg() return DB.director() end

function Director.sequence()
	local out = {}
	for _, s in ipairs(cfg().sequence or {}) do out[#out + 1] = tostring(s) end
	return out
end

function Director.states() return cfg().states or {} end
function Director.loop_from() return num.int(num.get(cfg(), "loop_from", 0)) end
function Director.band_fraction() return num.get(cfg(), "band_fraction", 1.0) + 0.0 end

function Director.index_for(run_index)
	local n = #Director.sequence()
	if n <= 0 then return -1 end
	local i = num.maxi(1, run_index) - 1
	if i < n then return i end
	local lf = num.clampi(Director.loop_from(), 0, n - 1)
	local span = n - lf
	return lf + (i - lf) % span
end

function Director.state_for(run_index)
	local i = Director.index_for(run_index)
	if i < 0 then return "" end
	return tostring(Director.sequence()[i + 1])
end

function Director.entry_for(run_index)
	return num.get(Director.states(), Director.state_for(run_index), {})
end

function Director.face_bias(run_index)
	return tostring(num.get(Director.entry_for(run_index), "face_bias", "median"))
end

function Director.shelf(run_index)
	return num.get(Director.entry_for(run_index), "shelf", {})
end

function Director.cycle_cfg() return cfg().cycle or {} end
function Director.cycle_groups() return Director.cycle_cfg().groups or {} end
function Director.cycle_mult() return num.get(Director.cycle_cfg(), "bias_mult", 3.0) + 0.0 end

function Director.cycle_slot(run_index)
	local groups = Director.cycle_groups()
	if #groups == 0 or run_index < 1 then return "" end
	local i = run_index - 1
	local gi = num.int(math.floor(i / Director.CYCLE_LEN)) % #groups
	local row = groups[gi + 1]
	local pos = i % Director.CYCLE_LEN
	if pos >= #row then return "" end
	return tostring(row[pos + 1])
end

function Director.cycle_axis(run_index)
	local s = Director.cycle_slot(run_index)
	if s == "" or num.has(Director.EXAM_KINDS, s) then return "" end
	return s
end

function Director.cycle_exam(run_index)
	local s = Director.cycle_slot(run_index)
	if num.has(Director.EXAM_KINDS, s) then return s end
	return ""
end

function Director.exam_family(face_id)
	if face_id == "" then return false end
	if face_id == "raisedbar" then return true end
	for _, e in ipairs(DB.faces().faces or {}) do
		if tostring(e.id) == face_id then return tostring(num.get(e, "base", "")) == "raisedbar" end
	end
	return false
end

-- 考试局保证:四墙里尽量至少一张加码族(零 RNG 消耗)
function Director.ensure_exam_wall(out, run_index)
	for _, w in ipairs(GameConfig.WALL_SECTIONS) do
		if Director.exam_family(tostring(num.get(out, w, ""))) then return out end
	end
	local walls = {}
	for i = #GameConfig.WALL_SECTIONS, 1, -1 do walls[#walls + 1] = GameConfig.WALL_SECTIONS[i] end
	for _, idx in ipairs(walls) do
		if idx ~= 0 then
			for _, fid in ipairs(SectionMod.pool_for(idx)) do
				local f = tostring(fid)
				local present = false
				for _, v in pairs(out) do
					if v == f then present = true end
				end
				if Director.exam_family(f) and SectionMod.unlocked_at(f, run_index) and not present then
					out[idx] = f
					return out
				end
			end
		end
	end
	return out
end

function Director.ctx_cfg() return cfg().context or {} end
function Director.novelty_on() return num.get(Director.ctx_cfg(), "novelty", false) and true or false end
function Director.streak_shift_on() return num.get(Director.ctx_cfg(), "streak_shift", false) and true or false end
function Director.returning_on() return num.get(Director.ctx_cfg(), "returning", false) and true or false end
function Director.explore_on() return num.get(Director.ctx_cfg(), "explore_shelf", false) and true or false end
function Director.tuning() return cfg().context_tuning or {} end
function Director.explore_mult() return num.get(Director.tuning(), "explore_mult", 1.5) + 0.0 end
function Director.return_gap_s() return num.int(num.get(Director.tuning(), "return_gap_days", 3)) * 86400 end

function Director.explore_boost(candidates, used)
	local boost = {}
	if used == nil or next(used) == nil or not Director.explore_on() then return boost end
	for _, j in ipairs(candidates) do
		if j.kind == "target" and used[tostring(j.id)] == nil then
			boost[tostring(j.id)] = Director.explore_mult()
		end
	end
	return boost
end

function Director.shift_bias(bias, streak, lose, win)
	lose = lose or 2
	win = win or 3
	local i = num.find(Director.BIASES, bias)
	if i < 0 then return bias end
	if streak <= -lose then
		i = num.maxi(0, i - 1)
	elseif streak >= win then
		i = num.mini(#Director.BIASES - 1, i + 1)
	end
	return Director.BIASES[i + 1]
end

function Director.bias_with_ctx(bias, ctx)
	if ctx == nil or next(ctx) == nil or not Director.streak_shift_on() then return bias end
	local tn = Director.tuning()
	return Director.shift_bias(bias, num.int(num.get(ctx, "streak", 0)),
		num.int(num.get(tn, "lose_streak", 2)), num.int(num.get(tn, "win_streak", 3)))
end

function Director._base_weights()
	return DB.economy().draft_rarity_weights or {}
end

function Director.shelf_rarity_mult(run_index)
	local m = num.get(Director.shelf(run_index), "rarity_weight_mult", {})
	local out = {}
	for k in pairs(Director._base_weights()) do
		out[tostring(k)] = num.get(m, k, 1.0) + 0.0
	end
	return out
end

function Director.shelf_weights(run_index)
	local base = Director._base_weights()
	local mult = Director.shelf_rarity_mult(run_index)
	local out = {}
	for k, v in pairs(base) do out[tostring(k)] = (v + 0.0) * (mult[tostring(k)] + 0.0) end
	return out
end

function Director.band_size(n)
	if n <= 0 then return 0 end
	return num.clampi(num.int(math.ceil(n * Director.band_fraction())), 1, n)
end

local function slice(arr, a, b)   -- [a, b) 0 基
	local out = {}
	for i = a + 1, b do out[#out + 1] = arr[i] end
	return out
end

function Director.band(ranked, bias)
	local n = #ranked
	if n == 0 then return {} end
	local k = Director.band_size(n)
	if bias == "mild" then return slice(ranked, 0, k) end
	if bias == "harsh" then return slice(ranked, n - k, n) end
	local start = num.int(math.floor((n - k) / 2.0))
	return slice(ranked, start, start + k)
end

-- 一档里掷一张:恰好消耗一步 PCG(带权时用 randi 手搓 [0,1))
function Director.pick_face(ranked, bias, rng, exclude, seen, familiar, weights)
	exclude = exclude or {}
	seen = seen or {}
	weights = weights or {}
	local b = Director.band(ranked, bias)
	if #b == 0 then return "" end
	local fresh = {}
	for _, id in ipairs(b) do
		if not num.has(exclude, id) then fresh[#fresh + 1] = id end
	end
	if #fresh == 0 then fresh = b end
	if next(seen) ~= nil and (Director.novelty_on() or familiar) then
		local kept = {}
		local best = -1
		for _, id in ipairs(fresh) do
			local c = num.int(num.get(seen, tostring(id), 0))
			local wins
			if familiar then wins = c > best else wins = (best < 0 or c < best) end
			if wins then
				best = c
				kept = { id }
			elseif c == best then
				kept[#kept + 1] = id
			end
		end
		fresh = kept
	end
	local boosted = false
	for _, id in ipairs(fresh) do
		if (num.get(weights, tostring(id), 1.0) + 0.0) ~= 1.0 then
			boosted = true
			break
		end
	end
	if not boosted then
		return tostring(fresh[rng:randi_range(0, #fresh - 1) + 1])
	end
	local total = 0.0
	for _, id in ipairs(fresh) do
		total = total + num.maxf(0.0, num.get(weights, tostring(id), 1.0) + 0.0)
	end
	local roll = (rng:randi() + 0.5) / 4294967296.0
	if total <= 0.0 then
		return tostring(fresh[num.mini(num.int(roll * #fresh), #fresh - 1) + 1])
	end
	roll = roll * total
	for _, id in ipairs(fresh) do
		roll = roll - num.maxf(0.0, num.get(weights, tostring(id), 1.0) + 0.0)
		if roll < 0.0 then return tostring(id) end
	end
	return tostring(fresh[#fresh])
end

-- 这一局四张脸(Director 版);ranking = {section_idx: [由易到难]}, 空 = 逐字节退回 SectionMod.roll
function Director.roll_run(run_index, rng, ranking, ctx)
	ranking = ranking or {}
	ctx = ctx or {}
	local returning = Director.returning_on() and (num.get(ctx, "returning", false) and true or false)
	local bias
	if returning then bias = "mild" else bias = Director.bias_with_ctx(Director.face_bias(run_index), ctx) end
	local seen = num.get(ctx, "seen", {})
	local caxis = ""
	if next(ranking) ~= nil then caxis = Director.cycle_axis(run_index) end
	local out = {}
	local drawn = {}
	for _, w in ipairs(GameConfig.WALL_SECTIONS) do
		local idx = w
		local skip = false
		if idx == 0 and run_index >= 1 then
			if not SectionMod.wall_face_unlocked(idx, run_index) then
				out[idx] = ""
				skip = true
			elseif rng:randf() < GameConfig.S1_EASY_CHANCE then
				out[idx] = ""
				skip = true
			end
		end
		if not skip then
			local ranked = Director.ranked_pool(idx, ranking, run_index)
			local f
			if #ranked == 0 then
				f = SectionMod.roll(idx, rng, drawn, run_index)
			else
				local boost = {}
				if caxis ~= "" then
					for _, fid in ipairs(ranked) do
						if num.has(SectionMod.attack_axes(tostring(fid)), caxis) then
							boost[tostring(fid)] = Director.cycle_mult()
						end
					end
				end
				f = Director.pick_face(ranked, bias, rng, drawn, seen, returning, boost)
			end
			out[idx] = f
			if f ~= "" then drawn[#drawn + 1] = f end
		end
	end
	local fixed = SectionMod.enforce_axis_budget(out, rng, run_index)
	if next(ranking) ~= nil and Director.cycle_exam(run_index) ~= "" then
		fixed = Director.ensure_exam_wall(fixed, run_index)
	end
	return fixed
end

function Director.ranked_pool(section_idx, ranking, run_index)
	if run_index == nil then run_index = -1 end
	local lst = ranking[section_idx]
	if lst == nil then return {} end
	local pool = SectionMod.pool_for(section_idx)
	local out = {}
	for _, id in ipairs(lst) do
		local s = tostring(id)
		if num.has(pool, s) and not num.has(out, s) and SectionMod.unlocked_at(s, run_index) then
			out[#out + 1] = s
		end
	end
	return out
end

return Director
