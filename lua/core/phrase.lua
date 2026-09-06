-- core/phrase.gd 的镜像:一拍的引擎无关逻辑(弃牌原位补、缓存对调、封条/盖牌、锁定结算)。
-- 不含时钟:编排层在锁定时刻调 lock_and_settle()。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("core%.$", ""))
local num = require(R .. "num")
local Card = require(P .. "card")
local Pattern = require(P .. "pattern")
local GameConfig = require(P .. "config")
local SectionMod = require(P .. "modifier")
local Economy = require(P .. "economy")
local BlindBoon = require(P .. "blind_boon")

local Phrase = {}
Phrase.__index = Phrase

function Phrase.new(deck_ref, cache_ref, starting_coins)
	local self = setmetatable({}, Phrase)
	self.deck = deck_ref
	self.hand = {}
	self.cache = cache_ref
	self.coins = starting_coins
	self.discards_used = 0
	self.discard_batch_max = 0
	self.faces_discarded = 0
	self.swapped_in = {}
	self._initial_hand = {}
	self.discard_actions_used = 0
	self.swap_actions_used = 0
	self.discard_cards_used = 0
	self.action_cards_used = 0
	self.action_count = 0
	self.action_track = ""
	self.phrase_idx = -1
	self.mod_roll = {}
	self.cache_scoring = false
	self.cache_discard_rank_sum = 0
	self.discard_budget = -1
	self.locked = false
	self.result = {}
	self.mod = ""
	self.boon = ""
	self.hidden = {}
	self.cache_meta = { ages = {}, next = 0 }
	self.initial_cache = {}
	self.sealed_hand_card = nil
	self.sealed_cache_card = nil
	self.locked_cache_cards = {}
	self.marked_cache_card = nil
	self.spotlight_card = nil
	self.ghost_cards = {}
	self.request_goal = ""
	self.request_prev_kind = -99
	self.request_met = true
	return self
end

