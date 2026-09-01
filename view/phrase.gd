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
## CUTIN = 教学特写(v6 分镜化):RESOLVE 滚分演完后的冻钟插播(α/β)——
## elapsed 不走、时间条/音浪同停, 2.5s 自动恢复、点按跳过;只在教学关出现,
## 正式局永远进不了这个状态(触发条件带 run.tutorial)。
enum St { FRONT, INTRO, DECISION, RESOLVE, DRAFT, END, CUTIN }

# 舞台几何整块搬去了 view/layout.gd(它是装配的事);编排只读这一个 —— 结算
# 屏停留多久, 因为 _process 拿它判什么时候进下一拍。data/ui.json 仍是权威。
var RESOLVE_HOLD: float = float(DB.ui()["stage"]["resolve_hold"])

var run := Run.new()        # progression state machine (core/run.gd)
var phrase: Phrase
var state: int = St.DECISION
var elapsed := 0.0

## ---- 教学关的钟:**照常走, 不冻结**(2026-08-17 用户拍板拆掉)----
##
## ⚑ 2026-08-16 我加过「玩家第一次动手才起钟」, 依据是用户那句「你还在那倒计时,
## 不是每个人都来得及看」。**2026-08-17 试玩后他自己否了**:「开头进教学的时候,
## 要点一下才会开始走, 没必要, 直接走。」
##
## ⚠⚠ **我漏掉的那件事:冻结是看不见的。** 玩家不知道钟停着, 只看到**游戏没反应** ——
## 「给你时间」和「卡住了」在屏幕上长得一模一样, 而后者更像默认解释。
## ⇒ 一个**需要解释才成立**的贴心, 在没有解释的地方就是 bug。
##
## ⚑ 拍长统一 8 秒(2026-08-18 用户拍板「教学关也按 8 秒」—— 12/10 放宽本是
## 没有新手数据支撑的待测假设, 用户用自己的手感否了它)。读的时间靠步进兜底给。
## 冻结只是第二层保险, 它的代价(看起来卡死)比收益大。
# per-phrase timing (always taken from the GameConfig hooks — plans plug in there)
var cur_duration := 12.0
var cur_warning := 11.0
var cur_lock := 11.75

# joker slot VIEWS — the slot data itself lives on run.joker_slots
var _home: HomeScreen = null
var _menu: Control = null     # 小丑牌图鉴页(叠在首页上,z 85 > 80)
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
## 唱片位 = **待播队列**(2026-09-01 还原成光碟, 并接了新职责)。
## 空着时就是一张转着的唱片;有排队的消耗牌时, 它们以「碟」的样子并排在这儿,
## 标签上刻着自己的拍号 —— 左→右就是播放顺序。
var vinyl: VinylDeck
var _coffer: Array = []         # 本次商店货架上的消耗牌 ×2(2026-08-31:1 → 2)
var _rule_next := false         # 点唱机:下一次消耗牌货架只出规则牌
var _coffer_used := false       # 一店一张:买走就不再补
var orbit: OrbitZone
var hand: Hand
var hud: Hud
var settle_fx: SettleFx
var run_end: RunEndScreen
var banner: BlindBanner
var tutor: Widgets.TutorHint      # 教学关的一行提示;正式局整块隐身
var blind_card: Widgets.BlindCard
var _bc_home := Vector2.ZERO
## 达标即收工(2026-08-27 A 案):按下按钮 → 本拍照常打完 → _advance 时结段并落袋。
## ⚠ 不做「立刻结段」:那会吞掉玩家本拍已经做的动作与这拍的分, 而按钮是在拍中按的。
## 暂停(2026-08-27 用户:「局内没有退出按钮……左上角应该有暂停, 二级菜单可以退出或者继续」)。
## ⚠ 冻的是**钟**不是画面:_process 在暂停时不推 elapsed, 手牌照旧显示但不吃操作。
var _paused := false
var pause_btn: Button = null
var pause_layer: Control = null
var intro: BlindIntro
var music: Music             # 每段一首的 8 秒循环(view/music.gd, 2026-08-18)
var beacon: Beacon           # Tape 回传(view/beacon.gd, 1.1;配置关着时自睡)
var fx: StageFeedback        # 屏震/弹跳/飘字 —— 纯表现, view/feedback.gd
var burst: FxBurst           # A 级触发特效(预支/百搭/谢幕/规则宣告), view/fxburst.gd
var _shown_score := 0        # what the HUD prints; counts up to run.section_score
## 分数滚动还没演完(2026-08-21 评审:`resolve_hold 1.0s` < 碎片 1.5s ⇒ `_refresh` 一离开 RESOLVE 就把
## `_shown_score` 拍成终值, 滚动 tween 到点时 from == to 直接 return —— 设计稿 t=2120ms 的
## count-up 从来没演过)。现在滚动期间 `_refresh` 不抢拍, 滚完 / 被打断(商店、局末)才归位。
var _score_roll: Tween = null


## 这一次「坐下」的身份 —— `{id, gap, runs_prev}`,整个进程只取一次。
## ⚠ 必须在 `_ready` 取而不是每局取:一局一取会让 `gap` 变成「上一局到这一局」,
## 那是**局间隔**不是**会话间隔**,两者是不同的量(D4 要的是后者)。
var _sess: Dictionary = {}


func _ready() -> void:
	# ⚑ 会话边界(D4)——「隔多久回来」跨应用启动才有意义, 所以数据来自存档层。
	_sess = SaveState.session_start()
	run.reset()
	_build_ui()
	# ⚑ 断点续玩 v2(2026-08-27 用户拍板:「关掉游戏重新打开的时候应该在首页,
	# 跳一个提示是要不要继续刚才的游戏, 可以选择继续或者放弃」)——
	# 旧版是「有快照就直接回牌桌」, 那在「杀标签页」场景成立, 但在**主动退出后重开**
	# 的场景是劫持:玩家想开新局, 却被扔回上一局的残局。改成**首页 + 询问**:
	# 选择权归玩家, 两条路都明确(继续 = 回拍边界;放弃 = 清快照, 首页照常)。
	_open_home()
	if not SaveState.is_probe() and not SaveState.checkpoint().is_empty():
		_ask_resume()


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


## The front page (docs/mockups/home.html). Like the picker it holds the clock —
## _process would otherwise tick against a null phrase.
func _open_home() -> void:
	if music != null:
		music.stop_music()
	if beacon != null:
		beacon.poke()        # 一局刚收尾 = 它的日志刚写完, 正是回传的时机
	set_process(false)
	state = St.FRONT
	_front_latch = false        # 回到前端 = 新的开局会话(V3 闩锁复位)
	Tape.on("nav", {"to": "home"})
	_home = HomeScreen.new()
	_home.start_pressed.connect(_on_home_start)
	_home.menu_pressed.connect(_open_menu)
	# 分享点击打点(动作在 home:剪贴板 + 回执;事实在这记 —— 打点只在编排器, 铁律)
	_home.share_pressed.connect(func() -> void: Tape.on("share", {}))
	add_child(_home)


func _on_home_start() -> void:
	_close_menu()
	if _home != null and is_instance_valid(_home):
		_home.queue_free()
	_home = null
	start_run()


## 图鉴页(2026-08-11 实装;2026-08-24 局外删除后只剩小丑牌一页)。
## 页签轨发同一个 menu_pressed(idx),idx 0 = 回首页(首页一直活在下面,关掉覆盖层即可)。
func _open_menu(idx: int) -> void:
	_close_menu()
	if idx <= 0:
		return
	Tape.on("nav", {"to": "album"})
	_menu = AlbumScreen.new()
	_menu.menu_pressed.connect(_open_menu)
	add_child(_menu)


func _close_menu() -> void:
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null


## 闩锁(外部审查 V3):queue_free 延迟生效 + 手机多点触控 —— start 双击会二次开局
## = Tape 重开 + 重进关。同一个前端会话只放行一次;回到前端(_open_home)复位。
var _front_latch := false


## Also the entry point for tools and tests that need to skip the front-end —
## a probe can jump straight into a run with one call.
## (2026-08-24 前叫 choose_character(i):主角系统删除后开局不再有身份参数。)
func start_run() -> void:
	if _front_latch:
		return
	_front_latch = true
	# ⚠⚠ **从首页开新一局必须先重置**(2026-08-17 真人试玩报的:「教学关退回主屏幕,
	# 点开始游戏, 居然还存着之前的小丑牌」)。`run.reset()` 原本只在 `_ready()` 和
	# 「再来一次」里调 —— **「回首页再开一局」这条路径整个漏了**。
	# ⚑ 它是教学关之前就存在的洞:以前没有「打完一局自己回首页」的出口, 所以没人撞到。
	# ⚠ 走 `_reset_run` 而不是裸 `run.reset()` —— 后者只清 Run 的状态, **不清槽位视图**,
	# 那样数据干净了但屏幕上还挂着旧卡面(比不重置更难查)。
	_reset_run(false)
	_close_menu()
	if _home != null and is_instance_valid(_home):
		_home.queue_free()
	_home = null
	_ensure_pause_ui()
	# ⚑ 教学关:**只在第一次启动时出现一次**(用户 2026-08-07 拍板「教学只要一次」)。
	# 判据存在 `SaveState`(`user://`), 与将来的断点续玩共用同一个存档层。
	# ⚠⚠ **必须在 roll_faces 之前设** —— 教学关不掷 Boss 脸(见 Run.roll_faces),
	# 而「起」按定义就是**安全的地方、无惩罚地理解机制**。顺序写反了截图里就会
	# 挂着一张「禁回」, 我第一版正是这么错的。
	run.tutorial = not SaveState.seen_tutorial()
	# ⚑ **游戏是唯一传真实局数的地方**(探针一律走缺省 = 全解锁, 理由在 SectionMod.unlocked_at)。
	# ⚠ `+1` 是因为掷脸发生在 `note_run_started()` **之前** —— 存档里的 `runs_total`
	# 此刻还是「以前玩过几局」, 而这一局是第 `runs_total + 1` 局。
	if not _begin_run():
		_deny_no_energy()   # 体力不足(2026-08-26 真闸门):不开局, 回首页 + 浮字
		return
	# 打点从这里开流 —— 四面墙定了, 这一局的初始条件已经完整
	# ⚠⚠ 教学关**照样打点, 但必须打上标记**:它是一局假局(6 拍、目标分 0、不判生死),
	# 混进 Tape 会污染 `tools/probbook.py` 的「合格真人局」分拣。
	# 不干脆不打点, 是因为 docs/design/difficulty.md §4 明写着要量的东西正在这里 ——
	# **新手的动作时刻分布**(12 秒够不够), 而那正是现有 Tape 全是熟练玩家所以缺的那一块。
	# ⚑ 会话边界(D4)——「一次坐下玩几局 / 隔多久回来」。目标函数换成留存之后,
	# **这是唯一能直接观测目标的量**。它跨局, 而 Tape 一局一个文件, 所以只能进 meta。
	Tape.begin({
		"sess": _sess,
		"tutorial": run.tutorial,
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
	_bc_home = blind_card.position   # 商店停靠(见 _open_draft)与还原共用的初始位
	vinyl = n["vinyl"]
	orbit = n["orbit"]
	hand = n["hand"]
	shop = n["shop"]
	settle_fx = n["settle_fx"]
	run_end = n["run_end"]
	banner = n["banner"]
	tutor = n["tutor"]
	intro = n["intro"]
	music = Music.new()
	add_child(music)
	beacon = Beacon.new()   # Tape 回传(1.1;缺省配置下自睡, 见 view/beacon.gd)
	add_child(beacon)

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
	shop.consumable_bought.connect(_on_consumable_bought)
	settle_fx.burst_started.connect(_on_settle_burst)
	run_end.next_pressed.connect(_on_end_next)
	run_end.retry_pressed.connect(_on_end_retry)
	run_end.home_pressed.connect(_on_end_home)
	intro.done.connect(_on_intro_done)

	fx = StageFeedback.new(self)
	add_child(fx)
	# 替换态的两个部件挂在最上层:选槽时商店已经关了, 它们要盖住小丑牌行以外的一切
	replace = ReplaceFlow.new(self, joker_views)
	# ⚠ 必须连在构造**之后** —— 第一版插进了 _build_ui 的信号块(那时 replace 还是 null),
	# 整个 _ready 当场断掉, headless 套件测不到 view, 是截图探针抓到的。
	replace.canceled.connect(_on_replace_canceled)
	# 教学特写的手势面(v6):插播期铺满全屏吃点击 = 「点按跳过」(intro 同手势)。
	# 平时隐身不吃事件;β 的 +N◆ 定格标签也挂在它上面(要盖住压暗层, 所以在最上)。
	_cutin_catch = Control.new()
	_cutin_catch.position = Vector2.ZERO
	_cutin_catch.size = Vector2(720, 1280)
	_cutin_catch.visible = false
	_cutin_catch.z_index = 60
	_cutin_catch.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_end_cutin())
	add_child(_cutin_catch)
	# A 级触发特效层(2026-08-27, 设计稿 docs/mockups/fx/)。**最后 add_child + z 100** ——
	# 规则宣告与超级百搭的仪式发生在**商店开着**的时候, 不盖在货架上面就等于没演。
	# 它不吃点击(IGNORE), 仪式不许抢走玩家那一拍。
	burst = FxBurst.new()
	add_child(burst)


# ============================== FLOW ==============================

## Shop-less section entries (run start / retry) open with the standalone
## blind card; the phrase clock holds until it dismisses. Sections behind a
## shop are announced on the shop's blind board instead, and mid-section
## phrases go straight to _start_phrase().
func _enter_section() -> void:
	# ⚠⚠ **教学关不弹盲注公示卡**(2026-08-17 试玩抓到)。它不掷脸、目标分恒 0,
	# 弹出来就是一张「小酒吧 · 目标分 0 · BOSS 墙」的空卡 —— 而教学关的第一印象
	# 应该是**直接开始玩**, 不是先读一张说明书。
	# ⚑ 这条闸和 `Run.face()`/`target()` 里那两道同源:**教学关的每一个「正式局才有的
	# 东西」都要显式挡一次**, 靠调用顺序约定挡不住(那条契约我自己一小时内违反过)。
	if run.tutorial:
		_tape_section()
		_start_phrase()
		return
	# ⚑ 公示卡(BlindIntro)2026-08-18 从流程退役 —— 盲注特写接任公示:
	# 「进场的时候以及每次更换盲注的时候, 盲注特写一下, 2 秒钟」(用户原话)。
	# 特写挂在 _start_phrase 的「段首拍」分支上, 开局/重开/段间三条路自然全覆盖。
	_tape_section()
	_start_phrase()


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


## 盲注特写(2026-08-18 用户:「一边翻转一边移到屏幕中间放大」, 定长 2 秒)。
## 动的是 blind_card **真身** —— 副本和本体迟早字对不上。期间 state=INTRO:
## 钟不走、手牌不吃点击, 与旧公示卡同一道闸。0.5s 飞入(|cos| 翻面)+ 1.1s 定格 + 0.4s 归位。
## 开局亮整局(2026-08-25 定案):特写期间在卡下方亮出四场路线 ——
## 调度/换阵解法的前提、公平性的承重墙(先定型后遇敌的解)。脸是开局掷定的, 只差公示。
var _route_label: Label = null


func _route_text() -> String:
	var names: Array = []
	for w in GameConfig.WALL_SECTIONS:
		var fid := String(run.run_faces.get(int(w), ""))
		if fid == "":
			names.append(Lingo.t("纯分数"))
		else:
			var m := SectionMod.by_id(fid)
			names.append(m.cn_name if m != null else fid)
	return Lingo.t("巡演路线 · %s") % " → ".join(PackedStringArray(names))


func _play_blind_closeup() -> void:
	state = St.INTRO
	if _route_label == null:
		_route_label = StageTheme.label("", StageTheme.zh(), 15,
			StageTheme.rim(0.72), HORIZONTAL_ALIGNMENT_CENTER)
		_route_label.position = Vector2(0, 812)
		_route_label.size = Vector2(720, 24)
		_route_label.z_index = 209
		add_child(_route_label)
	_route_label.text = _route_text()
	_route_label.visible = not run.tutorial
	# ⚠ 状态一变就要刷组件快照(hand 的 decide 是快照不是活查询):
	# 教学第 4 轮的特写在 _start_phrase 中途触发, 其后的 _refresh 在 INTRO 下把手牌
	# 禁用了一整拍 —— 用户:「特写后无法操作, 等到下一轮才能动」。起止各刷一次。
	_refresh()
	Tape.on("intro", {"closeup": true})
	var home: Vector2 = blind_card.position
	var hz: int = blind_card.z_index
	blind_card.z_index = 210
	blind_card.pivot_offset = blind_card.size * 0.5
	var center: Vector2 = Vector2(360.0, 600.0) - blind_card.size * 0.5
	var tw := create_tween()
	var leg := tw.tween_method(_closeup_fly.bind(home, center, true), 0.0, 1.0, 0.5)
	leg.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.1)
	leg = tw.tween_method(_closeup_fly.bind(center, home, false), 1.0, 0.0, 0.4)
	leg.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(_closeup_done.bind(home, hz))


