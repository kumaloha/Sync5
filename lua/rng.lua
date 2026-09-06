-- Godot 4.6 RandomNumberGenerator(PCG32, core/math/random_pcg.h + thirdparty/misc/pcg.cpp)的逐行复刻。
-- 64 位状态用两个 32 位肢体 {hi, lo} 表示, 乘法用 16 位肢体, 所以 5.1/LuaJIT/5.3+ 都能跑。
-- ⚠ 不许「简化」任何一步:randi_range 的拒绝采样、randf 的两步 + float32 舍入都是契约, 金样 rng 族盯着。
local P = (...):match("^(.-)[^%.]+$") or ""
local bits = require(P .. "bits")
local band, bor, bxor, rshift, lshift = bits.band, bits.bor, bits.bxor, bits.rshift, bits.lshift
local floor = math.floor
local N32 = 4294967296.0

local MULT_HI, MULT_LO = 0x5851F42D, 0x4C957F2D   -- 6364136223846793005
-- inc = (PCG_DEFAULT_INC_64 << 1) | 1, PCG_DEFAULT_INC_64 = 1442695040888963407 = 0x14057B7EF767814F
local INC_HI, INC_LO = 0x280AF6FD, 0xEECF029F
-- Godot 构造时的缺省种子(RandomNumberGenerator.new() 会 randomize, 镜像里一律显式 seed)
local DEFAULT_SEED_HI, DEFAULT_SEED_LO = 0xA72E2E44, 0x3F9DB29B  -- 12047754176567800795 (仅记录, 不用)

local function mul32lo(x, y)
	local x0 = x % 65536; local x1 = (x - x0) / 65536
	local y0 = y % 65536; local y1 = (y - y0) / 65536
	return (x0 * y0 + ((x1 * y0 + x0 * y1) % 65536) * 65536) % N32
end

-- (ahi:alo) * (bhi:blo) mod 2^64
local function mul64(ahi, alo, bhi, blo)
	local a0 = alo % 65536; local a1 = (alo - a0) / 65536
	local b0 = blo % 65536; local b1 = (blo - b0) / 65536
	local p00 = a0 * b0
	local mid = a0 * b1 + a1 * b0
	local p11 = a1 * b1
	local lo = p00 + (mid % 65536) * 65536
	local carry = floor(lo / N32)
	lo = lo % N32
	local hi = (p11 + (mid - mid % 65536) / 65536 + carry) % N32
	hi = (hi + mul32lo(ahi, blo) + mul32lo(alo, bhi)) % N32
	return hi, lo
end

local function add64(ahi, alo, bhi, blo)
	local lo = alo + blo
	local carry = floor(lo / N32)
	lo = lo % N32
	local hi = (ahi + bhi + carry) % N32
	return hi, lo
end

-- int64(可负)→ 两个 32 位肢体(二补码)。|s| < 2^53 时精确。
local function split64(s)
	local lo = s % N32
	local hi = floor(s / N32) % N32
	return hi, lo
end

local function clz32(x)
	if x == 0 then return 32 end
	assert(x > 0 and x < N32, "clz32: 输入必须是 [0, 2^32) 的无符号值(位运算垫片漏了归一?)")
	local n = 0
	local bit = 2147483648.0
	while x < bit do
		n = n + 1
		bit = bit / 2
	end
	return n
end

-- C 的 (float) 把 32 位整数舍到 24 位尾数(round-to-nearest-even)。输入 ∈ [2^31, 2^32)。
local function round_to_float32(v)
	local r = v % 256
	local q = (v - r) / 256
	if r > 128 or (r == 128 and q % 2 == 1) then q = q + 1 end
	return q * 256
end

local Rng = {}
Rng.__index = Rng

function Rng.new()
	local self = setmetatable({ hi = 0, lo = 0 }, Rng)
	return self
end

-- pcg32_random_r
function Rng:rand()
	local ohi, olo = self.hi, self.lo
	local nhi, nlo = mul64(ohi, olo, MULT_HI, MULT_LO)
	self.hi, self.lo = add64(nhi, nlo, INC_HI, INC_LO)
	-- xorshifted = ((old >> 18) ^ old) >> 27   (uint32)
	local s_lo = bor(rshift(olo, 18), lshift(band(ohi, 0x3FFFF), 14))
	local s_hi = rshift(ohi, 18)
	local x_lo = bxor(s_lo, olo)
	local x_hi = bxor(s_hi, ohi)
	local xorshifted = bor(rshift(x_lo, 27), lshift(band(x_hi, 0x7FFFFFF), 5))
	local rot = rshift(ohi, 27)          -- old >> 59
	return bor(rshift(xorshifted, rot), lshift(xorshifted, band(32 - rot, 31)))
end

-- pcg32_srandom_r(state = 0; inc 固定; step; state += seed; step)
function Rng:seed(s)
	self.hi, self.lo = 0, 0
	self:rand()
	local shi, slo = split64(s)
	self.hi, self.lo = add64(self.hi, self.lo, shi, slo)
	self:rand()
	return self
end

-- pcg32_boundedrand_r
function Rng:bounded(bound)
	local threshold = (N32 - bound) % bound
	while true do
		local r = self:rand()
		if r >= threshold then return r % bound end
	end
end

function Rng:randi()
	return self:rand()
end

-- RandomPCG::random(int, int)
function Rng:randi_range(from, to)
	if from == to then return from end
	local mn, mx
	if from < to then mn, mx = from, to else mn, mx = to, from end
	local diff = (mx - mn) % N32
	if diff == 4294967295 then
		return self:rand() + mn
	end
	return self:bounded(diff + 1) + mn
end

-- RandomPCG::randf():两步 + float32 舍入(director.gd 量到的「randf 消耗两步」就是它)
function Rng:randf()
	local off = self:rand()
	if off == 0 then return 0 end
	local v = round_to_float32(bor(self:rand(), 0x80000001))
	local e = -32 - clz32(off)
	return v * (2.0 ^ e)
end

-- RandomPCG::randd():三步, 64 位有效数一次舍入到 double
function Rng:randd()
	local off = self:rand()
	if off == 0 then return 0 end
	local hi = bor(self:rand(), 0x80000000)
	local lo = bor(self:rand(), 1)
	local sig = hi * N32 + lo
	local e = -64 - clz32(off)
	return sig * (2.0 ^ e)
end

function Rng:state_hex()
	local num = require(P .. "num")
	return num.hex8(self.hi) .. num.hex8(self.lo)
end

function Rng:set_state_hex(h)
	self.hi = tonumber(h:sub(1, 8), 16)
	self.lo = tonumber(h:sub(9, 16), 16)
	return self
end

-- Godot 侧 `rng.state` 是 int64;|state| 超过 2^53 时数值不精确, 镜像只用十六进制串。
function Rng:get_state_hex() return self:state_hex() end

function Rng:clone()
	local r = Rng.new()
	r.hi, r.lo = self.hi, self.lo
	return r
end

Rng._mul64 = mul64
Rng._add64 = add64
Rng._split64 = split64
Rng._clz32 = clz32
Rng._round_to_float32 = round_to_float32
return Rng
