-- 数值语义助手(docs/design/mirror.md §5)—— GDScript 与 Lua 默默分叉的地方全收在这里。
-- ⚠ 镜像里不许裸写 math.floor 代替 int(), 不许裸写 // 与 % 做整数除法。
local M = {}
local floor, ceil = math.floor, math.ceil

-- GDScript int(x):向零截断。
function M.int(x)
	if x >= 0 then return floor(x) end
	return ceil(x)
end

-- GDScript round(x):半数远离零。
function M.round(x)
	if x >= 0 then return floor(x + 0.5) end
	return ceil(x - 0.5)
end

-- GDScript 整数 `/`:向零截断(C 语义)。
function M.idiv(a, b)
	return M.int(a / b)
end

-- GDScript 整数 `%`:取被除数符号(C 语义)。
function M.imod(a, b)
	return a - b * M.idiv(a, b)
end

M.floor = floor
M.ceil = ceil
function M.maxi(a, b) if a > b then return a end return b end
function M.mini(a, b) if a < b then return a end return b end
function M.maxf(a, b) if a > b then return a end return b end
function M.minf(a, b) if a < b then return a end return b end
function M.clampi(x, lo, hi)
	if x < lo then return lo end
	if x > hi then return hi end
	return x
end
M.clampf = M.clampi
function M.absi(x) if x < 0 then return -x end return x end

-- ---- 容器 ----

-- Dictionary.get(k, d)
function M.get(t, k, d)
	if t == nil then return d end
	local v = t[k]
	if v == nil then return d end
	return v
end

-- Array.find(v) → 0 基下标, 找不到 -1。
function M.find(t, v)
	for i = 1, #t do
		if t[i] == v then return i - 1 end
	end
	return -1
end

function M.has(t, v)
	return M.find(t, v) >= 0
end

-- Array.erase(v):删第一个相等的元素。
function M.erase(t, v)
	for i = 1, #t do
		if t[i] == v then table.remove(t, i) return true end
	end
	return false
end

-- 类实例带 metatable, 是引用(GDScript 的 Object);纯表才被拷贝。
local function is_object(t)
	return getmetatable(t) ~= nil
end

-- duplicate(true):递归拷贝 Array/Dictionary, Object 仍是引用(与 GDScript 同)。
function M.deep(t)
	if type(t) ~= "table" or is_object(t) then return t end
	local out = {}
	for k, v in pairs(t) do
		out[k] = M.deep(v)
	end
	return out
end

-- duplicate():只拷一层。
function M.shallow(t)
	if type(t) ~= "table" or is_object(t) then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = v end
	return out
end

-- Dictionary.keys() 在 GDScript 里按插入序;Lua 的 pairs 无序。
-- 镜像里凡是「顺序影响结果」的字典遍历都必须走 sorted_keys(键为字符串或数字)。
function M.sorted_keys(t)
	local ks = {}
	for k in pairs(t) do ks[#ks + 1] = k end
	table.sort(ks, function(a, b)
		local ta, tb = type(a), type(b)
		if ta ~= tb then return ta < tb end
		return a < b
	end)
	return ks
end

function M.is_array(t)
	if type(t) ~= "table" then return false end
	local n = 0
	for k in pairs(t) do
		if type(k) ~= "number" then return false end
		n = n + 1
	end
	return n == #t
end

function M.size(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

-- ---- 浮点的位串(金样摘要用;两边逐位相同的唯一可靠口径) ----

-- 2^e 的精确表(重复乘除得到, 不走 pow)。
local POW2 = { [0] = 1.0 }
local function pow2(e)
	local v = POW2[e]
	if v then return v end
	if e > 0 then
		v = pow2(e - 1) * 2.0
	else
		v = pow2(e + 1) / 2.0
	end
	POW2[e] = v
	return v
end
M.pow2 = pow2

local HEX = "0123456789abcdef"
-- 32 位无符号 → 8 位十六进制(不用 %x:LuaJIT 对 ≥2^31 的值不可靠)。
function M.hex8(v)
	local out = {}
	for i = 8, 1, -1 do
		local d = v % 16
		out[i] = HEX:sub(d + 1, d + 1)
		v = (v - d) / 16
	end
	return table.concat(out)
end

function M.f64hex(x)
	if x ~= x then return "7ff8000000000000" end
	if x == math.huge then return "7ff0000000000000" end
	if x == -math.huge then return "fff0000000000000" end
	if x == 0 then
		if 1 / x < 0 then return "8000000000000000" end
		return "0000000000000000"
	end
	local sign = 0
	if x < 0 then sign = 1; x = -x end
	local e = floor(math.log(x) / math.log(2))
	-- log 的舍入会把 e 推出 [-1074, 1023]:pow2 溢出成 inf/0 后 m 的修正循环永不收敛(踩过)。
	if e > 1023 then e = 1023 elseif e < -1074 then e = -1074 end
	local m = x / pow2(e)
	while m >= 2 do m = m / 2; e = e + 1 end
	while m < 1 do m = m * 2; e = e - 1 end
	local expfield, frac
	if e < -1022 then
		expfield = 0
		frac = x / pow2(-1074)
	else
		expfield = e + 1023
		frac = (m - 1) * pow2(52)
	end
	local fhi = floor(frac / 4294967296.0)
	local flo = frac - fhi * 4294967296.0
	local hi = sign * 2147483648.0 + expfield * 1048576.0 + fhi
	return M.hex8(hi) .. M.hex8(flo)
end

function M.hex2f64(h)
	local hi = tonumber(h:sub(1, 8), 16)
	local lo = tonumber(h:sub(9, 16), 16)
	local sign = floor(hi / 2147483648.0)
	local expfield = floor((hi % 2147483648.0) / 1048576.0)
	local fhi = hi % 1048576.0
	local frac = fhi * 4294967296.0 + lo
	local x
	if expfield == 0 then
		x = frac * pow2(-1074)
	elseif expfield == 2047 then
		if frac == 0 then x = math.huge else x = 0 / 0 end
	else
		x = (1 + frac / pow2(52)) * pow2(expfield - 1023)
	end
	if sign == 1 then x = -x end
	return x
end

return M