func _closeup_done(home: Vector2, hz: int) -> void:
	if _route_label != null:
		_route_label.visible = false
	blind_card.z_index = hz
	blind_card.scale = Vector2.ONE
	blind_card.position = home
	if state == St.INTRO:
		state = St.DECISION      # 钟从这一刻才开始走(elapsed 已在 _start_phrase 归零)
		_refresh()               # 把 hand 的 decide 快照刷回可操作(卡死 bug 的另一半)
		music.sync_beat()        # 特写恰好 2.0s = 1 小节, 但 tween 有帧抖动 ⇒ 显式归零



## t 在 a_pos→b_pos 间插值飞行;flip=true 时 x 轴按 |cos| 做一次翻面(卡牌翻面同一 idiom)。
## 去程 t 0→1、回程 t 1→0 共用同一条几何, 不抄第二份。
func _closeup_fly(t: float, a_pos: Vector2, b_pos: Vector2, flip: bool) -> void:
	var k: float = t if flip else (1.0 - t)
	blind_card.position = a_pos.lerp(b_pos, k)
	var s: float = lerpf(1.0, 2.4, t)
	blind_card.scale = Vector2(s * (absf(cos(PI * t)) if flip else 1.0), s)


## γ 特写(v6, 一次性):教学毕转正式局的第一次段首, 开局公示卡多带一行盲注课 ——
## 「每场演出有一张盲注」+ 高光盲注板(view/intro.gd::set_tutor)。在 _start_phrase
## **末尾**触发(牌已发好), 期间 state=INTRO 钟不走;收卡 = _on_intro_done 恢复本拍,
## **不再重进 _start_phrase**(那会二次发牌)。放完即销存档旗, 从此回到盲注特写。
func _play_gamma_intro() -> void:
	state = St.INTRO
	_refresh()   # hand 的 decide 是快照:进 INTRO 要刷一次(特写卡死 bug 的同款教训)
	var c := Tutorial.cutin("gamma")
	intro.open(run.section_idx, run.target(),
		SectionMod.by_id(cur_modifier), BlindBoon.by_id(run.boon()))
	intro.set_tutor(String(c.get("command", "")), float(c.get("seconds", 4.0)))
	SaveState.mark_tutor_gamma_done()
	Tape.on("intro", {"gamma": true})


func _on_intro_done() -> void:
	if state == St.INTRO:
		# 主动点掉 vs 等它自己走完 —— 「急着打」和「在读盲注规则」是两回事。
		Tape.on("intro", {"skip": intro != null and intro.skipped})
		# ⚑ 公示卡现在开在 _start_phrase **之后**(γ 路径, 牌已在桌上), 所以这里只
		# **恢复本拍**:钟起步 + 快照刷回可操作 + 下拍归零(_closeup_done 同一套收尾)。
		# 旧写法 `_start_phrase()` 是公示卡还开在拍前的年代留下的 —— 现在会二次发牌。
		state = St.DECISION
		_refresh()
		music.sync_beat()


func _start_phrase() -> void:
	blind_card.position = _bc_home   # 商店停靠位还原(_open_draft 挪的)
	blind_card.z_index = 0
	# 拍与拍之间的钱记在 run 上, 一拍之内归 Phrase 管(弃牌与入场费都在那里扣)。
	# ⚠ 这一行不能省:商店是在**两拍之间**动钱的, 不同步回去 Beat 就会拿旧余额发牌。
	# ⚠ phrase == null 时**不动 run.coins**(2026-08-24 断点续玩):开局的起始金币由
	# `Run.reset()` 给, 恢复的余额由 `Run.restore()` 给 —— 这里再拍 STARTING_COINS
	# 会把恢复的钱包静默清成初始值。
	if phrase != null:
		run.coins = phrase.coins
	# boss faces are rolled for the whole run up front and PREVIEWED one
	# section ahead (Balatro shows the upcoming boss — the preview is what
	# turns a face from an execution into a routing decision)
	if run.phrase_in_section == 0:
		cur_modifier = run.face()
		var m := SectionMod.by_id(cur_modifier)
		var nxt := SectionMod.by_id(String(run.run_faces.get(run.section_idx + 1, "")))
		blind_card.setup(run.section_idx, m, nxt, BlindBoon.by_id(run.boon()))
		blind_card.roll_note = _roll_note()
		# ⚠ 教学关没有脸 ⇒ 盲注卡整块隐藏。不隐藏会留下一个**只剩 "BOSS" 边框的空壳**,
		# 那比没有更糟:玩家会以为这一关有个规则而他没看懂。(截图看出来的)
		blind_card.visible = not run.tutorial
	# ⚑ 断点快照:拍边界、发牌**之前**(2026-08-24)—— 恢复时从同一副堆序重发,
	# 玩家拿回同一手牌。教学关不存(6 拍重来更干净);探针闸在 SaveState 里。
	if not run.tutorial:
		SaveState.save_checkpoint(run.snapshot(_run_index))
	# 规则全在这一句里:解析脸 → 发牌(缓存容量在 start() 生效)→ 收入场费 → 推进计数器。
	# 这三样曾经在六个文件里各写一遍, 而入场费那份我一度还判断错了它有没有用(docs/design/tech.md)。
	phrase = Beat.begin(run)
	# ⚑ 到点的消耗牌在这里自己打 —— **必须在 `Beat.begin` 之后**(它要并进本拍加成),
	# **在决策之前**(玩家看到的分数预览必须已经含它)。
	_fire_due_consumables()
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
	_apply_tutor_hint()
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
	# 盲注特写:段首拍(开局 + 每次换盲注)。教学关与探针不进 ——
	# 教学关无脸无目标是空卡;探针的帧预算不该为纯表现买单。
	# ⚑ 特写期间 state=INTRO ⇒ **8 秒的钟不走**(用户:「特写的 2 秒不要跑那个 8 秒节奏」),
	# _process 只在 DECISION 计时, elapsed 在特写收尾才开始累加。
	if run.phrase_in_section == 0:
		music.play_section(run.section_idx)   # 每关一首(探针在 Music 里自静音)
	if run.phrase_in_section == 0 and not run.tutorial and not SaveState.is_probe():
		# γ 特写(v6, 一次性):教学刚完成后的第一次正式段首, 开局公示卡替代盲注特写 ——
		# 卡上多一行「每场演出有一张盲注」+ 高光盲注板;存档旗保证只此一次, 之后回特写。
		if SaveState.tutor_gamma_due():
			_play_gamma_intro()
		else:
			_play_blind_closeup()
	# 拍首下拍:钟起步的那一刻 kick 归零(Music.sync_beat 文件内有整套推导)。
	# 特写路径除外 —— 那 2 秒 state=INTRO 钟不走, kick 由 _closeup_done 落。
	if state == St.DECISION:
		music.sync_beat()


## 教学关的一行提示 + 分镜构图(v6)。抽成函数是为了**拍中推进后立刻重放**
## (2026-08-18 用户:「应该消失, 进入下一个提示」)。正式局 hint 空串 ⇒ 整块隐身。
## ⚑ 分镜(shot)= 高光构图(focus)+ 文字条锚位(_tutor_anchor)—— 同 shot 的步
## 镜头与条都不动, 只换词;`spot` 是随步走的次级强调(光斑)。
func _apply_tutor_hint() -> void:
	# ⚠ 区域名 → 矩形的翻译在**编排器**这一侧:`core/` 不认识像素(坐标归 ui.json)。
	var h := run.tutorial_hint()
	var rects: Array = []
	var spot := Rect2()
	var anchor := -1.0
	if run.tutorial:
		for name in Tutorial.focus(run.tutorial_step):
			var q := _tutor_rect(String(name))
			if q.size.x > 0.0:
				rects.append(q)
		var sp := Tutorial.spot(run.tutorial_step)
		if sp != "":
			spot = _tutor_rect(sp)
		anchor = _tutor_anchor(Tutorial.shot(run.tutorial_step))
	# ⚑ 把**全部**可高亮区域喂给提示条, 让它自己躲开(分镜给了锚位时锚位优先)。
	# 屏幕下半部三块区域占满, 硬贴高亮区必然压住别的字(第一版就是这么糊的)。
	var avoid: Array = []
	if run.tutorial:
		for rn in Tutorial.regions():
			var aq := hand.focus_rect(rn)
			if aq.size.x > 0.0:
				# ⚠ 往上放宽 44px —— 「手 牌 区」「缓 存 区」那两个标签画在**容器矩形之外**
				# (上方 ~35px), 只躲容器会让条正好压住标签。**可高亮区 ≠ 它的视觉范围**
				# —— 同 docs/design/ui_meta.md 那句「对齐类反馈要查视觉顶端而不是几何顶端」。
				avoid.append(Rect2(aq.position - Vector2(0, 44), aq.size + Vector2(0, 44)))
		# 手牌框(走圈轨道)整块入避让表(2026-08-24 用户:「教学文字高度不对, 会挡住
		# 读秒的进度条光圈」);往上放宽 20px —— 轨道辉光超出几何边。
		avoid.append(Rect2(orbit.position - Vector2(0.0, 20.0),
			orbit.size + Vector2(0.0, 20.0)))
	# ⚑ 压暗层的常亮洞(2026-08-24 用户两条:「倒计时边框也应该在教学的时候被看到」·
	# 「展示小丑牌的时候, 下方整个版面是黑的」):**手牌框顶起往下的整个操作面**
	# (倒计时边框/节拍菱形/读秒/手牌/缓存/理牌弃牌键)+ 顶栏, 教学期间永远不压暗。
	# ⚑ v6:focus 为空 = **全景分镜(C 拍)** —— 高光全撤, 压暗层整层隐身, 洞也不用给。
	var holes: Array = []
	if run.tutorial and not rects.is_empty():
		holes.append(Rect2(0.0, orbit.position.y, 720.0, 1280.0 - orbit.position.y))
		var hp: Array = DB.ui()["hud"]["pos"]
		var hs: Array = DB.ui()["hud"]["size"]
		holes.append(Rect2(float(hp[0]), float(hp[1]), float(hs[0]), float(hs[1])))
	tutor.set_hint(String(h["command"]), String(h["signal"]), rects, avoid, holes,
		anchor, spot)
	# 能力全程全开(用户拍板「取消全部能力压制」;unlock 第一步即全解锁)。
	# ⚠ 组件不认识教学关(铁律:组件只发意图, 状态由编排器给), 所以这里翻译成
	# 它听得懂的话:`multi_select`。正式局恒 true, 教学关第一步起也恒 true。
	hand.multi_select = run.tutorial_unlocked("multiselect")


