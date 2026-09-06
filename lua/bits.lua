-- 32 位位运算垫片:5.3+ 用运算符(经 load 延迟解析, 免得 `&` 在 5.1 里是语法错误),
-- LuaJIT/5.1 用 bit 库, 5.2 用 bit32。所有函数返回 [0, 2^32) 的无符号值。
local N = 4294967296

local ops
-- ⚠ 新版 LuaJIT 也编译得过 5.3 运算符, 但结果是 32 位**有符号**(-32 而不是 4294967264);
-- 所以运算符那支也要 `% 2^32` 归一, 而不是只 `& 0xFFFFFFFF`(踩过:clz32 拿到负数死循环)。
local chunk = load and load([[
	local N = 4294967295
	local M = 4294967296
	return {
		band = function(a, b) return ((a & b) & N) % M end,
		bor = function(a, b) return ((a | b) & N) % M end,
		bxor = function(a, b) return ((a ~ b) & N) % M end,
		rshift = function(a, n) return ((a >> n) & N) % M end,
		lshift = function(a, n) return ((a << n) & N) % M end,
	}
]])
if chunk then
	local ok, t = pcall(chunk)
	if ok and type(t) == "table" then ops = t end
end

if not ops then
	local ok, bit = pcall(require, "bit")
	if ok and type(bit) == "table" and bit.band then
		ops = {
			band = function(a, b) return bit.band(a, b) % N end,
			bor = function(a, b) return bit.bor(a, b) % N end,
			bxor = function(a, b) return bit.bxor(a, b) % N end,
			rshift = function(a, n) return bit.rshift(a, n) % N end,
			lshift = function(a, n) return bit.lshift(a, n) % N end,
		}
	end
end

if not ops then
	local ok, bit32 = pcall(require, "bit32")
	if ok and type(bit32) == "table" and bit32.band then
		ops = {
			band = bit32.band, bor = bit32.bor, bxor = bit32.bxor,
			rshift = bit32.rshift, lshift = bit32.lshift,
		}
	end
end

assert(ops, "bits.lua: 没有可用的位运算实现(需要 5.3+ 运算符、LuaJIT bit 或 bit32)")
return ops
