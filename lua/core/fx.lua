-- core/fx.gd 的镜像:效果 DSL 解释器。effects: [{when, do}], when 谓词取 AND, do 写一个结算通道。
-- 浮标文案逐字节与 Godot 一致(金样 fx 族盯着)。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("core%.$", ""))
local num = require(R .. "num")
local Pattern = require(P .. "pattern")
local GameConfig = require(P .. "config")
local fmt = string.format

local Fx = {}

Fx.TRIAL_WHEN = { "discards_eq", "discards_gte", "discard_batch_gte", "cache_mono_color",
	"cache_mono_suit", "cache_run", "cache_trio", "cache_all_faces", "swaps_eq" }
Fx.TRIAL_PER = { "discard", "cache_face", "face_discard", "swapped_scoring" }
Fx.TRIAL_DO = { "additive_cache_top" }
Fx.SAFE_WHEN = { "kind", "kind_in", "same_as_prev", "diff_from_prev", "acted_late", "acted_final",
	"coins_gte", "base_gte", "last_phrase", "first_phrase", "section_eq", "section_doubled",
	"counter_gte", "chance", "target_streak", "all_suits", "no_pair", "early_discards",
	"early_finish", "top_rank_gte" }
Fx.SAFE_PER = { "second_left", "cache_rank_sum", "hidden_scoring" }
Fx.SAFE_DO = { "mult", "mult_add", "additive", "bonus", "bonus_pct", "bonus_target_pct", "coins",
	"coins_factor", "mult_from_target_factor", "additive_face_value", "additive_low_value",
	"chips_per_card", "card_filter", "per", "cap", "step" }

-- 覆盖统计(check.lua 报「哪些操作码没被金样走到」)
Fx._seen_when = {}
Fx._seen_do = {}

local function warn(msg)
	if io and io.stderr then io.stderr:write("[Fx] " .. msg .. "\n") else print("[Fx] " .. msg) end
end