## 区域名 → 全屏矩形(教学 focus/spot/特写共用这一份翻译)。
## ⚑ 矩形从**活部件**取, 不读 ui.json 的手抄坐标(`Hand.focus_rect` 文件头:手抄的
## 第二份必然漂)。`ui.json` 的 `tutor_focus` 只剩「合法区域名白名单」一个职责。
func _tutor_rect(name: String) -> Rect2:
	match name:
		"hud":
			var hp: Array = DB.ui()["hud"]["pos"]
			var hs: Array = DB.ui()["hud"]["size"]
			return Rect2(float(hp[0]), float(hp[1]), float(hs[0]), float(hs[1]))
		"coins":
			# 金币 chip(β 特写):从活 Label 取, 放宽一圈让光圈不贴字
			return Rect2(hud.coin_anchor(), hud.coin_label.size).grow(10.0)
		"blind":
			return Rect2(blind_card.position, blind_card.size)
		"jokers":
			var q := Rect2(joker_views[0].position, joker_views[0].size)
			for jv in joker_views:
				q = q.merge(Rect2(jv.position, jv.size))
			return q
		"shelf":
			# 商店货架价签行(D 分镜)—— shop 铺满全屏, 局部坐标即全屏坐标
			return shop.price_row_rect().grow(6.0)
	return hand.focus_rect(name)


## 分镜的条锚位(v6:「分镜 = 高光构图 + 文字条锚位」)。返回 -1 = 走自动逻辑。
## A = 手牌区上方(手牌框辉光之上);B = 手牌与缓存行间(两拍不动);
## C/其他 = 自动(C 无高亮, 条落回默认空带);D 的锚在商店里, 由 _open_draft 算。
func _tutor_anchor(shot: String) -> float:
	var bh: float = Widgets.TutorHint.BAR.size.y
	match shot:
		"A":
			return orbit.position.y - 20.0 - 12.0 - bh
		"B":
			var top: float = orbit.position.y + orbit.size.y
			var bot: float = hand.focus_rect("cache").position.y
			return top + maxf(0.0, (bot - top - bh) * 0.5)
	return -1.0


## 本局是第几局(1 起)。探针恒 1 且喂空排序 —— 探针世界的掷法逐字节不变。
var _run_index := 1


## 给 Director 喂数(2026-08-18 用户拍板「director 是必须的」):
## 脸排序来自 data/ranking.json(tools/price.gd 的仪器输出, DB 校验四段齐全)。
## 探针喂空 {} ⇒ roll_run 逐字节退回旧掷法(director.gd 的承诺), 仪器复现性不漂。
func _feed_director() -> void:
	run.face_ranking = {} if SaveState.is_probe() else DB.ranking_tiers()
	# 玩家状态 m 的切片(2026-08-19「基于 context 生成关卡」):连胜/连败 + 见过的脸。
	# 探针恒空 ⇒ 掷法逐字节不变(min_run 同一条先例)。
	run.director_ctx = {} if SaveState.is_probe() \
		else {"streak": SaveState.streak(), "seen": SaveState.faces_seen(),
			"boons_seen": SaveState.boons_seen(),
			"returning": SaveState.returning_run()}

## (教学盲注样例 `_stage_tutor_props` 已删 2026-08-27, v6 分镜化:盲注这一课整个
## 搬去了 γ 特写 —— 教学毕转正式局的**第一次开局公示卡**上讲「每场演出有一张盲注」,
## 高光的就是真的盲注板, 登场时刻自带上下文;教学关内盲注卡保持隐藏, 不再摆样例脸。)


## 编排器报教学动作 + **拍中回执**:做完动作提示当场收掉(08-18「应该消失」拍板),
## 但**步进等结算**(2026-08-24 用户:「换一下之后立刻就跳到小丑牌了 ——
## 应该等结算完了再到小丑牌」)。下一步的内容属于下一拍;拍中只把这一步的提示
## 熄掉当回执, 高亮一起收(画面回正常), 结算后 `_start_phrase` 才上下一课。
func _note_tutorial(action: String) -> void:
	run.tutorial_note(action)
	if run.tutorial and Tutorial.require(run.tutorial_step) != "" \
			and run.tutorial_pending() == "":
		tutor.set_hint("", "")


## ---- 教学特写 α/β(v6 分镜化):RESOLVE 滚分后的冻钟插播 ----
## 冻钟只在教学关:state=CUTIN 时 _process 不累加 elapsed(时间条静止), 音浪/均衡器
## set_process(false) 同停;seconds 秒自动恢复, 期间点按跳过(_cutin_catch, intro 同手势)。
## 动作拍(2/3/4)不插播 —— after_step 只挂在 0(A 拍末)与 1(B 首拍末)。
var _cutins_played: Dictionary = {}
var _cutin_key := ""
var _cutin_auto: Tween = null
var _cutin_catch: Control = null
var _cutin_tag: Label = null      # β 的 +N◆ 定格
var _last_gain_coins := 0


## 这一拍末欠哪场插播("" = 没有)。γ 不在这里 —— 它长在转正式的公示卡上, 按名字分流。
## ⚠ 探针不插播(盲注特写同一条:帧预算不为纯表现买单);截图探针直接调 _begin_cutin。
func _cutin_due_key() -> String:
	if not run.tutorial or SaveState.is_probe():
		return ""
	for key in ["alpha", "beta"]:
		if _cutins_played.has(key):
			continue
		var c := Tutorial.cutin(String(key))
		if not c.is_empty() and int(c["after_step"]) == run.tutorial_step:
			return String(key)
	return ""


func _begin_cutin(key: String) -> void:
	_cutins_played[key] = true
	_cutin_key = key
	state = St.CUTIN
	var c := Tutorial.cutin(key)
	var rects: Array = []
	for name in c.get("focus", []):
		var q := _tutor_rect(String(name))
		if q.size.x > 0.0:
			rects.append(q)
	# 高光切到特写的 focus:不给常亮洞 —— 冻结期玩家动不了手, 全场只留这一块亮,
	# 这就是「切镜头」。条位走自动逻辑(贴着高亮区, 顶上放不下翻到下方)。
	tutor.set_hint(String(c.get("command", "")), "", rects, [], [])
	wave.set_process(false)
	eq.set_process(false)
	if key == "beta":
		# +N◆ 飘字定格:结算时的入账反馈是 0.8s 的飘字, 特写要把它按在原地讲一句 ——
		# 挂在手势面上(盖住压暗层), 结束一起收。
		_cutin_tag = StageTheme.label("+%d ◆" % _last_gain_coins,
			StageTheme.num("Bold"), 30, StageTheme.GOLD)
		# 挂在金币 chip 正下方、PHRASE 行之下(+42 会压到 PHRASE 字样, 截图对账抓的)
		_cutin_tag.position = hud.coin_anchor() + Vector2(16.0, 64.0)
		_cutin_catch.add_child(_cutin_tag)
	_cutin_catch.visible = true
	_cutin_auto = create_tween()
	_cutin_auto.tween_interval(maxf(0.5, float(c.get("seconds", 2.5))))
	_cutin_auto.tween_callback(_end_cutin)


func _end_cutin() -> void:
	if state != St.CUTIN:
		return
	if _cutin_auto != null and _cutin_auto.is_valid():
		_cutin_auto.kill()
	_cutin_auto = null
	_cutin_catch.visible = false
	if _cutin_tag != null and is_instance_valid(_cutin_tag):
		_cutin_tag.queue_free()
	_cutin_tag = null
	wave.set_process(true)
	eq.set_process(true)
	Tape.on("cutin", {"k": _cutin_key})
	_cutin_key = ""
	state = St.RESOLVE
	_advance()


func _process(delta: float) -> void:
	if _paused:
		return          # 钟停在原地 —— 暂停不该偷走玩家的秒数
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
			# final-seconds heartbeat: eq curtain reddens/speeds, each countdown
			# second kicks the wave and spins the record up toward the drop
			eq.urgency = clampf((elapsed - cur_warning) / maxf(cur_lock - cur_warning, 0.1), 0.0, 1.0) if warn else 0.0
			if warn:
				var d := int(ceil(cur_lock - elapsed))
				if d != _last_warn_digit:
					_last_warn_digit = d
					wave.on_action()
			if elapsed >= cur_lock:
				_settle()
		St.RESOLVE:
			elapsed += delta
			orbit.set_progress(1.0, false)
			eq.urgency = 0.0
			if elapsed >= RESOLVE_HOLD:
				# 教学特写(v6):挂在**滚分演完之后** —— α/β 讲的正是刚滚完的那个数字,
				# 滚动没完就再等一帧(教学关的 RESOLVE 因此可以比 1s 长, 正式局零改)。
				var ck := _cutin_due_key()
				if ck == "":
					_advance()
				elif not _rolling():
					_begin_cutin(ck)


func _settle() -> void:
	# ⚠ 2026-08-07: 这一拍的规则部分整个搬进了 `Core/Beat`(docs/design/tech.md)——
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
	_last_gain_coins = gained_coins   # β 特写的 +N◆ 定格读它(只在教学关消费)
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
		hud.score_anchor() + Vector2(24, 26), int(outcome.get("bonus", 0)),
		float(outcome.get("pattern_mult", 0.0)), float(outcome.get("joker_mult", 1.0)),
		float(outcome.get("bonus_pct", 0.0)), int(res.get("kind", -1)))
	# the merge beat lands at 450ms: shake the screen and kick the wave then
	var merge_tw := create_tween()
	merge_tw.tween_interval(0.45)
	merge_tw.tween_callback(func() -> void:
		fx.shake(9.0)
		wave.on_score(float(gained_score) / 80.0)
		# 牌型金币入账反馈(journey #3, 经济 v2 主收入):+N◆ 跟合拍一起落地,
		# 而不是结算瞬间 —— 同帧出手会被 base×mult 的大动画淹掉, 审计里那句
		# 「金币悄悄进 HUD 数字」正是这个形状。金币 chip 同拍脉冲一次,
		# 数字跳动与飘字互相佐证「大牌 = 多钱」。打点不加:入账已是事实记录。
		if gained_coins > 0:
			fx.float_text("+%d ◆" % gained_coins,
				hud.coin_anchor() + Vector2(20, 40), StageTheme.GOLD)
			fx.pop(hud.coin_label))
	# joker triggers pop over their slots, staggered
	var popups: Array = outcome["popups"]
	for k in range(popups.size()):
		var p: Dictionary = popups[k]
		var slot_view: Control = joker_views[p["slot"]]
		var at: Vector2 = slot_view.get_global_position() + Vector2(slot_view.size.x * 0.28, -6.0)
		var tw := create_tween()
		tw.tween_interval(0.30 + 0.22 * float(k))
		tw.tween_callback(fx.float_text.bind(String(p["text"]), at, StageTheme.GOLD))


