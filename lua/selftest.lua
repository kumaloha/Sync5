-- 自测(无金样那部分):数值语义 + 位串 + 64 位算术。 lua lua/selftest.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
package.path = root .. "/?.lua;" .. package.path
local num = require("num")
local Rng = require("rng")
local init = require("init")
local pass, fail = 0, 0
local function eq(a, b, msg)
	if a == b then pass = pass + 1 else fail = fail + 1; print("  x FAIL: " .. msg .. " (got " .. tostring(a) .. ", expected " .. tostring(b) .. ")") end
end
eq(num.int(-2.7), -2, "int trunc neg")
eq(num.int(2.7), 2, "int trunc pos")
eq(num.round(2.5), 3, "round half away +")
eq(num.round(-2.5), -3, "round half away -")
eq(num.round(0.49999), 0, "round below half")
eq(num.idiv(-7, 2), -3, "idiv C semantics")
eq(num.imod(-7, 2), -1, "imod C semantics")
eq(num.imod(7, -2), 1, "imod sign of dividend")
eq(num.f64hex(1.0), "3ff0000000000000", "f64hex 1.0")
eq(num.f64hex(0.1), "3fb999999999999a", "f64hex 0.1")
eq(num.f64hex(-2.5), "c004000000000000", "f64hex -2.5")
eq(num.f64hex(0), "0000000000000000", "f64hex 0")
eq(num.f64hex(2 ^ -1074), "0000000000000001", "f64hex min subnormal")
eq(num.f64hex(1e300), "7e37e43c8800759c", "f64hex 1e300")
for _, x in ipairs({ 0.1, 1 / 3, 123456.789, -0.0078125, 2 ^ -1000, 1.7976931348623157e308, 5e-324 }) do
	eq(num.hex2f64(num.f64hex(x)), x, "hex round trip " .. tostring(x))
end
eq(num.hex8(4294967295), "ffffffff", "hex8 max")
eq(num.hex8(0), "00000000", "hex8 zero")
-- 64 位乘法:0xFFFFFFFFFFFFFFFF * 0xFFFFFFFFFFFFFFFF mod 2^64 = 1
local hi, lo = Rng._mul64(0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF)
eq(hi, 0, "mul64 hi"); eq(lo, 1, "mul64 lo")
hi, lo = Rng._mul64(0, 0x12345678, 0, 0x9ABCDEF0)   -- = 0x0AF9F92B_3B2E0C60? 直接与 python 对: 0x12345678*0x9ABCDEF0
eq(num.hex8(hi) .. num.hex8(lo), "0b00ea4e242d2080", "mul64 32x32")
hi, lo = Rng._add64(0xFFFFFFFF, 0xFFFFFFFF, 0, 1)
eq(hi, 0, "add64 wrap hi"); eq(lo, 0, "add64 wrap lo")
hi, lo = Rng._split64(-1)
eq(hi, 0xFFFFFFFF, "split64 -1 hi"); eq(lo, 0xFFFFFFFF, "split64 -1 lo")
hi, lo = Rng._split64(4294967301)
eq(hi, 1, "split64 2^32+5 hi"); eq(lo, 5, "split64 2^32+5 lo")
eq(Rng._clz32(1), 31, "clz32 1"); eq(Rng._clz32(0x80000000), 0, "clz32 msb"); eq(Rng._clz32(0), 32, "clz32 0")
eq(Rng._round_to_float32(0x80000001), 0x80000000, "f32 round down")
eq(Rng._round_to_float32(0x80000180), 0x80000200, "f32 round half to even (odd q)")
eq(Rng._round_to_float32(0x80000080), 0x80000000, "f32 round half to even (even q)")
eq(Rng._round_to_float32(0xFFFFFFFF), 4294967296, "f32 round up to 2^32")
print(string.format("[%s%s] === RESULT: %d passed, %d failed ===", init.version, init.jit and (" / " .. init.jit) or "", pass, fail))
os.exit(fail > 0 and 1 or 0)
