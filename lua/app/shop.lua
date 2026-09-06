-- 商店的**非渲染逻辑**(view/shop.gd 的授予记账 + view/phrase.gd 的成交/替换/刷新/消耗牌/离店编排的镜像)。
-- 一次进店 = 一个 Shop 实例。经济动作全在这里(编排层调它), 渲染只读 Shop:view()。
-- rng:货架掷法的随机源(Godot 侧是全局随机;镜像由调用方传一条流, 对拍时传种子流)。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("app%.$", ""))
local num = require(R .. "num")
local Joker = require(R .. "core.joker")
local Economy = require(R .. "core.economy")
local Shelf = require(R .. "core.shelf")
local Consumable = require(R .. "core.consumable")
local DB = require(R .. "core.db")

local Shop = {}
Shop.__index = Shop

-- ctx:{run, rng, rarity_mult, explore_used, tape(可选 function(kind, payload)), rule_next(布尔, 跨店), on_deck_note(可选)}
function Shop.new(ctx)
	local self = setmetatable({}, Shop)
	self.run = ctx.run
	self.rng = ctx.rng
	self.rarity_mult = ctx.rarity_mult or {}
	self.explore_used = ctx.explore_used or {}
	self.tape = ctx.tape or function() end
	self.candidates = {}
	self.reroll_count = 0
	self.buys_left = 0
	self.shelf_bonus = 0
	self.grant_shelf = 0
	self.grant_extra_buys = 0
	self.grant_price = 0
	self.grant_free_reroll = 0
	self.grant_min_rarity = ""
	self.coffer = {}
	self.coffer_used = false
	self.shop_buys = 0
	self.perkeo_fired = false
	self.opened = false
	self.closed = false
	self.mid = false
	self.deny_last = ""
	self.events = {}
	return self
end

local function slots(self) return self.run.joker_slots end

-- ---- 进店(view/phrase.gd::_open_draft + Shop.open)----
function Shop:open(rule_next)
	local run = self.run
	Joker.notify_shop(slots(self), "enter")
	self.shop_buys = 0
	self.perkeo_fired = false
	self.mid = run.phrase_in_section > 0 and run.phrase_in_section < require(R .. "core.config").PHRASES_PER_SECTION
	self.shelf_bonus = run.shelf_bonus
	run.shelf_bonus = 0
	self.reroll_count = 0
	self.buys_left = 0
	self.grant_min_rarity = ""
	self:deal()
	self.coffer = self:roll_consumables(rule_next)
	self.coffer_used = false
	self.opened = true
	self.closed = false
	self.tape("shop", { mid = self.mid, sec = run.section_idx, coins = run.coins, offer = self:offers() })
	return self
end

function Shop:deal()
	local cands = Shelf.candidates(slots(self))
	local Director = require(R .. "core.director")
	self.candidates = Shelf.deal(slots(self), self.shelf_bonus, self.grant_shelf, self.grant_min_rarity,
		self.rng, self.rarity_mult, Director.explore_boost(cands, self.explore_used))
end

