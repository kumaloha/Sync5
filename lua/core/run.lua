-- core/run.gd 的镜像:一局站在哪里的状态机(牌堆/缓存/段与拍计数/槽位/脸/待播队列/债)。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("core%.$", ""))
local num = require(R .. "num")
local Rng = require(R .. "rng")
local Card = require(P .. "card")
local Deck = require(P .. "deck")
local Joker = require(P .. "joker")
local Consumable = require(P .. "consumable")
local GameConfig = require(P .. "config")
local SectionMod = require(P .. "modifier")
local BlindBoon = require(P .. "blind_boon")
local Pattern = require(P .. "pattern")
local DB = require(P .. "db")
local Lingo = require(P .. "lingo")
local Tutorial = require(P .. "tutorial")
local Director = require(P .. "director")

local Run = {}
Run.__index = Run

Run.Stage = { DECISION = 0, SETTLED = 1, ENDED = 2 }
Run.REQUEST_GOALS = { "color_mix", "face_or_ace", "initial_cache", "fresh_kind" }
Run.STEP_MAX_BEATS = 1

local function rnd_seed()
	return os.time() * 1000 + num.int((os.clock() * 1000000) % 1000)
end

function Run.new()
	local self = setmetatable({}, Run)
	self.deck = nil
	self.cache = {}
	self.section_idx = 0
	self.phrase_in_section = 0
	self.section_score = 0
	self.phrase_index = 0
	self.joker_slots = { false, false, false, false }
	self.consumables = {}
	self.debt = 0
	self.phrase_boosts = {}
	self.prev_kind = -99
	self.prev_target_hit = false
	self.mod_roll = {}
	self.shelf_bonus = 0
	self.first_kind = -99
	self.run_faces = {}
	self.run_boon = ""
	self.section_discards_used = 0
	self.section_kinds = {}
	self.cache_meta = { ages = {}, next = 0 }
	self.previous_raw_score = 0
	self.request_last = ""
	self._blind_rng = Rng.new():seed(rnd_seed())
	self._roll_rng = Rng.new():seed(rnd_seed() + 7)
	self._roll_seed = 0
	self.coins = 0
	self.stage = Run.Stage.DECISION
	self.tutorial = false
	self.face_ranking = {}
	self.director_ctx = {}
	self.target_table = {}
	self.tutorial_step = 0
	self._tutorial_acted = {}
	self._tutorial_step_beats = 0
	self.last_section_phrases = 0
	return self
end

-- 段末还预支(只此一份):付得起 ⇒ 扣款清账;付不起 ⇒ ok=false 账不动
function Run:repay_debt(coins_now)
	if self.debt <= 0 then return { ok = true, coins = coins_now, paid = 0, owed = 0 } end
	if coins_now < self.debt then return { ok = false, coins = coins_now, paid = 0, owed = self.debt } end
	local paid = self.debt
	self.debt = 0
	return { ok = true, coins = coins_now - paid, paid = paid, owed = 0 }
end

function Run:reset(face_seed)
	if face_seed == nil then face_seed = -1 end
	self.deck = Deck.new()
	num.clear(self.cache)
	self.section_idx = 0
	self:reset_section_state()
	self.phrase_index = 0
	self.joker_slots = { false, false, false, false }
	self.prev_kind = -99
	self.prev_target_hit = false
	self.cache_meta = { ages = {}, next = 0 }
	self.previous_raw_score = 0
	self.coins = GameConfig.STARTING_COINS
	self.stage = Run.Stage.DECISION
	self.tutorial_step = 0
	self._tutorial_acted = {}
	self._tutorial_step_beats = 0
	self.debt = 0
	self.consumables = {}
	self.phrase_boosts = {}
	self.mod_roll = {}
	self.shelf_bonus = 0
	self.last_section_phrases = 0
	self:roll_faces(face_seed)
end

-- 一局四张脸开局掷定;run_index = 第几局(1 起), -1 = 全解锁
function Run:roll_faces(face_seed, run_index)
	if face_seed == nil then face_seed = -1 end
	if run_index == nil then run_index = -1 end
	if face_seed >= 0 then
		self._blind_rng:seed(face_seed)
		self._roll_seed = face_seed
	else
		self._blind_rng:seed(rnd_seed())
		self._roll_rng:seed(rnd_seed() + 13)
		self._roll_seed = num.int(self._roll_rng:randi())
	end
	if self.tutorial then
		self.run_faces = {}
		self.run_boon = ""
		return
	end
	self.run_faces = Director.roll_run(run_index, self._blind_rng, self.face_ranking, self.director_ctx)
	self.run_boon = BlindBoon.roll(self._blind_rng, num.get(self.director_ctx, "boons_seen", {}))
