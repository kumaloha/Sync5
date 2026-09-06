-- 编排层的无头驱动(自测用):假时钟 + 随机意图, 从首页打到终局。 lua lua/tools/drive.lua [seed] [runs]
--   也是给她看的「怎么接」范例:App.new 注入存储/locale/时钟, 每帧 tick, 读 view, 发意图, 取 events。
local root = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
root = root:gsub("[/\\]tools$", "")
package.path = root .. "/?.lua;" .. package.path
local App = require("app.phrase")
local Rng = require("rng")

local seed = tonumber(arg and arg[1]) or 1
local runs = tonumber(arg and arg[2]) or 1
local mem = nil
local storage = { read = function() return mem end, write = function(s) mem = s end }
local now = 0
local app = App.new({ storage = storage, locale = function() return "cn" end, now_ms = function() return now end, seed = seed })
local prng = Rng.new():seed(seed * 17 + 5)
local counts = { beats = 0, shops = 0, buys = 0, ends = 0, events = 0, denies = 0 }

local function step(ms)
	now = now + ms
	app:tick(now)
	for _, e in ipairs(app:events()) do
		counts.events = counts.events + 1
		if e.kind == "deny" then counts.denies = counts.denies + 1 end
		if e.kind == "settle" then counts.beats = counts.beats + 1 end
		if e.kind == "shop_open" then counts.shops = counts.shops + 1 end
		if e.kind == "run_end" then counts.ends = counts.ends + 1 end
	end
end

app:start_run()
local frames = 0
local finished = 0
while finished < runs and frames < 200000 do
	frames = frames + 1
	local v = app:view()
	local st = v.screen
	if st == "intro" then
		if prng:randi_range(0, 3) == 0 then app:skip_intro() end
		step(100)
	elseif st == "decision" then
		local r = prng:randi_range(0, 9)
		if r <= 2 and v.hand then
			app:tap_hand(prng:randi_range(0, #v.hand.cards - 1))
			if prng:randi_range(0, 1) == 0 and #v.hand.cache > 0 then app:tap_cache(prng:randi_range(0, #v.hand.cache - 1)) end
			app:discard()
		elseif r == 3 and v.hand and #v.hand.cache > 0 then
			app:drag_swap(prng:randi_range(0, #v.hand.cards - 1), prng:randi_range(0, #v.hand.cache - 1))
		elseif r == 4 then
			app:sort()
		elseif r == 5 and v.hand then
			app:discard_one(prng:randi_range(0, 1) == 0 and "hand" or "cache", prng:randi_range(0, 2))
		end
		step(prng:randi_range(200, 1500))
	elseif st == "resolve" or st == "cutin" then
		step(300)
	elseif st == "draft" then
		local sv = v.shop
		if sv.replace_pick ~= nil then
			app:replace(prng:randi_range(0, 3))
		else
			local r = prng:randi_range(0, 9)
			if r <= 4 and #sv.offers > 0 then
				local res = app:buy(prng:randi_range(0, #sv.offers - 1))
				if res.ok then counts.buys = counts.buys + 1 end
			elseif r <= 6 then
				local res = app:buy_consumable(prng:randi_range(0, 1))
				if res.ok then counts.buys = counts.buys + 1 end
			elseif r == 7 then
				app:reroll()
			else
				app:leave()
			end
		end
		step(50)
	elseif st == "end" then
		finished = finished + 1
		if v.end_screen.win then
			print(string.format("  run %d: WIN score=%d target=%d", finished, v.end_screen.score, v.end_screen.target))
		else
			print(string.format("  run %d: LOSE at sec %d score=%d target=%d why=%s", finished, app.run.section_idx, v.end_screen.score, v.end_screen.target, v.end_screen.why or ""))
		end
		if finished < runs then
			if prng:randi_range(0, 1) == 0 then app:restart() else app:end_home(); app:start_run() end
		end
		step(50)
	elseif st == "front" then
		app:start_run()
		step(50)
	else
		step(50)
	end
end
print(string.format("frames=%d beats=%d shops=%d buys=%d ends=%d events=%d denies=%d save_bytes=%d", frames, counts.beats, counts.shops, counts.buys, counts.ends, counts.events, counts.denies, mem and #mem or 0))
assert(finished == runs, "did not finish")
