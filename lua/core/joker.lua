-- core/joker.gd 的镜像:jokers.json 之上的数据壳。钩子契约:apply / on_acquire / on_discard /
-- on_swap / on_phrase_end / on_section_end;成长状态在 state。槽数组里空位是 false。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("core%.$", ""))
local num = require(R .. "num")
local DB = require(P .. "db")
local Lingo = require(P .. "lingo")
local Fx = require(P .. "fx")

local Joker = {}
Joker.__index = Joker

function Joker.new(e)
	local self = setmetatable({}, Joker)
	self.id = tostring(e.id)
	self.name = tostring(e.name)
	self.cn_name = Lingo.pick(e)
	self.kind = tostring(e.kind)
	self.rarity = tostring(e.rarity)
	self.fx_text = tostring(e.fx)
	self._effects = e.effects or {}
	self._counters = e.counters or {}
	self._acquire = e.acquire or {}
	self._shelf = e.shelf or {}
	self._hold = e.hold or {}
	self.state = Fx.init_state(self._counters)
	self._trial_free_cached = -1
	return self
end

local function each(slots)
	local i = 0
	return function()
		while i < #slots do
			i = i + 1
			local j = slots[i]
			if j then return i, j end
		end
		return nil
	end
end
Joker.each = each

function Joker:shelf_target_mult()
	return num.get(self._shelf, "target_weight_mult", 1.0) + 0.0
end

function Joker:shelf_target_guaranteed()
	return num.get(self._shelf, "target_guaranteed", false) and true or false
end

function Joker.slots_copy_consumable(slots)
	for _, j in each(slots) do
		if num.get(j._shelf, "copy_consumable", false) then return true end
	end
	return false
end

-- 0 号槽是 Target 专用, Support 只能进 1..3(返回 0 基下标, 没空位 -1)
function Joker.first_free_support(slots)
	for k = 2, #slots do
		if not slots[k] then return k - 1 end
	end
	return -1
end

function Joker.has_room_for(slots, kind)
	return kind == "target" or Joker.first_free_support(slots) >= 0
end

function Joker.slots_guarantee_target(slots)
	for _, j in each(slots) do
		if j:shelf_target_guaranteed() then return true end
	end
	return false
end

function Joker.slots_target_mult(slots)
	local m = 1.0
	for _, j in each(slots) do m = m * j:shelf_target_mult() end
	return m
end

function Joker.slots_shelf_size(slots, bonus)
	bonus = bonus or 0
	local n = 3
	for _, j in each(slots) do
		n = num.maxi(n, num.int(num.get(j._shelf, "shelf_slots", 3)))
	end
	return num.mini(4, n + num.maxi(0, bonus))
end

function Joker.slots_cache_scoring(slots)
	for _, j in each(slots) do
		if num.get(j._hold, "cache_scoring", false) then return true end
	end
	return false
end

function Joker.slots_odds_mult(slots)
	local m = 1.0
	for _, j in each(slots) do
		m = num.maxf(m, num.get(j._hold, "odds_mult", 1.0) + 0.0)
	end
	return m
end

-- 客串:段寿命计数, 到寿返回 true(调用方清槽)
function Joker:tick_section_life()
	self:on_section_end()
	local life = num.int(num.get(self._hold, "section_life", 0))
	if life <= 0 then return false end
	self.state.ages = num.int(num.get(self.state, "ages", 0)) + 1
	return num.int(self.state.ages) >= life
end

function Joker:chance_rolls_needed()
	local n = 0
	for _, e in ipairs(self._effects) do
		if (e.when or {}).chance ~= nil then n = n + 1 end
	end
	return n
end

function Joker.slots_buy_limit(slots)
	local n = 1
	for _, j in each(slots) do
		n = num.maxi(n, num.int(num.get(j._shelf, "buy_limit", 1)))
	end
	return n
end

