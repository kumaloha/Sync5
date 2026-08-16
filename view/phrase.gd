extends Control

## Battle screen orchestrator — 1:1 recreation of the approved neon-stage mock.
## Discard-refill rules: select hand/cache cards → 弃牌 (1 coin each, instant
## refill). The character walks one lap around the hand frame per phrase;
## reaching the bottom-center beat point settles the hand automatically.

## FRONT = home screen / protagonist picker is up. It exists so the machine
## never idles in St.END: an END re-entry (double-tap, queued input) used to
## run _next_section() again and walk the section counter forward behind the
## front screen — the run then started on the wrong blind and a wall's
## 演出成功 surfaced "mid-run" (真人试玩 2026-08-05).
enum St { FRONT, INTRO, DECISION, RESOLVE, DRAFT, END }

# 舞台几何整块搬去了 view/layout.gd(它是装配的事);编排只读这一个 —— 结算
# 屏停留多久, 因为 _process 拿它判什么时候进下一拍。data/ui.json 仍是权威。
var RESOLVE_HOLD: float = float(DB.ui()["stage"]["resolve_hold"])

var run := Run.new()        # progression state machine (core/run.gd)
var phrase: Phrase
var state: int = St.DECISION
var elapsed := 0.0

# per-phrase timing (always taken from the GameConfig hooks — plans plug in there)
var cur_duration := 12.0
var cur_warning := 11.0
var cur_lock := 11.75

# joker slot VIEWS — the slot data itself lives on run.joker_slots
var _picker: PickWalker = null
var _home: HomeScreen = null
var _menu: Control = null     # 主角/小丑牌/荣誉 图鉴页(叠在首页上,z 85 > 80)
var joker_views: Array = []
var cur_modifier := ""        # this section's boss face ("" = none)
var acted_late := false        # any discard/swap/sort inside the final 2 seconds
var last_action_time := -1.0   # elapsed at the last action; -1 = untouched phrase
# ---- 2026-08-13 子波 2 的时钟观测(谢幕/秒表/早弃)。**时钟只在 view 侧读** ——
# core/ 不含时钟是铁律, 所以这三个量与 late/early 走同一条路:结算时装进 flags。
var acted_final := false       # 最后 FINAL_ACT_WINDOW 秒内动过手(谢幕, 比尾声更窄)
var last_discard_time := -1.0  # 最后一次**弃牌**的 elapsed;-1 = 本拍没弃过
var _last_warn_digit := -1     # countdown heartbeat edge detector (final 3s)
var _discard_gate_open := true # edge-cached so the keys redraw exactly once on close
var _swap_gate_open := true

# draft (2026-08 shop model) — the board lives in view/shop.gd, the replace
# state in view/replace.gd; 钱和打点留在这里(铁律)
var shop: Shop
var replace: ReplaceFlow

# --- ui refs ---
var wave: WaveView
var eq: EqStrip
var vinyl: VinylDeck
var orbit: OrbitZone
var hand: Hand
var hud: Hud
var settle_fx: SettleFx
var run_end: RunEndScreen
var banner: BlindBanner
var tutor: Widgets.TutorHint      # 教学关的一行提示;正式局整块隐身
var blind_card: Widgets.BlindCard
var intro: BlindIntro
var fx: StageFeedback        # 屏震/弹跳/飘字 —— 纯表现, view/feedback.gd
var _shown_score := 0        # what the HUD prints; counts up to run.section_score


## 这一次「坐下」的身份 —— `{id, gap, runs_prev}`,整个进程只取一次。
## ⚠ 必须在 `_ready` 取而不是每局取:一局一取会让 `gap` 变成「上一局到这一局」,
## 那是**局间隔**不是**会话间隔**,两者是不同的量(D4 要的是后者)。
var _sess: Dictionary = {}


func _ready() -> void:
	# ⚑ 会话边界(D4)——「隔多久回来」跨应用启动才有意义, 所以数据来自存档层。
	_sess = SaveState.session_start()
	run.reset()
	_build_ui()
	_open_home()


## 关窗/退出时把打点尾巴写下去。半途退出的 run 因此**有事件、没有 close**——
## 那正是「玩家中途弃局」的信号,别去补一条假的收尾。
##
## 失焦也要记:单拍只有 8 秒,玩家中途切出去一下,那一拍的 `at`/`act` 和相邻事件的
## `ms` 差**全是脏的**,不留痕就分辨不出来(手机上这不是边角情况)。
## 切后台顺手 flush —— 后台进程可能直接被系统杀掉,不落盘就全丢了。
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_PREDELETE:
			Tape.flush()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			Tape.on("focus", {"on": false, "at": elapsed})
			Tape.flush()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			Tape.on("focus", {"on": true, "at": elapsed})


## The front page (resources/home.html). Like the picker it holds the clock —
## _process would otherwise tick against a null phrase.
func _open_home() -> void:
	set_process(false)
	state = St.FRONT
	_front_latch = false        # 回到前端 = 新的选角会话(V3 闩锁复位)
	if _picker != null and is_instance_valid(_picker):
		_picker.queue_free()
		_picker = null
	Tape.on("nav", {"to": "home"})
	_home = HomeScreen.new()
	_home.start_pressed.connect(_on_home_start)
	_home.menu_pressed.connect(_open_menu)
	add_child(_home)


func _on_home_start() -> void:
	# 一次性闩锁(外部审查 V3):queue_free 延迟生效 + 手机多点触控 —— start 双击
	# 会无条件叠出第二层 PickWalker,孤儿层的 picked 还连着 choose_character。
	if _picker != null:
		return
	_close_menu()
	if _home != null and is_instance_valid(_home):
		_home.queue_free()
	_home = null
	_open_picker()


## 三个图鉴页(2026-08-11 resources/主角|小丑牌|荣誉.dc.html 实装)。
## 页面之间互切也走这里 —— 每页的页签轨发同一个 menu_pressed(idx),
## idx 0 = 回首页(首页一直活在下面,关掉覆盖层即可)。
func _open_menu(idx: int) -> void:
	_close_menu()
	if idx <= 0:
		return
	Tape.on("nav", {"to": ["home", "heroes", "album", "honors"][idx]})
	match idx:
		1: _menu = HeroesScreen.new()
		2: _menu = AlbumScreen.new()
		_: _menu = HonorsScreen.new()
	_menu.menu_pressed.connect(_open_menu)
	add_child(_menu)


func _close_menu() -> void:
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null


## The run starts on the protagonist pick screen. The phrase clock is held
## until a choice lands — _process drives the timer and would otherwise tick
## against a null phrase.
func _open_picker() -> void:
	set_process(false)
	state = St.FRONT
	Tape.on("nav", {"to": "pick"})
	_picker = PickWalker.new()
	_picker.picked.connect(choose_character)
	add_child(_picker)


## 闩锁的另一半(V3):两层选角或双击同一立绘会让 picked 双发 —— 二次开局
## = Tape 重开 + 重进关。同一个前端会话只放行一次;回到前端(_open_home)复位。
var _front_latch := false


