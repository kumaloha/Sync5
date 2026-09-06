-- core/lingo.gd 的镜像:gettext 式单表(data/lingo.json)。语言判定注入(她接 UrhoX 的 locale)。
-- 探针 / 对拍恒 cn;Tape 不走这一层。表里查不到的串原样返回。
local P = (...):match("^(.-)[^%.]+$") or ""
local DB = require(P .. "db")

local Lingo = {}
local _lang = ""
local _loc_cache = {}
local _resolver = nil   -- function() -> "cn" | "en";缺省 cn

-- 注入语言解析器(编排层在启动时调:env.locale())。
function Lingo.set_resolver(f)
	_resolver = f
	_lang = ""
	_loc_cache = {}
	DB._set_localizer(Lingo.localize)
end

function Lingo.lang()
	if _lang == "" then _lang = Lingo._resolve() end
	return _lang
end

function Lingo._resolve()
	if _resolver then
		local l = _resolver()
		if l == "cn" or l == "en" then return l end
	end
	return "cn"
end

-- 测试与设置页用:强制切语言并清缓存。
function Lingo.force(l)
	_lang = l
	_loc_cache = {}
	DB._set_localizer(Lingo.localize)
end

-- 单串翻译(代码字面量的出口)。cn 模式零开销原样返回。
function Lingo.t(zh)
	if Lingo.lang() ~= "en" then return zh end
	local tb = DB.lingo().table or {}
	local v = tb[zh]
	if v == nil then return zh end
	return v
end

-- 实体显示名:en 用数据里现成的 name, 缺了退回 cn。
function Lingo.pick(e)
	if Lingo.lang() == "en" then
		local n = e.name
		if n ~= nil and n ~= "" then return tostring(n) end
	end
	local cn = e.cn
	if cn == nil then cn = e.name end
	if cn == nil then return "" end
	return tostring(cn)
end

local function walk(v)
	local tv = type(v)
	if tv == "table" then
		local o = {}
		for k, x in pairs(v) do
			if type(k) == "string" and k:sub(1, 1) == "_" then
				o[k] = x
			else
				o[k] = walk(x)
			end
		end
		return o
	elseif tv == "string" then
		local tb = DB.lingo().table or {}
		local t = tb[v]
		if t == nil then return v end
		return t
	end
	return v
end

-- 整树翻译(DB 的 ui/tutorial/run 出口)。cn 原样返回同一个对象;en 返回深拷贝的翻译副本并缓存。
function Lingo.localize(d, cache_key)
	if Lingo.lang() ~= "en" then return d end
	local hit = _loc_cache[cache_key]
	if hit then return hit end
	local out = walk(d)
	_loc_cache[cache_key] = out
	return out
end

DB._set_localizer(Lingo.localize)
return Lingo
