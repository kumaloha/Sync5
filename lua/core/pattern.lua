-- core/pattern.gd 的镜像:牌型判定与五张最优组合。分数 = (chips + 点数和) × 牌型倍率。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("core%.$", ""))
local num = require(R .. "num")
local Card = require(P .. "card")
local DB = require(P .. "db")

local Pattern = {}

Pattern.Kind = {
	HIGH_CARD = 0, PAIR = 1, TWO_PAIR = 2, THREE_KIND = 3, STRAIGHT = 4, FLUSH = 5,
	FULL_HOUSE = 6, FOUR_KIND = 7, STRAIGHT_FLUSH = 8, ROYAL_FLUSH = 9,
}
-- 枚举名按值排(GDScript 的 Kind.keys() 顺序)
Pattern.KIND_NAMES = { "HIGH_CARD", "PAIR", "TWO_PAIR", "THREE_KIND", "STRAIGHT", "FLUSH",
	"FULL_HOUSE", "FOUR_KIND", "STRAIGHT_FLUSH", "ROYAL_FLUSH" }

-- data/patterns.json 的一张表 {Kind 名: 值} → {Kind 值: 值}
local function _load_table(which)
	local out = {}
	for name, v in pairs(DB.patterns()[which] or {}) do
		if which == "names" then
			out[Pattern.Kind[name]] = v
		else
			out[Pattern.Kind[name]] = num.int(v)
		end
	end
	return out
end

local function _load_kind_coins()
	local out = {}
	for name, v in pairs(DB.economy().kind_coins or {}) do
		out[Pattern.Kind[name]] = num.int(v)
	end
	return out
end

Pattern.NAMES = _load_table("names")
Pattern.BASE_CHIPS = _load_table("chips")
Pattern.BASE_MULT = _load_table("mult")
Pattern.BASE_COINS = _load_kind_coins()

Pattern.MEMO_CAP = 65536
Pattern.RULE_BITS = { shortcut = 1, fourfingers = 2, redtone = 4, blacktone = 8 }
local _memo = {}
local _memo_n = 0
local _buf5 = { false, false, false, false, false }
local _runsets_cache = {}
local _rank_cnt = {}

local function empty(t)
	return t == nil or next(t) == nil
end

