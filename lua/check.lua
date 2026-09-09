-- 金样对拍(docs/design/mirror.md §6):lua lua/check.lua  /  luajit lua/check.lua
-- 逐族读 golden/<族>.lua, 用镜像重放, 字符串逐字相同才算过。退出码 0 = 全绿。
-- SYNC5_CHECK=rng,pattern 只跑几族;重放器在 tools/fams.lua。
--
-- ⚑ 也能在引擎的沙箱里跑(不依赖 io / arg / dofile / os.exit):
--   local report = require("sync5.check").run({ print = print })   -- 返回 {pass, fail, lines}
-- 命令行跑时按脚本方式执行(有 arg 就当脚本)。
local P = (...)
local as_module = type(P) == "string" and P ~= "check" and not (rawget(_G, "arg") and arg[0])
local root_prefix
if type(P) == "string" and P:find("%.") then
	root_prefix = P:match("^(.-)[^%.]+$")      -- "sync5.check" → "sync5."
else
	root_prefix = ""
	local root = (rawget(_G, "arg") and arg[0] or ""):match("^(.*)[/\\]") or "."
	package.path = root .. "/?.lua;" .. package.path
end

local function run(opts)
	opts = opts or {}
	local out = opts.print or print
	local lines = {}
	local function say(s)
		lines[#lines + 1] = s
		out(s)
	end
	local num = require(root_prefix .. "num")
	local init = require(root_prefix .. "init")
	local fams = require(root_prefix .. "tools.fams")
	local H_prev = rawget(_G, "H")
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
				say(string.format("  x FAIL: %s\n      got      %s\n      expected %s", msg, tostring(a), tostring(b)))
			end
		end
	end

	local function golden(name)
		local ok, g = pcall(require, root_prefix .. "golden." .. name)
		if not ok then return nil end
		return g
	end

	local ORDER = { "rng", "pattern", "settle", "fx", "run", "visit" }
	local only = opts.only or (os and os.getenv and os.getenv("SYNC5_CHECK")) or nil
	local clock = (os and os.clock) or function() return 0 end
	for _, name in ipairs(ORDER) do
		if not only or only:find(name, 1, true) then
			local g = golden(name)
			if g == nil then
				say(string.format("  - %-8s skipped (no golden/%s.lua)", name, name))
			elseif fams[name] == nil then
				say(string.format("  - %-8s skipped (no replayer yet)", name))
			else
				local before = pass + fail
				local t0 = clock()
				local ok, err = pcall(fams[name], g, eq)
				if not ok then
					fail = fail + 1
					say(string.format("  x %-8s crashed: %s", name, tostring(err)))
				end
				say(string.format("  · %-8s %6d checks  %.2fs", name, pass + fail - before, clock() - t0))
			end
		end
	end
	say(string.format("[%s%s] === RESULT: %d passed, %d failed ===",
		init.version, init.jit and (" / " .. init.jit) or "", pass, fail))
	_G.H = H_prev
	return { pass = pass, fail = fail, lines = lines }
end

if as_module then
	return { run = run }
end
if io and io.stdout and io.stdout.setvbuf then io.stdout:setvbuf("no") end
local r = run()
if os and os.exit then os.exit(r.fail > 0 and 1 or 0) end
return r
