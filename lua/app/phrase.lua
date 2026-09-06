-- 编排层(view/phrase.gd 的**规则部分**的镜像):开局三步、拍钟、每 3 拍开店、结算、段末、终局、教学门、打点、待播队列。
-- 渲染与手势在她那层:每帧 app:tick(now_ms), 读 app:view() 画, 把手势翻成下面的意图, 取空 app:events()。
-- 契约全文在 app/CONTRACT.md。索引一律 0 基。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("app%.$", ""))
local num = require(R .. "num")
local Rng = require(R .. "rng")
local DB = require(R .. "core.db")
local Lingo = require(R .. "core.lingo")
local GameConfig = require(R .. "core.config")
local Run = require(R .. "core.run")
local Beat = require(R .. "core.beat")
local Economy = require(R .. "core.economy")
local SectionMod = require(R .. "core.modifier")
local BlindBoon = require(R .. "core.blind_boon")
local Tutorial = require(R .. "core.tutorial")
local Tape = require(R .. "core.tape")
local SaveState = require(R .. "core.save")
local Joker = require(R .. "core.joker")
local Pattern = require(R .. "core.pattern")
local Director = require(R .. "core.director")
local Shop = require(P .. "shop")

local App = {}
App.__index = App

App.St = { FRONT = "front", INTRO = "intro", DECISION = "decision", RESOLVE = "resolve", DRAFT = "draft", END = "end", CUTIN = "cutin" }
local St = App.St
App.CLOSEUP_SECONDS = 2.0       -- 盲注特写定长(view/phrase.gd::_play_blind_closeup)

-- opts:{ storage = {read, write}, locale = function() -> "cn"|"en", now_ms = function() -> ms, seed = 可选(货架随机流), tape_sink = 可选, fresh = 可选 }
function App.new(opts)
	opts = opts or {}
	local self = setmetatable({}, App)
	SaveState.storage = opts.storage
	SaveState.fresh = opts.fresh and true or false
	SaveState.probe = false
	if opts.locale then
		Lingo.set_resolver(function()
			local saved = SaveState.lang()
			if saved == "cn" or saved == "en" then return saved end
			return opts.locale()
		end)
	end
	self.now_ms = opts.now_ms or function() return num.int(os.clock() * 1000) end
	Tape.now_ms = self.now_ms
	Tape.sink = opts.tape_sink
	self.rng = Rng.new():seed(opts.seed or (os.time() * 7 + 3))
	self.run = Run.new()
	self.phrase = nil
	self.state = St.FRONT
	self.elapsed = 0.0
	self._last_ms = nil
	self.cur_duration = 8.0
	self.cur_warning = 5.0
	self.cur_lock = 7.75
	self.cur_modifier = ""
	self.acted_late = false
	self.acted_final = false
	self.last_action_time = -1.0
	self.last_discard_time = -1.0
	self.paused = false
	self.shop = nil
	self.replace_pick = nil          -- 替换态:货架下标(0 基)
	self.rule_next = false
	self.sel_hand = {}               -- 点选(0 基下标集合)
	self.sel_cache = {}
	self.intro_left = 0.0
	self.intro_kind = ""             -- "closeup" | "gamma"
	self.cutin_key = ""
	self.cutin_left = 0.0
	self.cutins_played = {}
	self.last_gain_coins = 0
	self.end_screen = nil            -- {win, score, target, wage, why}
	self.resume_prompt = false
	self.run_index = 1
	self.events_q = {}
	self.shown_score = 0
	self.sess = SaveState.session_start()
	self.run:reset()
	self.resume_prompt = next(SaveState.checkpoint()) ~= nil
	Tape.on("nav", { to = "home" })
	return self
end

