-- core/shelf.gd 的镜像:货架组装(候选 → 这次上架的几张), 纯函数。授予记账与成交在 app/shop.lua。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("core%.$", ""))
local num = require(R .. "num")
local Joker = require(P .. "joker")
local Economy = require(P .. "economy")

local Shelf = {}

function Shelf.candidates(slots)
	local first_target = not slots[1]
	local owned = {}
	for _, j in Joker.each(slots) do owned[#owned + 1] = j.id end
	local out = {}
	for _, j in ipairs(Joker.pool()) do
		if not num.has(owned, j.id) then
			if first_target then
				if j.kind == "target" then out[#out + 1] = j end
			else
				out[#out + 1] = j
			end
		end
	end
	return out
end

function Shelf.deal(slots, shelf_bonus, grant_shelf, min_rarity, rng, rarity_mult, boost)
	rarity_mult = rarity_mult or {}
	boost = boost or {}
	local cands = Shelf.candidates(slots)
	local first_target = not slots[1]
	local shelf_n = Joker.slots_shelf_size(slots, shelf_bonus)
	if grant_shelf > 0 then shelf_n = num.maxi(shelf_n, grant_shelf) end
	local offer = {}
	if first_target then
		if rng == nil then
			-- 镜像没有全局随机:无 rng 时按池序取前三(编排层一律传 rng)
		else
			for i = #cands - 1, 1, -1 do
				local j = rng:randi_range(0, i)
				local tmp = cands[i + 1]
				cands[i + 1] = cands[j + 1]
				cands[j + 1] = tmp
			end
		end
		for i = 1, num.mini(3, #cands) do offer[i] = cands[i] end
	else
		offer = Economy.weighted_pick(cands, shelf_n, Joker.slots_target_mult(slots), rng, rarity_mult, boost)
		if Joker.slots_guarantee_target(slots) then
			local has_t = false
			for _, j in ipairs(offer) do
				if j.kind == "target" then has_t = true end
			end
			if not has_t then
				local tp = {}
				for _, j in ipairs(cands) do
					if j.kind == "target" then tp[#tp + 1] = j end
				end
				if #tp > 0 and #offer > 0 then
					local k = rng and rng:randi_range(0, #tp - 1) or 0
					offer[#offer] = tp[k + 1]
				end
			end
		end
	end
	if min_rarity ~= "" then offer = Shelf.rich_only(offer, cands) end
	return offer
end

function Shelf.rich_only(offer, cands)
	local rich = {}
	for _, j in ipairs(offer) do
		if j.rarity ~= "common" then rich[#rich + 1] = j end
	end
	if #rich < #offer then
		for _, j in ipairs(cands) do
			if #rich >= #offer then break end
			if j.rarity ~= "common" and not num.has(rich, j) then rich[#rich + 1] = j end
		end
		if #rich == #offer then return rich end
	end
	return offer
end

function Shelf.refill(slots, on_shelf, min_rarity, rng, rarity_mult, boost)
	local taken = {}
	for _, jj in Joker.each(slots) do taken[jj.id] = true end
	for _, c in ipairs(on_shelf) do
		if c then taken[c.id] = true end
	end
	local pool = {}
	for _, cand in ipairs(Joker.pool()) do
		if not taken[cand.id] and not (min_rarity ~= "" and tostring(cand.rarity) == "common") then
			pool[#pool + 1] = cand
		end
	end
	if #pool == 0 then
		for _, cand in ipairs(Joker.pool()) do
			if not taken[cand.id] then pool[#pool + 1] = cand end
		end
	end
	if #pool == 0 then return nil end
	local picked = Economy.weighted_pick(pool, 1, Joker.slots_target_mult(slots), rng, rarity_mult or {}, boost or {})
	return picked[1]
end

return Shelf