## Shards have launched — start rolling the score up to meet them.
func _on_settle_burst() -> void:
	var from := _shown_score
	var to := run.section_score
	if to == from:
		return
	if _score_roll != null and _score_roll.is_valid():
		_score_roll.kill()
	_score_roll = create_tween()
	_score_roll.tween_interval(0.62)
	_score_roll.tween_method(func(v: float) -> void:
			_shown_score = int(round(v))
			hud.set_score_text(_shown_score),
		float(from), float(to), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_score_roll.tween_callback(func() -> void:
			_score_roll = null
			_refresh())


## ⚠⚠ **主动收工整块退役**(2026-08-31 用户:「不要提前结束的机制了。我玩起来也不用」)：
## `early_settle()` · `_can_early_lock()` · `_on_vinyl_tapped()` · 收工键 · 落袋经济。
## ⚑ 早收**没消失**, 它变成纯被动判据(见 `_acted_early`)—— 四张时机卡照常活着。

## 收工键(2026-08-27 A 案):段分达标才现身, 写明能落袋多少 ——
## 与唱片(单拍提前结算)**语义分开**:唱片结这一拍, 它结这一段。
## 位置贴盲注卡下方(它讲「你在打什么」, 收工是对这一段的处置)。
## 暂停键 + 二级菜单(继续 / 退出本局)。键叠在 HUD 左上角;菜单是全屏层。
## 退出 = **放弃本局**:清快照、不记战绩(体力已在开局扣过, 成本已付), 回首页。
func _ensure_pause_ui() -> void:
	if pause_btn != null:
		return
	pause_btn = Button.new()
	pause_btn.text = "❚❚"
	pause_btn.add_theme_font_size_override("font_size", 15)
	pause_btn.focus_mode = Control.FOCUS_NONE
	var pb := StageTheme.box(Color(0.05, 0.06, 0.13, 0.88), StageTheme.rim(0.5), 1, 9)
	for st in ["normal", "hover", "pressed"]:
		pause_btn.add_theme_stylebox_override(st, pb)
	pause_btn.add_theme_color_override("font_color", Color("aab6dd"))
	pause_btn.position = Vector2(6, 6)
	pause_btn.size = Vector2(34, 30)
	pause_btn.z_index = 70
	pause_btn.pressed.connect(_on_pause)
	add_child(pause_btn)

	pause_layer = Control.new()
	# ⚠ 显式 720×1280, 不用 anchors preset:编排器根节点没有 size, FULL_RECT 撑不开
	# (第一版就是这样 —— `visible=true` 但整层零尺寸, 截图里什么都没有)。
	pause_layer.position = Vector2.ZERO
	pause_layer.size = Vector2(720, 1280)
	pause_layer.z_index = 120
	pause_layer.visible = false
	pause_layer.mouse_filter = Control.MOUSE_FILTER_STOP   # 吃掉底下的一切点击
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0.02, 0.72)
	dim.size = Vector2(720, 1280)
	pause_layer.add_child(dim)
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel",
		StageTheme.box(Color(0.04, 0.05, 0.12, 0.96), StageTheme.CYAN, 1, 16))
	panel.position = Vector2(170, 470)
	panel.size = Vector2(380, 230)
	pause_layer.add_child(panel)
	var title := StageTheme.label(Lingo.t("暂停"), StageTheme.zh(), 26,
		StageTheme.CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(170, 492)
	title.size = Vector2(380, 34)
	pause_layer.add_child(title)
	var resume := Button.new()
	resume.text = Lingo.t("继续 ▸")
	resume.add_theme_font_override("font", StageTheme.zh())
	resume.add_theme_font_size_override("font_size", 19)
	resume.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed"]:
		resume.add_theme_stylebox_override(st,
			StageTheme.box(Color(0.06, 0.16, 0.20, 0.95), StageTheme.CYAN, 1, 12))
	resume.add_theme_color_override("font_color", Color("cdf7f2"))
	resume.position = Vector2(206, 552)
	resume.size = Vector2(308, 46)
	resume.pressed.connect(_on_resume)
	pause_layer.add_child(resume)
	var quit_b := Button.new()
	quit_b.text = Lingo.t("退出本局(不计战绩)")
	quit_b.add_theme_font_override("font", StageTheme.zh())
	quit_b.add_theme_font_size_override("font_size", 17)
	quit_b.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed"]:
		quit_b.add_theme_stylebox_override(st,
			StageTheme.box(Color(0.20, 0.06, 0.10, 0.95), Color("ff5f7e"), 1, 12))
	quit_b.add_theme_color_override("font_color", Color("ffc3cf"))
	quit_b.position = Vector2(206, 612)
	quit_b.size = Vector2(308, 44)
	quit_b.pressed.connect(_on_quit_run)
	pause_layer.add_child(quit_b)
	add_child(pause_layer)


func _on_pause() -> void:
	# 只在真正「在打」的时候可暂停:商店/结算屏/首页自带停顿, 再叠一层只会打架。
	if _paused or not [St.DECISION, St.RESOLVE, St.INTRO].has(state):
		return
	_paused = true
	pause_layer.visible = true
	Tape.on("pause", {"at": elapsed, "sec": run.section_idx})


func _on_resume() -> void:
	_paused = false
	pause_layer.visible = false


## 退出本局:清快照 + 不记战绩 + 回首页(体力已在开局扣过 —— 成本已付, 不二次惩罚)。
func _on_quit_run() -> void:
	_paused = false
	pause_layer.visible = false
	Tape.on("nav", {"to": "quit"})
	Tape.close({"ok": false, "sec": run.section_idx, "score": run.section_score,
		"target": run.target(), "beats": run.phrase_index, "why": "quit"})
	Tape.flush()
	SaveState.clear_checkpoint()
	_reset_run(false)
	_open_home()


## 买下货架上那张消耗牌。**经济动作只发生在编排器** —— 扣钱、执行、打点都在这里。
##
## ⚑⚑ **2026-09-01:消耗牌全部自动触发, 「点一下」这个动作整个没了。**
## 用户原话:「现在玩起来有点怪, 比如那个塞 4 张万能卡, 还要自己点一下才生效,
## 完全不用点」。⇒ `fire: "buy"` 的 13 张**买下这一刻就执行**(它们改的是牌堆或这次
## 商店, 没有「哪一拍」可选);其余 4 张排进待播队列, 到自己的拍号自己打。
## ⚠ 栏位满的拒绝分支一并删除 —— 队列没有硬上限(理由见 `Run.consumables`)。
func _on_consumable_bought(c, price: int) -> void:
	phrase.coins -= price
	run.coins = phrase.coins
	var used: Dictionary = run.take_consumable(c)
	Tape.on("cbuy", {"id": c.id, "price": price, "coins": phrase.coins})
	if not used.is_empty():
		_apply_consumable(used, "buy")
	# ⚑⚑ **5 选 1**(2026-08-31 用户拍板):3 张小丑 + 2 张消耗是**同一个池子**,
	# 一次进店只成交 **1 张** —— 消耗牌不再有专属名额, 它和小丑牌**抢同一次购买**。
	# ⚠ 这是**收紧**:此前消耗牌每店白送一格, 而这一层实测值 +18.8pt 通关率。
	# ⚠⚠ 所以计数走**同一个 `_shop_buys`** —— 分开数就等于又给了它一个专属名额,
	# 那正是 2026-08-29 修过的形状(「奖励某件事的东西不能和那件事抢同一个资源」的反面:
	# 这里要的恰恰是**让它们抢**)。
	_shop_buys += 1
	_coffer_used = true
	var buy_limit := maxi(Joker.slots_buy_limit(run.joker_slots), shop.granted_buy_limit())
	if _shop_buys < buy_limit:
		# 联票:还有配额 ⇒ 货架不清, 可以接着从五张里再挑(用户:「点完那个 4 选 2,
		# 可以直接再选 2 张」)。⚠ 买走的那张要从货架上摘掉, 不重掷(重掷 = 免费刷新)。
		_coffer_used = false
		for i in range(_coffer.size()):
			if _coffer[i] != null and String(_coffer[i].id) == String(c.id):
				_coffer[i] = null
		_refresh_shop_consumables()
		return
	_refresh_shop_consumables()
	_perkeo_on_exit()
	shop.close()
	_start_phrase()


## ⚑ 商店类 action 的执行口 —— **只此一处**。
## 六种动作各自改一个商店参数, 由 shop 在下一次 _deal/_render 时消费。
func _apply_shop_action(id: String, act: Dictionary) -> void:
	if act.has("shelf_slots"):               # 联票:这次商店 4 选 2
		shop.grant_shelf(int(act["shelf_slots"]), int(act.get("buy_limit", 1)))
	if act.has("price_delta"):               # 赞助:这次商店全场降价
		shop.grant_price_delta(int(act["price_delta"]))
	if act.has("rule_guaranteed"):           # 点唱机:下次商店的**消耗牌位**必出规则牌
		# ⚠⚠ 2026-08-30 二批转生后**目标换了** —— 规则牌全部搬到消耗牌一侧,
		# 小丑牌货架上再也不会有规则牌, 原来的 `shop.grant_rule_guaranteed()`
		# 会**静默变成空操作**(那正是本项目栽过七次的形状)。
		_rule_next = true
	if act.has("deck_rule"):                 # 规则牌(近道/四指/黑调/红调):烙进牌堆
		# ⚠ 商店通路此前**没有这一支** —— 拍内通路有(`_on_consumable_used`),
		# 而这四张 `when: "any"` 两处都能点。少一支 = 在商店点它什么都不发生。
		run.deck.rules[String(act["deck_rule"])] = true
		_fx_rule_decree(id)
	if act.has("free_reroll"):               # 加急:免费刷新
		shop.grant_free_reroll(int(act["free_reroll"]))
	if act.has("min_rarity"):                  # 挑高:下次货架没有普通卡
		shop.grant_min_rarity(String(act["min_rarity"]))
	if act.has("loan"):                      # 预支:当场借, 下一个段边界还
		var ln: Dictionary = act["loan"]
		# ⚠ 走 `Economy.grant` 收口 —— 与旧的循环贷同一条(要吃穷开心的 coin_cap)。
		phrase.coins = Economy.grant(phrase.coins, int(ln.get("borrow", 0)), run.joker_slots)
		run.coins = phrase.coins
		run.debt += int(ln.get("repay", 0))
		Tape.on("loan", {"get": int(ln.get("borrow", 0)), "owe": run.debt,
			"coins": run.coins})
		if not run.tutorial:            # 借入流金(fx_advance ①)
			burst.loan_borrow(_purse_anchor(), int(ln.get("borrow", 0)))
	if act.has("copy_one_destroy_rest"):     # 砧座:复制一张小丑牌, 摧毁其余
		_anvil()
	if act.has("wilds"):
		run.deck.add_wilds(id, int(act["wilds"]))
	if act.has("trim_low"):
		run.deck.trim_low_ranks()


## 砧座:随机留一张小丑牌并复制到相邻槽, 其余销毁。
## ⚠ 只有**装着 ≥2 张**才有意义 —— 1 张时「复制一张、毁掉其余」= 什么都没发生,
## 那种情况应当在按下之前就挡住(armed 判定), 而不是静默吃掉一张消耗牌。
func _anvil() -> void:
	# ⚠ **只在 support 里掷**(2026-08-30 code review):留下 Target 时复制无处可放
	# (它只在 0 号槽生效)⇒ 砧座会变成「摧毁其余、什么也不给」, 而那是**随机发生**的 ——
	# 玩家点下去才知道亏不亏。⇒ 语义改成确定的:**留一张 support 并复制它**。
	var owned: Array = []
	for i in range(1, run.joker_slots.size()):
		if run.joker_slots[i] != null:
			owned.append(i)
	if owned.size() < 2:
		return
	# ⚠ 走 `run.deck.pick_index` 而不是全局 `randi()` —— 探针要可复现
	# (与 beat.gd 的 luck_rolls 同一条随机源纪律)。
	var keep: int = owned[run.deck.pick_index(owned.size())]
	var kept = run.joker_slots[keep]
	for i in range(run.joker_slots.size()):
		if i != keep:
			run.joker_slots[i] = null
	# ⚑ 复制品**继承成长状态**(2026-08-30 code review 补):`Joker.by_id` 拿的是
	# 干净的新卡, 留下转型(已累积 +120%)或收藏家(已记 5 次买卡)时,
	# 复制品的计数器是 **0** —— 玩家会觉得「复制了个空壳」。
	# ⚠ 留下的是 **Target** 时也要复制:首版判 `kind == "support"` 才复制,
	# 于是留下 Target 时**砧座等于「摧毁其余、什么也不给」**, 纯亏。
	# ⇒ Target 复制到 support 槽没有意义(它只在 0 号槽生效), 改为**留在原位不动**,
	#   并把「至少两张」的门槛提到调用前(见 `_consumable_effective`)。
	if kept.kind == "support":
		for i in range(1, run.joker_slots.size()):
			if run.joker_slots[i] == null:
				var dup = Joker.by_id(kept.id)
				dup.state = kept.state.duplicate(true)
				run.joker_slots[i] = dup
				break
	for i in range(joker_views.size()):
		joker_views[i].set_joker(run.joker_slots[i])
	Tape.on("anvil", {"kept": String(kept.id)})


## 掷一张上架的消耗牌。等权重(消耗牌没有稀有度轴 —— 12 张的池子再分档就太细了),
## 排除已在栏位里的。
## ⚑ 掷**两张**货架消耗牌(2026-08-31:1 → 2, 用户「每次出 3 小丑 2 消耗给用户选」)。
## ⚠ 两张互不重复、也不与栏位里已有的重复 —— 「2 选 1」里出两张一样的等于没得选。
## ⚠ 点唱机(`_rule_next`)只作用在**第一张**上:它保证的是「出一张规则牌」, 不是全出。
func _roll_consumables() -> Array:
	var held := {}
	for c in run.consumables:
		if c != null:
			held[c.id] = true
	var pool: Array = []
	for e in DB.consumables():
		if not held.has(String(e["id"])):
			pool.append(e)
	var out: Array = []
	for i in range(2):
		if pool.is_empty():
			out.append(null)
			continue
		var use := pool
		# 点唱机:这一次的**第一格**只从规则牌里抽(抽不出就退回全池, 不空手)。
		if i == 0 and _rule_next:
			_rule_next = false
			var rp: Array = []
			for e in pool:
				if Consumable.new(e).is_rule_card():
					rp.append(e)
			if not rp.is_empty():
				use = rp
		# ⚠ 同一条随机源纪律:走 `run.deck.pick_index`, 探针才复现得出同一张货架。
		var pick = use[run.deck.pick_index(use.size())]
		out.append(Consumable.new(pick))
		pool.erase(pick)
	return out


## 帕奇欧:离店时复制一张消耗牌。**三个 close 点都要走** —— 「第二条入口漏掉
## 主路径的步骤」是这个项目最贵的形状之一(CLAUDE.md 开局三步那条)。
## ⚠ 栏位满就不复制(静默跳过, 不是报错):那是玩家自己没腾位置。
func _perkeo_on_exit() -> void:
	if not Joker.slots_copy_consumable(run.joker_slots):
		return
	# ⚠ 队列没有上限了(2026-09-01), 所以「栏位满」这个跳过分支删掉。
	# ⚑ 但它的射程**变窄了**:自动触发之后, 离店那一刻手里只可能有**时机卡**
	# (buy 类买下即执行、根本不进队)⇒ 帕奇欧现在只复制开场/副歌/彩头/快闪。
	# 这是机制的真实后果, 不是 bug —— 定价要跟着重估(TODO)。
	var src: Array = run.consumables.duplicate()
	if src.is_empty():
		return
	# ⚠ `run.deck.pick_index` 而不是全局 `randi()` —— 探针可复现(同 beat.gd 的纪律)。
	var pick = src[run.deck.pick_index(src.size())]
	for e in DB.consumables():
		if String(e["id"]) == pick.id:
			var copy := Consumable.new(e)
			var used: Dictionary = run.take_consumable(copy)
			if not used.is_empty():
				_apply_consumable(used, "perkeo")
			Tape.on("perkeo", {"id": pick.id})
			break
	_refresh_queue()


## ⚑ 这张牌**现在按下去会不会真的发生点什么**(2026-08-29)。
## 砧座在只装了 ≤1 张小丑牌时,「复制一张、摧毁其余」等于什么都没做,
## 而消耗牌是一次性的:**买下去就没了**。让它可买等于给玩家挖一个静默的坑。
## ⚠ 判据来自今天反复出现的形状:**不报错的失败最贵**。
func _consumable_effective(c) -> bool:
	if c.action.has("copy_one_destroy_rest"):
		# ⚠ 只数 **support**(槽 1..3)—— 砧座在 support 里掷、复制到 support 槽,
		# Target 不参与(它只在 0 号槽生效, 复制无处可放)。
		var n := 0
		for i in range(1, run.joker_slots.size()):
			if run.joker_slots[i] != null:
				n += 1
		return n >= 2
	return true


## ⚑ `_consumable_effective` 的门从「点得动吗」搬到了「**买得动吗**」(2026-09-01)。
## 自动触发之后没有「点」这一步, 而砧座在 support ≤1 时买了等于白花 4◆ ——
## 与其让它静默浪费, 不如在货架上就压暗。判据一字未改, 只是位置换了。
func _refresh_shop_consumables() -> void:
	var eff: Array = []
	for c in _coffer:
		eff.append(c != null and _consumable_effective(c))
	shop.set_consumables([] if _coffer_used else _coffer, phrase.coins, eff)


## ⚑ **一次性执行口**(2026-09-01)——买入即触发和到点触发**共用这一份**。
## ⚠ 分两族:牌堆类(与 `Joker.on_acquire` 同一批键)交给 `Deck`, 商店类交给 shop。
## `boost` 不在这里 —— 它在 `Run._take` 里就并进了本拍加成。
func _apply_consumable(used: Dictionary, why: String) -> void:
	var cid := String(used["id"])
	var act: Dictionary = used.get("action", {})
	if act.has("wilds"):
		run.deck.add_wilds(cid, int(act["wilds"]))
	if act.has("trim_low"):
		run.deck.trim_low_ranks()
	if act.has("deck_rule"):
		run.deck.rules[String(act["deck_rule"])] = true
		_fx_rule_decree(cid)
	_apply_shop_action(cid, act)
	Tape.on("consumable", {"id": cid, "why": why,
		"phrase": run.phrase_in_section})


## 这一拍轮到谁了 —— **每拍开始时调一次**(在 `Beat.begin` 之后, 决策之前)。
## ⚠ 顺序不能反:先 `age_consumables()` 再 `due_consumables()`, 否则「下一拍」永远等不到。
## ⚑ 到期的碟报给结算动画那一位(用户 2026-09-01:「算的时候提示是什么卡生效就好了」)。
func _fire_due_consumables() -> void:
	run.age_consumables()
	var fired: Array = run.due_consumables(run.phrase_in_section + 1)
	var names: Array = []
	for used in fired:
		_apply_consumable(used, "due")
		for e in DB.consumables():
			if String(e["id"]) == String(used["id"]):
				names.append({"name": Lingo.pick({"cn": e.get("cn", ""), "name": e.get("name", "")})})
				break
	settle_fx.pending_consumables = names
	_refresh_queue()


## 把待播队列画到唱片位上(三碟并排, 先打的在左;第 4 张叠成 +1)。
func _refresh_queue() -> void:
	var q: Array = []
	for c in run.consumables:
		q.append({"id": String(c.id), "beat": c.fire_label(), "name": c.display_name()})
	vinyl.set_queue(q)


## "Early finish" needs at least one action — an untouched phrase never counts,
## or momentum would grow while the player idles (principle A4).
## _settle 与 _advance 共用这一份判据(判定只许有一份真相)。
func _acted_early() -> bool:
	# ⚑⚑ 判据 **B**(2026-08-31 用户):「最后一次动作**距离结算**还有多久」。
	# 旧口径 `last_action_time <= 3.5`(距开拍)在 8 秒拍下等价, 但**拍长一变就分叉**。
	# ⚠ 一拍不动手拿不到(A4:不许挂机)。⚠ 主动收工已退役 ⇒ 每拍走满全长,
	# 所以代价是**决策速度**, 不再是「早点动完然后干等」(那条老病一并消掉)。
	if last_action_time < 0.0:
		return false
	return (cur_lock - last_action_time) >= GameConfig.EARLY_FINISH_LEFT


## 分数滚动进行中(含 burst 前的等待:settle_fx 还没到 1.5s 时 tween 尚未建, 看 fx 的相位)
func _rolling() -> bool:
	if _score_roll != null and _score_roll.is_valid():
		return true
	return settle_fx.visible and settle_fx.is_processing() and run.section_score != _shown_score


func _stop_roll() -> void:
	if _score_roll != null and _score_roll.is_valid():
		_score_roll.kill()
	_score_roll = null
	_shown_score = run.section_score


func _advance() -> void:
	Beat.phrase_end(run, phrase, {"early": _acted_early()})
	# ⚑ 教学关的步进在这里, 而且**只在这里** —— 一拍收尾时结算「这一步的动作做到没有」。
	# `play` 仍然照记(每拍必然结算一手), v6 里没有步再拿它当门, 记着只是账目完整。
	# ⚠ 顺序:先记 play → 再 try_advance → 再 `run.advance()` → 最后才轮到 `tutorial_done()`,
	# 因为 `tutorial_done()` 读的正是 try_advance 推出来的那个下标。
	run.tutorial_note("play")
	run.tutorial_try_advance()
	var out := run.advance()
	# ⚑ 教学关的商店时刻只有一个(2026-08-24 用户:「一开始就是没有小丑牌, 直接跳出来
	# 让玩家选小丑牌」;v6 = 分镜 D):推进到**最后一步**时弹真商店(首张 Target 免费
	# 三选一, 与正式局同一个流程), D 的提示条锚在商店盲注板下、focus 指价签行;
	# 选完/继续 ▸ 都消费这一课(`tutorial_shop_seen`)回拍 —— 每 3 拍的正式节奏在
	# 教学段不再开第二次店, 商店的完整节奏留给正式局自己展示。
	if run.tutorial and not bool(out["section_done"]):
		if run.tutorial_step == Tutorial.shop_step() and run.joker_slots[0] == null:
			_open_draft()
			return
		if bool(out["shop_break"]):
			_start_phrase()
			return
	# ⚑ 教学关走完 = 记下「看过了」→ 回首页, 玩家下一局起就是正式局。
	# ⚠ 放在生死判定**之前** —— 教学关 target 恒 0, 走到这里 `cleared` 必真,
	# 但把它夹在下面那段结算逻辑里会让「教学关不判生死」变成一个隐式的巧合。
	# **显式返回, 别依赖巧合。**
	# ⚑⚑ **教学走完 = 收起提示, 接着把这一局打完**(2026-08-17 用户拍板:
	# 「为什么不让玩家玩完一局, 后面别提示了就正常玩呗」)。
	#
	# ⚠ 旧行为是**回首页** —— 玩家的体感是「游戏突然跳出去了」, 他连一局都还没打过。
	# ⚑ 而数字正好对上:**教学 6 步 = 一段 6 拍**, 所以切换点**恰好落在段边界**上,
	# 不会出现「打了一半规则突然变了」。
	#
	# 切换要做三件, 缺一不可:
	#   ① `tutorial = false` —— 目标分/脸/拍长立刻回到正式局(它们全看这个标志);
	#   ② **现在才掷脸** —— 教学关期间 `roll_faces` 是提前返回的(`run_faces` 是空的),
	#      不补掷的话后面三段全都没有 Boss;
	#   ③ 收起提示条。
	# ⚠ **不再 `Tape.close`** —— 这一局还没完, 关掉打点会把后三段的数据丢光。
	# ⚠ 2026-08-18 改 4 轮后步数(4)< 段拍数(6):**转正式必须仍卡在段边界** ——
	# 第 5-6 拍是无提示的自由拍(样品还在手, 随便试), 提示自己隐身(步过界 hint 为空)。
	if run.tutorial and run.tutorial_done() and bool(out["section_done"]):
		SaveState.mark_tutorial_seen()
		run.tutorial = false
		_feed_director()
		run.roll_faces(-1, SaveState.runs_total())
		tutor.set_hint("", "")
		# (借展样品已删 2026-08-24 —— 教学商店里选/买的卡本来就该带进正式局, 无可收回)
		# γ 特写的存档旗在 mark_tutorial_seen 里一起立 —— 下一个正式段首的公示卡带课。
		Tape.on("tutorial_done", {"beat": run.phrase_index})
	if bool(out["section_done"]):
		state = St.END
		Tape.on("sec_end", {"i": run.section_idx, "score": run.section_score,
			"target": run.target(), "ok": bool(out["cleared"]),
			"coins": phrase.coins, "beats": run.phrase_in_section})
		if not bool(out["cleared"]):
			Tape.close({"ok": false, "sec": run.section_idx,
				"score": run.section_score, "target": run.target(),
				"beats": run.phrase_index})
			SaveState.clear_checkpoint()   # 局终 = 快照作废(断点续玩只救半局, 不救死局)
			# 跨局记账:战绩/见过的脸/boon/构筑入存档(喂 Director 的 ctx)。
			SaveState.settle_run_meta(false, run.section_idx, _faces_encountered(),
				String(run.boon()), _final_target_id())
			music.play_jingle(false)
			run_end.show_fail(run.section_score, run.target())
			return
		# clear wage, shown as the panel chip(走 grant —— 金币上限的四个入账口之一)
		phrase.coins = Economy.grant(phrase.coins, GameConfig.SECTION_CLEAR_REWARD,
			run.joker_slots)
		# 预支还款(2026-08-26 金融组):工资入账后判 —— 付不起 = run 失败,
		# **含 S4**(通关那一刻也得先还钱, 卡面写明 "or die")。死因记 Tape;
		# fail 屏的死因行归 UI 批(现屏只念分数, 分数达标却失败的困惑由卡面契约兜)。
		var loan_out := {"repay": run.debt}
		if int(loan_out.repay) > 0:
			if phrase.coins < int(loan_out.repay):
				Tape.close({"ok": false, "sec": run.section_idx,
					"score": run.section_score, "target": run.target(),
					"beats": run.phrase_index, "why": "loan"})
				SaveState.clear_checkpoint()
				SaveState.settle_run_meta(false, run.section_idx, _faces_encountered(),
					String(run.boon()), _final_target_id())
				music.play_jingle(false)
				# 违约碎裂(fx_advance ③):红闪 + 卡面碎成玻璃片。**在 show_fail 之前发** ——
				# 特效层 z=100 盖在 fail 屏之上, 碎片正好落在「你死了」那一屏上。
				if not run.tutorial:
					burst.loan_default(_loan_anchor(), int(loan_out.repay))
				# 死因行:分数达标却因预支违约死掉, 只念分数会让玩家困惑(文案在
				# ui.json 的 banner 节, DB.ui() 已过语言层, %d = 还不上的还款额)
				run_end.show_fail(run.section_score, run.target(),
					String(DB.ui().get("banner", {}).get("fail_loan", "%d◆")) % int(loan_out.repay))
				return
			phrase.coins -= int(loan_out.repay)
			run.coins = phrase.coins
			Tape.on("loan", {"pay": int(loan_out.repay), "coins": phrase.coins})
			# 逐段抽走(fx_advance ②):一枚金币被红色拽出钱包
			if not run.tutorial:
				burst.loan_repay(_purse_anchor(), int(loan_out.repay))
		if bool(out["finale"]):
			Tape.close({"ok": true, "sec": run.section_idx,
				"score": run.section_score, "target": run.target(),
				"beats": run.phrase_index})
			SaveState.clear_checkpoint()   # 通关同款:整局已收束, 快照作废
			# 2026-08-06 用户:「为什么中途要跳那个通关成功的页面啊, 只有一整关通关才跳」——
			# 全屏庆祝**只留给整轮结束**。改成 4 段全墙之后, 挂在墙上的旧规则等于每段都发,
			# 一局 5 分钟被打断 4 次; 庆祝是稀缺资源, 现在全程只发 1 次。
			SaveState.settle_run_meta(true, GameConfig.SECTIONS_PER_RUN,
				_faces_encountered(), String(run.boon()), _final_target_id())
			music.play_jingle(true)
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


## 这一局收官时的 Target(构筑倾向的原料, 探索型货架的分母)。"" = 一局没装过 Target。
func _final_target_id() -> String:
	for j in run.joker_slots:
		if j != null and String(j.kind) == "target":
			return String(j.id)
	return ""


## 这一局「见过」的脸:打到的每一段 + 预告过的下一场 —— 喂 `faces_seen`
## (新鲜感轴的分母)。没打到也没预告的脸不算见过, 全记会把 N 轴静默清零。
func _faces_encountered() -> Array:
	var out: Array = []
	for i in range(mini(run.section_idx + 2, GameConfig.SECTIONS_PER_RUN)):
		var f := String(run.run_faces.get(i, ""))
		if f != "":
			out.append(f)
	return out


## advance to the next blind and open the shop — every section boundary is a
## shop visit; with full slots it becomes the buy-new-replace-old flow
func _next_section() -> void:
	# 客串到寿的清槽发生在 `run.next_section()` 里(core 侧, 单一咬合)。
	# ⚠⚠ **视图此前没有跟着摘** —— 卡在数据里已经没了, 槽位上还挂着它的卡面
	# (2026-08-27 做谢幕特效时发现的真 bug)。先记摘前的持仓, 摘完比对空出来的槽:
	# 一是演谢幕, 二是把卡面清掉。两件事同一个来源, 不会再分叉。
	var before: Array = run.joker_slots.duplicate()
	run.next_section()
	_bow_out(before)
	# ⚠ 段初自动借款已删(2026-08-30 三批转生):预支变成消耗牌, 玩家在商店主动烧。
	_tape_section()
	_open_draft()


## 到寿离场(fx_gueststar_exit):追光收窄 + 深鞠一躬 + 空槽粉色余晖。
## 「不许凭空蒸发」是这一页设计稿的原话 —— 清卡面与演谢幕是同一次比对的两个动作。
func _bow_out(before: Array) -> void:
	for i in range(run.joker_slots.size()):
		if i >= before.size() or before[i] == null or run.joker_slots[i] != null:
			continue
		var jv: Control = joker_views[i]
		if not run.tutorial:
			burst.guest_exit(Rect2(jv.get_global_position(), jv.size),
				String(before[i].cn_name))
		jv.set_joker(null)


## HUD 金币位(全局)—— 预支三拍的钱包锚点。coin_label 右对齐, 宽 160。
func _purse_anchor() -> Vector2:
	return hud.coin_anchor() + Vector2(150, 15)


## ⚠ 违约碎裂的锚点:预支转生为消耗牌后**没有常驻槽位**了 ⇒ 固定落在钱包。
## (旧版找的是「持有预支卡的那个槽位」, 那时它是一张一直在场的小丑牌。)
func _loan_anchor() -> Vector2:
	return _purse_anchor()


## ⚠⚠ **`_loan_borrow` 已删(2026-08-30 三批转生)** —— 借款不再是段初的自动动作,
## 而是玩家在商店烧掉预支消耗牌的那一刻(见 `_apply_shop_action` 的 `loan` 分支)。
## 留这段注释是因为「段初自动 +borrow」这个行为在 Tape 里有历史读数, 别把两代混着看。


## success screen: 下一场演出 (or 谢幕 on the finale)
func _on_end_next() -> void:
	if state != St.END:
		return
	run_end.close()
	if run.section_idx >= GameConfig.SECTIONS_PER_RUN - 1:
		_on_end_home()          # 谢幕: the run is complete, take a bow
		return
	_next_section()


## fail screen: 再来一次 — fresh run
func _on_end_retry() -> void:
	if state != St.END:
		return
	Tape.on("nav", {"to": "retry"})
	run_end.close()
	_reset_run(true)
	# 与开局同一份三步(评审 R2):Director/min_run/局数都要算上这一局。
	# ⚑ 同一份三步 = 同一道体力闸:重开 = 新 run, 照扣;不足 = 不开局, 回首页浮字。
	if not _begin_run():
		_deny_no_energy()
		return
	# 重开 = 新的一局, 得开新流, 否则两局的事件会串在同一条时间轴上
	Tape.begin({"sess": _sess, "tutorial": run.tutorial,
		"faces": run.run_faces.duplicate(), "targets": GameConfig.SECTION_TARGETS,
		"coins": GameConfig.STARTING_COINS, "retry": true,
		"struct": {"sec": GameConfig.SECTIONS_PER_RUN,
			"pps": GameConfig.PHRASES_PER_SECTION,
			"ppshop": GameConfig.PHRASES_PER_SHOP,
			"dur": GameConfig.phrase_duration(0)}})
	_enter_section()


## either screen: 返回主页
func _on_end_home() -> void:
	if state != St.END:
		return
	Tape.on("nav", {"to": "back"})
	Tape.flush()
	run_end.close()
	_reset_run(false)
	_open_home()


## `_keep` 曾是 keep_character(再来一次保主角)—— 主角系统删除后参数只剩语义占位,
## 两条调用路径(重开/回首页)保持原签名, 免得再分叉。
func _reset_run(_keep: bool) -> void:
	phrase = null
	run.reset()
	if burst != null:
		burst.clear()      # 换局 = 上一局没演完的仪式作废(同 SettleFx.dismiss 的口径)
	for i in range(joker_views.size()):
		joker_views[i].set_joker(null)
	_shown_score = 0
	_cutins_played.clear()   # 教学特写按局记(--fresh 重进教学关要能再放一遍)


## 开局三步(2026-08-21 评审 R2 收口):定局数 → 喂 Director(排序表 + 玩家状态 m)→
## 按真实局数掷脸 → 记局数。**开局与「再来一次」必须走同一份。**
## 此前重开路径只调 `_reset_run()`, 而 `Run.reset()` 内部用缺省 `run_index = -1` 掷脸 ⇒
## min_run 门失效(禁回第 2 局重开就能冒出来)、Director 永远第 1 局状态、ctx 用上一局的
## 快照、runs_total/history 分叉 —— 四条全静默。「第二条入口漏掉主路径的步骤」是这个项目
## 最贵的形状之一, 所以收成一个函数, 别再让两条入口各写各的。
## ⚠ `_run_index` 的 `+1`:掷脸发生在 `note_run_started()` 之前, 存档里还是「以前玩过几局」。
## ⚑ 体力真闸门(2026-08-26 用户拍板「体力是开局扣一点」)装在**这一份**入口的第 0 步 ——
## 开局与重开自然同闸(重开 = 新 run, 照扣);只挡首页按钮就是「第二条入口漏步骤」的老坑反着犯。
## 教学关不扣、探针恒放行, 口径都收在 SaveState.spend_energy_for_run(一处)。
## 返回 false = 体力不足**什么都没发生**(不扣/不掷/不记局), 调用方不开局(回首页浮字)。
func _begin_run() -> bool:
	if not SaveState.spend_energy_for_run(run.tutorial):
		return false
	_run_index = 1 if SaveState.is_probe() else SaveState.runs_total() + 1
	_feed_director()
	run.roll_faces(-1, _run_index)
	SaveState.note_run_started()
	music.new_run()   # 一局一首(2026-08-25 拍板):开局清曲, 第一拍重抽
	return true


## 体力不足挡开局:回首页 + 浮字(2026-08-26 真闸门)。事实记 Tape(打点只在编排器;
## 局外事件与首页 nav 同款, 不落 run 文件 —— 那是 Tape.begin 的既有口径)。
## 浮字挂编排器的 fx 层(z=60), 盖在重开的首页上方。
## TODO(商业化批, SDK 选型归用户):「看广告领体力」真入口 —— 本批只留桩:
## 下面第二行浮字提一句, 不做任何 SDK 调用、不加任何按钮。
func _deny_no_energy() -> void:
	Tape.on("deny", {"why": "energy"})
	_open_home()
	fx.float_text(Lingo.t("体力不足,明天回满"), Vector2(243.0, 986.0), Color("ff5f7e"), 90)
	fx.float_text(Lingo.t("看广告补体力 · 敬请期待"), Vector2(228.0, 1026.0), StageTheme.GOLD, 90)


## 从快照恢复半局(2026-08-24)。恢复**不走开局三步** —— 掷脸/喂 Director/记局数
## 都已在原局发生, 产物在快照里(core/run.gd::restore 文件头有整段论证)。
## 返回 false = 没有快照或快照坏了, 调用方照常开首页。
## 续玩询问卡(2026-08-27):首页之上的一层, 两个出口。
## ⚠ 不自动恢复也不自动清 —— 玩家不选就什么都不发生(快照留着, 下次开还问)。
func _ask_resume() -> void:
	var layer := Control.new()
	layer.position = Vector2.ZERO
	layer.size = Vector2(720, 1280)
	layer.z_index = 130
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0.02, 0.74)
	dim.size = Vector2(720, 1280)
	layer.add_child(dim)
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel",
		StageTheme.box(Color(0.04, 0.05, 0.12, 0.96), StageTheme.CYAN, 1, 16))
	panel.position = Vector2(150, 470)
	panel.size = Vector2(420, 250)
	layer.add_child(panel)
	var snap := SaveState.checkpoint()
	var sec := int(snap.get("section_idx", 0)) + 1
	var title := StageTheme.label(Lingo.t("上次的演出还没结束"), StageTheme.zh(), 23,
		StageTheme.CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(150, 494)
	title.size = Vector2(420, 32)
	layer.add_child(title)
	var sub := StageTheme.label(Lingo.t("进行到第 %d 场") % sec, StageTheme.zh(), 16,
		StageTheme.rim(0.7), HORIZONTAL_ALIGNMENT_CENTER)
	sub.position = Vector2(150, 528)
	sub.size = Vector2(420, 24)
	layer.add_child(sub)
	var go := Button.new()
	go.text = Lingo.t("继续演出 ▸")
	go.add_theme_font_override("font", StageTheme.zh())
	go.add_theme_font_size_override("font_size", 19)
	go.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed"]:
		go.add_theme_stylebox_override(st,
			StageTheme.box(Color(0.06, 0.16, 0.20, 0.95), StageTheme.CYAN, 1, 12))
	go.add_theme_color_override("font_color", Color("cdf7f2"))
	go.position = Vector2(186, 572)
	go.size = Vector2(348, 46)
	go.pressed.connect(func() -> void:
		layer.queue_free()
		if not _resume_run():
			_open_home())
	layer.add_child(go)
	var drop := Button.new()
	drop.text = Lingo.t("放弃, 开新的一局")
	drop.add_theme_font_override("font", StageTheme.zh())
	drop.add_theme_font_size_override("font_size", 17)
	drop.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed"]:
		drop.add_theme_stylebox_override(st,
			StageTheme.box(Color(0.16, 0.06, 0.09, 0.95), Color("ff5f7e"), 1, 12))
	drop.add_theme_color_override("font_color", Color("ffc3cf"))
	drop.position = Vector2(186, 630)
	drop.size = Vector2(348, 44)
	drop.pressed.connect(func() -> void:
		SaveState.clear_checkpoint()
		layer.queue_free())
	layer.add_child(drop)
	add_child(layer)


func _resume_run() -> bool:
	var snap := SaveState.checkpoint()
	if snap.is_empty():
		return false
	# ⚠⚠ **先把首页收掉**(2026-08-27 真人报「点继续游戏其实没有继续」)——
	# 旧流程是 `_ready` 里「有快照就直接恢复、从不开首页」, 所以没人管过关闭;
	# 改成「首页 + 询问卡」之后, 恢复出来的牌桌**被首页层盖住**, 看着就像没反应。
	# ⚑ 与 start_run 同一套收场动作(菜单 + 首页节点), 别只藏不释放。
	_close_menu()
	if _home != null and is_instance_valid(_home):
		_home.queue_free()
	_home = null
	_front_latch = true
	_reset_run(false)
	if not run.restore(snap):
		SaveState.clear_checkpoint()
		_reset_run(false)     # 半恢复的 run 不能留着 —— 重置回干净初态
		return false
	_run_index = int(snap.get("run_index", 1))
	_front_latch = true
	for i in range(joker_views.size()):
		joker_views[i].set_joker(run.joker_slots[i])
	# 恢复开新 Tape 流并打上 resume 标记 —— 原流没有 close(那本身就是「中断过」的信号),
	# 分析侧按 resume + 同 install_id 把两截拼回一局。
	Tape.begin({"sess": _sess, "tutorial": false, "resume": true,
		"faces": run.run_faces.duplicate(), "targets": GameConfig.SECTION_TARGETS,
		"coins": run.coins,
		"struct": {"sec": GameConfig.SECTIONS_PER_RUN,
			"pps": GameConfig.PHRASES_PER_SECTION,
			"ppshop": GameConfig.PHRASES_PER_SHOP,
			"dur": GameConfig.phrase_duration(0)}})
	set_process(true)
	music.new_run()   # 恢复也算新的一次坐下, 重抽一首(局内仍恒定)
	# 段中恢复:段首拍才做的接线(盲注卡/音乐, 见 _start_phrase 的 phrase_in_section==0
	# 分支)这里自己补 —— 恢复点可以落在段中任何一拍。
	if run.phrase_in_section > 0:
		cur_modifier = run.face()
		blind_card.setup(run.section_idx, SectionMod.by_id(cur_modifier),
			SectionMod.by_id(String(run.run_faces.get(run.section_idx + 1, ""))),
			BlindBoon.by_id(run.boon()))
		blind_card.roll_note = _roll_note()
		blind_card.visible = true
		music.play_section(run.section_idx)
	_start_phrase()
	return true


# ============================== DRAFT ==============================

func _open_draft() -> void:
	state = St.DRAFT
	settle_fx.dismiss()   # 分解面板铺在货架带上, 商店一开必须立刻让位(2026-08-18)
	_stop_roll()          # 滚动一起收, 商店盲注板讲的是终值
	# ⚠ **进商店先收掉教学提示条**(2026-08-17 试玩报的:「选小丑牌了, 前面的提示怎么还在」)。
	# 它只在 `_start_phrase` 设, 而商店是**从拍中间弹出来的全屏层** —— 没人负责清它,
	# 于是上一拍那句话就压在货架上。
	# ⚑ 不用记状态再恢复:下一拍 `_start_phrase()` 照常重设, 那里本来就是唯一的入口。
	tutor.set_hint("", "")
	# 盲注卡挪到商店下部(2026-08-27 用户:「展示盲注没错, 但压住小丑牌很奇怪, 放下面」)——
	# 它 z 本就悬在商店层上(这是「选牌时看得到盲注」的实现), 只挪位不动 z;
	# 还原走下一拍 _start_phrase(与教学提示条同款:不记状态, 唯一入口重设)。
	var bcp: Array = DB.ui()["shop"].get("blindcard_pos", [28, 940])
	blind_card.position = Vector2(float(bcp[0]), float(bcp[1]))
	blind_card.z_index = 61   # 抬过商店内容层(shop 内浮字 60)—— 停靠是为了「看得见」
	_shop_buys = 0        # 联票的续买配额按「一次进店」计
	# a mid-section shop opens with the blind's counter part-way through; a
	# section-end one opens at phrase 0 of the blind being entered
	var mid: bool = run.phrase_in_section > 0 \
		and run.phrase_in_section < GameConfig.PHRASES_PER_SECTION
	# 教学段商店不摆升级栏(2026-08-18 用户:「下面 4 个是干嘛, 不应该要」——
	# 栏里列的是借展样品, 给要收回的卡挂升级报价既误导又花钱打水漂;教学商店只教「买」)
	# Director 的货架偏置(establish 抬 common / experiment 抬 rare…):探针中性
	shop.set_shelf_rarity_mult({} if SaveState.is_probe() else Director.shelf_rarity_mult(_run_index))
	# 探索型货架的原料(玩过的 Target):探针恒空 ⇒ 货架掷法逐字节不变
	shop.set_explore_used({} if SaveState.is_probe() else SaveState.targets_used())
	# 点名的解除奖励:本次开店 +1 货架位, 消费即清源(三条开店入口都走本函数, 单一咬合点)。
	shop.shelf_bonus = run.shelf_bonus
	run.shelf_bonus = 0
	# 巡演路线(journey #4):开局特写亮过整局四脸, 但**做构筑决策的时刻在商店**,
	# versus 的「调度/排期」解法要求在这里也看得到全局 —— 盲注板脚注亮四场缩略。
	shop.set_route(_shop_route())
	shop.open(run.joker_slots, phrase.coins, run.section_idx,
		SectionMod.by_id(String(run.run_faces.get(run.section_idx, ""))),
		run.section_score if mid else -1,
		run.phrases_left() if mid else -1,
		run.target(),      # ⚠ 加码脸乘过的那个目标, 不是原始表(2026-08-09)
		BlindBoon.by_id(run.boon()))
	# ⚑ 每次开店抽一张消耗牌上架(2026-08-29)。**独立一格, 不进三选一** ——
	# 混进去等于用消耗牌换掉小丑牌的多样性(与「转型/换旗抢名额」同型的资源错配)。
	# 已持有的不再上架, 免得开局就撞见两张一样的。
	_coffer = _roll_consumables()
	_coffer_used = false
	_refresh_shop_consumables()
	# 分镜 D(v6):教学商店自己带条 —— 锚在商店盲注板下, focus 指货架价签行,
	# 货架操作面(卡/价签/按钮)进常亮洞(玩家要挑的卡不许黑)。必须在 shop.open
	# **之后**:价签行的矩形是 _layout 按当拍货架数摆出来的, 开店前是空的。
	# 教学层画在商店之上(layout 的层序), 压暗构图对商店同样成立。
	if run.tutorial and run.tutorial_step == Tutorial.shop_step():
		var h := run.tutorial_hint()
		var pr := shop.price_row_rect().grow(6.0)
		tutor.set_hint(String(h["command"]), String(h["signal"]),
			[] if pr.size.x <= 0.0 else [pr], [], [shop.shelf_zone_rect()],
			shop.board_rect().end.y + 12.0)
	# 段中/段末两态要分开统计:段中是「已知缺口下的解题」, 段末是「对下一场下注」,
	# 购买行为本来就不该混在一起看(docs/design/levels.md 的核心论证)
	Tape.on("shop", {"mid": mid, "sec": run.section_idx, "coins": phrase.coins,
		"offer": shop.offers(), "slots": Tape.slots(run.joker_slots),
		"left": run.phrases_left() if mid else -1,
		"need": run.deficit() if mid else -1})


## 商店盲注板的巡演路线行(journey #4)—— 与开局特写的 `_route_text()` 同一份事实
## (`run.run_faces`), 换成按段拆开的结构, 板子才能给「已打过/当前/未来」上不同的色。
## state: 0 已打过(勾+压暗)/ 1 当前段(档位色)/ 2 未来(常规)。
## 教学关返回空数组 = 不画(教学没有脸, 四个「纯分数」只是噪声)。
func _shop_route() -> Array:
	if run.tutorial:
		return []
	var out: Array = []
	for i in range(GameConfig.SECTIONS_PER_RUN):
		var m := SectionMod.by_id(String(run.run_faces.get(i, "")))
		out.append({
			"name": m.cn_name if m != null else Lingo.t("纯分数"),
			"state": 0 if i < run.section_idx else (1 if i == run.section_idx else 2)})
	return out


## 一次进店已成交几张(联票 buy_limit 的计数;每次 _open_draft 归零)。
var _shop_buys := 0


## Shop signals — the board picked; money and slots change ONLY here.
func _on_shop_bought(j, price: int) -> void:
	if state != St.DRAFT:
		return
	# 0 = 本局首张 Target(免费三选一, Target 唯一保留的特例);
	# 之后 Target 与 Support 一样按稀有度定价(2026-08-06 回池, 原专属 8◆ 已废)。
	# ⚠ 余额在**这里**复查(经济动作只发生在编排器):shop 的显示态与真钱包可能差一拍
	# (升级路径一直复查, 买入路径此前没有 —— 2026-08-21 评审)。
	if price < 0 or phrase.coins < price:
		Tape.on("deny", {"why": "buy_stale"})
		return
	phrase.coins -= price
	Tape.on("buy", {"id": String(j.id), "kind": String(j.kind),
		"price": price, "coins": phrase.coins})
	_note_tutorial("buy")
	# 收藏家:每买一张。⚠ **在装卡之前发** —— 否则刚买的这张会给自己记一次,
	# 「每买 1 张 +15」就凭空多了第一次(转型同理:换旗不该给新旗自己记一次)。
	Joker.notify_shop(run.joker_slots, "buy")
	var _swapped_target := false
	if j.kind == "target":
		var swapping: bool = run.joker_slots[0] != null
		_swapped_target = swapping
		if swapping:
			Joker.notify_shop(run.joker_slots, "target_swap")   # 转型:换旗有代价(丢掉旧旗)
			# ⚑ 旧旗折半回收(2026-08-27 真人报「target 无法替换老 target」时查出的
			# **规则不一致**):CLAUDE.md 写的是「满槽 = 买新替旧, 旧卡折半回收」,
			# 而换旗这条路上旧 Target **直接蒸发、一分不退** —— Support 替换有退,
			# 换旗没有, 同一条规则两种待遇。补上, 并与 Support 用同一个口径与浮字。
			var trefund := Economy.sell_value(run.joker_slots[0])
			if trefund > 0:
				phrase.coins = Economy.grant(phrase.coins, trefund, run.joker_slots)
				run.coins = phrase.coins
				fx.float_text("+%d ◆" % trefund,
					joker_views[0].get_global_position() + Vector2(30, 40), StageTheme.GOLD)
		run.joker_slots[0] = j
		j.on_acquire(run.deck)          # 百搭 shuffles 大小王 in at this moment
		joker_views[0].set_joker(j)
		fx.pop(joker_views[0])
		_fx_acquired(j, 0)
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
				_fx_acquired(j, k)
				placed = true
				break
		if not placed:
			push_error("[shop] 买了 '%s' 却没有空的 Support 槽 —— 钱已扣。上游的满槽判定漏了 kind"
				% String(j.id))
	# 刚装的卡若自带金币上限(穷开心), 存量当场修剪 —— 卡面「上限 5」对已经很富的
	# 玩家也必须为真(D2:卡面不许说谎), 而修剪只许发生在编排器手里。
	phrase.coins = Economy.cap_held(phrase.coins, run.joker_slots)
	# 教学关:挑完那张免费 Target 立刻开拍(2026-08-24 用户流程「选了就开拍」)。
	# v6:关店 = 消费分镜 D(这一课的展示面就是商店层), 后面是无提示自由拍。
	if run.tutorial and j.kind == "target":
		run.tutorial_shop_seen()
		_perkeo_on_exit()
		shop.close()
		_start_phrase()
		return
	# 联票:限额未满就留在店里续买(同一货架摘牌重估, 不重掷)。
	# 限额从槽位实时读 —— 本次买的若是联票, 当店立刻多出一次成交。
	# ⚠ 走替换流(满槽)的成交不回商店:那条流程以 _start_phrase 收尾, 视为用掉全部余额。
	# ⚑⚑ **换旗不占购买名额**(2026-08-29):换旗是路线决策, 不是囤货 —— 让它挤掉
	# 当店唯一一次成交, 会造成一个**自我否定**的结构:奖励换旗的卡(转型)和换旗动作
	# 抢同一个名额 ⇒ 想买转型就不能换旗, 想换旗就买不到转型。
	# 实测(sim, 未稀释口径):**持有转型的局换旗 0.65 次, 未持有的反而 0.94 次** ——
	# 拿着「每次换旗 +40%」的人换得更少, 因果就在这一行。
	if not (j.kind == "target" and _swapped_target):
		_shop_buys += 1
	# ⚑ 联票(消耗牌)的本店限额叠在小丑牌的之上(2026-08-30 code review 补:
	# `_grant_buy_limit` 此前**只被写入和清零, 从没被读过** —— 那张卡在游戏里是空白的)。
	var buy_limit := maxi(Joker.slots_buy_limit(run.joker_slots), shop.granted_buy_limit())
	if _shop_buys < buy_limit:
		# 剩余配额由**这里**算并传下去 —— 视图不自己数(经济动作只发生在编排器),
		# 它只拿这个数去写副标题的「还能再选 N 张」。
		shop.sold(j, run.joker_slots, phrase.coins, buy_limit - _shop_buys)
		return
	_perkeo_on_exit()
	shop.close()
	_start_phrase()


# (升级函数 2026-08-26 随升级系统删除;它的注释头和尾行 `_start_phrase()` 曾被落下 ——
# GDScript 把注释当空白, 那行孤儿代码**接进了上一个函数**, 买满限额关店时会把
# `_start_phrase()` 跑两遍:重复发牌、重收入场费, 而且不报错。2026-08-27 清掉。)


## 买入仪式(2026-08-27 A 级特效批)—— 买入 / 满槽替换**两条安装路径共用这一份**,
## 挂在三个 `on_acquire()` 调用点上。「第二条入口漏掉主路径的步骤」是这个项目最贵的
## 形状之一, 所以不许各写各的。
##
## ⚠⚠ **超级百搭也是规则牌**(它带 `acquire.wilds`, `is_rule_card()` 对它为真)——
## 必须**先判它再判规则牌**, 否则同一次买入会同时演旋涡和宣告横幅。
func _fx_acquired(j, slot: int) -> void:
	if j == null or run.tutorial:
		return
	if String(j.id) == "superwild":
		# 入库仪式画在**音浪轴**(720/2, 534)上:牌堆在游戏里没有实体, 而四张 JOKER
		# 进的是牌堆不是槽位, 挂在槽位上会说错话。
		# ⚠ 螺旋起手半径 182, 短暂压到手牌区上沿(672)—— 这一条**不违反「不挡牌面」**:
		# 它只在商店成交那一刻放, 那时货架本来就盖着牌桌(设计稿也把它单列为
		# 「商店购入时的一次性入库仪式」, 不在结算链内)。
		burst.superwild(Vector2(360, 534))
		return
	# ⚠ 规则牌的宣告横幅**已移到 `_fx_rule_decree`** —— 2026-08-30 起规则牌是消耗牌,
	# 它的时刻不再是「装进槽位」而是「用掉」, 也没有可以收尾缩向的常驻槽位。


## 规则宣告横幅 —— 规则牌(消耗牌)被用掉的那一刻。
## ⚠ 文案取自 `data/consumables.json`(cn / fx), **view 里不写卡面字**(与小丑牌同一条)。
## 收尾落在屏幕中轴:规则改的是牌堆, 而牌堆在游戏里没有实体, 挂到某个槽位上会说错话
## (与超级百搭的入库仪式同一条理由)。
func _fx_rule_decree(cid: String) -> void:
	if run.tutorial:
		return
	for e in DB.consumables():
		if String(e["id"]) == cid:
			var c := Consumable.new(e)
			burst.rule_decree(c.display_name(), String(c.fx_text), cid,
				Vector2(360, 534))
			return


## full slots: pick which support to swap out (old sells for half)
func _on_shop_replace(j) -> void:
	if state != St.DRAFT:
		return
	# 进入替换态。**「看了但没换」原本零痕迹** —— 后 3 次商店 100% 是替换场景,
	# 而只记成交和差钱, 分不出「换不起」还是「不值得换」。
	Tape.on("repl_open", {"id": String(j.id), "price": Economy.shelf_price(j, run.joker_slots),
		"coins": phrase.coins, "slots": Tape.slots(run.joker_slots)})
	_perkeo_on_exit()
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
	run.tutorial_shop_seen()   # v6:分镜 D 的另一个出口(不买也算上完这一课), 正式局无操作
	_perkeo_on_exit()
	shop.close()
	_start_phrase()


func _on_shop_reroll(cost: int) -> void:
	if state != St.DRAFT or replace.pick != null:
		return
	if cost < 0 or phrase.coins < cost:
		Tape.on("deny", {"why": "reroll_stale"})
		return
	phrase.coins -= cost
	Joker.notify_shop(run.joker_slots, "reroll")     # 淘碟:刷新是付费动作(A4✓)
	Tape.on("rerl", {"k": shop.reroll_count(), "cost": cost, "coins": phrase.coins})
	shop.redeal(run.joker_slots, phrase.coins, run.section_idx)


## 成交(或取消)。⚠ 钱与打点必须留在这里 —— replace.gd 只复位 UI。
## 放弃替换 —— 显式按钮与「点 Target 槽」两条路走同一个函数(判定一份真相)。
## ⚠ 未付款:成交那一刻才扣钱, 放弃无需退款, 新卡留在货架上可反悔再拿。
func _on_replace_canceled() -> void:
	# ⚠ 只查 pick 不查 state(2026-08-27 真人报「不想替任何牌但界面不能操作」):
	# 取消是无副作用的逃生口, 状态再歪也必须能退 —— 困在替换态是最贵的卡死形状。
	if replace.pick == null:
		return
	Tape.on("repl_off", {"id": String(replace.pick.id), "coins": phrase.coins})
	replace.exit()
	shop.show_board()


func _on_slot_tapped(k: int) -> void:
	if state != St.DRAFT or replace.pick == null:
		return
	var new_j = replace.pick
	if k == 0:
		_on_replace_canceled()       # tapping the target cancels(与按钮同源)
		return
	var old = run.joker_slots[k]
	var price := Economy.shelf_price(new_j, run.joker_slots)
	# (借展样品的零退款特判已随样品一起删 2026-08-24 —— 槽里的卡现在全是玩家自己拿的)
	var refund := Economy.sell_value(old)
	if phrase.coins + refund < price:
		fx.float_text(Lingo.t("◆ 不足"), joker_views[k].get_global_position() + Vector2(30, 40), Color("ff5f7e"))
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
	_fx_acquired(new_j, k)
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
			return Lingo.t("点歌 · %s") % Run.request_label(phrase.request_goal)
		"lostpage":
			return Lingo.t("将丢 · %s") % ("?" if phrase.marked_cache_card == null \
				else phrase.marked_cache_card.label())
		"throttle":
			# 2026-08-25 张数重铸:限的是弃换合计张数, 不再是次数。
			return Lingo.t("弃换余 %d 张") % maxi(0,
				SectionMod.action_cards_max(cur_modifier) - phrase.action_cards_used)
		"onetake":
			return Lingo.t("弃牌余 %d 张") % maxi(0,
				SectionMod.discard_cards_max(cur_modifier) - phrase.discard_cards_used)
		"callout":
			if bool(run.mod_roll.get("solved", false)):
				return Lingo.t("点名已解除 ✓")
			return Lingo.t("点名 · %s") % String(DB.ui().get("patterns", {})
				.get(str(int(run.mod_roll.get("kind", -1))), "?"))
		"oneswap":
			return Lingo.t("交换余 %d 次") % maxi(0,
				SectionMod.swap_action_limit(cur_modifier) - phrase.swap_actions_used)
		"ration":
			return Lingo.t("弃牌余 %d 张") % maxi(0, phrase.discard_budget - phrase.discards_used)
		"trilogy":
			return Lingo.t("曲目 %d/%d") % [run.section_kinds.size(),
				SectionMod.required_kinds(cur_modifier)]
		"switchtrack":
			return Lingo.t("选择轨道") if phrase.action_track == "" else (
				Lingo.t("仅可弃牌") if phrase.action_track == "discard" else Lingo.t("仅可交换"))
		"handseal":
			return Lingo.t("弃牌封 · %s") % ("?" if phrase.sealed_hand_card == null \
				else phrase.sealed_hand_card.label())
		"doubleseal":
			return Lingo.t("手牌/缓存双封")
		"wetink":
			return Lingo.t("缓存锁 %d") % phrase.locked_cache_cards.size()
		"rush":
			if run.boon() == "spotlight" and phrase.spotlight_card != null:
				return Lingo.t("聚光 · %s") % phrase.spotlight_card.label()
			return Lingo.t("固定 6 秒")
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
		_note_tutorial("swap")
		_action_feedback()
	else:
		Tape.on("deny", {"why": "blind_swap", "h": hand_i, "c": cache_i, "at": elapsed})
		fx.float_text(_deny_swap_why(), hand.card_pos(hand_i) + Vector2(30, -10), StageTheme.PINK)
	_refresh()


## Central action feedback: wave blip + timing marks (Finale / Momentum read
## these — the only clock-derived joker signals, per docs/design/jokers.md A2).
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


## 掷类脸的明掷结果文案(轮盘/变色灯, 2026-08-25):追加在盲注卡命令行后,
## 开局即示人 —— 明掷纪律:随机决定多难/打哪个, 但结果必须当场亮出来。
## ensure 幂等, 先掷后读;文案全走 Lingo(t_lingo 守裸中文)。
func _roll_note() -> String:
	run.ensure_mod_roll()
	var roll: Dictionary = run.mod_roll
	if int(roll.get("sec", -2)) != run.section_idx:
		return ""
	if roll.has("worse"):
		if bool(roll["worse"]):
			return " " + Lingo.t("(掷出:封 2 格)")
		return " " + Lingo.t("(掷出:封 1 格)")
	var suit := int(roll.get("suit", -1))
	if suit >= 0:
		var names := [Lingo.t("梅花"), Lingo.t("方块"), Lingo.t("红桃"), Lingo.t("黑桃")]
		return " " + Lingo.t("(中签:%s)") % names[suit]
	if roll.has("kind"):
		# 牌型名走 ui.json 的 patterns 表(DB 出口已本地化, 不再包 Lingo)。
		var kname := String(DB.ui().get("patterns", {}).get(str(int(roll["kind"])), "?"))
		return " " + Lingo.t("(点名:%s)") % kname
	return ""


## 弃牌被拒时的原因短语(2026-08-11 用户「为什么经常不能弃牌」):镜像 core
## can_discard 的分支顺序逐条问过去, 文案在 data/ui.json hand.deny(改文案=改 JSON),
## 代码里只留兜底 —— 拒绝必须说清是哪张脸在拒。
func _deny_discard_why(sel_h: Array, sel_c: Array) -> String:
	var d: Dictionary = DB.ui().get("hand", {}).get("deny", {})
	if not _discard_open():
		return String(d.get("window", "弃牌已关闭"))
	var lim := SectionMod.discard_action_limit(cur_modifier)
	if lim >= 0 and phrase.discard_actions_used >= lim:
		return String(d.get("onetake", "弃牌张数到顶"))
	var shared := SectionMod.action_limit(cur_modifier)
	if shared >= 0 and phrase.action_count >= shared:
		return String(d.get("throttle", "弃换张数用尽"))
	# 张数重铸(2026-08-25):镜像 can_discard 新增的两条张数分支, 文案复用同两把钥匙。
	var sel_n: int = sel_h.size() + sel_c.size()
	var cards_cap := SectionMod.discard_cards_max(cur_modifier)
	if cards_cap >= 0 and phrase.discard_cards_used + sel_n > cards_cap:
		return String(d.get("onetake", "弃牌张数到顶"))
	var combo_cap := SectionMod.action_cards_max(cur_modifier)
	if combo_cap >= 0 and phrase.action_cards_used + sel_n > combo_cap:
		return String(d.get("throttle", "弃换张数用尽"))
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
		return String(d.get("throttle", "弃换张数用尽"))
	var combo_cap := SectionMod.action_cards_max(cur_modifier)
	if combo_cap >= 0 and phrase.action_cards_used + 1 > combo_cap:
		return String(d.get("throttle", "弃换张数用尽"))
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
		_note_tutorial("discard")
		# 跨区多选 = 手牌和缓存**同时**选中过 —— 教学关第 6 步教的正是这个,
		# 而它只有在这里才看得出来(组件只报选了哪些下标, 不报「这算不算跨区」)。
		if sel_h.size() > 0 and sel_c.size() > 0:
			_note_tutorial("multiselect")
		_notify_discard(total)
		hand.clear_selection()
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
		# ⚑ 拖到弃牌键的单张直弃也算数 —— 教学关第 2/3 步问的是「弃没弃」,
		# 不是「用哪个手势弃的」。只记多选那条路会让拖拽玩家永远推进不了。
		_note_tutorial("discard")
		hand.clear_selection()
		_action_feedback()
	else:
		Tape.on("deny", {"why": "blind_discard", "k": 1, "at": elapsed})
	_refresh()


## ---- drag & drop targets ----


# ============================== RENDER ==============================

func _refresh() -> void:
	var decide: bool = state == St.DECISION
	if state != St.RESOLVE and not _rolling():
		_shown_score = run.section_score
	# ⚠⚠ **必须走 `run.target()`, 不许直接索引 SECTION_TARGETS**(2026-08-09 修的真 bug):
	# 判生死走的是 `Run.target()`(乘了 `SectionMod.target_mult`), 而这里曾经读原始表 ——
	# `raisedbar`(目标 ×1.5)进池之后, HUD 会显示 4198 而实际要 6297, 进度条甚至先满、
	# 最后判失败。**同一个函数被绕过的第六次**(前五次见 LESSONS.md「模型覆盖」)。
	var target: int = run.target()
	hud.refresh({"section_idx": run.section_idx, "coins": phrase.coins,
		"score": _shown_score, "target": target, "phrase_no": run.phrase_index,
		# 教学关 target = 0 ⇒ 0/0 = NaN(GDScript 浮点除零不报错), 进度条会画成残条(评审)
		"fraction": 0.0 if target <= 0 else float(run.section_score) / float(target)})
	var sel_n: int = hand.sel_hand.size() + hand.sel_cache.size()
	hand.discard_key.fee = GameConfig.DISCARD_COST * maxi(1, sel_n)

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
		"mask_rank": SectionMod.hide_ranks(cur_modifier) and decide,
		"mask_suit": SectionMod.hide_suits(cur_modifier) and decide,
		"discard_blocked_hand": phrase.discard_blocked_hand(),
		"discard_blocked_cache": phrase.discard_blocked_cache(),
		"swap_blocked_hand": phrase.swap_blocked_hand(),
		"swap_blocked_cache": phrase.swap_blocked_cache(),
		"marked_cards": marked_cards})
	# ⚠ 牌堆剩余张数**不再显示**(2026-08-31 用户拍板)——唱片是它唯一的显示位。