## Also the entry point for tools and tests that need to skip the front-end;
## it tears down BOTH the home screen and the picker, so a probe can jump
## straight into a run with one call.
func choose_character(i: int) -> void:
	if _front_latch:
		return
	_front_latch = true
	_close_menu()
	if _home != null and is_instance_valid(_home):
		_home.queue_free()
	_home = null
	if _picker != null and is_instance_valid(_picker):
		_picker.queue_free()
	_picker = null
	run.character = Character.roster()[i]
	orbit.set_character(i)
	# 点唱片 = 提前收工(2026-08-13 用户拍板)。⚠ 连在这里而不是 _ready:
	# `vinyl` 是 StageLayout 建的, 选角之后才拿到引用(同 orbit)。
	if not vinyl.tapped.is_connected(_on_vinyl_tapped):
		vinyl.tapped.connect(_on_vinyl_tapped)
	# ⚑ 教学关:**只在第一次启动时出现一次**(用户 2026-08-07 拍板「教学只要一次」)。
	# 判据存在 `SaveState`(`user://`), 与将来的断点续玩共用同一个存档层。
	# ⚠⚠ **必须在 roll_faces 之前设** —— 教学关不掷 Boss 脸(见 Run.roll_faces),
	# 而「起」按定义就是**安全的地方、无惩罚地理解机制**。顺序写反了截图里就会
	# 挂着一张「禁回」, 我第一版正是这么错的。
	run.tutorial = not SaveState.seen_tutorial()
	run.roll_faces()
	# 打点从这里开流 —— 主角与四面墙都定了, 这一局的初始条件已经完整
	# ⚠⚠ 教学关**照样打点, 但必须打上标记**:它是一局假局(6 拍、目标分 0、不判生死),
	# 混进 Tape 会污染 `tools/probbook.py` 的「合格真人局」分拣。
	# 不干脆不打点, 是因为 design/difficulty.md §4 明写着要量的东西正在这里 ——
	# **新手的动作时刻分布**(12 秒够不够), 而那正是现有 Tape 全是熟练玩家所以缺的那一块。
	# ⚑ 会话边界(D4)——「一次坐下玩几局 / 隔多久回来」。目标函数换成留存之后,
	# **这是唯一能直接观测目标的量**。它跨局, 而 Tape 一局一个文件, 所以只能进 meta。
	SaveState.note_run_started()
	Tape.begin({
		"sess": _sess,
		"tutorial": run.tutorial,
		"char": i, "cn": run.character.cn_name,
		"faces": run.run_faces.duplicate(),
		"targets": GameConfig.SECTION_TARGETS,
		"coins": GameConfig.STARTING_COINS,
		# 结构参数必须随局记下:表会改, 老日志不能被新结构的口径误读
		"struct": {"sec": GameConfig.SECTIONS_PER_RUN,
			"pps": GameConfig.PHRASES_PER_SECTION,
			"ppshop": GameConfig.PHRASES_PER_SHOP,
			"dur": GameConfig.phrase_duration(0)},
	})
	set_process(true)
	_enter_section()


# ============================== BUILD ==============================

## 装配本身在 `view/layout.gd`(建节点、排版、层序 —— 跑完就不再参与逻辑)。
## 这里只剩**接线**:谁的意图由谁处理。组件对外只发意图信号, 钱与打点在这一侧落地。
func _build_ui() -> void:
	var n := StageLayout.build(self)
	hud = n["hud"]
	joker_views = n["joker_views"]
	wave = n["wave"]
	eq = n["eq"]
	blind_card = n["blind_card"]
	vinyl = n["vinyl"]
	orbit = n["orbit"]
	hand = n["hand"]
	shop = n["shop"]
	settle_fx = n["settle_fx"]
	run_end = n["run_end"]
	banner = n["banner"]
	tutor = n["tutor"]
	intro = n["intro"]

	for i in range(joker_views.size()):
		joker_views[i].tapped.connect(_on_slot_tapped.bind(i))  # only live in replace mode
	hand.sort_pressed.connect(_on_hand_sort)
	hand.discard_pressed.connect(_on_hand_discard)
	hand.single_discard.connect(_on_hand_single_discard)
	hand.swap_requested.connect(_on_hand_swap)
	hand.selection_changed.connect(_refresh)
	# 点选是唯一一整类原本不可见的玩家动作 —— 从 disc 只看得到最终提交的集合,
	# 看不到选了又取消、跨区试探。用户 2026-08-06 拍板「文件翻倍不是问题, 点选也要」。
	hand.card_picked.connect(func(zone: String, i: int, on: bool) -> void:
		Tape.on("pick", {"z": zone, "i": i, "on": on, "at": elapsed}))
	shop.bought.connect(_on_shop_bought)
	shop.replace_requested.connect(_on_shop_replace)
	shop.skipped.connect(_on_shop_skipped)
	shop.reroll_paid.connect(_on_shop_reroll)
	shop.denied.connect(func(why: String) -> void: Tape.on("deny", {"why": why}))
	settle_fx.burst_started.connect(_on_settle_burst)
	run_end.next_pressed.connect(_on_end_next)
	run_end.retry_pressed.connect(_on_end_retry)
	run_end.home_pressed.connect(_on_end_home)
	intro.done.connect(_on_intro_done)

	fx = StageFeedback.new(self)
	add_child(fx)
	# 替换态的两个部件挂在最上层:选槽时商店已经关了, 它们要盖住小丑牌行以外的一切
	replace = ReplaceFlow.new(self, joker_views)


# ============================== FLOW ==============================

## Shop-less section entries (run start / retry) open with the standalone
## blind card; the phrase clock holds until it dismisses. Sections behind a
## shop are announced on the shop's blind board instead, and mid-section
## phrases go straight to _start_phrase().
func _enter_section() -> void:
	state = St.INTRO
	var m := SectionMod.by_id(String(run.run_faces.get(run.section_idx, "")))
	var boon := BlindBoon.by_id(run.boon())
	_tape_section()
	intro.open(run.section_idx, run.target(), m, boon)


## 进段打点。两个入口:_enter_section(开局/重开)与 _next_section(段间),
## 都在 section_idx 已经落到新值之后。序列断号 = 流程 bug 的直接证据 ——
## 「连点跳段」那次事故在日志里就是 sec 从 2 直接跳到 4。
func _tape_section() -> void:
	Tape.on("sec", {"i": run.section_idx, "target": run.target(),
		"face": String(run.run_faces.get(run.section_idx, "")),
		"boon": run.boon(),
		"wall": GameConfig.is_wall(run.section_idx),
		# ⚠ 段首 `phrase` 还没建(第一段就是这样), 此时钱在 `run.coins` 上。
		# 原本这里写死 0, 于是**第一段的 `sec` 事件把起始金币记成了 0**(真值 6)——
		# `run` 首事件里另有起始金币, 所以日志内部自相矛盾, 按段分析会被污染。
		# 2026-08-09 外部审查发现。
		"coins": run.coins if phrase == null else phrase.coins})