function Shop:roll_consumables(rule_next)
	local held = {}
	for _, c in ipairs(self.run.consumables) do held[c.id] = true end
	local out = {}
	local deck = self.run.deck
	for _, e in ipairs(Consumable.roll_shelf(held, rule_next and true or false, 2, function(n) return deck:pick_index(n) end)) do
		out[#out + 1] = e and Consumable.new(e) or false
	end
	return out
end

-- ---- 价格与可购性(view/shop.gd::_price / _affordable)----
function Shop:price(j)
	local sp = Economy.shelf_price(j, slots(self))
	if sp > 0 then return num.maxi(1, sp + self.grant_price) end
	return 0
end

function Shop:has_room(j)
	return Joker.has_room_for(slots(self), tostring(j.kind))
end

function Shop:affordable(j)
	local price = self:price(j)
	if price == 0 then return true end
	local coins = self.run.coins
	if j.kind == "target" then return coins >= price end
	local budget = coins
	if not self:has_room(j) then
		local best_sell = 0
		local s = slots(self)
		for k = 2, #s do
			if s[k] then best_sell = num.maxi(best_sell, Economy.sell_value(s[k])) end
		end
		budget = budget + best_sell
	end
	return budget >= price
end

function Shop:reroll_cost_now()
	return Economy.reroll_cost(self.reroll_count, self.grant_price)
end

function Shop:buy_limit()
	return Joker.slots_buy_limit(slots(self)) + self.grant_extra_buys
end

function Shop:offers()
	local out = {}
	for _, j in ipairs(self.candidates) do
		out[#out + 1] = { id = tostring(j.id), kind = tostring(j.kind), rarity = tostring(j.rarity),
			price = self:price(j), aff = self:affordable(j) }
	end
	return out
end

-- 砧座买了有没有用(support ≥ 2 才有意义)
function Shop:consumable_effective(c)
	if c.action.copy_one_destroy_rest ~= nil then
		local n = 0
		local s = slots(self)
		for k = 2, #s do
			if s[k] then n = n + 1 end
		end
		return n >= 2
	end
	return true
end

-- ---- 成交后的去留(view/phrase.gd 三条路径共用的名额判)----
function Shop:_after_sale(sold_joker)
	if self.shop_buys < self:buy_limit() then
		if sold_joker ~= nil then self:sold(sold_joker) end
		self.buys_left = self:buy_limit() - self.shop_buys
		return true   -- 留在店里
	end
	self:_exit()
	return false
end

function Shop:_exit()
	self:perkeo_on_exit()
	self:close()
end

function Shop:close()
	self.grant_shelf = 0
	self.grant_extra_buys = 0
	self.grant_price = 0
	self.grant_free_reroll = 0
	self.closed = true
end

-- 摘掉售出的那张, 原位补一张(Shelf.refill)
function Shop:sold(j)
	local at = num.find(self.candidates, j)
	num.erase(self.candidates, j)
	local Director = require(R .. "core.director")
	local refill = Shelf.refill(slots(self), self.candidates, self.grant_min_rarity, self.rng,
		self.rarity_mult, Director.explore_boost(Joker.pool(), self.explore_used))
	if refill ~= nil then
		if at >= 0 and at <= #self.candidates then
			table.insert(self.candidates, at + 1, refill)
		else
			self.candidates[#self.candidates + 1] = refill
		end
	end
end

-- ---- 买小丑牌(view/shop.gd::_on_pick → view/phrase.gd::_on_shop_bought)----
-- 返回 { ok, why, replace = true(满槽, 进替换流), stay = 是否还在店里 }
function Shop:buy(i)
	local j = self.candidates[i + 1]
	if self.closed or j == nil then return { ok = false, why = "closed" } end
	if not self:affordable(j) then
		self.tape("deny", { why = "price" })
		return { ok = false, why = "price" }
	end
	if not self:has_room(j) then
		self.tape("repl_open", { id = j.id, price = self:price(j), coins = self.run.coins })
		return { ok = false, replace = true, why = "replace" }
	end
	return self:_install_bought(j, self:price(j))
end

function Shop:_install_bought(j, price)
	local run = self.run
	if price < 0 or run.coins < price then
		self.tape("deny", { why = "buy_stale" })
		return { ok = false, why = "buy_stale" }
	end
	run.coins = run.coins - price
	self.tape("buy", { id = j.id, kind = j.kind, price = price, coins = run.coins })
	run:tutorial_note("buy")
	Joker.notify_shop(slots(self), "buy")
	local swapped_target = false
	local s = slots(self)
	if j.kind == "target" then
		local swapping = s[1] and true or false
		swapped_target = swapping
		if swapping then
			Joker.notify_shop(s, "target_swap")
			local trefund = Economy.sell_value(s[1])
			if trefund > 0 then run.coins = Economy.grant(run.coins, trefund, s) end
		end
		s[1] = j
		j:on_acquire(run.deck)
	else
		local placed = false
		for k = 2, #s do
			if not s[k] then
				s[k] = j
				j:on_acquire(run.deck)
				placed = true
				break
			end
		end
		if not placed then print("[shop] 买了 '" .. j.id .. "' 却没有空的 Support 槽") end
	end
	run.coins = Economy.cap_held(run.coins, s)
	if run.tutorial and j.kind == "target" then
		run:tutorial_shop_seen()
		self:_exit()
		return { ok = true, stay = false }
	end
	if not (j.kind == "target" and swapped_target) then
		self.shop_buys = self.shop_buys + 1
	end
	return { ok = true, stay = self:_after_sale(j) }
end

-- ---- 满槽替换:货架第 i 张换进第 k 槽(k 0 基, 1..3;k=0 = 取消)----
function Shop:replace(i, k)
	local new_j = self.candidates[i + 1]
	if self.closed or new_j == nil then return { ok = false, why = "closed" } end
	if k == 0 then
		self.tape("repl_off", { id = new_j.id, coins = self.run.coins })
		return { ok = false, why = "cancel", stay = true }
	end
	local run = self.run
	local s = slots(self)
	local old = s[k + 1]
	local price = self:price(new_j)
	local refund = old and Economy.sell_value(old) or 0
	if run.coins + refund < price then
		self.tape("deny", { why = "replace" })
		return { ok = false, why = "replace", stay = true }
	end
	run.coins = Economy.grant(run.coins, refund, s) - price
	self.tape("repl", { ["in"] = new_j.id, out = old and old.id or "", slot = k, price = price, back = refund, coins = run.coins })
	Joker.notify_shop(s, "buy")
	s[k + 1] = new_j
	new_j:on_acquire(run.deck)
	run.coins = Economy.cap_held(run.coins, s)
	self.shop_buys = self.shop_buys + 1
	return { ok = true, stay = self:_after_sale(new_j) }
end

-- ---- 刷新(view/shop.gd::_on_reroll → phrase.gd::_on_shop_reroll)----
function Shop:reroll()
	if self.closed then return { ok = false, why = "closed" } end
	if self.grant_free_reroll > 0 then
		self.grant_free_reroll = self.grant_free_reroll - 1
		Joker.notify_shop(slots(self), "reroll")
		self.tape("rerl", { k = self.reroll_count, cost = 0, coins = self.run.coins })
		self:deal()
		return { ok = true, cost = 0, stay = true }
	end
	local cost = self:reroll_cost_now()
	if self.run.coins < cost then
		self.tape("deny", { why = "reroll" })
		return { ok = false, why = "reroll", stay = true }
	end
	self.reroll_count = self.reroll_count + 1
	self.run.coins = self.run.coins - cost
	Joker.notify_shop(slots(self), "reroll")
	self.tape("rerl", { k = self.reroll_count, cost = cost, coins = self.run.coins })
	self:deal()
	return { ok = true, cost = cost, stay = true }
end

-- ---- 买消耗牌(view/shop.gd::_on_cshelf_pressed → phrase.gd::_on_consumable_bought)----
function Shop:buy_consumable(i)
	local c = self.coffer[i + 1]
	if self.closed or not c or self.coffer_used then return { ok = false, why = "closed" } end
	if self.run.coins < c.price then
		self.tape("deny", { why = "consumable" })
		return { ok = false, why = "consumable", stay = true }
	end
	if not self:consumable_effective(c) then
		self.tape("deny", { why = "consumable" })
		return { ok = false, why = "consumable", stay = true }
	end
	local run = self.run
	run.coins = run.coins - c.price
	local used = run:take_consumable(c)
	self.tape("cbuy", { id = c.id, price = c.price, coins = run.coins })
	if next(used) ~= nil then self:apply_consumable(used, "buy") end
	self.shop_buys = self.shop_buys + 1
	self.coffer_used = true
	if self.shop_buys < self:buy_limit() then
		self.coffer_used = false
		for k = 1, #self.coffer do
			if self.coffer[k] and tostring(self.coffer[k].id) == tostring(c.id) then self.coffer[k] = false end
		end
		self.buys_left = self:buy_limit() - self.shop_buys
		return { ok = true, stay = true }
	end
	self:_exit()
	return { ok = true, stay = false }
end

-- ---- 「继续 ▸」(唯一免费出口)----
function Shop:leave()
	if self.closed then return { ok = false, why = "closed" } end
	self.tape("leave", { coins = self.run.coins })
	self.run:tutorial_shop_seen()
	self:_exit()
	return { ok = true, stay = false }
end

-- ---- 一次性执行口(买入即触发 / 到点触发共用;view/phrase.gd::_apply_consumable + _apply_shop_action)----
function Shop:apply_consumable(used, why)
	local run = self.run
	local cid = tostring(used.id)
	local act = used.action or {}
	if act.wilds ~= nil then run.deck:add_wilds(cid, num.int(act.wilds)) end
	if act.trim_low ~= nil then run.deck:trim_low_ranks() end
	if act.deck_rule ~= nil then run.deck.rules[tostring(act.deck_rule)] = true end
	self:apply_shop_action(cid, act)
	self.tape("consumable", { id = cid, why = why, phrase = run.phrase_in_section })
end

function Shop:apply_shop_action(id, act)
	local run = self.run
	if act.shelf_slots ~= nil then
		self.grant_shelf = num.maxi(self.grant_shelf, num.int(act.shelf_slots))
		if self.opened and not self.closed then self:deal() end
	end
	if act.extra_buys ~= nil then self.grant_extra_buys = self.grant_extra_buys + num.int(act.extra_buys) end
	if act.price_delta ~= nil then self.grant_price = self.grant_price + num.int(act.price_delta) end
	if act.rule_guaranteed ~= nil then self.rule_next = true end
	if act.deck_rule ~= nil then run.deck.rules[tostring(act.deck_rule)] = true end
	if act.free_reroll ~= nil then self.grant_free_reroll = self.grant_free_reroll + num.int(act.free_reroll) end
	if act.min_rarity ~= nil then
		self.grant_min_rarity = tostring(act.min_rarity)
		if self.opened and not self.closed then self:deal() end
	end
	if act.loan ~= nil then
		local ln = act.loan
		run.coins = Economy.grant(run.coins, num.int(num.get(ln, "borrow", 0)), slots(self))
		run.debt = run.debt + num.int(num.get(ln, "repay", 0))
		self.tape("loan", { get = num.int(num.get(ln, "borrow", 0)), owe = run.debt, coins = run.coins })
	end
	if act.copy_one_destroy_rest ~= nil then self:anvil() end
	if act.wilds ~= nil then run.deck:add_wilds(id, num.int(act.wilds)) end
	if act.trim_low ~= nil then run.deck:trim_low_ranks() end
end

-- 砧座:随机留一张 support 并复制到相邻空槽, 其余(含 Target)销毁
function Shop:anvil()
	local run = self.run
	local s = slots(self)
	local owned = {}
	for i = 2, #s do
		if s[i] then owned[#owned + 1] = i end
	end
	if #owned < 2 then return end
	local keep = owned[run.deck:pick_index(#owned) + 1]
	local kept = s[keep]
	for i = 1, #s do
		if i ~= keep then s[i] = false end
	end
	if kept.kind == "support" then
		for i = 2, #s do
			if not s[i] then
				local dup = Joker.by_id(kept.id)
				dup.state = num.deep(kept.state)
				s[i] = dup
				break
			end
		end
	end
	self.tape("anvil", { kept = tostring(kept.id) })
end

-- 帕奇欧:离店时复制一张队列里的消耗牌(每次进店一次)
function Shop:perkeo_on_exit()
	if self.perkeo_fired then return end
	self.perkeo_fired = true
	local run = self.run
	if not Joker.slots_copy_consumable(slots(self)) then return end
	local src = num.shallow(run.consumables)
	if #src == 0 then return end
	local pick = src[run.deck:pick_index(#src) + 1]
	for _, e in ipairs(DB.consumables()) do
		if tostring(e.id) == pick.id then
			local copy = Consumable.new(e)
			local used = run:take_consumable(copy)
			if next(used) ~= nil then self:apply_consumable(used, "perkeo") end
			self.tape("perkeo", { id = pick.id })
			break
		end
	end
end

-- 渲染层读的纯数据
function Shop:view()
	local cons = {}
	for i = 1, #self.coffer do
		local c = self.coffer[i]
		if c and not self.coffer_used then
			cons[i] = { id = c.id, name = c:display_name(), price = c.price, stamp = c:is_instant() and "" or c:fire_label(),
				armed = self.run.coins >= c.price and self:consumable_effective(c), fx = c.fx_text }
		else
			cons[i] = false
		end
	end
	return {
		open = self.opened and not self.closed, mid = self.mid,
		offers = self:offers(), consumables = cons,
		reroll_cost = self.grant_free_reroll > 0 and 0 or self:reroll_cost_now(),
		buys_left = self.buys_left, coins = self.run.coins,
		first_target = not slots(self)[1],
	}
end

return Shop
