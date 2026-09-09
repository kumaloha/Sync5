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


-- ⚑⚑ core/shelf.gd 的 `Shelf.Visit` 孪生 —— 一次进店的记账(view / ShopSim / lua/app/shop.lua
-- 共用的一份, 2026-09-09 收 mirror.md §12 的第二个代价)。字段与方法名逐字相同;
-- 它**不拥有** coins / joker_slots / deck / rule_next / loan —— 那些留在调用方。
-- ⚠ `tools/mirror.py` 只查顶层 `func` ⇒ **它查不到内部类**;这个孪生由金样的 `visit` 族
--   逐字段对拍(`tools/golden.gd::_fam_visit` → `lua/tools/fams.lua::fams.visit`), 不是靠覆盖门。
-- ⚠ 槽位空位在 Lua 侧是 `false`(镜像通例), 在 Godot 侧是 `null`。
Shelf.Visit = {}
Shelf.Visit.__index = Shelf.Visit

function Shelf.Visit.new()
	local self = setmetatable({}, Shelf.Visit)
	self.reroll_count = 0
	self.buys_left = 0
	self.shelf_bonus = 0
	self.grant_shelf = 0
	self.grant_extra_buys = 0
	self.grant_price = 0
	self.grant_free_reroll = 0
	self.grant_min_rarity = ""
	self.shop_buys = 0
	self.coffer_used = false
	self.perkeo_fired = false
	self.closed = false
	return self
end

-- 进店归零(其余授予不清 —— 上一店 close() 已经清过)
function Shelf.Visit:open(run_shelf_bonus)
	self.shop_buys = 0
	self.perkeo_fired = false
	self.reroll_count = 0
	self.buys_left = 0
	self.grant_min_rarity = ""
	self.coffer_used = false
	self.closed = false
	self.shelf_bonus = num.int(run_shelf_bonus)
end

function Shelf.Visit:price(j, slots)
	local sp = Economy.shelf_price(j, slots)
	if sp > 0 then return num.maxi(1, sp + self.grant_price) end
	return 0
end

function Shelf.Visit:affordable(j, slots, coins)
	local p = self:price(j, slots)
	if p == 0 then return true end
	if j.kind == "target" then return coins >= p end
	local budget = coins
	if not Joker.has_room_for(slots, tostring(j.kind)) then
		local best_sell = 0
		for k = 2, #slots do
			if slots[k] then best_sell = num.maxi(best_sell, Economy.sell_value(slots[k])) end
		end
		budget = budget + best_sell
	end
	return budget >= p
end

function Shelf.Visit:reroll_cost_now()
	return Economy.reroll_cost(self.reroll_count, self.grant_price)
end

-- 免费刷新不推阶梯(不调 note_reroll)
function Shelf.Visit:take_free_reroll()
	if self.grant_free_reroll <= 0 then return false end
	self.grant_free_reroll = self.grant_free_reroll - 1
	return true
end

function Shelf.Visit:note_reroll()
	self.reroll_count = self.reroll_count + 1
end

function Shelf.Visit:buy_limit(slots)
	return Joker.slots_buy_limit(slots) + self.grant_extra_buys
end

function Shelf.Visit:note_buy()
	self.shop_buys = self.shop_buys + 1
end

-- 一次成交之后还留在店里吗(离店的其它副作用由调用方在此之前跑)
function Shelf.Visit:stay(slots)
	local limit = self:buy_limit(slots)
	if self.shop_buys < limit then
		self.buys_left = limit - self.shop_buys
		return true
	end
	self:close()
	return false
end

-- 只认属于记账的五个键;返回 { redeal = bool }
function Shelf.Visit:apply_action(act)
	local redeal = false
	if act.shelf_slots ~= nil then
		self.grant_shelf = num.maxi(self.grant_shelf, num.int(act.shelf_slots))
		redeal = true
	end
	if act.extra_buys ~= nil then self.grant_extra_buys = self.grant_extra_buys + num.int(act.extra_buys) end
	if act.price_delta ~= nil then self.grant_price = self.grant_price + num.int(act.price_delta) end
	if act.free_reroll ~= nil then self.grant_free_reroll = self.grant_free_reroll + num.int(act.free_reroll) end
	if act.min_rarity ~= nil then
		self.grant_min_rarity = tostring(act.min_rarity)
		redeal = true
	end
	return { redeal = redeal }
end

-- 离店:清「这次商店」类的四个授予(grant_min_rarity 是「下次货架」类, 清零点在 open)
function Shelf.Visit:close()
	self.grant_shelf = 0
	self.grant_extra_buys = 0
	self.grant_price = 0
	self.grant_free_reroll = 0
	self.closed = true
end

return Shelf