local function starts(s, pre)
	return s:sub(1, #pre) == pre
end

function Fx.trial_free(effects)
	for _, e in ipairs(effects) do
		for k in pairs(e.when or {}) do
			if num.has(Fx.TRIAL_WHEN, k) or not num.has(Fx.SAFE_WHEN, k) then return false end
		end
		local d = e["do"] or {}
		for k in pairs(d) do
			if num.has(Fx.TRIAL_DO, k) or not num.has(Fx.SAFE_DO, k) then return false end
		end
		if d.per ~= nil then
			local per = tostring(d.per)
			if num.has(Fx.TRIAL_PER, per) then return false end
			if not num.has(Fx.SAFE_PER, per) and not starts(per, "counter:") and not starts(per, "coins:") then
				return false
			end
		end
	end
	return true
end

function Fx.apply_effects(effects, state, ctx)
	local popup = ""
	for _, e in ipairs(effects) do
		if Fx._when_ok(e.when or {}, state, ctx) then
			local text = Fx._do(e["do"], state, ctx)
			if text ~= "" then
				if popup == "" then popup = text else popup = popup .. " " .. text end
			end
		end
	end
	return popup
end

local function kind_of(name)
	return Pattern.Kind[tostring(name)]
end

-- ⚠ 谓词的求值顺序 = when 字典的键序。GDScript 按插入序, Lua 的 pairs 无序 ——
-- 唯一有副作用的谓词是 chance(消耗一枚预掷), 同一条 when 里 chance 与别的谓词并存时
-- 短路顺序会影响消耗。数据里 chance 都是单独成条(t_db 可锁), 这里按键名排序保证确定性。
function Fx._when_ok(w, state, ctx)
	for _, k in ipairs(num.sorted_keys(w)) do
		local v = w[k]
		Fx._seen_when[k] = (Fx._seen_when[k] or 0) + 1
		if k == "kind" then
			if num.int(ctx.kind) ~= kind_of(v) then return false end
		elseif k == "kind_in" then
			local hit = false
			for _, n in ipairs(v) do
				if num.int(ctx.kind) == kind_of(n) then hit = true end
			end
			if not hit then return false end
		elseif k == "same_as_prev" then
			if num.int(ctx.prev_kind) ~= num.int(ctx.kind) then return false end
		elseif k == "diff_from_prev" then
			if num.int(ctx.prev_kind) == -99 or num.int(ctx.prev_kind) == num.int(ctx.kind) then return false end
		elseif k == "acted_late" then
			if not ctx.acted_late then return false end
		elseif k == "discards_eq" then
			if num.int(ctx.discards) ~= num.int(v) then return false end
		elseif k == "discards_gte" then
			if num.int(ctx.discards) < num.int(v) then return false end
		elseif k == "coins_gte" then
			if num.int(ctx.coins) < num.int(v) then return false end
		elseif k == "base_gte" then
			if num.int(ctx.base_score) < num.int(v) then return false end
		elseif k == "last_phrase" then
			if num.int(num.get(ctx, "phrase_idx", -1)) ~= GameConfig.PHRASES_PER_SECTION - 1 then return false end
		elseif k == "cache_mono_color" then
			local mc = num.get(ctx, "cache_cards", {})
			if #mc == 0 then return false end
			local colors = {}
			for _, c in ipairs(mc) do
				if not c:is_wild() then colors[c:is_red()] = true end
			end
			if num.size(colors) ~= 1 then return false end
		elseif k == "cache_mono_suit" then
			local cards = num.get(ctx, "cache_cards", {})
			if #cards == 0 then return false end
			local suits = {}
			for _, c in ipairs(cards) do
				if not c:is_wild() then suits[c.suit] = true end
			end
			if num.size(suits) > 1 then return false end
		elseif k == "top_rank_gte" then
			local top = 0
			for _, c in ipairs(num.get(ctx, "scoring_cards", {})) do
				top = num.maxi(top, num.int(c.rank))
			end
			if top < num.int(v) then return false end
		elseif k == "counter_gte" then
			if (num.get(state, tostring(v[1]), 0.0) + 0.0) < v[2] + 0.0 then return false end
		elseif k == "first_phrase" then
			if num.int(num.get(ctx, "phrase_idx", -1)) ~= 0 then return false end
		elseif k == "section_eq" then
			if num.int(num.get(ctx, "section_idx", -1)) ~= num.int(v) then return false end
		elseif k == "early_finish" then
			if not num.get(ctx, "early_finish", false) then return false end
		elseif k == "chance" then
			local lucks = num.get(ctx, "luck_rolls", {})
			if #lucks == 0 then return false end
			local rv = table.remove(lucks, 1) + 0.0
			local need = num.minf(1.0, (v + 0.0) * (num.get(ctx, "odds_mult", 1.0) + 0.0))
			if rv >= need then return false end
		elseif k == "target_streak" then
			if (num.get(ctx, "target_factor", 1.0) + 0.0) <= 1.0 then return false end
			if not num.get(ctx, "prev_target_hit", false) then return false end
		elseif k == "acted_final" then
			if not num.get(ctx, "acted_final", false) then return false end
		elseif k == "early_discards" then
			if not num.get(ctx, "early_discards", false) then return false end
		elseif k == "swaps_eq" then
			if num.int(num.get(ctx, "swaps", 0)) ~= num.int(v) then return false end
		elseif k == "discard_batch_gte" then
			if num.int(num.get(ctx, "discard_batch_max", 0)) < num.int(v) then return false end
		elseif k == "section_doubled" then
			local sd_target = num.int(num.get(ctx, "section_target", 0))
			if sd_target <= 0 or num.int(num.get(ctx, "section_score", 0)) < sd_target * 2 then return false end
		elseif k == "all_suits" then
			local seen = {}
			for _, c in ipairs(num.get(ctx, "scoring_cards", {})) do
				if not c:is_wild() then seen[c.suit] = true end
			end
			if num.size(seen) < 4 then return false end
		elseif k == "no_pair" then
			local seen = {}
			for _, c in ipairs(num.get(ctx, "scoring_cards", {})) do
				if not c:is_wild() then
					if seen[c.rank] then return false end
					seen[c.rank] = true
				end
			end
		elseif k == "cache_all_faces" then
			local cc = num.get(ctx, "cache_cards", {})
			if #cc == 0 then return false end
			for _, c in ipairs(cc) do
				if not c:is_wild() and (c.rank < 11 or c.rank > 13) then return false end
			end
		elseif k == "cache_run" then
			local rr = {}
			for _, c in ipairs(num.get(ctx, "cache_cards", {})) do
				if not c:is_wild() then rr[#rr + 1] = num.int(c.rank) end
			end
			if #rr < 3 then return false end
			table.sort(rr)
			for i = 2, #rr do
				if rr[i] ~= rr[i - 1] + 1 then return false end
			end
		elseif k == "cache_trio" then
			local tr = {}
			for _, c in ipairs(num.get(ctx, "cache_cards", {})) do
				if not c:is_wild() then tr[#tr + 1] = num.int(c.rank) end
			end
			if #tr < 3 then return false end
			for _, r in ipairs(tr) do
				if r ~= tr[1] then return false end
			end
		else
			warn("unknown predicate '" .. tostring(k) .. "'")
			return false
		end
	end
	return true
end

-- per / step 的计数倍数
function Fx._count(d, state, ctx)
	local per = tostring(num.get(d, "per", ""))
	local c = 1.0
	if per == "discard" then
		c = num.int(ctx.discards) + 0.0
	elseif per == "cache_face" then
		local nf = 0
		for _, cc in ipairs(num.get(ctx, "cache_cards", {})) do
			if not cc:is_wild() and cc.rank >= 11 and cc.rank <= 13 then nf = nf + 1 end
		end
		c = nf + 0.0
	elseif per == "second_left" then
		c = math.floor(num.maxf(0.0, num.get(ctx, "seconds_left", 0.0) + 0.0)) + 0.0
	elseif per == "face_discard" then
		c = num.int(num.get(ctx, "faces_discarded", 0)) + 0.0
	elseif per == "swapped_scoring" then
		c = num.int(num.get(ctx, "swapped_scoring", 0)) + 0.0
	elseif starts(per, "counter:") then
		c = num.get(state, per:sub(9), 0.0) + 0.0
	elseif per == "cache_rank_sum" then
		c = num.get(ctx, "cache_rank_sum", 0) + 0.0
	elseif per == "hidden_scoring" then
		c = num.get(ctx, "hidden_scoring", 0) + 0.0
	elseif starts(per, "coins:") then
		c = num.idiv(num.int(ctx.coins), num.int(tonumber(per:sub(7)))) + 0.0
	end
	if d.step ~= nil then
		c = num.idiv(num.int(c), num.int(d.step)) + 0.0
	end
	return c
end

local function mark_do(d)
	for k in pairs(d) do Fx._seen_do[k] = (Fx._seen_do[k] or 0) + 1 end
end

local CHANNELS = { "mult", "mult_add", "additive", "bonus", "bonus_target_pct", "bonus_pct", "coins" }

function Fx._do(d, state, ctx)
	mark_do(d)
	if d.mult_from_target_factor ~= nil then
		local tf = num.get(ctx, "target_factor", 1.0) + 0.0
		if tf > 1.0 then
			local mf = 1.0 + (tf - 1.0) * (d.mult_from_target_factor + 0.0)
			ctx.mult = ctx.mult * mf
			return fmt("×%.1f", mf)
		end
		return ""
	end
	if d.additive_face_value ~= nil then
		local val = num.int(d.additive_face_value)
		local boost = 0
		for _, c in ipairs(num.get(ctx, "scoring_cards", {})) do
			if c.rank >= 11 and c.rank <= 13 then boost = boost + (val - c.rank) end
		end
		if boost > 0 then
			ctx.additive = ctx.additive + boost
			return fmt("+%d", boost)
		end
		return ""
	end
	if d.additive_low_value ~= nil then
		local lval = num.int(d.additive_low_value)
		local lboost = 0
		for _, c in ipairs(num.get(ctx, "scoring_cards", {})) do
			if not c:is_wild() and c.rank >= 2 and c.rank <= 5 then lboost = lboost + (lval - c.rank) end
		end
		if lboost > 0 then
			ctx.additive = ctx.additive + lboost
			return fmt("+%d", lboost)
		end
		return ""
	end
	if d.coins_factor ~= nil then
		ctx.coins_factor = (num.get(ctx, "coins_factor", 1.0) + 0.0) * (d.coins_factor + 0.0)
		return "◆×" .. Fx._fmt_factor(d.coins_factor + 0.0)
	end
	if d.additive_cache_top ~= nil then
		local ctop = 0
		for _, c in ipairs(num.get(ctx, "cache_cards", {})) do
			if not c:is_wild() then ctop = num.maxi(ctop, num.int(c.rank)) end
		end
		ctop = ctop * num.int(d.additive_cache_top)
		if ctop > 0 then
			ctx.additive = ctx.additive + ctop
			return fmt("+%d", ctop)
		end
		return ""
	end
	if d.chips_per_card ~= nil then
		local per_card = num.int(d.chips_per_card)
		local filt = tostring(num.get(d, "card_filter", ""))
		local hits = 0
		for _, c in ipairs(num.get(ctx, "scoring_cards", {})) do
			if not c:is_wild() then
				local hit = false
				if filt == "red" then hit = c:is_red()
				elseif filt == "black" then hit = not c:is_red()
				elseif filt == "rank_lte_5" then hit = c.rank <= 5
				else warn("unknown card_filter '" .. filt .. "'") end
				if hit then hits = hits + 1 end
			end
		end
		if hits > 0 then
			local add = per_card * hits
			ctx.additive = ctx.additive + add
			return fmt("+%d", add)
		end
		return ""
	end

	local cnt = Fx._count(d, state, ctx)
	if cnt <= 0.0 then return "" end
	for _, ch in ipairs(CHANNELS) do
		local raw = d[ch]
		if raw ~= nil then
			local amt
			if type(raw) == "table" then
				amt = num.get(state, tostring(raw.counter), 0.0) + 0.0
			else
				amt = raw + 0.0
			end
			local contrib = amt * cnt
			if d.cap ~= nil then contrib = num.minf(contrib, d.cap + 0.0) end
			if ch == "mult" then
				ctx.mult = ctx.mult * contrib
				if math.abs(contrib - num.round(contrib)) < 0.001 then
					return fmt("×%d", num.round(contrib))
				end
				return fmt("×%.1f", contrib)
			elseif ch == "mult_add" then
				local f = 1.0 + contrib
				ctx.mult = ctx.mult * f
				return fmt("×%.2f", f)
			elseif ch == "additive" then
				local r = num.round(contrib)
				if r == 0 then return "" end
				ctx.additive = ctx.additive + r
				return fmt("+%d", r)
			elseif ch == "bonus" then
				local r = num.round(contrib)
				ctx.bonus = ctx.bonus + r
				return fmt("+%d", r)
			elseif ch == "bonus_target_pct" then
				local st = num.int(num.get(ctx, "section_target", 0))
				local per_beat
				if st > 0 then
					per_beat = st / GameConfig.PHRASES_PER_SECTION
				else
					per_beat = GameConfig.avg_beat_target()
				end
				local amt_pts = num.round(per_beat * contrib)
				if amt_pts == 0 then return "" end
				ctx.bonus = ctx.bonus + amt_pts
				return fmt("+%d", amt_pts)
			elseif ch == "bonus_pct" then
				if contrib < 0.001 then return "" end
				ctx.bonus_pct = ctx.bonus_pct + contrib
				return fmt("+%d%%", num.round(contrib * 100.0))
			elseif ch == "coins" then
				local r = num.round(contrib)
				if r == 0 then return "" end
				ctx.coins_bonus = ctx.coins_bonus + r
				return fmt("+%d◆", r)
			end
		end
	end
	warn("do has no known channel")
	return ""
end

-- ---- 计数器喂养 ----

function Fx.init_state(counters)
	local st = {}
	for cname, spec in pairs(counters or {}) do
		if spec.init ~= nil then st[cname] = spec.init + 0.0 end
	end
	return st
end

function Fx.on_discard(counters, state, n)
	if n <= 0 then return end
	for cname, spec in pairs(counters or {}) do
		if tostring(num.get(spec, "on_discard", "")) == "sum" then
			state[cname] = (num.get(state, cname, 0.0) + 0.0) + n
		end
	end
end

-- kind = "reroll" | "buy" | "target_swap"
function Fx.on_shop_event(counters, state, kind)
	local key = "on_" .. kind
	for cname, spec in pairs(counters or {}) do
		if spec[key] ~= nil then
			state[cname] = (num.get(state, cname, 0.0) + 0.0) + spec[key]
		end
	end
end

function Fx.on_phrase_end(counters, state, x)
	local early = num.get(x, "early_finish", false) and true or false
	for cname, spec in pairs(counters or {}) do
		if spec.on_early_finish ~= nil and early then
			state[cname] = (num.get(state, cname, 0.0) + 0.0) + spec.on_early_finish
		end
		if spec.pulse_on_early_finish ~= nil then
			state[cname] = early and 1.0 or 0.0
		end
		if spec.decay_per_phrase ~= nil then
			state[cname] = num.maxf(num.get(spec, "floor", 0.0) + 0.0,
				(num.get(state, cname, 0.0) + 0.0) - spec.decay_per_phrase)
		end
	end
end

-- 倍数的显示:整数不带小数点(×2), 非整数保留一位(×1.5)。
function Fx._fmt_factor(v)
	if math.abs(v - num.round(v)) < 0.01 then return fmt("%d", num.int(v)) end
	return fmt("%.1f", v)
end

return Fx
