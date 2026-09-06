-- core/deck.gd 的镜像:52 张牌堆 + 弃牌堆;手牌与缓存在外面, 洗回时自然不含它们。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("core%.$", ""))
local num = require(R .. "num")
local Rng = require(R .. "rng")
local Card = require(P .. "card")

local Deck = {}
Deck.__index = Deck

Deck.TRIM_RANK_MAX = 3

-- seed_value 缺省 -1 = 随机种子(与 Godot 的 randomize 一样不可复现)。
function Deck.new(seed_value)
	if seed_value == nil then seed_value = -1 end
	local self = setmetatable({
		draw_pile = {},
		discard_pile = {},
		_rng = Rng.new(),
		rules = {},
		wild_extra = {},
		trim_low = false,
	}, Deck)
	if seed_value >= 0 then
		self._rng:seed(seed_value)
	else
		self._rng:seed(os.time() * 1000 + num.int((os.clock() * 1000000) % 1000))
	end
	self:_build_full()
	return self
end

function Deck:_build_full()
	num.clear(self.draw_pile)
	num.clear(self.discard_pile)
	for s = 0, 3 do
		for r = 2, 14 do
			self.draw_pile[#self.draw_pile + 1] = Card.new(r, s)
		end
	end
	self:shuffle()
end

-- 超级百搭注入:按来源记账, 同一来源只生效一次;注入的 JOKER 用 suit 2/3 轮流。
function Deck:add_wilds(source, n)
	if self.wild_extra[source] ~= nil then return end
	self.wild_extra[source] = n
	for i = 0, n - 1 do
		self.draw_pile[#self.draw_pile + 1] = Card.new(Card.JOKER_RANK, 2 + (i % 2))
	end
	self:shuffle()
end

-- 修剪:2 和 3 永久离开牌库(手里握着的不当场没收, 弃掉时经 discard() 过滤离场)。
function Deck:trim_low_ranks()
	if self.trim_low then return end
	self.trim_low = true
	for i = #self.draw_pile, 1, -1 do
		local c = self.draw_pile[i]
		if not c:is_wild() and c.rank <= Deck.TRIM_RANK_MAX then
			table.remove(self.draw_pile, i)
		end
	end
	for i = #self.discard_pile, 1, -1 do
		local c = self.discard_pile[i]
		if not c:is_wild() and c.rank <= Deck.TRIM_RANK_MAX then
			table.remove(self.discard_pile, i)
		end
	end
end

function Deck:shuffle()
	local pile = self.draw_pile
	for i = #pile - 1, 1, -1 do
		local j = self._rng:randi_range(0, i)
		local tmp = pile[i + 1]
		pile[i + 1] = pile[j + 1]
		pile[j + 1] = tmp
	end
end

function Deck:draw()
	if #self.draw_pile == 0 then
		self:_reshuffle_discard()
	end
	if #self.draw_pile == 0 then
		return nil
	end
	return table.remove(self.draw_pile)
end

-- 只抽点数在闭区间内的下一张, 不合格的留在堆里(Low End 的补牌用)。
function Deck:draw_rank_range(min_rank, max_rank)
	if #self.draw_pile == 0 then
		self:_reshuffle_discard()
	end
	local found = self:_take_rank_range(min_rank, max_rank)
	if found ~= nil then return found end
	if #self.discard_pile > 0 then
		for _, c in ipairs(self.discard_pile) do
			self.draw_pile[#self.draw_pile + 1] = c
		end
		num.clear(self.discard_pile)
		self:shuffle()
		return self:_take_rank_range(min_rank, max_rank)
	end
	return nil
end

function Deck:_take_rank_range(min_rank, max_rank)
	for i = #self.draw_pile, 1, -1 do
		local card = self.draw_pile[i]
		if card.rank >= min_rank and card.rank <= max_rank then
			table.remove(self.draw_pile, i)
			return card
		end
	end
	return nil
end

-- [0, n) 的随机下标, 走牌堆自己的 rng(core 不许碰时钟或全局随机)。
function Deck:pick_index(n)
	if n <= 1 then return 0 end
	return self._rng:randi_range(0, n - 1)
end

function Deck:discard(card)
	if card == nil then return end
	if self.trim_low and not card:is_wild() and card.rank <= Deck.TRIM_RANK_MAX then
		return
	end
	self.discard_pile[#self.discard_pile + 1] = card
end

function Deck:_reshuffle_discard()
	self.draw_pile = num.shallow(self.discard_pile)
	num.clear(self.discard_pile)
	self:shuffle()
end

-- 设想抽 n 张但不消耗牌堆(求解器用);一次调用内不放回;不够就并上弃牌堆。
function Deck:peek_many(rng, n)
	if n <= 0 then return {} end
	local pool = num.shallow(self.draw_pile)
	if #pool < n then
		for _, c in ipairs(self.discard_pile) do pool[#pool + 1] = c end
	end
	if #pool < n then return {} end
	local out = {}
	for _ = 1, n do
		local j = rng:randi_range(0, #pool - 1)
		out[#out + 1] = pool[j + 1]
		table.remove(pool, j + 1)
	end
	return out
end

function Deck:remaining()
	return #self.draw_pile
end

function Deck:total()
	return #self.draw_pile + #self.discard_pile
end

-- 断点续玩快照:两堆的顺序、规则旗、万能牌记账、低段裁剪、RNG 状态(十六进制串)。
function Deck:snapshot()
	return {
		draw = Deck.cards_out(self.draw_pile), disc = Deck.cards_out(self.discard_pile),
		wildx = num.deep(self.wild_extra), trim = self.trim_low,
		rules = num.deep(self.rules), rng = self._rng:state_hex(),
	}
end

function Deck.cards_out(arr)
	local out = {}
	for _, c in ipairs(arr) do
		out[#out + 1] = { c.rank, c.suit }
	end
	return out
end

function Deck.from_snapshot(d)
	local deck = Deck.new(0)
	num.clear(deck.draw_pile)
	num.clear(deck.discard_pile)
	for _, p in ipairs(d.draw or {}) do
		deck.draw_pile[#deck.draw_pile + 1] = Card.new(num.int(p[1]), num.int(p[2]))
	end
	for _, p in ipairs(d.disc or {}) do
		deck.discard_pile[#deck.discard_pile + 1] = Card.new(num.int(p[1]), num.int(p[2]))
	end
	deck.wild_extra = num.deep(d.wildx or {})
	deck.trim_low = d.trim == true
	deck.rules = num.deep(d.rules or {})
	if type(d.rng) == "string" then
		deck._rng:set_state_hex(d.rng)
	else
		deck._rng:set_state_hex("0000000000000000")
	end
	return deck
end

-- 复制一份牌堆给假想推演用:必须有自己的 RNG(推演不许消耗真实局的随机数序列)。
function Deck:fork(seed_value)
	local d = Deck.new(seed_value)
	d.draw_pile = num.shallow(self.draw_pile)
	d.discard_pile = num.shallow(self.discard_pile)
	d.wild_extra = num.deep(self.wild_extra)
	d.trim_low = self.trim_low
	d.rules = num.deep(self.rules)
	return d
end

return Deck
