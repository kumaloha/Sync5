-- core/card.gd 的镜像。rank 2..14(J/Q/K/A = 11/12/13/14), suit 0..3;万能牌 rank 15。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("core%.$", ""))
local num = require(R .. "num")

local Card = {}
Card.__index = Card

Card.SUITS = { "C", "D", "H", "S" }          -- 下标 = suit + 1(梅花/方块/红桃/黑桃)
Card.SUIT_GLYPHS = { "♣", "♦", "♥", "♠" }
Card.RANK_NAMES = { [11] = "J", [12] = "Q", [13] = "K", [14] = "A" }
Card.JOKER_RANK = 15
Card.JOKER_BIG = 0
Card.JOKER_LITTLE = 1

function Card.new(r, s)
	return setmetatable({ rank = r, suit = s }, Card)
end

function Card:is_wild()
	return self.rank == Card.JOKER_RANK
end

function Card:is_big_joker()
	return self.rank == Card.JOKER_RANK and self.suit == Card.JOKER_BIG
end

function Card:rank_label()
	if self:is_wild() then
		if self:is_big_joker() then return "★" end
		return "☆"
	end
	return Card.RANK_NAMES[self.rank] or num.itos(self.rank)
end

function Card:label()
	return self:rank_label() .. Card.SUITS[self.suit + 1]
end

function Card:glyph()
	return self:rank_label() .. Card.SUIT_GLYPHS[self.suit + 1]
end

-- 理牌比较器:点数降序, 同点数按花色降序(游戏侧 Phrase.sort_hand 与重放侧共用这一份)。
function Card.sort_desc(a, b)
	if a.rank ~= b.rank then return a.rank > b.rank end
	return a.suit > b.suit
end

-- label() 的逆:"10S" / "KC" / "★C" → Card;认不出的串返回 rank = -1, 不抛错也不猜。
-- ⚠ 花色字母是最后一个字节(ASCII), 点数串是它前面的全部字节(★/☆ 是 3 字节 UTF-8, 按字节比即可)。
function Card.from_label(s)
	if #s < 2 then return Card.new(-1, 0) end
	local su = num.find(Card.SUITS, s:sub(-1))
	if su < 0 then return Card.new(-1, 0) end
	local rs = s:sub(1, -2)
	if rs == "★" or rs == "☆" then
		return Card.new(Card.JOKER_RANK, su)
	end
	for r, name in pairs(Card.RANK_NAMES) do
		if name == rs then return Card.new(r, su) end
	end
	if rs:match("^[%+%-]?%d+$") then
		return Card.new(tonumber(rs), su)
	end
	return Card.new(-1, su)
end

function Card:is_red()
	if self:is_wild() then return self:is_big_joker() end
	return self.suit == 1 or self.suit == 2
end

-- 金样 / 摘要用:[rank, suit]
function Card:to_golden()
	return { self.rank, self.suit }
end

return Card
