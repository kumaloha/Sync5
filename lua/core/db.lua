-- core/db.gd 的镜像 —— **只搬访问器**(docs/design/mirror.md §2):1.4k 行校验是测试期门禁,
-- 数据在 Godot 侧过检后共享。这里读的是 tools/luagen.py 生成的 lua/data/*.lua。
-- run()/ui()/tutorial() 过 Lingo.localize(与 Godot 同:en 模式整树替换展示串)。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("core%.$", ""))
local num = require(R .. "num")

local DB = {}
local _cache = {}
local _localizer = nil   -- 由 lingo.lua 注册:function(tbl, name) -> tbl

function DB._set_localizer(f)
	_localizer = f
	_cache = {}
end

local function raw(name)
	local v = _cache[name]
	if v == nil then
		v = require(R .. "data." .. name)
		_cache[name] = v
	end
	return v
end

local function localized(name)
	local key = "@" .. name
	local v = _cache[key]
	if v == nil then
		v = raw(name)
		if _localizer then v = _localizer(v, name) end
		_cache[key] = v
	end
	return v
end

function DB.load_error() return "" end
function DB.run() return localized("run") end
function DB.economy() return raw("economy") end
function DB.faces() return raw("faces") end
function DB.boons() return raw("boons") end
function DB.jokers() return raw("jokers").jokers or {} end
function DB.consumables() return raw("consumables").consumables or {} end
function DB.sim() return raw("sim") end
function DB.ui() return localized("ui") end
function DB.tape() return raw("tape") end
function DB.tutorial() return localized("tutorial") end
function DB.profile() return raw("profile") end
function DB.lingo() return raw("lingo") end
function DB.ranking() return raw("ranking") end
function DB.director() return raw("director") end
function DB.patterns() return raw("patterns") end

-- {段号(int): [由易到难的 face_id]}
function DB.ranking_tiers()
	local out = {}
	for k, v in pairs(DB.ranking()) do
		if type(k) == "string" and k:sub(1, 1) ~= "_" then
			out[tonumber(k)] = v
		end
	end
	return out
end

return DB
