-- core/consumable.gd 的镜像:消耗牌 —— 一次性、全部自动触发(fire = "buy" | "next" | 1..6)。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("core%.$", ""))
local num = require(R .. "num")
local DB = require(P .. "db")
local Lingo = require(P .. "lingo")

local Consumable = {}
Consumable.__index = Consumable

function Consumable.new(e)
	local self = setmetatable({}, Consumable)
	self._raw = e
	self.id = tostring(e.id or "")
	self.name = tostring(e.name or "")
	self.cn_name = tostring(e.cn or "")
	self.fx_text = tostring(e.fx or "")
	self.price = num.int(e.price or 3)
	self.fire = e.fire
	if self.fire == nil then self.fire = "buy" end
	self.action = num.deep(e.action or {})
	self.boost = num.deep(e.boost or {})
	self.queued_beats = 0
	return self
end

function Consumable:is_instant()
	return type(self.fire) == "string" and self.fire == "buy"
end

-- beat = 段内拍号(1 起), queued_beats = 排队至今经过的拍数
function Consumable:due_on(beat, queued_beats)
	if self:is_instant() then return false end
	if type(self.fire) == "string" then
		return self.fire == "next" and queued_beats >= 1
	end
	return num.int(self.fire) == beat
end

function Consumable:fire_label()
	if type(self.fire) == "string" then return "▸" end
	return num.itos(num.int(self.fire))
end

function Consumable:is_rule_card()
	return self.action.deck_rule ~= nil
end

function Consumable:display_name()
	return Lingo.pick({ cn = self.cn_name, name = self.name })
end

function Consumable:clone()
	local c = Consumable.new(self._raw)
	c.queued_beats = self.queued_beats
	return c
end

-- 消耗牌货架掷牌(游戏与 bot 共用):排除已在队列的;第一格在「必出规则牌」时只从规则牌里抽;
-- pick(n) 返回 [0, n) 的下标。返回原始数据行, 池空的格子是 false。
function Consumable.roll_shelf(held, rule_first, n, pick)
	local pool = {}
	for _, e in ipairs(DB.consumables()) do
		if held[tostring(e.id)] == nil then pool[#pool + 1] = e end
	end
	local out = {}
	for i = 0, n - 1 do
		if #pool == 0 then
			out[#out + 1] = false
		else
			local use = pool
			if i == 0 and rule_first then
				local rp = {}
				for _, e in ipairs(pool) do
					if Consumable.new(e):is_rule_card() then rp[#rp + 1] = e end
				end
				if #rp > 0 then use = rp end
			end
			local picked = use[num.int(pick(#use)) + 1]
			out[#out + 1] = picked
			num.erase(pool, picked)
		end
	end
	return out
end

return Consumable
