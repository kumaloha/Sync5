-- 金样对拍(docs/design/mirror.md §6):lua lua/check.lua  /  luajit lua/check.lua
-- 逐族读 golden/<族>.lua, 用镜像重放, 字符串逐字相同才算过。退出码 0 = 全绿。
-- SYNC5_CHECK=rng,pattern 只跑几族;重放器在 tools/fams.lua。
local root = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
package.path = root .. "/?.lua;" .. package.path
io.stdout:setvbuf("no")
local num = require("num")
local init = require("init")
local fams = require("tools.fams")
_G.H = num.hex2f64   -- 金样里的浮点是 H"<f64hex>"

local pass, fail = 0, 0
local shown = 0
local function eq(a, b, msg)
	if a == b then
		pass = pass + 1
	else
		fail = fail + 1
		if shown < 30 then
			shown = shown + 1
			print(string.format("  x FAIL: %s\n      got      %s\n      expected %s", msg, tostring(a), tostring(b)))
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
			local t0 = os.clock()
			local ok, err = pcall(fams[name], g, eq)
			if not ok then
				fail = fail + 1
				print(string.format("  x %-8s crashed: %s", name, tostring(err)))
			end
			print(string.format("  · %-8s %6d checks  %.2fs", name, pass + fail - before, os.clock() - t0))
		end
	end
end
print(string.format("[%s%s] === RESULT: %d passed, %d failed ===",
	init.version, init.jit and (" / " .. init.jit) or "", pass, fail))
os.exit(fail > 0 and 1 or 0)