function Joker.slots_price_delta(slots)
	local d = 0
	for _, j in each(slots) do
		d = d + num.int(num.get(j._shelf, "price_delta", 0))
	end
	return d
end

function Joker.slots_loan(slots)
	local borrow, repay = 0, 0
	for _, j in each(slots) do
		if j._hold.loan ~= nil then
			borrow = borrow + num.int(num.get(j._hold.loan, "borrow", 0))
			repay = repay + num.int(num.get(j._hold.loan, "repay", 0))
		end
	end
	return { borrow = borrow, repay = repay }
end

function Joker.slots_rule_guaranteed(slots)
	for _, j in each(slots) do
		if num.get(j._shelf, "rule_guaranteed", false) then return true end
	end
	return false
end

function Joker.slots_coin_cap(slots)
	local cap = 999999
	for _, j in each(slots) do
		if j._hold.coin_cap ~= nil then cap = num.mini(cap, num.int(j._hold.coin_cap)) end
	end
	return cap
end

function Joker:is_rule_card()
	return next(self._acquire) ~= nil
end

function Joker:on_acquire(deck)
	if deck == nil then return end
	if self._acquire.wilds ~= nil then
		deck:add_wilds(self.id, num.int(self._acquire.wilds))
	end
	if self._acquire.deck_rule ~= nil then
		deck.rules[tostring(self._acquire.deck_rule)] = true
	end
	if self._acquire.trim_low ~= nil then
		deck:trim_low_ranks()
	end
end

function Joker:on_discard(n)
	Fx.on_discard(self._counters, self.state, n)
end

function Joker:swap_bonus_pct()
	local total = 0.0
	for _, e in ipairs(self._effects) do
		local d = e["do"] or {}
		if d.bonus_pct ~= nil then
			local per = tostring(num.get(d, "per", ""))
			if per:sub(1, 8) == "counter:" then
				local spec = num.get(self._counters, per:sub(9), {})
				if spec.on_target_swap ~= nil then
					total = total + (d.bonus_pct + 0.0) * (spec.on_target_swap + 0.0)
				end
			end
		end
	end
	return total
end

function Joker:on_swap() end

function Joker:on_shop_event(kind)
	Fx.on_shop_event(self._counters, self.state, kind)
end

function Joker.notify_shop(slots, kind)
	for _, j in each(slots) do j:on_shop_event(kind) end
end

function Joker:on_phrase_end(x)
	Fx.on_phrase_end(self._counters, self.state, x)
end

function Joker:on_section_end() end

function Joker:apply(ctx)
	return Fx.apply_effects(self._effects, self.state, ctx)
end

function Joker:has_effects()
	return #self._effects > 0
end

function Joker:trial_free()
	if self._trial_free_cached < 0 then
		self._trial_free_cached = Fx.trial_free(self._effects) and 1 or 0
	end
	return self._trial_free_cached == 1
end

function Joker.by_id(p_id)
	for _, e in ipairs(DB.jokers()) do
		if tostring(e.id) == p_id then return Joker.new(e) end
	end
	return nil
end

function Joker.pool()
	local out = {}
	for _, e in ipairs(DB.jokers()) do out[#out + 1] = Joker.new(e) end
	return out
end

function Joker:clone()
	for _, e in ipairs(DB.jokers()) do
		if tostring(e.id) == self.id then
			local j = Joker.new(e)
			j.state = num.deep(self.state)
			return j
		end
	end
	return nil
end

-- 摘要:id + state(键排序), 空槽由调用方写 "-"
function Joker:digest()
	local parts = {}
	for _, k in ipairs(num.sorted_keys(self.state)) do
		local v = self.state[k]
		if type(v) == "number" then
			parts[#parts + 1] = k .. "=" .. num.f64hex(v + 0.0)
		else
			parts[#parts + 1] = k .. "=" .. tostring(v)
		end
	end
	return self.id .. "{" .. table.concat(parts, ",") .. "}"
end

return Joker
