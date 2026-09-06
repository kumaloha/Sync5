-- 金样对拍(docs/design/mirror.md §6):lua lua/check.lua  /  luajit lua/check.lua
-- 逐族读 golden/<族>.lua, 用镜像重放, 字符串逐字相同才算过。退出码 0 = 全绿。
local root = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
package.path = root .. "/?.lua;" .. package.path
io.stdout:setvbuf("no")
local num = require("num")
local Rng = require("rng")
local init = require("init")
_G.H = num.hex2f64   -- 金样里的浮点是 H"<f64hex>"

local pass, fail = 0, 0
local shown = 0
local function eq(a, b, msg)
	if a == b then
		pass = pass + 1
	else
		fail = fail + 1
		if shown < 40 then
			shown = shown + 1
			print(string.format("  x FAIL: %s (got %s, expected %s)", msg, tostring(a), tostring(b)))
		end
	end
end

local function exists(path)
	local f = io.open(path, "r")
	if f then f:close() return true end
	return false
end

local function golden(name)
	local path = root .. "/golden/" .. name .. ".lua"
	if not exists(path) then return nil end
	return dofile(path)
end

local fams = {}

-- ---------------------------------------------------------------- rng
function fams.rng(g)
	for ci, case in ipairs(g) do
		local rng = Rng.new():seed(case.seed)
		for i, op in ipairs(case.ops) do
			local k = op[1]
			local tag = string.format("rng seed=%d step=%d %s", case.seed, i, k)
			if k == "i" then
				eq(rng:randi(), op[2], tag)
			elseif k == "r" then
				eq(rng:randi_range(op[2], op[3]), op[4], tag .. string.format("(%d,%d)", op[2], op[3]))
			elseif k == "f" then
				eq(num.f64hex(rng:randf()), num.f64hex(op[2]), tag)
			elseif k == "s" then
				eq(rng:state_hex(), op[2], tag)
			elseif k == "S" then
				rng:set_state_hex(op[2])
			end
		end
	end
end

-- ---------------------------------------------------------------- 主流程
local ORDER = { "rng", "pattern", "settle", "fx", "run" }
local only = os.getenv("SYNC5_CHECK")
for _, name in ipairs(ORDER) do
	if not only or only:find(name, 1, true) then
		local g = golden(name)
		if g == nil then
			print(string.format("  - %-8s skipped (no golden/%s.lua)", name, name))
		elseif fams[name] == nil then
			print(string.format("  - %-8s skipped (no replayer yet)", name))
		else
			local before = pass + fail
			local ok, err = pcall(fams[name], g)
			if not ok then
				fail = fail + 1
				print(string.format("  x %-8s crashed: %s", name, tostring(err)))
			end
			print(string.format("  · %-8s %d checks", name, pass + fail - before))
		end
	end
end
print(string.format("[%s%s] === RESULT: %d passed, %d failed ===",
	init.version, init.jit and (" / " .. init.jit) or "", pass, fail))
os.exit(fail > 0 and 1 or 0)