-- 发手牌, 缓存补到这张脸的容量(先裁后补)。
function Phrase:start()
	num.clear(self.hand)
	for _ = 1, GameConfig.HAND_SIZE do
		local c = self.deck:draw()
		if c ~= nil then self.hand[#self.hand + 1] = c end
	end
	local cap = SectionMod.cache_cap(self.mod)
	if num.get(self.mod_roll, "worse", false) then
		cap = num.maxi(0, cap - SectionMod.roll_cache_extra(self.mod))
	end
	while #self.cache > cap do
		self.deck:discard(table.remove(self.cache))
	end
	while #self.cache < cap do
		local cc = self.deck:draw()
		if cc == nil then break end
		self.cache[#self.cache + 1] = cc
	end
	self.discards_used = 0
	self.discard_batch_max = 0
	self.faces_discarded = 0
	self.swapped_in = {}
	self._initial_hand = {}
	for _, hc in ipairs(self.hand) do self._initial_hand[hc] = true end
	self.discard_actions_used = 0
	self.swap_actions_used = 0
	self.discard_cards_used = 0
	self.action_cards_used = 0
	self.cache_discard_rank_sum = 0
	self.action_count = 0
	self.action_track = ""
	self.locked = false
	self.result = {}
	self.request_met = self.request_goal == ""
	self.locked_cache_cards = {}
	self.marked_cache_card = nil
	self.spotlight_card = nil
	self.ghost_cards = {}
	self:_sync_cache_ages()
	if SectionMod.cache_evict(self.mod) == 1 and #self.cache > 0 then
		self.marked_cache_card = self.cache[self.deck:pick_index(#self.cache) + 1]
	end
	self.initial_cache = num.shallow(self.cache)
	self.sealed_hand_card = self:_pick_sealed_hand()
	self.sealed_cache_card = self:_pick_sealed_cache()
	if BlindBoon.spotlight_cards(self.boon) > 0 then
		self.spotlight_card = self.deck:draw()
	end
	self.hidden = {}
	if SectionMod.hide_faces(self.mod) then
		for _, c in ipairs(self.hand) do
			if c.rank >= 11 and c.rank <= 13 then self.hidden[c] = true end
		end
		for _, c in ipairs(self.cache) do
			if c.rank >= 11 and c.rank <= 13 then self.hidden[c] = true end
		end
	end
	local extra_hide = SectionMod.hide_random(self.mod)
	if extra_hide > 0 and #self.hand > 0 then
		local pick_pool = {}
		for i = 0, #self.hand - 1 do pick_pool[#pick_pool + 1] = i end
		for _ = 1, num.mini(extra_hide, #pick_pool) do
			local j = self.deck:pick_index(#pick_pool)
			self.hidden[self.hand[pick_pool[j + 1] + 1]] = true
			table.remove(pick_pool, j + 1)
		end
	end
end

function Phrase:can_discard(count)
	if self.locked or count <= 0 or self.coins < Economy.discard_cost(count) then return false end
	local limit = SectionMod.discard_action_limit(self.mod)
	if limit >= 0 and self.discard_actions_used >= limit then return false end
	local shared = SectionMod.action_limit(self.mod)
	if shared >= 0 and self.action_count >= shared then return false end
	local cards_cap = SectionMod.discard_cards_max(self.mod)
	if cards_cap >= 0 and self.discard_cards_used + count > cards_cap then return false end
	local combo_cap = SectionMod.action_cards_max(self.mod)
	if combo_cap >= 0 and self.action_cards_used + count > combo_cap then return false end
	if SectionMod.exclusive_action_tracks(self.mod) and self.action_track == "swap" then return false end
	if self.discard_budget >= 0 and self.discards_used + count > self.discard_budget then return false end
	return true
end

-- hand_indices / cache_indices 一律 0 基(契约)
function Phrase:can_discard_selected(hand_indices, cache_indices)
	cache_indices = cache_indices or {}
	if not self:can_discard(#hand_indices + #cache_indices) then return false end
	local seen_hand = {}
	for _, i in ipairs(hand_indices) do
		if i < 0 or i >= #self.hand or seen_hand[i] then return false end
		seen_hand[i] = true
		if self.hand[i + 1] == self.sealed_hand_card then return false end
	end
	local seen_cache = {}
	for _, i in ipairs(cache_indices) do
		if i < 0 or i >= #self.cache or seen_cache[i] then return false end
		seen_cache[i] = true
		if self.cache[i + 1] == self.sealed_hand_card or self.cache[i + 1] == self.sealed_cache_card then return false end
	end
	return true
end

function Phrase:discard_selected(hand_indices, cache_indices)
	cache_indices = cache_indices or {}
	local total = #hand_indices + #cache_indices
	if not self:can_discard_selected(hand_indices, cache_indices) then return false end
	self.coins = self.coins - Economy.discard_cost(total)
	self.discards_used = self.discards_used + total
	self.discard_batch_max = num.maxi(self.discard_batch_max, total)
	for _, fi in ipairs(hand_indices) do
		local c = self.hand[fi + 1]
		if c ~= nil and c.rank >= 11 and c.rank <= 13 then self.faces_discarded = self.faces_discarded + 1 end
	end
	for _, fi in ipairs(cache_indices) do
		local c = self.cache[fi + 1]
		if c ~= nil and c.rank >= 11 and c.rank <= 13 then self.faces_discarded = self.faces_discarded + 1 end
	end
	local blind_refill = SectionMod.hide_refill(self.mod)
	local face_refill = SectionMod.hide_faces(self.mod)
	if BlindBoon.ghost_first_discard(self.boon) and #self.ghost_cards == 0 and #hand_indices > 0 then
		for _, first_i in ipairs(hand_indices) do
			local fc = self.hand[num.int(first_i) + 1]
			self.ghost_cards[#self.ghost_cards + 1] = Card.new(fc.rank, fc.suit)
		end
	end
	for _, i in ipairs(hand_indices) do
		local old = self.hand[i + 1]
		self.hidden[old] = nil
		self.deck:discard(old)
		local nc = self:_draw_refill()
		if nc == nil then nc = self.deck:draw() end
		self.hand[i + 1] = nc
		if nc ~= nil and (blind_refill or (face_refill and nc.rank >= 11 and nc.rank <= 13)) then
			self.hidden[nc] = true
		end
	end
	for _, i in ipairs(cache_indices) do
		local old_cache = self.cache[i + 1]
		self.cache_discard_rank_sum = self.cache_discard_rank_sum + old_cache.rank
		self.hidden[old_cache] = nil
		self:_forget_cache_age(old_cache)
		self.deck:discard(old_cache)
		local nc = self:_draw_refill()
		self.cache[i + 1] = nc
		self:_remember_cache_age(nc)
		if nc ~= nil and (blind_refill or (face_refill and nc.rank >= 11 and nc.rank <= 13)) then
			self.hidden[nc] = true
		end
	end
	self.discard_actions_used = self.discard_actions_used + 1
	self.discard_cards_used = self.discard_cards_used + total
	self.action_cards_used = self.action_cards_used + total
	self.action_count = self.action_count + 1
	if self.action_track == "" then self.action_track = "discard" end
	return true
end

-- 手牌与缓存对调(免费, 时间是代价)。probe = 假想交换, 不计动作数。
function Phrase:swap_with_cache(hand_index, cache_index, probe)
	if not self:can_swap_action() or hand_index < 0 or hand_index >= #self.hand then return false end
	if cache_index < 0 or cache_index >= #self.cache then return false end
	if SectionMod.cache_blocks_red(self.mod) and self.hand[hand_index + 1]:is_red() then return false end
	local cc = self.cache[cache_index + 1]
	if cc == self.sealed_cache_card or self.locked_cache_cards[cc] then return false end
	local tmp = self.hand[hand_index + 1]
	self.hand[hand_index + 1] = cc
	self.cache[cache_index + 1] = tmp
	self.swapped_in[self.hand[hand_index + 1]] = true
	self.swapped_in[tmp] = nil
	self:_forget_cache_age(self.hand[hand_index + 1])
	self:_remember_cache_age(tmp)
	if SectionMod.cache_lock_phrases(self.mod) > 0 then
		self.locked_cache_cards[tmp] = true
	end
	if not probe then self:commit_probe_swap() end
	return true
end

function Phrase:commit_probe_swap()
	self.swap_actions_used = self.swap_actions_used + 1
	self.action_cards_used = self.action_cards_used + 1
	self.action_count = self.action_count + 1
	if self.action_track == "" then self.action_track = "swap" end
end

function Phrase:swapped_scoring_count(resolved)
	local n = 0
	for _, c in ipairs(resolved) do
		if c ~= nil and self.swapped_in[c] and not self._initial_hand[c] then n = n + 1 end
	end
	return n
end

function Phrase:can_swap_action()
	if self.locked or #self.hand == 0 or #self.cache == 0 then return false end
	local swap_limit = SectionMod.swap_action_limit(self.mod)
	if swap_limit >= 0 and self.swap_actions_used >= swap_limit then return false end
	local shared = SectionMod.action_limit(self.mod)
	if shared >= 0 and self.action_count >= shared then return false end
	local combo_cap = SectionMod.action_cards_max(self.mod)
	if combo_cap >= 0 and self.action_cards_used + 1 > combo_cap then return false end
	if SectionMod.exclusive_action_tracks(self.mod) and self.action_track == "discard" then return false end
	return true
end

function Phrase:discard_blocked_hand()
	local out = {}
	if self.sealed_hand_card ~= nil then out[self.sealed_hand_card] = true end
	return out
end

function Phrase:swap_blocked_hand()
	local out = {}
	if SectionMod.cache_blocks_red(self.mod) then
		for _, card in ipairs(self.hand) do
			if card:is_red() then out[card] = true end
		end
	end
	return out
end

function Phrase:swap_blocked_cache()
	local out = num.shallow(self.locked_cache_cards)
	if self.sealed_cache_card ~= nil then out[self.sealed_cache_card] = true end
	return out
end

function Phrase:discard_blocked_cache()
	local out = {}
	if self.sealed_hand_card ~= nil then out[self.sealed_hand_card] = true end
	if self.sealed_cache_card ~= nil then out[self.sealed_cache_card] = true end
	return out
end

function Phrase:_draw_refill()
	local min_rank = SectionMod.refill_rank_min(self.mod)
	local max_rank = SectionMod.refill_rank_max(self.mod)
	if min_rank > 2 or max_rank < Card.JOKER_RANK then
		return self.deck:draw_rank_range(min_rank, max_rank)
	end
	return self.deck:draw()
end

function Phrase:_lowest_starting_hand()
	local out = nil
	for _, card in ipairs(self.hand) do
		if out == nil or card.rank < out.rank then out = card end
	end
	return out
end

function Phrase:_pick_sealed_hand()
	if SectionMod.seals_random_start(self.mod) and #self.hand > 0 then
		return self.hand[self.deck:pick_index(#self.hand) + 1]
	end
	if SectionMod.seals_lowest_start(self.mod) then return self:_lowest_starting_hand() end
	return nil
end

function Phrase:_pick_sealed_cache()
	if SectionMod.seals_random_cache(self.mod) and #self.cache > 0 then
		return self.cache[self.deck:pick_index(#self.cache) + 1]
	end
	if SectionMod.seals_oldest_cache(self.mod) then return self:_oldest_cache_card() end
	return nil
end

function Phrase:_sync_cache_ages()
	if type(self.cache_meta.ages) ~= "table" then self.cache_meta.ages = {} end
	if self.cache_meta.next == nil then self.cache_meta.next = 0 end
	local ages = self.cache_meta.ages
	for card in pairs(ages) do
		if not num.has(self.cache, card) then ages[card] = nil end
	end
	for _, card in ipairs(self.cache) do self:_remember_cache_age(card) end
end

function Phrase:_remember_cache_age(card)
	if card == nil then return end
	local ages = self.cache_meta.ages
	if ages[card] ~= nil then return end
	ages[card] = num.int(self.cache_meta.next)
	self.cache_meta.next = num.int(self.cache_meta.next) + 1
end

function Phrase:_forget_cache_age(card)
	if card ~= nil and self.cache_meta.ages ~= nil then
		self.cache_meta.ages[card] = nil
	end
end

function Phrase:_oldest_cache_card()
	local out = nil
	local best_age = 9007199254740991
	local ages = self.cache_meta.ages
	for _, card in ipairs(self.cache) do
		local age = ages[card]
		if age == nil then age = best_age end
		if age < best_age then
			best_age = age
			out = card
		end
	end
	return out
end

-- 理牌:点数降序, 同点数花色降序(比较器只此一份 Card.sort_desc)
function Phrase:sort_hand()
	if self.locked then return end
	table.sort(self.hand, Card.sort_desc)
end

function Phrase:current_best()
	return Pattern.evaluate_best(self:_scoring_cards(), self.deck.rules)
end

function Phrase:_scoring_cards()
	local cards = num.shallow(self.hand)
	if self.spotlight_card ~= nil then cards[#cards + 1] = self.spotlight_card end
	for _, ghost in ipairs(self.ghost_cards) do cards[#cards + 1] = ghost end
	if self.cache_scoring then
		for _, cc in ipairs(self.cache) do
			if cc ~= nil then cards[#cards + 1] = cc end
		end
	end
	return cards
end

function Phrase:has_initial_cache_in_hand()
	for _, card in ipairs(self.hand) do
		if num.has(self.initial_cache, card) then return true end
	end
	return false
end

-- visible = hand + cache;返回 0 基下标
function Phrase:hidden_indices(visible)
	local out = {}
	if SectionMod.hide_ranks(self.mod) or SectionMod.hide_suits(self.mod) then
		for i = 0, #visible - 1 do out[#out + 1] = i end
		return out
	end
	if next(self.hidden) == nil then return out end
	for i = 1, #visible do
		if self.hidden[visible[i]] then out[#out + 1] = i - 1 end
	end
	return out
end

function Phrase:visible_rank_of(card)
	if card == nil or SectionMod.hide_ranks(self.mod) or self.hidden[card] then return -1 end
	return card.rank
end

function Phrase:visible_suit_of(card)
	if card == nil or SectionMod.hide_suits(self.mod) or self.hidden[card] then return -1 end
	return card.suit
end

function Phrase:lock_and_settle()
	if self.locked then return self.result end
	self.locked = true
	self.result = Pattern.evaluate_best(self:_scoring_cards(), self.deck.rules)
	if self.request_goal ~= "" then
		self.request_met = self:_request_satisfied(self.result)
	end
	local hs = 0
	local resolved = num.get(self.result, "resolved", {})
	if SectionMod.hide_ranks(self.mod) or SectionMod.hide_suits(self.mod) then
		hs = #resolved
	else
		for _, hc in ipairs(resolved) do
			if self.hidden[hc] then hs = hs + 1 end
		end
	end
	self.result.hidden_scoring = hs
	self.hidden = {}
	return self.result
end

function Phrase:_request_satisfied(res)
	local g = self.request_goal
	if g == "color_mix" then
		local has_red, has_black = false, false
		for _, card in ipairs(self.hand) do
			has_red = has_red or card:is_red()
			has_black = has_black or not card:is_red()
		end
		return has_red and has_black
	elseif g == "face_or_ace" then
		for _, card in ipairs(self.hand) do
			if card.rank >= 11 and card.rank <= 14 then return true end
		end
		return false
	elseif g == "initial_cache" then
		for _, card in ipairs(self.hand) do
			if num.has(self.initial_cache, card) then return true end
		end
		return false
	elseif g == "fresh_kind" then
		return self.request_prev_kind ~= -99 and num.int(num.get(res, "kind", -99)) ~= self.request_prev_kind
	end
	return true
end

function Phrase:request_goal_valid(goal)
	local visible = num.shallow(self.hand)
	for _, c in ipairs(self.cache) do visible[#visible + 1] = c end
	if goal == "color_mix" then
		local has_red, has_black = false, false
		for _, card in ipairs(visible) do
			has_red = has_red or card:is_red()
			has_black = has_black or not card:is_red()
		end
		return has_red and has_black
	elseif goal == "face_or_ace" then
		for _, card in ipairs(visible) do
			if card.rank >= 11 and card.rank <= 14 then return true end
		end
		return false
	elseif goal == "initial_cache" then
		return #self.initial_cache > 0
	elseif goal == "fresh_kind" then
		if self.request_prev_kind == -99 then return false end
		if num.int(num.get(self:current_best(), "kind", -99)) ~= self.request_prev_kind then return true end
		for hi = 1, #self.hand do
			for ci = 1, #self.cache do
				local candidate = num.shallow(self.hand)
				candidate[hi] = self.cache[ci]
				if num.int(num.get(Pattern.evaluate_best(candidate, self.deck.rules), "kind", -99)) ~= self.request_prev_kind then
					return true
				end
			end
		end
		return false
	end
	return false
end

-- 拍末:手牌进弃牌堆;驱逐脸在这里丢缓存(下一拍 start() 再补满)
function Phrase:cleanup()
	for _, c in ipairs(self.hand) do self.deck:discard(c) end
	num.clear(self.hand)
	if self.spotlight_card ~= nil then
		self.deck:discard(self.spotlight_card)
		self.spotlight_card = nil
	end
	self.ghost_cards = {}
	local evict_left = SectionMod.cache_evict(self.mod)
	if self.marked_cache_card ~= nil and evict_left > 0 then
		evict_left = evict_left - 1
		local marked_i = num.find(self.cache, self.marked_cache_card)
		if marked_i >= 0 then
			self:_forget_cache_age(self.marked_cache_card)
			self.deck:discard(self.marked_cache_card)
			table.remove(self.cache, marked_i + 1)
		end
		self.marked_cache_card = nil
	end
	for _ = 1, evict_left do
		if #self.cache == 0 then break end
		local j = self.deck:pick_index(#self.cache)
		self:_forget_cache_age(self.cache[j + 1])
		self.deck:discard(self.cache[j + 1])
		table.remove(self.cache, j + 1)
	end
end

return Phrase
