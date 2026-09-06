-- core/blind_boon.gd 的镜像:盲注增益(boons.json)。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("core%.$", ""))
local num = require(R .. "num")
local DB = require(P .. "db")
local Lingo = require(P .. "lingo")

local BlindBoon = {}
BlindBoon.__index = BlindBoon

function BlindBoon.new(e)
	return setmetatable({
		id = tostring(e.id), name = tostring(e.name), cn_name = Lingo.pick(e), fx_text = tostring(e.fx),
	}, BlindBoon)
end

function BlindBoon.roster()
	local out = {}
	for _, e in ipairs(DB.boons().boons or {}) do out[#out + 1] = BlindBoon.new(e) end
	return out
end

function BlindBoon.ids()
	local out = {}
	for _, b in ipairs(BlindBoon.roster()) do out[#out + 1] = b.id end
	return out
end

function BlindBoon.by_id(p_id)
	for _, b in ipairs(BlindBoon.roster()) do
		if b.id == p_id then return b end
	end
	return nil
end

-- seen = {boon_id: 见过几次};非空且 Director.novelty_on() 时收缩到最少见的那批;恒一次掷点。
function BlindBoon.roll(rng, seen)
	seen = seen or {}
	local pool = BlindBoon.ids()
	if #pool == 0 then return "" end
	if next(seen) ~= nil then
		local ok, Director = pcall(require, P .. "director")
		if ok and Director.novelty_on() then
			local kept = {}
			local best = -1
			for _, id in ipairs(pool) do
				local c = num.int(num.get(seen, tostring(id), 0))
				if best < 0 or c < best then
					best = c
					kept = { id }
				elseif c == best then
					kept[#kept + 1] = id
				end
			end
			pool = kept
		end
	end
	return tostring(pool[rng:randi_range(0, #pool - 1) + 1])
end

function BlindBoon._param(boon_id, key, dflt)
	for _, e in ipairs(DB.boons().boons or {}) do
		if tostring(e.id) == boon_id then
			local v = (e.params or {})[key]
			if v == nil then return dflt end
			return v + 0.0
		end
	end
	return dflt
end

function BlindBoon.score_replay_factor(boon_id) return BlindBoon._param(boon_id, "score_replay_factor", 0.0) end
function BlindBoon.spotlight_cards(boon_id) return num.int(BlindBoon._param(boon_id, "spotlight_cards", 0.0)) end
function BlindBoon.previous_raw_factor(boon_id) return BlindBoon._param(boon_id, "previous_raw_factor", 0.0) end
function BlindBoon.ghost_first_discard(boon_id) return BlindBoon._param(boon_id, "ghost_first_discard", 0.0) > 0.0 end

return BlindBoon