end

function Run:face()
	if self.tutorial then return "" end
	return tostring(num.get(self.run_faces, self.section_idx, ""))
end

function Run:boon()
	if self.section_idx < GameConfig.SECTIONS_PER_RUN - 1 then return "" end
	return self.run_boon
end

function Run:next_request_goal(p)
	local pool = num.shallow(Run.REQUEST_GOALS)
	if self.phrase_in_section == 0 then num.erase(pool, "fresh_kind") end
	if p ~= nil then
		local valid = {}
		for _, goal in ipairs(pool) do
			if p:request_goal_valid(tostring(goal)) then valid[#valid + 1] = goal end
		end
		pool = valid
	end
	if #pool > 1 then num.erase(pool, self.request_last) end
	if #pool == 0 then return "" end
	local picked = tostring(pool[self._blind_rng:randi_range(0, #pool - 1) + 1])
	self.request_last = picked
	return picked
end

function Run.request_label(goal)
	if goal == "color_mix" then return Lingo.t("红黑同台") end
	if goal == "face_or_ace" then return Lingo.t("含 J/Q/K/A") end
	if goal == "initial_cache" then return Lingo.t("用初始缓存") end
	if goal == "fresh_kind" then return Lingo.t("更换牌型") end
	return ""
end

-- 断点续玩快照(事实)
function Run:snapshot(run_index)
	local slots_out = {}
	for i = 1, #self.joker_slots do
		local j = self.joker_slots[i]
		if j then slots_out[i] = { id = j.id, st = num.deep(j.state) } else slots_out[i] = false end
	end
	local consumables_out = {}
	for _, c in ipairs(self.consumables) do
		consumables_out[#consumables_out + 1] = { id = tostring(c.id), q = num.int(c.queued_beats) }
	end
	local ages_out = {}
	local ages = self.cache_meta.ages or {}
	for i = 1, #self.cache do
		if ages[self.cache[i]] ~= nil then ages_out[num.itos(i - 1)] = num.int(ages[self.cache[i]]) end
	end
	local kinds_out = {}
	for k, v in pairs(self.section_kinds) do kinds_out[num.itos(num.int(k))] = v end
	local faces_out = {}
	for k, v in pairs(self.run_faces) do faces_out[num.itos(num.int(k))] = tostring(v) end
	return {
		v = 1, run_index = run_index,
		section_idx = self.section_idx, phrase_index = self.phrase_index,
		phrase_in_section = self.phrase_in_section, section_score = self.section_score,
		section_discards_used = self.section_discards_used,
		prev_kind = self.prev_kind, prev_target_hit = self.prev_target_hit,
		mod_roll = num.shallow(self.mod_roll), shelf_bonus = self.shelf_bonus, roll_seed = self._roll_seed,
		first_kind = self.first_kind,
		previous_raw_score = self.previous_raw_score, request_last = self.request_last,
		boon = self.run_boon, coins = self.coins, faces = faces_out,
		kinds = kinds_out, cache = Deck.cards_out(self.cache),
		cache_ages = ages_out, cache_next = num.int(self.cache_meta.next or 0),
		slots = slots_out, deck = self.deck:snapshot(),
		consumables = consumables_out, debt = self.debt,
	}
end

function Run:restore(d)
	if num.int(num.get(d, "v", 0)) ~= 1 or d.deck == nil or d.faces == nil then return false end
	self.deck = Deck.from_snapshot(d.deck)
	num.clear(self.cache)
	for _, p in ipairs(d.cache or {}) do
		self.cache[#self.cache + 1] = Card.new(num.int(p[1]), num.int(p[2]))
	end
	self.cache_meta = { ages = {}, next = num.int(num.get(d, "cache_next", 0)) }
	for k, v in pairs(d.cache_ages or {}) do
		local i = num.int(tonumber(k))
		if i >= 0 and i < #self.cache then self.cache_meta.ages[self.cache[i + 1]] = num.int(v) end
	end
	self.joker_slots = { false, false, false, false }
	local slots_in = d.slots or {}
	for i = 1, num.mini(#slots_in, #self.joker_slots) do
		local e = slots_in[i]
		if e and type(e) == "table" then
			local j = Joker.by_id(tostring(e.id or ""))
			if j ~= nil then
				j.state = num.deep(e.st or {})
				self.joker_slots[i] = j
			end
		end
	end
	self.consumables = {}
	self.debt = num.int(num.get(d, "debt", 0))
	for _, item in ipairs(d.consumables or {}) do
		if item then
			local cid = type(item) == "table" and tostring(item.id or "") or tostring(item)
			for _, e in ipairs(DB.consumables()) do
				if tostring(e.id) == cid then
					local c = Consumable.new(e)
					if type(item) == "table" then c.queued_beats = num.int(num.get(item, "q", 0)) end
					self.consumables[#self.consumables + 1] = c
					break
				end
			end
		end
	end
	self.phrase_boosts = {}
	self.run_faces = {}
	for k, v in pairs(d.faces or {}) do self.run_faces[num.int(tonumber(k))] = tostring(v) end
	self.section_kinds = {}
	for k, v in pairs(d.kinds or {}) do self.section_kinds[num.int(tonumber(k))] = v end
	self.section_idx = num.int(num.get(d, "section_idx", 0))
	self.phrase_index = num.int(num.get(d, "phrase_index", 0))
	self.phrase_in_section = num.int(num.get(d, "phrase_in_section", 0))
	self.section_score = num.int(num.get(d, "section_score", 0))
	self.section_discards_used = num.int(num.get(d, "section_discards_used", 0))
	self.prev_kind = num.int(num.get(d, "prev_kind", -99))
	self.prev_target_hit = num.get(d, "prev_target_hit", false) and true or false
	self.mod_roll = type(d.mod_roll) == "table" and d.mod_roll or {}
	self.shelf_bonus = num.int(num.get(d, "shelf_bonus", 0))
	self._roll_seed = num.int(num.get(d, "roll_seed", 0))
	self.first_kind = num.int(num.get(d, "first_kind", -99))
	self.previous_raw_score = num.int(num.get(d, "previous_raw_score", 0))
	self.request_last = tostring(num.get(d, "request_last", ""))
	self.run_boon = tostring(num.get(d, "boon", ""))
	self.coins = num.int(num.get(d, "coins", 0))
	self.tutorial = false
	self.tutorial_step = 0
	self.stage = Run.Stage.DECISION
	return true
end

-- 段目标(乘过脸的加码与曲目税);教学关恒 0
function Run:target()
	if self.tutorial then return 0 end
	local tbl = (#self.target_table > 0) and self.target_table or GameConfig.SECTION_TARGETS
	return num.round(Run.section_target_for(tbl, self.section_idx, self:face())
		* Run.variety_mult(self:face(), num.size(self.section_kinds)))
end

-- 掷类脸的段级明掷(专用流, 段首重播种;同段幂等)
function Run:ensure_mod_roll()
	if num.int(num.get(self.mod_roll, "sec", -1)) == self.section_idx then return end
	self.mod_roll = { sec = self.section_idx }
	self._roll_rng:seed(self._roll_seed + self.section_idx * 7919)
	local m = self:face()
	if m == "" then return end
	local ch = SectionMod.roll_chance(m)
	if ch > 0.0 then
		self.mod_roll.worse = self._roll_rng:randi_range(0, 99) < num.round(ch * 100.0)
	end
	if SectionMod.rolls_suit(m) then
		self.mod_roll.suit = self._roll_rng:randi_range(0, 3)
	end
	if SectionMod.rolls_kind(m) then
		local kind_pool = { Pattern.Kind.TWO_PAIR, Pattern.Kind.THREE_KIND, Pattern.Kind.STRAIGHT, Pattern.Kind.FLUSH }
		self.mod_roll.kind = num.int(kind_pool[self._roll_rng:randi_range(0, #kind_pool - 1) + 1])
		self.mod_roll.solved = false
	end
end

function Run.phrase_duration_for(section, mod, phrase_idx)
	if phrase_idx == nil then phrase_idx = -1 end
	return GameConfig.phrase_duration(section) - SectionMod.time_penalty_at(mod, phrase_idx)
end

function Run:phrase_duration()
	if self.tutorial then return Tutorial.seconds(self.tutorial_step) end
	return Run.phrase_duration_for(self.section_idx, self:face(), self.phrase_in_section)
end

-- ---- 教学关进度 ----
function Run:tutorial_note(action)
	if self.tutorial then self._tutorial_acted[action] = true end
end

function Run:tutorial_try_advance()
	if not self.tutorial then return false end
	local need = Tutorial.require(self.tutorial_step)
	local ok = need == "" or (self._tutorial_acted[need] and true or false)
	self._tutorial_step_beats = self._tutorial_step_beats + 1
	if ok or self._tutorial_step_beats >= Run.STEP_MAX_BEATS then
		if need ~= "" then self._tutorial_acted[need] = nil end
		self.tutorial_step = self.tutorial_step + 1
		self._tutorial_step_beats = 0
	end
	return ok
end

function Run:tutorial_shop_seen()
	if self.tutorial and self.tutorial_step == Tutorial.shop_step() then
		self.tutorial_step = self.tutorial_step + 1
		self._tutorial_step_beats = 0
	end
end

function Run:tutorial_pending()
	if not self.tutorial then return "" end
	local need = Tutorial.require(self.tutorial_step)
	if need == "" or self._tutorial_acted[need] then return "" end
	return need
end

function Run:tutorial_unlocked(component)
	return (not self.tutorial) or Tutorial.is_unlocked(component, self.tutorial_step)
end

function Run:tutorial_hint()
	if self.tutorial then return Tutorial.hint(self.tutorial_step) end
	return { command = "", signal = "" }
end

function Run:tutorial_done()
	return self.tutorial and self.tutorial_step >= Tutorial.steps()
end

-- 判生死的唯一实现:表里的基准 × 脸的加码
function Run.section_target_for(table_, section, mod)
	if #table_ == 0 then return 0 end
	local base = num.int(table_[num.mini(section, #table_ - 1) + 1])
	return num.round(base * SectionMod.target_mult(mod))
end

-- 曲目税:缺一种, 目标升一档
function Run.variety_mult(mod, kinds_made)
	local quota = SectionMod.required_kinds(mod)
	if quota <= 0 then return 1.0 end
	local missing = num.maxi(0, quota - kinds_made)
	return 1.0 + SectionMod.variety_penalty(mod) * missing
end

function Run:advance()
	self.phrase_in_section = self.phrase_in_section + 1
	local done = self.phrase_in_section >= GameConfig.PHRASES_PER_SECTION
	return {
		section_done = done,
		shop_break = (not done) and (self.phrase_in_section % GameConfig.PHRASES_PER_SHOP == 0),
		cleared = done and self.section_score >= self:target(),
		is_wall = GameConfig.is_wall(self.section_idx),
		finale = self.section_idx >= GameConfig.SECTIONS_PER_RUN - 1,
	}
end

function Run:_take(c)
	num.erase(self.consumables, c)
	if next(c.boost) ~= nil then self.phrase_boosts[#self.phrase_boosts + 1] = c.boost end
	return { id = c.id, action = c.action, boost = c.boost }
end

-- 买下的那一刻:buy 类返回 action 交给调用方执行, 其余排队(返回 {} = 排队去了)
function Run:take_consumable(c)
	if c:is_instant() then
		if next(c.boost) ~= nil then self.phrase_boosts[#self.phrase_boosts + 1] = c.boost end
		return { id = c.id, action = c.action, boost = c.boost }
	end
	c.queued_beats = 0
	self.consumables[#self.consumables + 1] = c
	return {}
end

function Run:age_consumables()
	for _, c in ipairs(self.consumables) do c.queued_beats = c.queued_beats + 1 end
end

-- 这一拍轮到谁(beat 从 1 起);返回 {id, action, boost} 数组
function Run:due_consumables(beat)
	local out = {}
	for _, c in ipairs(num.shallow(self.consumables)) do
		if c:due_on(beat, c.queued_beats) then out[#out + 1] = self:_take(c) end
	end
	return out
end

function Run:phrases_left()
	return num.maxi(0, GameConfig.PHRASES_PER_SECTION - self.phrase_in_section)
end

function Run:deficit()
	return num.maxi(0, self:target() - self.section_score)
end

function Run:next_section()
	self.last_section_phrases = self.phrase_in_section
	for i = 1, #self.joker_slots do
		local j = self.joker_slots[i]
		if j and j:tick_section_life() then self.joker_slots[i] = false end
	end
	self.section_idx = num.mini(self.section_idx + 1, GameConfig.SECTIONS_PER_RUN - 1)
	self:reset_section_state()
end

function Run:reset_section_state()
	self.phrase_in_section = 0
	self.section_score = 0
	self.first_kind = -99
	self.section_discards_used = 0
	self.section_kinds = {}
	self.request_last = ""
end

return Run