-- ---------------------------------------------------------------- 事件队列(一次性)
function App:_emit(kind, payload)
	payload = payload or {}
	payload.kind = kind
	self.events_q[#self.events_q + 1] = payload
end

function App:events()
	local q = self.events_q
	self.events_q = {}
	return q
end

-- ---------------------------------------------------------------- 开局
function App:start_run()
	if self.state ~= St.FRONT then return false end
	self:_reset_run()
	self.run.tutorial = not SaveState.seen_tutorial()
	if not self:_begin_run() then
		self:_emit("deny", { why = "energy", text = Lingo.t("体力不足,明天回满") })
		Tape.on("deny", { why = "energy" })
		return false
	end
	Tape.begin({
		sess = self.sess, tutorial = self.run.tutorial, faces = num.shallow(self.run.run_faces),
		targets = GameConfig.SECTION_TARGETS, coins = GameConfig.STARTING_COINS,
		struct = { sec = GameConfig.SECTIONS_PER_RUN, pps = GameConfig.PHRASES_PER_SECTION,
			ppshop = GameConfig.PHRASES_PER_SHOP, dur = GameConfig.phrase_duration(0) },
	})
	self:_enter_section()
	return true
end

-- 开局三步:定局数 → 喂 Director → 按真实局数掷脸 → 记局数(开局与重开同一份;体力闸在第 0 步)
function App:_begin_run()
	if not SaveState.spend_energy_for_run(self.run.tutorial) then return false end
	self.run_index = SaveState.runs_total() + 1
	self:_feed_director()
	self.run:roll_faces(-1, self.run_index)
	SaveState.note_run_started()
	return true
end

function App:_feed_director()
	self.run.face_ranking = DB.ranking_tiers()
	self.run.director_ctx = { streak = SaveState.streak(), seen = SaveState.faces_seen(),
		boons_seen = SaveState.boons_seen(), returning = SaveState.returning_run() }
end

function App:_reset_run()
	self.phrase = nil
	self.run:reset()
	self.rule_next = false
	self.shown_score = 0
	self.cutins_played = {}
	self.sel_hand = {}
	self.sel_cache = {}
	self.replace_pick = nil
	self.shop = nil
	self.end_screen = nil
end

function App:_enter_section()
	self:_tape_section()
	self:_start_phrase()
end

function App:_tape_section()
	local run = self.run
	Tape.on("sec", { i = run.section_idx, target = run:target(),
		face = tostring(num.get(run.run_faces, run.section_idx, "")), boon = run:boon(),
		wall = GameConfig.is_wall(run.section_idx),
		coins = self.phrase and self.phrase.coins or run.coins })
end

-- ---------------------------------------------------------------- 一拍
function App:_start_phrase()
	local run = self.run
	if self.phrase ~= nil then run.coins = self.phrase.coins end
	if run.phrase_in_section == 0 then
		self.cur_modifier = run:face()
	end
	if not run.tutorial then
		SaveState.save_checkpoint(run:snapshot(self.run_index))
	end
	self.phrase = Beat.begin(run)
	self:_fire_due_consumables()
	self.state = St.DECISION
	self.elapsed = 0.0
	self.acted_late = false
	self.acted_final = false
	self.last_action_time = -1.0
	self.last_discard_time = -1.0
	self.cur_duration = run:phrase_duration()
	self.cur_warning = GameConfig.warning_time(self.cur_duration)
	self.cur_lock = GameConfig.lock_time(self.cur_duration)
	self.sel_hand = {}
	self.sel_cache = {}
	Tape.on("beat", { i = run.phrase_index, p = run.phrase_in_section, dur = self.cur_duration,
		coins = self.phrase.coins, hand = Tape.cards(self.phrase.hand), cache = Tape.cards(run.cache),
		boon = run:boon(), request = self.phrase.request_goal,
		spotlight = self.phrase.spotlight_card and self.phrase.spotlight_card:label() or "" })
	self:_emit("deal")
	-- 段首拍的盲注特写(教学关不进);γ 特写 = 教学毕后的第一次段首
	if run.phrase_in_section == 0 and not run.tutorial then
		if SaveState.tutor_gamma_due() then
			self.state = St.INTRO
			self.intro_kind = "gamma"
			local c = Tutorial.cutin("gamma")
			self.intro_left = num.get(c, "seconds", 4.0)
			SaveState.mark_tutor_gamma_done()
			Tape.on("intro", { gamma = true })
		else
			self.state = St.INTRO
			self.intro_kind = "closeup"
			self.intro_left = App.CLOSEUP_SECONDS
			Tape.on("intro", { closeup = true })
		end
	end
end

function App:_fire_due_consumables()
	local run = self.run
	run:age_consumables()
	local fired = run:due_consumables(run.phrase_in_section + 1)
	local names = {}
	for _, used in ipairs(fired) do
		self:_ensure_shop():apply_consumable(used, "due")
		for _, e in ipairs(DB.consumables()) do
			if tostring(e.id) == tostring(used.id) then
				names[#names + 1] = Lingo.pick({ cn = e.cn or "", name = e.name or "" })
				break
			end
		end
	end
	if #names > 0 then self:_emit("disc_fired", { names = names }) end
end

-- 商店对象跨拍存在(到点的消耗牌要走它的执行口);进店时 open()
function App:_ensure_shop()
	if self.shop == nil then
		self.shop = Shop.new({ run = self.run, rng = self.rng, rarity_mult = {}, explore_used = {},
			tape = function(k, p) Tape.on(k, p) end })
	end
	return self.shop
end

function App:skip_intro()
	if self.state ~= St.INTRO then return false end
	Tape.on("intro", { skip = true })
	self.state = St.DECISION
	return true
end

-- 每帧调:now_ms 单调毫秒。返回本帧发生的状态名。
function App:tick(now_ms)
	if self._last_ms == nil then self._last_ms = now_ms end
	local dt = (now_ms - self._last_ms) / 1000.0
	self._last_ms = now_ms
	if dt < 0 then dt = 0 end
	if self.paused then return self.state end
	local st = self.state
	if st == St.INTRO then
		self.intro_left = self.intro_left - dt
		if self.intro_left <= 0 then
			Tape.on("intro", { skip = false })
			self.state = St.DECISION
		end
	elseif st == St.DECISION then
		self.elapsed = self.elapsed + dt
		if self.elapsed >= self.cur_lock then self:_settle() end
	elseif st == St.RESOLVE then
		self.elapsed = self.elapsed + dt
		if self.elapsed >= self:_resolve_hold() then
			local ck = self:_cutin_due_key()
			if ck == "" then self:_advance() else self:_begin_cutin(ck) end
		end
	elseif st == St.CUTIN then
		self.cutin_left = self.cutin_left - dt
		if self.cutin_left <= 0 then self:_end_cutin() end
	end
	return self.state
end

function App:_resolve_hold()
	return num.get(DB.ui().stage, "resolve_hold", 1.0) + 0.0
end

function App:_seconds_left()
	return num.maxf(0.0, self.cur_lock - self.elapsed)
end

function App:_discard_open()
	return SectionMod.discard_open(self.cur_modifier, self:_seconds_left()) and self.run:tutorial_unlocked("discard")
end

function App:_swap_open()
	return SectionMod.swap_open(self.cur_modifier, self:_seconds_left())
		and (self.phrase == nil or self.phrase:can_swap_action()) and self.run:tutorial_unlocked("cache")
end

function App:_acted_early()
	if self.last_action_time < 0.0 then return false end
	return (self.cur_lock - self.last_action_time) >= GameConfig.EARLY_FINISH_LEFT
end

function App:_action_feedback()
	if self.state == St.DECISION then
		self.last_action_time = self.elapsed
		if self.elapsed >= self.cur_duration - GameConfig.LATE_ACT_WINDOW then self.acted_late = true end
		if self.elapsed >= self.cur_duration - GameConfig.FINAL_ACT_WINDOW then self.acted_final = true end
	end
	self:_emit("action")
end

function App:_note_discard_time()
	if self.state == St.DECISION then self.last_discard_time = self.elapsed end
end

function App:_notify_discard(n)
	self:_note_discard_time()
	for _, j in Joker.each(self.run.joker_slots) do j:on_discard(n) end
end

function App:_note_tutorial(action)
	self.run:tutorial_note(action)
end

function App:_settle()
	local run = self.run
	local outcome = Beat.settle(run, self.phrase, {
		late = self.acted_late, early = self:_acted_early(), final = self.acted_final,
		secs_left = (self.last_action_time >= 0.0) and num.maxf(0.0, self.cur_lock - self.last_action_time) or 0.0,
		early_discards = self.last_discard_time >= 0.0 and self.last_discard_time <= GameConfig.EARLY_DISCARD_WINDOW,
	})
	local res = outcome.res
	local gained_score = num.int(outcome.score)
	local gained_coins = num.int(outcome.coins)
	self.last_gain_coins = gained_coins
	Tape.on("settle", {
		kind = num.int(num.get(res, "kind", -1)), chips = num.int(num.get(res, "chips", 0)),
		base = num.int(outcome.base), mult = outcome.mult + 0.0, bonus = num.int(num.get(outcome, "bonus", 0)),
		score = gained_score, coin = gained_coins, total = run.section_score,
		disc = self.phrase.discards_used, late = self.acted_late, act = self.last_action_time,
		mod = self.cur_modifier, raw = num.int(num.get(outcome, "raw_score", gained_score)),
		boon = run:boon(), boon_bonus = num.int(num.get(outcome, "boon_bonus", 0)),
		request = self.phrase.request_goal, request_ok = self.phrase.request_met,
		cards = Tape.cards(num.get(res, "resolved", {})), fired = Tape.fired(outcome.popups, run.joker_slots),
	})
	self.state = St.RESOLVE
	self.elapsed = 0.0
	self.sel_hand = {}
	self.sel_cache = {}
	self:_emit("settle", {
		base = num.int(outcome.base), mult = outcome.mult + 0.0, score = gained_score,
		bonus = num.int(num.get(outcome, "bonus", 0)), pattern_mult = num.get(outcome, "pattern_mult", 0.0) + 0.0,
		joker_mult = num.get(outcome, "joker_mult", 1.0) + 0.0, bonus_pct = num.get(outcome, "bonus_pct", 0.0) + 0.0,
		kind = num.int(num.get(res, "kind", -1)), coins = gained_coins, popups = outcome.popups,
		total = run.section_score, resolved = Tape.cards(num.get(res, "resolved", {})),
	})
	self.shown_score = run.section_score
end

function App:_cutin_due_key()
	if not self.run.tutorial then return "" end
	for _, key in ipairs({ "alpha", "beta" }) do
		if not self.cutins_played[key] then
			local c = Tutorial.cutin(key)
			if next(c) ~= nil and num.int(c.after_step) == self.run.tutorial_step then return key end
		end
	end
	return ""
end

function App:_begin_cutin(key)
	self.cutins_played[key] = true
	self.cutin_key = key
	self.state = St.CUTIN
	local c = Tutorial.cutin(key)
	self.cutin_left = num.maxf(0.5, num.get(c, "seconds", 2.5) + 0.0)
	self:_emit("cutin", { key = key, command = c.command, focus = c.focus, coins = self.last_gain_coins })
end

function App:_end_cutin()
	if self.state ~= St.CUTIN then return end
	Tape.on("cutin", { k = self.cutin_key })
	self.cutin_key = ""
	self.state = St.RESOLVE
	self:_advance()
end

function App:_advance()
	local run = self.run
	Beat.phrase_end(run, self.phrase, { early = self:_acted_early() })
	run:tutorial_note("play")
	run:tutorial_try_advance()
	local out = run:advance()
	if run.tutorial and not out.section_done then
		if run.tutorial_step == Tutorial.shop_step() and not run.joker_slots[1] then
			self:_open_draft()
			return
		end
		if out.shop_break then
			self:_start_phrase()
			return
		end
	end
	if run.tutorial and run:tutorial_done() and out.section_done then
		SaveState.mark_tutorial_seen()
		run.tutorial = false
		self:_feed_director()
		run:roll_faces(-1, SaveState.runs_total())
		Tape.on("tutorial_done", { beat = run.phrase_index })
	end
	if out.section_done then
		self.state = St.END
		Tape.on("sec_end", { i = run.section_idx, score = run.section_score, target = run:target(),
			ok = out.cleared, coins = self.phrase.coins, beats = run.phrase_in_section })
		if not out.cleared then
			Tape.close({ ok = false, sec = run.section_idx, score = run.section_score, target = run:target(), beats = run.phrase_index })
			SaveState.clear_checkpoint()
			SaveState.settle_run_meta(false, run.section_idx, self:_faces_encountered(), tostring(run:boon()), self:_final_target_id())
			self.end_screen = { win = false, score = run.section_score, target = run:target(), why = "" }
			self:_emit("run_end", { win = false })
			return
		end
		self.phrase.coins = Economy.grant(self.phrase.coins, GameConfig.SECTION_CLEAR_REWARD, run.joker_slots)
		if run.debt > 0 then
			local owed = run.debt
			local rp = run:repay_debt(self.phrase.coins)
			if not rp.ok then
				Tape.close({ ok = false, sec = run.section_idx, score = run.section_score, target = run:target(), beats = run.phrase_index, why = "loan" })
				SaveState.clear_checkpoint()
				SaveState.settle_run_meta(false, run.section_idx, self:_faces_encountered(), tostring(run:boon()), self:_final_target_id())
				local fmt_ = tostring(num.get(DB.ui().banner or {}, "fail_loan", "%d◆"))
				self.end_screen = { win = false, score = run.section_score, target = run:target(),
					why = (fmt_:gsub("%%d", num.itos(owed))) }
				self:_emit("loan_default", { owed = owed })
				self:_emit("run_end", { win = false })
				return
			end
			self.phrase.coins = rp.coins
			run.coins = self.phrase.coins
			Tape.on("loan", { pay = rp.paid, coins = self.phrase.coins })
			self:_emit("loan_repay", { paid = rp.paid })
		end
		if out.finale then
			Tape.close({ ok = true, sec = run.section_idx, score = run.section_score, target = run:target(), beats = run.phrase_index })
			SaveState.clear_checkpoint()
			SaveState.settle_run_meta(true, GameConfig.SECTIONS_PER_RUN, self:_faces_encountered(), tostring(run:boon()), self:_final_target_id())
			self.end_screen = { win = true, score = run.section_score, target = run:target(),
				wage = GameConfig.SECTION_CLEAR_REWARD, gig = GameConfig.gig_of(run.section_idx) + 1 }
			self:_emit("run_end", { win = true })
		else
			self:_emit("section_clear", { score = run.section_score, target = run:target(), wage = GameConfig.SECTION_CLEAR_REWARD })
			self:_next_section()
		end
		return
	end
	if out.shop_break then
		self:_open_draft()
		return
	end
	self:_start_phrase()
end

function App:_final_target_id()
	local j = self.run.joker_slots[1]
	if j and tostring(j.kind) == "target" then return tostring(j.id) end
	return ""
end

function App:_faces_encountered()
	local out = {}
	local run = self.run
	for i = 0, num.mini(run.section_idx + 2, GameConfig.SECTIONS_PER_RUN) - 1 do
		local f = tostring(num.get(run.run_faces, i, ""))
		if f ~= "" then out[#out + 1] = f end
	end
	return out
end

function App:_next_section()
	local run = self.run
	local before = num.shallow(run.joker_slots)
	run:next_section()
	for i = 1, #run.joker_slots do
		if before[i] and not run.joker_slots[i] then
			self:_emit("guest_exit", { slot = i - 1, name = before[i].cn_name })
		end
	end
	self:_tape_section()
	self:_open_draft()
end

-- ---------------------------------------------------------------- 商店
function App:_open_draft()
	self.state = St.DRAFT
	self.replace_pick = nil
	local shop = self:_ensure_shop()
	shop.rarity_mult = Director.shelf_rarity_mult(self.run_index)
	shop.explore_used = SaveState.targets_used()
	shop:open(self.rule_next)
	self.rule_next = false
	self:_emit("shop_open")
end

function App:_after_shop(res)
	if self.shop.rule_next then
		self.rule_next = true
		self.shop.rule_next = false
	end
	if res and res.stay == false then
		self:_emit("shop_close")
		self:_start_phrase()
	end
	return res
end

function App:buy(i)
	if self.state ~= St.DRAFT or self.replace_pick ~= nil then return { ok = false, why = "state" } end
	local res = self.shop:buy(i)
	if res.replace then
		self.replace_pick = i
		self:_emit("replace_open", { shelf = i })
		return res
	end
	if not res.ok then self:_emit("deny", { why = res.why, text = self:_deny_shop_text(res.why) }) end
	return self:_after_shop(res)
end

function App:replace(k)
	if self.state ~= St.DRAFT or self.replace_pick == nil then return { ok = false, why = "state" } end
	local i = self.replace_pick
	if k == 0 then
		self.replace_pick = nil
		self.shop:replace(i, 0)
		self:_emit("replace_cancel")
		return { ok = false, why = "cancel", stay = true }
	end
	local res = self.shop:replace(i, k)
	if res.ok then
		self.replace_pick = nil
	else
		self:_emit("deny", { why = res.why, text = Lingo.t("◆ 不足") })
		return res
	end
	return self:_after_shop(res)
end

function App:cancel_replace()
	return self:replace(0)
end

function App:reroll()
	if self.state ~= St.DRAFT or self.replace_pick ~= nil then return { ok = false, why = "state" } end
	local res = self.shop:reroll()
	if not res.ok then self:_emit("deny", { why = res.why, text = self:_deny_shop_text(res.why) }) end
	return self:_after_shop(res)
end

function App:buy_consumable(i)
	if self.state ~= St.DRAFT or self.replace_pick ~= nil then return { ok = false, why = "state" } end
	local res = self.shop:buy_consumable(i)
	if not res.ok then self:_emit("deny", { why = res.why, text = self:_deny_shop_text(res.why) }) end
	if res.ok then self:_emit("disc_bought", { shelf = i }) end
	return self:_after_shop(res)
end

-- 「继续 ▸」
function App:leave()
	if self.state ~= St.DRAFT or self.replace_pick ~= nil then return { ok = false, why = "state" } end
	return self:_after_shop(self.shop:leave())
end

function App:_deny_shop_text(why)
	local cfg = DB.ui().shop or {}
	return tostring(num.get(cfg, "insufficient", "◆ 不足"))
end

-- ---------------------------------------------------------------- 手牌意图(点击 = 纯选择;拖拽 = 对调)
local function toggle(set, i)
	if set[i] then set[i] = nil else set[i] = true end
end

function App:tap_hand(i)
	if self.state ~= St.DECISION then return false end
	if i < 0 or i >= #self.phrase.hand then return false end
	toggle(self.sel_hand, i)
	Tape.on("pick", { z = "hand", i = i, on = self.sel_hand[i] and true or false, at = self.elapsed })
	return true
end

function App:tap_cache(i)
	if self.state ~= St.DECISION then return false end
	if i < 0 or i >= #self.run.cache then return false end
	toggle(self.sel_cache, i)
	Tape.on("pick", { z = "cache", i = i, on = self.sel_cache[i] and true or false, at = self.elapsed })
	return true
end

function App:clear_selection()
	self.sel_hand = {}
	self.sel_cache = {}
end

local function keys_sorted(set)
	local out = {}
	for k in pairs(set) do out[#out + 1] = k end
	table.sort(out)
	return out
end

function App:sort()
	if self.state ~= St.DECISION then return false end
	self.phrase:sort_hand()
	self.sel_hand = {}
	Tape.on("sort", { at = self.elapsed })
	self:_action_feedback()
	return true
end

function App:drag_swap(hand_i, cache_i)
	if self.state ~= St.DECISION then
		if self.state == St.RESOLVE then self:_emit("deny", { why = "locked", text = self:_hand_deny("locked", "本拍已锁定") }) end
		return false
	end
	if not self:_swap_open() then
		Tape.on("deny", { why = "blind_swap", h = hand_i, c = cache_i, at = self.elapsed })
		self:_emit("deny", { why = "blind_swap", text = self:_deny_swap_why() })
		return false
	end
	if self.phrase:swap_with_cache(hand_i, cache_i) then
		Tape.on("swap", { h = hand_i, c = cache_i, at = self.elapsed })
		self:_note_tutorial("swap")
		self:_action_feedback()
		self.sel_hand = {}
		self.sel_cache = {}
		return true
	end
	Tape.on("deny", { why = "blind_swap", h = hand_i, c = cache_i, at = self.elapsed })
	self:_emit("deny", { why = "blind_swap", text = self:_deny_swap_why() })
	return false
end

-- 弃掉当前选中的(跨区多选)
function App:discard()
	if self.state ~= St.DECISION then
		if self.state == St.RESOLVE then self:_emit("deny", { why = "locked", text = self:_hand_deny("locked", "本拍已锁定") }) end
		return false
	end
	local sel_h, sel_c = keys_sorted(self.sel_hand), keys_sorted(self.sel_cache)
	return self:_discard_indices(sel_h, sel_c, #sel_h > 0 and #sel_c > 0)
end

-- 拖到弃牌键 = 单张直弃
function App:discard_one(zone, idx)
	if self.state ~= St.DECISION then return false end
	if zone ~= "hand" and zone ~= "cache" then return false end
	local sel_h = zone == "hand" and { idx } or {}
	local sel_c = zone == "cache" and { idx } or {}
	return self:_discard_indices(sel_h, sel_c, false)
end

function App:_discard_indices(sel_h, sel_c, multiselect)
	local total = #sel_h + #sel_c
	local p = self.phrase
	local selection_ok = total > 0 and p:can_discard_selected(sel_h, sel_c)
	if total == 0 or not self:_discard_open() or not selection_ok then
		local why = "empty"
		if total > 0 then
			if p.coins < Economy.discard_cost(total) then why = "coins" else why = "blind_discard" end
		end
		Tape.on("deny", { why = why, k = total, at = self.elapsed })
		if total > 0 then self:_emit("deny", { why = why, text = self:_deny_discard_why(sel_h, sel_c) }) end
		return false
	end
	local gone = {}
	for _, i in ipairs(sel_h) do gone[#gone + 1] = p.hand[i + 1]:label() end
	for _, i in ipairs(sel_c) do gone[#gone + 1] = self.run.cache[i + 1]:label() end
	if p:discard_selected(num.shallow(sel_h), num.shallow(sel_c)) then
		local got = {}
		for _, i in ipairs(sel_h) do
			if p.hand[i + 1] then got[#got + 1] = p.hand[i + 1]:label() end
		end
		for _, i in ipairs(sel_c) do
			if self.run.cache[i + 1] then got[#got + 1] = self.run.cache[i + 1]:label() end
		end
		Tape.on("disc", { k = total, h = #sel_h, c = #sel_c, cost = Economy.discard_cost(total),
			coins = p.coins, cards = gone, got = got, at = self.elapsed })
		self:_note_tutorial("discard")
		if multiselect then self:_note_tutorial("multiselect") end
		self:_notify_discard(total)
		self.sel_hand = {}
		self.sel_cache = {}
		self:_action_feedback()
		self:_emit("discard", { hand = sel_h, cache = sel_c })
		return true
	end
	return false
end

function App:_hand_deny(key, dflt)
	return tostring(num.get(num.get(DB.ui().hand or {}, "deny", {}), key, dflt))
end

function App:_deny_discard_why(sel_h, sel_c)
	local p = self.phrase
	local m = self.cur_modifier
	if p.coins < Economy.discard_cost(#sel_h + #sel_c) then return self:_hand_deny("coins", "◆ 不足") end
	if not self:_discard_open() then return self:_hand_deny("window", "弃牌已关闭") end
	local lim = SectionMod.discard_action_limit(m)
	if lim >= 0 and p.discard_actions_used >= lim then return self:_hand_deny("onetake", "弃牌张数到顶") end
	local shared = SectionMod.action_limit(m)
	if shared >= 0 and p.action_count >= shared then return self:_hand_deny("throttle", "弃换张数用尽") end
	local sel_n = #sel_h + #sel_c
	local cards_cap = SectionMod.discard_cards_max(m)
	if cards_cap >= 0 and p.discard_cards_used + sel_n > cards_cap then return self:_hand_deny("onetake", "弃牌张数到顶") end
	local combo_cap = SectionMod.action_cards_max(m)
	if combo_cap >= 0 and p.action_cards_used + sel_n > combo_cap then return self:_hand_deny("throttle", "弃换张数用尽") end
	if SectionMod.exclusive_action_tracks(m) and p.action_track == "swap" then return self:_hand_deny("track_swap", "已选交换轨") end
	if p.discard_budget >= 0 and p.discards_used + sel_n > p.discard_budget then return self:_hand_deny("budget", "弃牌额度不足") end
	return self:_hand_deny("sealed", "选中有被封的牌")
end

function App:_deny_swap_why()
	local p = self.phrase
	local m = self.cur_modifier
	local lim = SectionMod.swap_action_limit(m)
	if lim >= 0 and p.swap_actions_used >= lim then return self:_hand_deny("oneswap", "本拍已换过") end
	local shared = SectionMod.action_limit(m)
	if shared >= 0 and p.action_count >= shared then return self:_hand_deny("throttle", "弃换张数用尽") end
	local combo_cap = SectionMod.action_cards_max(m)
	if combo_cap >= 0 and p.action_cards_used + 1 > combo_cap then return self:_hand_deny("throttle", "弃换张数用尽") end
	if SectionMod.exclusive_action_tracks(m) and p.action_track == "discard" then return self:_hand_deny("track_discard", "已选弃牌轨") end
	if not self:_swap_open() then return self:_hand_deny("swap_window", "交换已关闭") end
	return self:_hand_deny("blocked", "这张换不了")
end

-- ---------------------------------------------------------------- 结算屏 / 暂停 / 断点
function App:end_next()
	if self.state ~= St.END or self.end_screen == nil then return false end
	self.end_screen = nil
	if self.run.section_idx >= GameConfig.SECTIONS_PER_RUN - 1 then
		return self:end_home()
	end
	self:_next_section()
	return true
end

function App:restart()
	if self.state ~= St.END then return false end
	Tape.on("nav", { to = "retry" })
	self:_reset_run()
	if not self:_begin_run() then
		self:_emit("deny", { why = "energy", text = Lingo.t("体力不足,明天回满") })
		self.state = St.FRONT
		return false
	end
	Tape.begin({ sess = self.sess, tutorial = self.run.tutorial, faces = num.shallow(self.run.run_faces),
		targets = GameConfig.SECTION_TARGETS, coins = GameConfig.STARTING_COINS, retry = true,
		struct = { sec = GameConfig.SECTIONS_PER_RUN, pps = GameConfig.PHRASES_PER_SECTION,
			ppshop = GameConfig.PHRASES_PER_SHOP, dur = GameConfig.phrase_duration(0) } })
	self:_enter_section()
	return true
end

function App:end_home()
	if self.state ~= St.END then return false end
	Tape.on("nav", { to = "back" })
	Tape.flush()
	self:_reset_run()
	self.state = St.FRONT
	Tape.on("nav", { to = "home" })
	return true
end

function App:pause()
	if self.paused or (self.state ~= St.DECISION and self.state ~= St.RESOLVE) then return false end
	self.paused = true
	Tape.on("pause", { at = self.elapsed, sec = self.run.section_idx })
	return true
end

function App:resume()
	self.paused = false
	return true
end

function App:quit_run()
	self.paused = false
	Tape.on("nav", { to = "quit" })
	Tape.close({ ok = false, sec = self.run.section_idx, score = self.run.section_score,
		target = self.run:target(), beats = self.run.phrase_index, why = "quit" })
	SaveState.clear_checkpoint()
	self:_reset_run()
	self.state = St.FRONT
	return true
end

-- 首页询问卡:继续上次的半局
function App:resume_run()
	self.resume_prompt = false
	return self:_resume_run()
end

function App:drop_checkpoint()
	self.resume_prompt = false
	SaveState.clear_checkpoint()
end

function App:_resume_run()
	local snap = SaveState.checkpoint()
	if next(snap) == nil then return false end
	self:_reset_run()
	if not self.run:restore(snap) then
		SaveState.clear_checkpoint()
		self:_reset_run()
		return false
	end
	self.run_index = num.int(num.get(snap, "run_index", 1))
	Tape.begin({ sess = self.sess, tutorial = false, resume = true, faces = num.shallow(self.run.run_faces),
		targets = GameConfig.SECTION_TARGETS, coins = self.run.coins,
		struct = { sec = GameConfig.SECTIONS_PER_RUN, pps = GameConfig.PHRASES_PER_SECTION,
			ppshop = GameConfig.PHRASES_PER_SHOP, dur = GameConfig.phrase_duration(0) } })
	if self.run.phrase_in_section > 0 then self.cur_modifier = self.run:face() end
	self:_start_phrase()
	return true
end

-- ---------------------------------------------------------------- 文案(盲注卡状态行 / 明掷)
function App:_blind_status()
	local p = self.phrase
	local m = self.cur_modifier
	if p == nil then return "" end
	if m == "request" then
		return (Lingo.t("点歌 · %s"):gsub("%%s", Run.request_label(p.request_goal)))
	elseif m == "lostpage" then
		return (Lingo.t("将丢 · %s"):gsub("%%s", p.marked_cache_card and p.marked_cache_card:label() or "?"))
	end
	return ""
end

function App:_roll_note()
	local run = self.run
	run:ensure_mod_roll()
	local roll = run.mod_roll
	if num.int(num.get(roll, "sec", -2)) ~= run.section_idx then return "" end
	if roll.worse ~= nil then
		if roll.worse then return " " .. Lingo.t("(掷出:封 2 格)") end
		return " " .. Lingo.t("(掷出:封 1 格)")
	end
	local suit = num.int(num.get(roll, "suit", -1))
	if suit >= 0 then
		local names = { Lingo.t("梅花"), Lingo.t("方块"), Lingo.t("红桃"), Lingo.t("黑桃") }
		return " " .. (Lingo.t("(中签:%s)"):gsub("%%s", names[suit + 1]))
	end
	if roll.kind ~= nil then
		local kname = tostring(num.get(DB.ui().patterns or {}, num.itos(num.int(roll.kind)), "?"))
		return " " .. (Lingo.t("(点名:%s)"):gsub("%%s", kname))
	end
	return ""
end

function App:_shop_route()
	if self.run.tutorial then return {} end
	local out = {}
	for i = 0, GameConfig.SECTIONS_PER_RUN - 1 do
		local m = SectionMod.by_id(tostring(num.get(self.run.run_faces, i, "")))
		local state = 2
		if i < self.run.section_idx then state = 0 elseif i == self.run.section_idx then state = 1 end
		out[#out + 1] = { name = m and m.cn_name or Lingo.t("纯分数"), state = state }
	end
	return out
end

-- ---------------------------------------------------------------- 视图(每帧可读的纯数据)
local function card_view(c, extra)
	if c == nil then return false end
	local v = { rank = c.rank, suit = c.suit, label = c:label(), glyph = c:glyph(), red = c:is_red(), wild = c:is_wild() }
	if extra then for k, x in pairs(extra) do v[k] = x end end
	return v
end

function App:view()
	local run = self.run
	local p = self.phrase
	local decide = self.state == St.DECISION
	local v = { screen = self.state, paused = self.paused, resume_prompt = self.resume_prompt }
	if self.state == St.FRONT then
		v.home = { runs_total = SaveState.runs_total(), energy = SaveState.energy(), energy_max = SaveState.energy_max(),
			profile = SaveState.profile(), seen_tutorial = SaveState.seen_tutorial(),
			faces = self.run.run_faces, targets = GameConfig.SECTION_TARGETS }
		return v
	end
	local target = run:target()
	v.hud = { section_idx = run.section_idx, coins = p and p.coins or run.coins, score = run.section_score,
		target = target, phrase_no = run.phrase_index, fraction = target <= 0 and 0.0 or run.section_score / target,
		elapsed = self.elapsed, duration = self.cur_duration, warning = self.cur_warning, lock = self.cur_lock,
		seconds_left = self:_seconds_left(), warn = decide and self.elapsed >= self.cur_warning,
		countdown = decide and num.int(math.ceil(self.cur_lock - self.elapsed)) or 0,
		progress = self.cur_lock > 0 and num.minf(1.0, self.elapsed / self.cur_lock) or 0.0 }
	local m = SectionMod.by_id(self.cur_modifier)
	local nxt = SectionMod.by_id(tostring(num.get(run.run_faces, run.section_idx + 1, "")))
	local boon = BlindBoon.by_id(run:boon())
	v.blind = { section_idx = run.section_idx, gig = GameConfig.gig_of(run.section_idx) + 1,
		blind_name = GameConfig.blind_name(run.section_idx), gig_name = GameConfig.gig_name(run.section_idx),
		is_wall = GameConfig.is_wall(run.section_idx), target = target,
		face = m and { id = m.id, name = m.cn_name, fx = m.fx_text, base = SectionMod.base_of(m.id) } or false,
		next_face = nxt and { id = nxt.id, name = nxt.cn_name, fx = nxt.fx_text } or false,
		boon = boon and { id = boon.id, name = boon.cn_name, fx = boon.fx_text } or false,
		status = self:_blind_status(), roll_note = self:_roll_note(), visible = not run.tutorial,
		route = self:_shop_route() }
	local jokers = {}
	for i = 1, #run.joker_slots do
		local j = run.joker_slots[i]
		jokers[i] = j and { id = j.id, name = j.cn_name, kind = j.kind, rarity = j.rarity, fx = j.fx_text, state = num.deep(j.state) } or false
	end
	v.jokers = jokers
	local queue = {}
	for _, c in ipairs(run.consumables) do queue[#queue + 1] = { id = c.id, beat = c:fire_label(), name = c:display_name() } end
	v.vinyl = queue
	if p ~= nil then
		local best = p:current_best()
		local scoring = {}
		if next(best) ~= nil then
			for _, c in ipairs(best.cards) do scoring[c] = true end
		end
		for c in pairs(p.hidden) do scoring[c] = nil end
		local mask_rank = SectionMod.hide_ranks(self.cur_modifier) and decide
		local mask_suit = SectionMod.hide_suits(self.cur_modifier) and decide
		local dbh, dbc = p:discard_blocked_hand(), p:discard_blocked_cache()
		local sbh, sbc = p:swap_blocked_hand(), p:swap_blocked_cache()
		local hand = {}
		for i, c in ipairs(p.hand) do
			hand[i] = card_view(c, { selected = self.sel_hand[i - 1] and true or false, scoring = scoring[c] and true or false,
				hidden = p.hidden[c] and true or false, mask_rank = mask_rank, mask_suit = mask_suit,
				discard_blocked = dbh[c] and true or false, swap_blocked = sbh[c] and true or false })
		end
		local cache = {}
		for i, c in ipairs(run.cache) do
			cache[i] = card_view(c, { selected = self.sel_cache[i - 1] and true or false, scoring = scoring[c] and true or false,
				hidden = p.hidden[c] and true or false, mask_rank = mask_rank, mask_suit = mask_suit,
				discard_blocked = dbc[c] and true or false, swap_blocked = sbc[c] and true or false,
				marked = (p.marked_cache_card == c) })
		end
		local sel_n = num.size(self.sel_hand) + num.size(self.sel_cache)
		v.hand = { cards = hand, cache = cache, decide = decide, fee = sel_n * GameConfig.DISCARD_COST,
			can_discard_sel = sel_n > 0 and self:_discard_open() and p:can_discard_selected(keys_sorted(self.sel_hand), keys_sorted(self.sel_cache)),
			can_drop = self:_discard_open() and p:can_discard(1), can_swap = self:_swap_open(),
			best_kind = next(best) ~= nil and best.kind or -1, best_name = next(best) ~= nil and best.name or "",
			spotlight = card_view(p.spotlight_card), request = p.request_goal, request_label = Run.request_label(p.request_goal) }
	end
	if self.state == St.DRAFT and self.shop then
		v.shop = self.shop:view()
		v.shop.replace_pick = self.replace_pick
		v.shop.section_idx = run.section_idx
		v.shop.score = self.shop.mid and run.section_score or -1
		v.shop.left = self.shop.mid and run:phrases_left() or -1
		v.shop.need = self.shop.mid and run:deficit() or -1
		v.shop.target = target
		v.shop.route = self:_shop_route()
	end
	if self.state == St.END then v.end_screen = self.end_screen end
	if self.state == St.INTRO then v.intro = { kind = self.intro_kind, left = self.intro_left, route = self:_shop_route() } end
	if self.state == St.CUTIN then
		local c = Tutorial.cutin(self.cutin_key)
		v.cutin = { key = self.cutin_key, command = c.command, focus = c.focus, left = self.cutin_left, coins = self.last_gain_coins }
	end
	if run.tutorial then
		local h = run:tutorial_hint()
		v.tutorial = { step = run.tutorial_step, hint = h, pending = run:tutorial_pending(),
			focus = Tutorial.focus(run.tutorial_step), shot = Tutorial.shot(run.tutorial_step), spot = Tutorial.spot(run.tutorial_step),
			unlocked = Tutorial.unlocked(run.tutorial_step), shop_step = run.tutorial_step == Tutorial.shop_step() }
	end
	return v
end

return App