func _on_intro_done() -> void:
	if state == St.INTRO:
		# 主动点掉 vs 等它自己走完 —— 「急着打」和「在读盲注规则」是两回事,
		# 也是教学空间那个待验问题(S1 就是墙、开局就带 Boss 规则)的观测点
		Tape.on("intro", {"skip": intro != null and intro.skipped})
		_start_phrase()


func _start_phrase() -> void:
	# 拍与拍之间的钱记在 run 上, 一拍之内归 Phrase 管(弃牌与入场费都在那里扣)。
	# ⚠ 这一行不能省:商店是在**两拍之间**动钱的, 不同步回去 Beat 就会拿旧余额发牌。
	run.coins = GameConfig.STARTING_COINS if phrase == null else phrase.coins
	# boss faces are rolled for the whole run up front and PREVIEWED one
	# section ahead (Balatro shows the upcoming boss — the preview is what
	# turns a face from an execution into a routing decision)
	if run.phrase_in_section == 0:
		cur_modifier = run.face()
		var m := SectionMod.by_id(cur_modifier)
		var nxt := SectionMod.by_id(String(run.run_faces.get(run.section_idx + 1, "")))
		blind_card.setup(run.section_idx, m, nxt, BlindBoon.by_id(run.boon()))
		# ⚠ 教学关没有脸 ⇒ 盲注卡整块隐藏。不隐藏会留下一个**只剩 "BOSS" 边框的空壳**,
		# 那比没有更糟:玩家会以为这一关有个规则而他没看懂。(截图看出来的)
		blind_card.visible = not run.tutorial
	# 规则全在这一句里:解析脸 → 发牌(缓存容量在 start() 生效)→ 收入场费 → 推进计数器。
	# 这三样曾经在六个文件里各写一遍, 而入场费那份我一度还判断错了它有没有用(design/tech.md)。
	phrase = Beat.begin(run)
	state = St.DECISION
	elapsed = 0.0
	acted_late = false
	acted_final = false
	last_action_time = -1.0
	last_discard_time = -1.0
	_last_warn_digit = -1
	cur_duration = run.phrase_duration()
	cur_warning = GameConfig.warning_time(cur_duration)
	cur_lock = GameConfig.lock_time(cur_duration)
	_discard_gate_open = _discard_open()
	_swap_gate_open = _swap_open()
	# 教学关的一行提示 + 分区指向 —— 正式局 hint 是空串, TutorHint 整块隐身。
	# ⚠ 区域名 → 矩形的翻译在**编排器**这一侧:`core/` 不认识像素(坐标归 ui.json)。
	var h := run.tutorial_hint()
	var rects: Array = []
	if run.tutorial:
		var geo: Dictionary = DB.ui().get("tutor_focus", {})
		for name in Tutorial.focus(run.phrase_in_section):
			if geo.has(name):
				rects.append(geo[name])
	tutor.set_hint(String(h["command"]), String(h["signal"]), rects)
	# 跨区多选在教学关第 5 步才解锁 —— 在那之前每次只能选一张。
	# ⚠ 组件不认识教学关(铁律:组件只发意图, 状态由编排器给), 所以这里翻译成
	# 它听得懂的话:`multi_select`。正式局恒 true。
	hand.multi_select = run.tutorial_unlocked("multiselect")
	orbit.set_mode("walk")
	hand.clear_selection()
	hand.deal_flip()
	# 手牌/缓存快照 —— 只记发到手里的牌本身。
	# 曾经在这里记过 best0(「不动手会是什么牌型」), 已删:那是**反事实不是事实**,
	# 能从 hand 推出来, 而且它的值依赖当时的牌型表和 Deck.rules —— 表一改
	# (2026-08-06 抄 Balatro 那次), 老日志的 best0 就和同一行的 hand 打架, 且不会报错。
	Tape.on("beat", {"i": run.phrase_index, "p": run.phrase_in_section,
		"dur": cur_duration, "coins": phrase.coins,
		"hand": Tape.cards(phrase.hand), "cache": Tape.cards(run.cache),
		"boon": run.boon(), "request": phrase.request_goal,
		"spotlight": "" if phrase.spotlight_card == null else phrase.spotlight_card.label()})
	_refresh()


func _process(delta: float) -> void:
	match state:
		St.DECISION:
			elapsed += delta
			var discard_now := _discard_open()
			var swap_now := _swap_open()
			if discard_now != _discard_gate_open or swap_now != _swap_gate_open:
				_discard_gate_open = discard_now
				_swap_gate_open = swap_now
				_refresh()
			var warn := elapsed >= cur_warning
			orbit.set_progress(elapsed / cur_lock, warn, cur_lock - elapsed)
			# 可以收工时唱片亮金环 + 中心显示能省下几秒(时钟只在这里读)
			vinyl.set_armed(_can_early_lock(), maxf(0.0, cur_lock - elapsed))
			# final-seconds heartbeat: eq curtain reddens/speeds, each countdown
			# second kicks the wave and spins the record up toward the drop
			eq.urgency = clampf((elapsed - cur_warning) / maxf(cur_lock - cur_warning, 0.1), 0.0, 1.0) if warn else 0.0
			if warn:
				var d := int(ceil(cur_lock - elapsed))
				if d != _last_warn_digit:
					_last_warn_digit = d
					wave.on_action()
					vinyl.spin_boost()
			if elapsed >= cur_lock:
				_settle()
		St.RESOLVE:
			elapsed += delta
			orbit.set_progress(1.0, false)
			eq.urgency = 0.0
			if elapsed >= RESOLVE_HOLD:
				_advance()