-- 5..7 张牌里最优的五张。返回 {} 若少于 5 张。
function Pattern.evaluate_best(cards, rules)
	rules = rules or {}
	if #cards < 5 then return {} end
	local best = {}
	local best_score = -1
	for _, combo in ipairs(Pattern._combos_indices(#cards, 5)) do
		local five = {}
		for _, i in ipairs(combo) do five[#five + 1] = cards[i + 1] end
		local res = Pattern._score_five(five, rules)
		if res.score > best_score then
			best_score = res.score
			best = res
		end
	end
	return best
end

-- 只算分数, 不建结果字典(带分数记忆)。必须与 evaluate_best(five).score 逐位相同。
function Pattern.score_five(five, rules)
	rules = rules or {}
	if #five ~= 5 then
		local r = Pattern.evaluate_best(five, rules)
		if empty(r) then return 0 end
		return r.score
	end
	local rk = 0
	if not empty(rules) then rk = Pattern._rules_key(rules) end
	local key = -1
	if rk >= 0 then
		key = Pattern._key5(five) + rk * 1073741824
		local hit = _memo[key]
		if hit ~= nil then return hit end
	end
	local s = -1
	for _, c in ipairs(five) do
		if c:is_wild() then
			s = Pattern._score_five(five, rules).score
			break
		end
	end
	if s < 0 then
		local kind = Pattern._classify(five, rules)
		local rsum = 0
		for _, c in ipairs(five) do rsum = rsum + c.rank end
		s = (Pattern.BASE_CHIPS[kind] + rsum) * Pattern.BASE_MULT[kind]
	end
	if key >= 0 then
		if _memo_n >= Pattern.MEMO_CAP then
			_memo = {}
			_memo_n = 0
		end
		if _memo[key] == nil then _memo_n = _memo_n + 1 end
		_memo[key] = s
	end
	return s
end

-- 规则字典 → 4 位;含未知键返回 -1(不进记忆)。
function Pattern._rules_key(rules)
	local rk = 0
	for k, v in pairs(rules) do
		local bit = Pattern.RULE_BITS[k]
		if bit == nil then return -1 end
		if v then rk = rk + bit end
	end
	return rk
end

-- 5 张牌的顺序无关键:编码(rank×4+suit)排序后拼成 30 位。
function Pattern._key5(five)
	local a = five[1].rank * 4 + five[1].suit
	local b = five[2].rank * 4 + five[2].suit
	local c = five[3].rank * 4 + five[3].suit
	local d = five[4].rank * 4 + five[4].suit
	local e = five[5].rank * 4 + five[5].suit
	local t
	if a > b then t = a; a = b; b = t end
	if d > e then t = d; d = e; e = t end
	if c > e then t = c; c = e; e = t end
	if c > d then t = c; c = d; d = t end
	if b > e then t = b; b = e; e = t end
	if a > d then t = a; a = d; d = t end
	if a > c then t = a; a = c; c = t end
	if b > d then t = b; b = d; d = t end
	if b > c then t = b; b = c; c = t end
	return a + b * 64 + c * 4096 + d * 262144 + e * 16777216
end

-- 8 选 5 的最高分, 复用缓冲。
function Pattern.best_score_of(cards, rules)
	rules = rules or {}
	if #cards < 5 then return 0 end
	local best = -1
	for _, combo in ipairs(Pattern._combos_indices(#cards, 5)) do
		for j = 1, 5 do _buf5[j] = cards[combo[j] + 1] end
		local s = Pattern.score_five(_buf5, rules)
		if s > best then best = s end
	end
	return num.maxi(0, best)
end

-- 恰好五张, 万能牌解析到最优代入。
function Pattern._score_five(five, rules)
	rules = rules or {}
	local has_wild = false
	for _, c in ipairs(five) do
		if c:is_wild() then has_wild = true end
	end
	if not has_wild then
		return Pattern._pack(five, five, rules)
	end
	return Pattern._score_many_wilds(five, rules)
end

-- 仅测试参照的 k≤2 暴力(每张万能试 52 张实牌)。
function Pattern._score_five_brute(five, rules)
	rules = rules or {}
	local wild_idx = {}
	for i = 1, #five do
		if five[i]:is_wild() then wild_idx[#wild_idx + 1] = i end
	end
	if #wild_idx == 0 then return Pattern._pack(five, five, rules) end
	assert(#wild_idx <= 2, "brute 参照只支持 k<=2")
	local best = {}
	local best_score = -1
	local subs = {}
	for s = 0, 3 do
		for r = 2, 14 do subs[#subs + 1] = Card.new(r, s) end
	end
	local trial = num.shallow(five)
	if #wild_idx == 1 then
		for _, a in ipairs(subs) do
			trial[wild_idx[1]] = a
			local res = Pattern._pack(five, trial, rules)
			if res.score > best_score then best_score = res.score; best = res end
		end
	else
		for _, a in ipairs(subs) do
			trial[wild_idx[1]] = a
			for _, b in ipairs(subs) do
				trial[wild_idx[2]] = b
				local res = Pattern._pack(five, trial, rules)
				if res.score > best_score then best_score = res.score; best = res end
			end
		end
	end
	return best
end

-- 万能牌解析 = 全域候选构造(三族:顺子窗 / 点数族 / 同花兜底), 打分仍走同一份判型。
function Pattern._score_many_wilds(five, rules)
	local reals = {}
	for _, c in ipairs(five) do
		if not c:is_wild() then reals[#reals + 1] = c end
	end
	local k = #five - #reals
	local suits_pool = {}
	local real_ranks = {}
	for _, c in ipairs(reals) do
		if not num.has(suits_pool, c.suit) then suits_pool[#suits_pool + 1] = c.suit end
		if not num.has(real_ranks, c.rank) then real_ranks[#real_ranks + 1] = c.rank end
	end
	if #suits_pool == 0 then suits_pool = { 0 } end
	local cands = {}
	-- ① 顺子/同花顺窗
	for _, w in ipairs(Pattern._run_sets(rules)) do
		local gaps = {}
		for _, r in ipairs(w) do
			if not num.has(real_ranks, r) then gaps[#gaps + 1] = r end
		end
		if #gaps <= k then
			local spare = k - #gaps
			for _, s in ipairs(suits_pool) do
				local cand = num.shallow(reals)
				for _, r in ipairs(gaps) do cand[#cand + 1] = Card.new(r, s) end
				for _ = 1, spare do cand[#cand + 1] = Card.new(14, s) end
				cands[#cands + 1] = cand
			end
		end
	end
	-- ② 点数族
	local targets = num.shallow(real_ranks)
	if not num.has(targets, 14) then targets[#targets + 1] = 14 end
	if not num.has(targets, 13) then targets[#targets + 1] = 13 end
	local assigns = {}
	Pattern._rank_multisets(targets, k, 1, {}, assigns)
	for _, asg in ipairs(assigns) do
		local cand = num.shallow(reals)
		for i = 1, #asg do cand[#cand + 1] = Card.new(asg[i], (i - 1) % 4) end
		cands[#cands + 1] = cand
	end
	-- ③ 同花兜底
	for _, s in ipairs(suits_pool) do
		local cand = num.shallow(reals)
		for _ = 1, k do cand[#cand + 1] = Card.new(14, s) end
		cands[#cands + 1] = cand
	end
	-- 严格大于才换 ⇒ 平分取第一个候选(与 Godot 逐位相同)
	local best_cand = {}
	local best_score = -1
	for _, cand in ipairs(cands) do
		local sc = Pattern._score_plain5(cand, rules)
		if sc > best_score then
			best_score = sc
			best_cand = cand
		end
	end
	return Pattern._pack(five, best_cand, rules)
end

function Pattern._score_plain5(five, rules)
	local kind = Pattern._classify(five, rules)
	local rsum = 0
	for _, c in ipairs(five) do rsum = rsum + c.rank end
	return (Pattern.BASE_CHIPS[kind] + rsum) * Pattern.BASE_MULT[kind]
end

-- 顺子候选的 rank 集合表, 按 (近道, 四指) 组合缓存。A 恒为 14。
function Pattern._run_sets(rules)
	local shortcut = num.get(rules, "shortcut", false) and true or false
	local four = num.get(rules, "fourfingers", false) and true or false
	local key = (shortcut and 1 or 0) + (four and 2 or 0)
	if _runsets_cache[key] then return _runsets_cache[key] end
	local sets = {}
	for t = 6, 14 do
		sets[#sets + 1] = { t - 4, t - 3, t - 2, t - 1, t }
	end
	sets[#sets + 1] = { 14, 2, 3, 4, 5 }
	if shortcut then
		for lo = 1, 9 do
			for drop = lo + 1, lo + 4 do
				local s5 = {}
				for r = lo, lo + 5 do
					if r ~= drop then s5[#s5 + 1] = (r == 1) and 14 or r end
				end
				sets[#sets + 1] = s5
			end
		end
	end
	if four then
		for lo = 1, 11 do
			local s4 = {}
			for r = lo, lo + 3 do s4[#s4 + 1] = (r == 1) and 14 or r end
			sets[#sets + 1] = s4
		end
		if shortcut then
			for lo = 1, 10 do
				for drop = lo + 1, lo + 3 do
					local s4 = {}
					for r = lo, lo + 4 do
						if r ~= drop then s4[#s4 + 1] = (r == 1) and 14 or r end
					end
					sets[#sets + 1] = s4
				end
			end
		end
	end
	_runsets_cache[key] = sets
	return sets
end

-- targets 的 k 元多重组合(不计顺序)。start 为 1 基。
function Pattern._rank_multisets(targets, k, start, cur, out)
	if #cur == k then
		out[#out + 1] = num.shallow(cur)
		return
	end
	for i = start, #targets do
		cur[#cur + 1] = targets[i]
		Pattern._rank_multisets(targets, k, i, cur, out)
		cur[#cur] = nil
	end
end

function Pattern._pack(original, resolved, rules)
	local kind = Pattern._classify(resolved, rules or {})
	local rsum = 0
	for _, c in ipairs(resolved) do rsum = rsum + c.rank end
	local chips = Pattern.BASE_CHIPS[kind] + rsum
	return {
		kind = kind,
		name = Pattern.NAMES[kind],
		cards = original,
		resolved = num.shallow(resolved),
		chips = chips,
		pmult = Pattern.BASE_MULT[kind],
		rank_sum = rsum,
		score = chips * Pattern.BASE_MULT[kind],
		coins = Pattern.BASE_COINS[kind],
	}
end

function Pattern._classify(five, rules)
	if empty(rules) then return Pattern._classify_fast(five) end
	return Pattern._classify_ref(five, rules)
end

-- 无规则牌时的快路径:点数计数 + 位集合, 零分配零排序。必须与 _classify_ref 逐位相同。
function Pattern._classify_fast(five)
	for i = 0, 14 do _rank_cnt[i] = 0 end
	local present = {}
	local suit0 = five[1].suit
	local is_flush = true
	for _, c in ipairs(five) do
		local r = c.rank
		_rank_cnt[r] = _rank_cnt[r] + 1
		present[r] = true
		if c.suit ~= suit0 then is_flush = false end
	end
	local pairs_n = 0
	local has3, has4 = false, false
	for r = 2, 14 do
		local n = _rank_cnt[r]
		if n == 2 then pairs_n = pairs_n + 1
		elseif n == 3 then has3 = true
		elseif n == 4 then has4 = true end
	end
	local is_straight = false
	for lo = 2, 10 do
		if present[lo] and present[lo + 1] and present[lo + 2] and present[lo + 3] and present[lo + 4] then
			is_straight = true
			break
		end
	end
	if not is_straight and present[14] and present[2] and present[3] and present[4] and present[5] then
		is_straight = true
	end
	local K = Pattern.Kind
	if is_straight and is_flush then
		if present[10] and present[11] and present[12] and present[13] and present[14] then
			return K.ROYAL_FLUSH
		end
		return K.STRAIGHT_FLUSH
	end
	if has4 then return K.FOUR_KIND end
	if has3 and pairs_n >= 1 then return K.FULL_HOUSE end
	if is_flush then return K.FLUSH end
	if is_straight then return K.STRAIGHT end
	if has3 then return K.THREE_KIND end
	if pairs_n >= 2 then return K.TWO_PAIR end
	if pairs_n >= 1 then return K.PAIR end
	return K.HIGH_CARD
end

function Pattern._classify_ref(five, rules)
	rules = rules or {}
	local ranks = {}
	local suits = {}
	local rank_count = {}
	for _, c in ipairs(five) do
		ranks[#ranks + 1] = c.rank
		suits[c.suit] = true
		rank_count[c.rank] = (rank_count[c.rank] or 0) + 1
	end
	table.sort(ranks)
	local is_flush = num.size(suits) == 1
	if not is_flush then
		local red_on = num.get(rules, "redtone", false) and true or false
		local black_on = num.get(rules, "blacktone", false) and true or false
		if red_on or black_on then
			local colors = {}
			for _, c in ipairs(five) do colors[c:is_red()] = true end
			if num.size(colors) == 1 then
				if colors[true] then is_flush = red_on else is_flush = black_on end
			end
		end
	end
	if not is_flush and num.get(rules, "fourfingers", false) then
		local tally = {}
		for _, c in ipairs(five) do
			local key
			if num.get(rules, "redtone", false) and c:is_red() then
				key = "red"
			elseif num.get(rules, "blacktone", false) and not c:is_red() then
				key = "black"
			else
				key = num.itos(c.suit)
			end
			tally[key] = (tally[key] or 0) + 1
			if tally[key] >= 4 then
				is_flush = true
				break
			end
		end
	end
	local is_straight = Pattern._is_straight(ranks, rules)
	local counts = {}
	for _, v in pairs(rank_count) do counts[#counts + 1] = v end
	table.sort(counts, function(a, b) return a > b end)
	local K = Pattern.Kind
	if is_straight and is_flush then
		if ranks[1] == 10 and ranks[5] == 14 then return K.ROYAL_FLUSH end
		return K.STRAIGHT_FLUSH
	end
	if counts[1] == 4 then return K.FOUR_KIND end
	if counts[1] == 3 and #counts > 1 and counts[2] == 2 then return K.FULL_HOUSE end
	if is_flush then return K.FLUSH end
	if is_straight then return K.STRAIGHT end
	if counts[1] == 3 then return K.THREE_KIND end
	if counts[1] == 2 and #counts > 1 and counts[2] == 2 then return K.TWO_PAIR end
	if counts[1] == 2 then return K.PAIR end
	return K.HIGH_CARD
end

-- ranks 升序五个;近道允许一个空位, 四指接受四连(可叠加)。
function Pattern._is_straight(ranks, rules)
	rules = rules or {}
	local shortcut = num.get(rules, "shortcut", false) and true or false
	local four = num.get(rules, "fourfingers", false) and true or false
	for _, ace_low in ipairs({ false, true }) do
		local distinct = {}
		for _, r in ipairs(ranks) do
			if ace_low and r == 14 then distinct[1] = true else distinct[r] = true end
		end
		local ds = {}
		for r in pairs(distinct) do ds[#ds + 1] = r end
		table.sort(ds)
		if Pattern._run_exists(ds, 5, 0) then return true end
		if shortcut and Pattern._run_exists(ds, 5, 1) then return true end
		if four and Pattern._run_exists(ds, 4, 0) then return true end
		if four and shortcut and Pattern._run_exists(ds, 4, 1) then return true end
	end
	return false
end

function Pattern._run_exists(ds, need, gaps)
	if #ds < need then return false end
	for _, lo in ipairs(ds) do
		local cnt = 0
		for _, v in ipairs(ds) do
			if v >= lo and v <= lo + need - 1 + gaps then cnt = cnt + 1 end
		end
		if cnt >= need then return true end
	end
	return false
end

-- range(n) 的 k 元组合(0 基下标, 与 Godot 同;调用方 +1)。
function Pattern._combos_indices(n, k)
	local res = {}
	Pattern._combo_helper(0, n, k, {}, res)
	return res
end

function Pattern._combo_helper(start, n, k, combo, res)
	if #combo == k then
		res[#res + 1] = num.shallow(combo)
		return
	end
	for i = start, n - 1 do
		combo[#combo + 1] = i
		Pattern._combo_helper(i + 1, n, k, combo, res)
		combo[#combo] = nil
	end
end

function Pattern._memo_size() return _memo_n end

return Pattern
