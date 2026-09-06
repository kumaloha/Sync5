-- core/tutorial.gd 的镜像:教学关脚本(data/tutorial.json)—— 第 N 拍该多长、该亮什么、该说什么。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("core%.$", ""))
local num = require(R .. "num")
local DB = require(P .. "db")
local GameConfig = require(P .. "config")

local Tutorial = {}
Tutorial.ACTIONS = { "play", "discard", "swap", "multiselect", "buy" }
Tutorial.ARG_KEYS = { "discard_cost", "joker_price" }

local function steps_() return DB.tutorial().steps or {} end

function Tutorial.require(step)
	local s = steps_()
	if step < 0 or step >= #s then return "" end
	return tostring(num.get(s[step + 1], "require", ""))
end

function Tutorial._arg_value(name)
	if name == "discard_cost" then return GameConfig.DISCARD_COST end
	if name == "joker_price" then return num.int(num.get(GameConfig.JOKER_PRICES, "common", 0)) end
	return 0
end

-- %d 价签代入(GDScript 的 `text % vals`)
function Tutorial._fmt(text, args)
	if args == nil or #args == 0 then return text end
	local vals = {}
	for _, a in ipairs(args) do vals[#vals + 1] = Tutorial._arg_value(tostring(a)) end
	local i = 0
	return (text:gsub("%%d", function()
		i = i + 1
		return num.itos(vals[i] or 0)
	end))
end

function Tutorial.steps() return #steps_() end

function Tutorial.seconds(step)
	local s = steps_()
	if step < 0 or step >= #s then return GameConfig.phrase_duration(0) end
	return num.get(s[step + 1], "seconds", GameConfig.phrase_duration(0)) + 0.0
end

function Tutorial.unlocked(step)
	local out = {}
	local s = steps_()
	for i = 1, num.mini(step + 1, #s) do
		for _, c in ipairs(s[i].unlock or {}) do
			local id = tostring(c)
			if not num.has(out, id) then out[#out + 1] = id end
		end
	end
	if step >= #s then return Tutorial.components() end
	return out
end

function Tutorial.is_unlocked(component, step)
	return num.has(Tutorial.unlocked(step), component)
end

function Tutorial.hint(step)
	local s = steps_()
	if step < 0 or step >= #s then return { command = "", signal = "" } end
	local st = s[step + 1]
	return { command = Tutorial._fmt(tostring(num.get(st, "command", "")), st.args or {}),
		signal = tostring(num.get(st, "signal", "")) }
end

function Tutorial.shot(step)
	local s = steps_()
	if step < 0 or step >= #s then return "" end
	return tostring(num.get(s[step + 1], "shot", ""))
end

function Tutorial.spot(step)
	local s = steps_()
	if step < 0 or step >= #s then return "" end
	return tostring(num.get(s[step + 1], "spot", ""))
end

function Tutorial.shop_step() return #steps_() - 1 end

function Tutorial.cutin(key)
	local c = num.get(DB.tutorial().cutins or {}, key, {})
	if type(c) ~= "table" or next(c) == nil then return {} end
	local focus = {}
	for _, r in ipairs(c.focus or {}) do focus[#focus + 1] = tostring(r) end
	return { after_step = num.int(num.get(c, "after_step", -1)), seconds = num.get(c, "seconds", 2.5) + 0.0,
		focus = focus, command = Tutorial._fmt(tostring(num.get(c, "command", "")), c.args or {}) }
end

function Tutorial.focus(step)
	local s = steps_()
	if step < 0 or step >= #s then return {} end
	local out = {}
	for _, r in ipairs(s[step + 1].focus or {}) do out[#out + 1] = tostring(r) end
	return out
end

function Tutorial.regions()
	local out = {}
	for _, k in ipairs(num.sorted_keys(DB.ui().tutor_focus or {})) do
		if tostring(k):sub(1, 1) ~= "_" then out[#out + 1] = tostring(k) end
	end
	return out
end

function Tutorial.components()
	local out = {}
	for _, c in ipairs(DB.tutorial().components or {}) do out[#out + 1] = tostring(c) end
	return out
end

return Tutorial