func _settle() -> void:
	# ⚠ 2026-08-07: 这一拍的规则部分整个搬进了 `Core/Beat`(design/tech.md)——
	# 游戏和模拟器共用同一份编排, 因为「一拍怎么走完」曾经被写了六遍, 而五次
	# 「规则在游戏里、不在模型里」的事故有三次直接出自那些副本。
	# 这里只剩表现:Tape 打点 / 三段式结算动画 / popup。
	# early 必须传:settle ctx 的 early_finish 只认这里的 flags(core/beat.gd),
	# 漏传 = 速弹在真机恒假而 sim 侧为真 —— 模型/游戏分叉(C7 反向,TODO C10)。
	# 时钟观测一律经 flags 交给 core(core/ 不含时钟 —— 铁律)。
	# `secs_left` = 锁定时刻减最后一次动手的时刻:**没动过手的一拍记 0**,
	# 否则「整拍不操作」会拿到满额剩余秒数, 秒表就成了「什么都不做最赚」的挂机卡(A4)。
	var outcome := Beat.settle(run, phrase, {
		"late": acted_late, "early": _acted_early(), "final": acted_final,
		# ⚠⚠ **按「结算这一刻」算剩余, 不是按「最后动手那一刻」**(2026-08-13 修)。
		# 子波 2 的第一版写的是 `cur_lock - last_action_time` —— 那算的是
		# 「最后动手时还剩多少」, 于是「2 秒动完手然后干等到底」也能拿满额剩余,
		# **秒表变成了奖励干等**。卡面写的是 "at settle", 结算时刻的剩余才是它。
		# 主动锁定(点唱片)时 elapsed 就是锁定时刻 → 真实剩余;
		# 自然走完时 elapsed >= cur_lock → 剩 0。一个式子同时对两条路径成立。
		"secs_left": maxf(0.0, cur_lock - elapsed),
		"early_discards": last_discard_time >= 0.0 \
			and last_discard_time <= GameConfig.EARLY_DISCARD_WINDOW,
	})
	var res: Dictionary = outcome["res"]
	var gained_score := int(outcome["score"])
	var gained_coins := int(outcome["coins"])
	# 全场最重的一条:G/D 对账、牌型频率、经济产出全靠它。
	# fired 记 joker id 而不是 popup 文案 —— 只有 id 能和 report.gd 的
	# trigger_n 直接对齐, 文案改一个字就对不上了。
	Tape.on("settle", {
		"kind": int(res.get("kind", -1)), "chips": int(res.get("chips", 0)),
		"base": int(outcome["base"]), "mult": float(outcome["mult"]),
		"bonus": int(outcome.get("bonus", 0)), "score": gained_score,
		# ⚠ `total` 是**入账后**的段内累计。搬进 Beat 之前这里写的是
		# `run.section_score + gained_score`(因为那时入账在打点之后), 现在 Beat 已经
		# 入过账了 —— 照抄旧写法会把这一拍算两遍, 而日志不会报错。
		"coin": gained_coins, "total": run.section_score,
		"disc": phrase.discards_used, "late": acted_late,
		"act": last_action_time, "mod": cur_modifier,
		"raw": int(outcome.get("raw_score", gained_score)),
		"boon": run.boon(), "boon_bonus": int(outcome.get("boon_bonus", 0)),
		"request": phrase.request_goal, "request_ok": phrase.request_met,
		"cards": Tape.cards(res.get("resolved", [])),
		"fired": Tape.fired(outcome["popups"], run.joker_slots)})
	state = St.RESOLVE
	elapsed = 0.0
	hand.clear_selection()
	orbit.set_mode("dance")
	_refresh()

	# three-phase settle: 基础分 × 乘数 = 分数 → shatter → count up
	settle_fx.play(int(outcome["base"]), float(outcome["mult"]), gained_score,
		hud.score_anchor() + Vector2(24, 26), int(outcome.get("bonus", 0)))
	# the merge beat lands at 450ms: shake the screen and kick the wave then
	var merge_tw := create_tween()
	merge_tw.tween_interval(0.45)
	merge_tw.tween_callback(func() -> void:
		fx.shake(9.0)
		wave.on_score(float(gained_score) / 80.0))
	# joker triggers pop over their slots, staggered; slot -1 is the
	# protagonist, whose text pops over the beat point they are dancing on
	var popups: Array = outcome["popups"]
	for k in range(popups.size()):
		var p: Dictionary = popups[k]
		var at: Vector2
		var col := StageTheme.GOLD
		if int(p["slot"]) < 0:
			at = orbit.get_global_position() + Vector2(orbit.size.x * 0.5 + 24.0, orbit.size.y - 54.0)
			col = orbit.character_color()
		else:
			var slot_view: Control = joker_views[p["slot"]]
			at = slot_view.get_global_position() + Vector2(slot_view.size.x * 0.28, -6.0)
		var tw := create_tween()
		tw.tween_interval(0.30 + 0.22 * float(k))
		tw.tween_callback(fx.float_text.bind(String(p["text"]), at, col))
	if gained_coins > 0:
		fx.float_text("+%d ◆" % gained_coins, hud.coin_anchor() + Vector2(20, 40), StageTheme.GOLD)


## Shards have launched — start rolling the score up to meet them.
func _on_settle_burst() -> void:
	var from := _shown_score
	var to := run.section_score
	if to == from:
		return
	var tw := create_tween()
	tw.tween_interval(0.62)
	tw.tween_method(func(v: float) -> void:
			_shown_score = int(round(v))
			hud.set_score_text(_shown_score),
		float(from), float(to), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 提前收工:立刻结算这一拍。**2026-08-13 起真的有调用方了** ——
## 点唱片(`_on_vinyl_tapped`), 用户拍板的交互。
## ⚠ 这个函数在此之前是**孤立的钩子**(零调用方), 而四张时机卡
## (速弹/惯性/定格/秒表)全建在它上面 —— 于是「早锁」的真实语义一直是
## 「早点动完手然后干等」, 真人早锁率 8% / bot 78% 的差距根因就在这里:
## 干等 4.5 秒的代价对真人是真的, 对不感知时间的 bot 是零。
func early_settle() -> void:
	if state == St.DECISION:
		_settle()


## 能不能收工:必须在决策态、过了防手滑的下限、且**动过至少一次手**。
## ⚠ 最后一条与 `_acted_early()` 同源(A4:不许挂机)—— 一拍不动就点收工
## 拿不到早锁加成, 那就别让它看起来可点。
func _can_early_lock() -> bool:
	return state == St.DECISION and elapsed >= GameConfig.EARLY_LOCK_MIN \
		and last_action_time >= 0.0


func _on_vinyl_tapped() -> void:
	if not _can_early_lock():
		return
	Tape.on("lock", {"at": elapsed, "left": maxf(0.0, cur_lock - elapsed)})
	early_settle()


## "Early finish" needs at least one action — an untouched phrase never counts,
## or momentum would grow while the player idles (principle A4).
## _settle 与 _advance 共用这一份判据(判定只许有一份真相)。
func _acted_early() -> bool:
	return last_action_time >= 0.0 and last_action_time <= GameConfig.EARLY_FINISH_TIME


func _advance() -> void:
	Beat.phrase_end(run, phrase, {"early": _acted_early()})
	var out := run.advance()
	# ⚑ 教学关走完 = 记下「看过了」→ 回首页, 玩家下一局起就是正式局。
	# ⚠ 放在生死判定**之前** —— 教学关 target 恒 0, 走到这里 `cleared` 必真,
	# 但把它夹在下面那段结算逻辑里会让「教学关不判生死」变成一个隐式的巧合。
	# **显式返回, 别依赖巧合。**
	if run.tutorial_done():
		Tape.close({"ok": true, "tutorial": true, "beats": run.phrase_index})
		SaveState.mark_tutorial_seen()
		tutor.set_hint("", "")
		_open_home()
		return
	if bool(out["section_done"]):
		state = St.END
		Tape.on("sec_end", {"i": run.section_idx, "score": run.section_score,
			"target": run.target(), "ok": bool(out["cleared"]),
			"coins": phrase.coins, "beats": run.phrase_in_section})
		if not bool(out["cleared"]):
			Tape.close({"ok": false, "sec": run.section_idx,
				"score": run.section_score, "target": run.target(),
				"beats": run.phrase_index})
			run_end.show_fail(run.section_score, run.target())
			return
		# clear wage, shown as the panel chip(走 grant —— 金币上限的四个入账口之一)
		phrase.coins = Economy.grant(phrase.coins, GameConfig.SECTION_CLEAR_REWARD,
			run.joker_slots)
		if bool(out["finale"]):
			Tape.close({"ok": true, "sec": run.section_idx,
				"score": run.section_score, "target": run.target(),
				"beats": run.phrase_index})
			# 2026-08-06 用户:「为什么中途要跳那个通关成功的页面啊, 只有一整关通关才跳」——
			# 全屏庆祝**只留给整轮结束**。改成 4 段全墙之后, 挂在墙上的旧规则等于每段都发,
			# 一局 5 分钟被打断 4 次; 庆祝是稀缺资源, 现在全程只发 1 次。
			run_end.show_success(run.section_score, run.target(), GameConfig.SECTION_CLEAR_REWARD,
				true, GameConfig.gig_of(run.section_idx) + 1)
		else:
			# 中途过关 —— 轻横幅(≤1s 自动滑走)直接进商店, 不打断节奏
			banner.pop(run.section_score, run.target(), GameConfig.SECTION_CLEAR_REWARD)
			_next_section()
		return
	if bool(out["shop_break"]):
		# 段中商店(2026-08-06): section 不结束 —— 不清分、不判生死、不发横幅,
		# 只是把货架推到玩家面前。`section_idx` 保持在当前盲注上, 所以商店顶部
		# 那块板显示的是**这一段的进度**(已得/还差/还剩几拍), 而不是下一场预告。
		# 买完照常 `_start_phrase()` 接着打第 4 拍 —— 出口路径与段末商店共用。
		_open_draft()
		return
	_start_phrase()


## advance to the next blind and open the shop — every section boundary is a
## shop visit; with full slots it becomes the buy-new-replace-old flow
func _next_section() -> void:
	run.next_section()
	_tape_section()
	_open_draft()


## success screen: 下一场演出 (or 谢幕 on the finale)
func _on_end_next() -> void:
	if state != St.END:
		return
	run_end.close()
	if run.section_idx >= GameConfig.SECTIONS_PER_RUN - 1:
		_on_end_home()          # 谢幕: the run is complete, take a bow
		return
	_next_section()


## fail screen: 再来一次 — same protagonist, fresh run
func _on_end_retry() -> void:
	if state != St.END:
		return
	Tape.on("nav", {"to": "retry"})
	run_end.close()
	_reset_run(true)      # 再来一次 keeps the protagonist, per design/levels.md
	# 重开 = 新的一局, 得开新流, 否则两局的事件会串在同一条时间轴上
	Tape.begin({"char": run.character.idx, "cn": run.character.cn_name,
		"faces": run.run_faces.duplicate(), "targets": GameConfig.SECTION_TARGETS,
		"coins": GameConfig.STARTING_COINS, "retry": true,
		"struct": {"sec": GameConfig.SECTIONS_PER_RUN,
			"pps": GameConfig.PHRASES_PER_SECTION,
			"ppshop": GameConfig.PHRASES_PER_SHOP,
			"dur": GameConfig.phrase_duration(0)}})
	_enter_section()


## either screen: 返回主页 — back to the protagonist pick
func _on_end_home() -> void:
	if state != St.END:
		return
	Tape.on("nav", {"to": "back"})
	Tape.flush()
	run_end.close()
	_reset_run(false)
	_open_home()


## keep_character: 再来一次 restarts the tour with the SAME protagonist —
## Run.reset() clears it, so it is restored here (the orbit walker was still
## showing the old one, so the passive silently went missing).
func _reset_run(keep_character: bool) -> void:
	phrase = null
	var who: Character = run.character
	run.reset()
	if keep_character:
		run.character = who
	for i in range(joker_views.size()):
		joker_views[i].set_joker(null)
	_shown_score = 0


# ============================== DRAFT ==============================

func _open_draft() -> void:
	state = St.DRAFT
	_shop_buys = 0        # 联票的续买配额按「一次进店」计
	# a mid-section shop opens with the blind's counter part-way through; a
	# section-end one opens at phrase 0 of the blind being entered
	var mid: bool = run.phrase_in_section > 0 \
		and run.phrase_in_section < GameConfig.PHRASES_PER_SECTION
	shop.open(run.joker_slots, phrase.coins, run.section_idx,
		SectionMod.by_id(String(run.run_faces.get(run.section_idx, ""))),
		run.section_score if mid else -1,
		run.phrases_left() if mid else -1,
		run.target(),      # ⚠ 加码脸乘过的那个目标, 不是原始表(2026-08-09)
		BlindBoon.by_id(run.boon()))
	# 段中/段末两态要分开统计:段中是「已知缺口下的解题」, 段末是「对下一场下注」,
	# 购买行为本来就不该混在一起看(design/levels.md 的核心论证)
	Tape.on("shop", {"mid": mid, "sec": run.section_idx, "coins": phrase.coins,
		"offer": shop.offers(), "slots": Tape.slots(run.joker_slots),
		"left": run.phrases_left() if mid else -1,
		"need": run.deficit() if mid else -1})


## 一次进店已成交几张(联票 buy_limit 的计数;每次 _open_draft 归零)。
var _shop_buys := 0


## Shop signals — the board picked; money and slots change ONLY here.
func _on_shop_bought(j, price: int) -> void:
	if state != St.DRAFT:
		return
	# 0 = 本局首张 Target(免费三选一, Target 唯一保留的特例);
	# 之后 Target 与 Support 一样按稀有度定价(2026-08-06 回池, 原专属 8◆ 已废)。
	phrase.coins -= price
	Tape.on("buy", {"id": String(j.id), "kind": String(j.kind),
		"price": price, "coins": phrase.coins})
	# 收藏家:每买一张。⚠ **在装卡之前发** —— 否则刚买的这张会给自己记一次,
	# 「每买 1 张 +15」就凭空多了第一次(转型同理:换旗不该给新旗自己记一次)。
	Joker.notify_shop(run.joker_slots, "buy")
	if j.kind == "target":
		var swapping: bool = run.joker_slots[0] != null
		if swapping:
			Joker.notify_shop(run.joker_slots, "target_swap")   # 转型:换旗有代价(丢掉旧旗)
		run.joker_slots[0] = j
		j.on_acquire(run.deck)          # 百搭 shuffles 大小王 in at this moment
		joker_views[0].set_joker(j)
		fx.pop(joker_views[0])
	else:
		# pay and install into the first empty support slot
		# ⚠⚠ **找不到空位必须响** —— 2026-08-16 真人试玩踩到:`view/shop.gd` 当时用
		# `_slots.has(null)`(四个槽)判满, 而 Support 只能进 1..3, 于是「没有 Target +
		# 三个 Support 满」时这个循环**空转**, 玩家**钱扣了、卡没了、没有任何提示**。
		# 上游已按 kind 修好(`Shop._has_slot_for`), 这里留一道**响亮的**兜底:
		# 静默的 for-else 正是这个项目最贵的那类失败。
		var placed := false
		for k in range(1, run.joker_slots.size()):
			if run.joker_slots[k] == null:
				run.joker_slots[k] = j
				j.on_acquire(run.deck)
				joker_views[k].set_joker(j)
				fx.pop(joker_views[k])
				placed = true
				break
		if not placed:
			push_error("[shop] 买了 '%s' 却没有空的 Support 槽 —— 钱已扣。上游的满槽判定漏了 kind"
				% String(j.id))
	# 刚装的卡若自带金币上限(穷开心), 存量当场修剪 —— 卡面「上限 5」对已经很富的
	# 玩家也必须为真(D2:卡面不许说谎), 而修剪只许发生在编排器手里。
	phrase.coins = Economy.cap_held(phrase.coins, run.joker_slots)
	# 联票:限额未满就留在店里续买(同一货架摘牌重估, 不重掷)。
	# 限额从槽位实时读 —— 本次买的若是联票, 当店立刻多出一次成交。
	# ⚠ 走替换流(满槽)的成交不回商店:那条流程以 _start_phrase 收尾, 视为用掉全部余额。
	_shop_buys += 1
	if _shop_buys < Joker.slots_buy_limit(run.joker_slots):
		shop.sold(j, run.joker_slots, phrase.coins)
		return
	shop.close()
	_start_phrase()


## full slots: pick which support to swap out (old sells for half)
func _on_shop_replace(j) -> void:
	if state != St.DRAFT:
		return
	# 进入替换态。**「看了但没换」原本零痕迹** —— 后 3 次商店 100% 是替换场景,
	# 而只记成交和差钱, 分不出「换不起」还是「不值得换」。
	Tape.on("repl_open", {"id": String(j.id), "price": Economy.shelf_price(j, run.joker_slots),
		"coins": phrase.coins, "slots": Tape.slots(run.joker_slots)})
	shop.close()
	# UI 那摊(提示条带价、新卡钉出来、四个槽开始接手势)在 view/replace.gd
	# 价从编排器传进去 —— 赞助的折扣价要和成交价同源(replace.gd 不认识槽位)
	replace.enter(j, Economy.shelf_price(j, run.joker_slots))


## 「继续 ▸」= 不买就走。2026-08-06 起**没有奖励**(用户拿掉了跳过机制),
## 它纯粹是商店的免费出口 —— 买不起又刷不起时的唯一退路。
func _on_shop_skipped() -> void:
	if state != St.DRAFT or replace.pick != null:
		return
	Tape.on("leave", {"coins": phrase.coins})
	shop.close()
	_start_phrase()


func _on_shop_reroll(cost: int) -> void:
	if state != St.DRAFT or replace.pick != null:
		return
	phrase.coins -= cost
	Joker.notify_shop(run.joker_slots, "reroll")     # 淘碟:刷新是付费动作(A4✓)
	Tape.on("rerl", {"k": shop.reroll_count(), "cost": cost, "coins": phrase.coins})
	shop.redeal(run.joker_slots, phrase.coins, run.section_idx)


## 成交(或取消)。⚠ 钱与打点必须留在这里 —— replace.gd 只复位 UI。
func _on_slot_tapped(k: int) -> void:
	if state != St.DRAFT or replace.pick == null:
		return
	var new_j = replace.pick
	if k == 0:
		Tape.on("repl_off", {"id": String(new_j.id), "coins": phrase.coins})
		replace.exit()               # tapping the target cancels
		shop.show_board()
		return
	var old = run.joker_slots[k]
	var price := Economy.shelf_price(new_j, run.joker_slots)
	var refund := Economy.sell_value(old)
	if phrase.coins + refund < price:
		fx.float_text("◆ 不足", joker_views[k].get_global_position() + Vector2(30, 40), Color("ff5f7e"))
		Tape.on("deny", {"why": "replace"})
		return
	# 回收进账走 grant, 付款直接扣;换进的卡若自带上限, 装完再修剪存量(cap_held)
	phrase.coins = Economy.grant(phrase.coins, refund, run.joker_slots) - price
	Tape.on("repl", {"in": String(new_j.id),
		"out": "" if old == null else String(old.id), "slot": k,
		"price": price, "back": refund, "coins": phrase.coins})
	if refund > 0:
		fx.float_text("+%d ◆" % refund, joker_views[k].get_global_position() + Vector2(30, 40), StageTheme.GOLD)
	# 收藏家:替换流也是一次购买(同买入路径, 在装卡前发 —— 新卡不给自己记)
	Joker.notify_shop(run.joker_slots, "buy")
	run.joker_slots[k] = new_j
	new_j.on_acquire(run.deck)
	# ⚠ 修剪必须在**装卡之后** —— 装之前读的是旧槽位, 新卡自带的上限根本不在里面。
	phrase.coins = Economy.cap_held(phrase.coins, run.joker_slots)
	joker_views[k].set_joker(new_j)
	fx.pop(joker_views[k])
	replace.exit()
	_start_phrase()


# ============================== INPUT ==============================


func _seconds_left() -> float:
	return maxf(0.0, cur_lock - elapsed)


## ⚑ 教学关的部件门控**复用脸的那条闸门**(2026-08-15), 不新造机制:
## 「这一拍能不能弃牌」本来就有唯一的判定口, 教学关只是再加一个合取项。
## 好处是 UI 的灰化/提示文案**全都自动跟着走** —— 它们读的就是这两个函数
## (`can_discard_sel` / `can_drop` / `can_swap` 都在 `_vm()` 里由它们喂)。
## ⚠ 正式局 `tutorial_unlocked()` 恒真, 所以这两行对非教学关**逐字节无影响**。
func _discard_open() -> bool:
	return SectionMod.discard_open(cur_modifier, _seconds_left()) \
		and run.tutorial_unlocked("discard")


func _swap_open() -> bool:
	return SectionMod.swap_open(cur_modifier, _seconds_left()) \
		and (phrase == null or phrase.can_swap_action()) \
		and run.tutorial_unlocked("cache")


func _blind_status() -> String:
	match cur_modifier:
		"request":
			return "点歌 · %s" % Run.request_label(phrase.request_goal)
		"lostpage":
			return "将丢 · %s" % ("?" if phrase.marked_cache_card == null \
				else phrase.marked_cache_card.label())
		"throttle":
			return "操作余 %d" % maxi(0, SectionMod.action_limit(cur_modifier) - phrase.action_count)
		"onetake":
			return "弃牌余 %d 次" % maxi(0,
				SectionMod.discard_action_limit(cur_modifier) - phrase.discard_actions_used)
		"oneswap":
			return "交换余 %d 次" % maxi(0,
				SectionMod.swap_action_limit(cur_modifier) - phrase.swap_actions_used)
		"ration":
			return "弃牌余 %d 张" % maxi(0, phrase.discard_budget - phrase.discards_used)
		"trilogy":
			return "曲目 %d/%d" % [run.section_kinds.size(),
				SectionMod.required_kinds(cur_modifier)]
		"switchtrack":
			return "选择轨道" if phrase.action_track == "" else (
				"仅可弃牌" if phrase.action_track == "discard" else "仅可交换")
		"handseal":
			return "弃牌封 · %s" % ("?" if phrase.sealed_hand_card == null \
				else phrase.sealed_hand_card.label())
		"doubleseal":
			return "手牌/缓存双封"
		"wetink":
			return "缓存锁 %d" % phrase.locked_cache_cards.size()
		"rush":
			if run.boon() == "spotlight" and phrase.spotlight_card != null:
				return "聚光 · %s" % phrase.spotlight_card.label()
			return "固定 6 秒"
	return ""


func _on_hand_sort() -> void:
	if state != St.DECISION:
		return
	phrase.sort_hand()
	hand.on_sorted()
	Tape.on("sort", {"at": elapsed})
	_action_feedback()
	_refresh()


## Hand intent: tap-select or drag-drop asked for a hand↔run.cache swap.
func _on_hand_swap(hand_i: int, cache_i: int) -> void:
	if state != St.DECISION:
		# 锁定后的操作不许静默吞掉(2026-08-12 用户「即将结算的时候就已经无法
		# 操作了」——一半体感来自这里的无声 return)。只在 RESOLVE 提示:
		# 商店/公示卡状态下手牌本来就不在台上。
		if state == St.RESOLVE:
			fx.float_text(String(DB.ui().get("hand", {}).get("deny", {})
				.get("locked", "本拍已锁定")),
				hand.card_pos(hand_i) + Vector2(30, -10), StageTheme.PINK)
		return
	if not _swap_open():
		Tape.on("deny", {"why": "blind_swap", "h": hand_i, "c": cache_i, "at": elapsed})
		fx.float_text(_deny_swap_why(), hand.card_pos(hand_i) + Vector2(30, -10), StageTheme.PINK)
		_refresh()
		return
	if phrase.swap_with_cache(hand_i, cache_i):
		Tape.on("swap", {"h": hand_i, "c": cache_i, "at": elapsed})
		_action_feedback()
	else:
		Tape.on("deny", {"why": "blind_swap", "h": hand_i, "c": cache_i, "at": elapsed})
		fx.float_text(_deny_swap_why(), hand.card_pos(hand_i) + Vector2(30, -10), StageTheme.PINK)
	_refresh()


## Central action feedback: wave blip + timing marks (Finale / Momentum read
## these — the only clock-derived joker signals, per design/jokers.md A2).
## ⚠ 名字叫 feedback, 但它**不是**表现层, 所以没跟着搬去 view/feedback.gd:
## 它写 last_action_time / acted_late, 而那两个值 _settle 要打进日志、_advance
## 要拿来判「提前完成」。真正的表现只有最后那一行。
func _action_feedback() -> void:
	if state == St.DECISION:
		last_action_time = elapsed
		if elapsed >= cur_duration - GameConfig.LATE_ACT_WINDOW:
			acted_late = true
		# 谢幕:比尾声更窄的一档(默认最后 1 秒)。⚠ 两者是**包含关系**不是互斥 ——
		# 压到最后一秒的操作同时点亮尾声与谢幕, 那是有意的(窄窗口的溢价叠在宽窗口上)。
		if elapsed >= cur_duration - GameConfig.FINAL_ACT_WINDOW:
			acted_final = true
	wave.on_action()


## 弃牌专属的时刻(早弃 earlyout 读它)。⚠ 与 `_action_feedback` 分开:
## 那个记的是「任何动作」, 而早弃问的是「**弃牌**都赶在前面了吗」——
## 交换/理牌不该弄脏这个读数。
func _note_discard_time() -> void:
	if state == St.DECISION:
		last_discard_time = elapsed


## 弃牌是**原位补牌**, 补进来的是什么必须记下来 —— 那是随机的, 事后推不出来。
## 少了它, 一拍内第一次弃牌之后的手牌就断链了, 而那正是同拍后续动作的局面。
## 调用时机:在 discard_selected() 之后, 索引位上已经是新牌。
func _refilled(sel_h: Array, sel_c: Array) -> Array:
	var out: Array = []
	for i in sel_h:
		if i >= 0 and i < phrase.hand.size() and phrase.hand[i] != null:
			out.append(phrase.hand[i].label())
	for i in sel_c:
		if i >= 0 and i < run.cache.size() and run.cache[i] != null:
			out.append(run.cache[i].label())
	return out


## A paid discard went through — feed the growth counters (vinyl, bassline).
## ⚑ **所有成功弃牌的共同出口**(跨区多选 / 单张直弃 / 拖到弃牌键三条路都过这里),
## 所以弃牌时刻记在这一处就够了 —— 记在三个调用点上必然漏一个。
func _notify_discard(n: int) -> void:
	_note_discard_time()
	for j in run.joker_slots:
		if j != null:
			j.on_discard(n)


## 弃牌被拒时的原因短语(2026-08-11 用户「为什么经常不能弃牌」):镜像 core
## can_discard 的分支顺序逐条问过去, 文案在 data/ui.json hand.deny(改文案=改 JSON),
## 代码里只留兜底 —— 拒绝必须说清是哪张脸在拒。
func _deny_discard_why(sel_h: Array, sel_c: Array) -> String:
	var d: Dictionary = DB.ui().get("hand", {}).get("deny", {})
	if not _discard_open():
		return String(d.get("window", "弃牌已关闭"))
	var lim := SectionMod.discard_action_limit(cur_modifier)
	if lim >= 0 and phrase.discard_actions_used >= lim:
		return String(d.get("onetake", "本拍已弃过"))
	var shared := SectionMod.action_limit(cur_modifier)
	if shared >= 0 and phrase.action_count >= shared:
		return String(d.get("throttle", "操作已用尽"))
	if SectionMod.exclusive_action_tracks(cur_modifier) and phrase.action_track == "swap":
		return String(d.get("track_swap", "已选交换轨"))
	if phrase.discard_budget >= 0 \
			and phrase.discards_used + sel_h.size() + sel_c.size() > phrase.discard_budget:
		return String(d.get("budget", "弃牌额度不足"))
	return String(d.get("sealed", "选中有被封的牌"))


func _deny_swap_why() -> String:
	var d: Dictionary = DB.ui().get("hand", {}).get("deny", {})
	var lim := SectionMod.swap_action_limit(cur_modifier)
	if lim >= 0 and phrase.swap_actions_used >= lim:
		return String(d.get("oneswap", "本拍已换过"))
	var shared := SectionMod.action_limit(cur_modifier)
	if shared >= 0 and phrase.action_count >= shared:
		return String(d.get("throttle", "操作已用尽"))
	if SectionMod.exclusive_action_tracks(cur_modifier) and phrase.action_track == "discard":
		return String(d.get("track_discard", "已选弃牌轨"))
	if not _swap_open():
		return String(d.get("swap_window", "交换已关闭"))
	return String(d.get("blocked", "这张换不了"))


func _on_hand_discard(sel_h: Array, sel_c: Array) -> void:
	if state != St.DECISION:
		if state == St.RESOLVE:
			fx.float_text(String(DB.ui().get("hand", {}).get("deny", {})
				.get("locked", "本拍已锁定")),
				hand.discard_key_pos() + Vector2(34, -12), StageTheme.PINK)
		return
	var total: int = sel_h.size() + sel_c.size()
	var selection_ok := phrase.can_discard_selected(sel_h, sel_c) if total > 0 else false
	if total == 0 or not _discard_open() or not selection_ok:
		hand.reject_discard()    # nothing selected, or not enough coins
		# 「想弃但弃不了」是挫败点, 也是弃牌定价的直接证据 —— 只记成交会漏掉它
		var why := "empty" if total == 0 else ("blind_discard" if not _discard_open() \
			or not selection_ok else "coins")
		Tape.on("deny", {"why": why,
			"k": total, "at": elapsed})
		# 2026-08-11 用户反馈「为什么经常不能弃牌」:键抖动只说「不行」不说「为什么」——
		# 盲注的动作限制脸(收线/一口气/岔轨/配给/封条)拒绝时必须把原因浮出来。
		if total > 0:
			fx.float_text(_deny_discard_why(sel_h, sel_c),
				hand.discard_key_pos() + Vector2(34, -12), StageTheme.PINK)
		return
	# 弃掉的是哪几张, 得在换牌之前抄下来
	var gone: Array = []
	for i in sel_h:
		gone.append(phrase.hand[i].label())
	for i in sel_c:
		gone.append(run.cache[i].label())
	if phrase.discard_selected(sel_h.duplicate(), sel_c.duplicate()):
		for i in sel_h:
			hand.ghost(i)
		Tape.on("disc", {"k": total, "h": sel_h.size(), "c": sel_c.size(),
			"cost": Economy.discard_cost(total), "coins": phrase.coins,
			"cards": gone, "got": _refilled(sel_h, sel_c), "at": elapsed})
		_notify_discard(total)
		hand.clear_selection()
		vinyl.spin_boost()
		_action_feedback()
	_refresh()


## A card was dropped straight onto the 弃牌 key -> discard just that card.
func _on_hand_single_discard(zone: String, idx: int) -> void:
	if state != St.DECISION:
		return
	var hand_sel: Array = [idx] if zone == "hand" else []
	var cache_sel: Array = [idx] if zone == "cache" else []
	if not ["hand", "cache"].has(zone):
		return
	if not _discard_open() or not phrase.can_discard_selected(hand_sel, cache_sel):
		hand.reject_discard()
		Tape.on("deny", {"why": "blind_discard",
			"k": 1, "at": elapsed})
		return
	var succeeded := false
	if zone == "hand":
		if idx >= 0 and idx < phrase.hand.size():
			var gone := phrase.hand[idx].label()
			if phrase.discard_selected([idx], []):
				hand.ghost(idx)
				Tape.on("disc", {"k": 1, "h": 1, "c": 0,
					"cost": Economy.discard_cost(1), "coins": phrase.coins,
					"cards": [gone], "got": _refilled([idx], []), "at": elapsed})
				_notify_discard(1)
				succeeded = true
	elif zone == "cache":
		if idx < 0 or idx >= run.cache.size():
			return
		var gone_c: String = run.cache[idx].label()
		if phrase.discard_selected([], [idx]):
			Tape.on("disc", {"k": 1, "h": 0, "c": 1,
				"cost": Economy.discard_cost(1), "coins": phrase.coins,
				"cards": [gone_c], "got": _refilled([], [idx]), "at": elapsed})
			_notify_discard(1)
			succeeded = true
	if succeeded:
		hand.clear_selection()
		vinyl.spin_boost()
		_action_feedback()
	else:
		Tape.on("deny", {"why": "blind_discard", "k": 1, "at": elapsed})
	_refresh()


## ---- drag & drop targets ----


# ============================== RENDER ==============================

func _refresh() -> void:
	var decide: bool = state == St.DECISION
	if state != St.RESOLVE:
		_shown_score = run.section_score
	# ⚠⚠ **必须走 `run.target()`, 不许直接索引 SECTION_TARGETS**(2026-08-09 修的真 bug):
	# 判生死走的是 `Run.target()`(乘了 `SectionMod.target_mult`), 而这里曾经读原始表 ——
	# `raisedbar`(目标 ×1.5)进池之后, HUD 会显示 4198 而实际要 6297, 进度条甚至先满、
	# 最后判失败。**同一个函数被绕过的第六次**(前五次见 LESSONS.md「模型覆盖」)。
	var target: int = run.target()
	hud.refresh({"section_idx": run.section_idx, "coins": phrase.coins,
		"score": _shown_score, "target": target, "phrase_no": run.phrase_index,
		"fraction": float(run.section_score) / float(target)})

	# 「当前牌型」读数面板已删除(用户 2026-08-05:「PAIR 100 那个区域去掉,
	# 根本不知道什么意思」)——它没有任何说明, 又和结算三段式的分数演算重复。
	# 哪五张在计分仍由手牌高亮指出。
	var best := phrase.current_best()
	var scoring_set := {}
	if not best.is_empty():
		for c in best["cards"]:
			scoring_set[c] = true
	# ⚠ 盖着的牌不许高亮「这张在计分」—— 那等于把它的身份漏出去。
	# 计分本身照常(盖牌拿走的是视野, 不是价值), 只是不告诉玩家。
	for c in phrase.hidden:
		scoring_set.erase(c)

	# hand + run.cache + keys render in view/hand.gd; assemble its view-model
	var total_sel: int = hand.selection_total()
	blind_card.set_status(_blind_status())
	var marked_cards := {}
	if phrase.marked_cache_card != null:
		marked_cards[phrase.marked_cache_card] = true
	hand.refresh({"hand": phrase.hand, "cache": run.cache, "scoring": scoring_set,
		"decide": decide, "fee": total_sel * GameConfig.DISCARD_COST,
		"can_discard_sel": total_sel > 0 and _discard_open() \
			and phrase.can_discard_selected(hand.sel_hand, hand.sel_cache),
		"can_drop": _discard_open() and phrase.can_discard(1),
		"can_swap": _swap_open(), "hidden": phrase.hidden,
		"discard_blocked_hand": phrase.discard_blocked_hand(),
		"discard_blocked_cache": phrase.discard_blocked_cache(),
		"swap_blocked_hand": phrase.swap_blocked_hand(),
		"swap_blocked_cache": phrase.swap_blocked_cache(),
		"marked_cards": marked_cards})
	vinyl.set_count(run.deck.remaining())
