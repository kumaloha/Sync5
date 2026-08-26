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
var music: Music             # 每段一首的 8 秒循环(view/music.gd, 2026-08-18)
var beacon: Beacon           # Tape 回传(view/beacon.gd, 1.1;配置关着时自睡)
var fx: StageFeedback        # 屏震/弹跳/飘字 —— 纯表现, view/feedback.gd
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
	# ⚑ 断点续玩(2026-08-24):有半局快照就直接回到拍边界, 不过首页 ——
	# 移动 Web 的刚需场景是「iOS 杀了标签页, 玩家点回来」, 他要的是牌桌不是菜单。
	if not SaveState.is_probe() and _resume_run():
		return
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
	# 点唱片 = 提前收工(2026-08-13 用户拍板)。⚠ 连在这里而不是 _ready:
	# `vinyl` 是 StageLayout 建的, 开局之后才拿到引用。
	if not vinyl.tapped.is_connected(_on_vinyl_tapped):
		vinyl.tapped.connect(_on_vinyl_tapped)
	# ⚑ 教学关:**只在第一次启动时出现一次**(用户 2026-08-07 拍板「教学只要一次」)。
	# 判据存在 `SaveState`(`user://`), 与将来的断点续玩共用同一个存档层。
	# ⚠⚠ **必须在 roll_faces 之前设** —— 教学关不掷 Boss 脸(见 Run.roll_faces),
	# 而「起」按定义就是**安全的地方、无惩罚地理解机制**。顺序写反了截图里就会
	# 挂着一张「禁回」, 我第一版正是这么错的。
	run.tutorial = not SaveState.seen_tutorial()
	# ⚑ **游戏是唯一传真实局数的地方**(探针一律走缺省 = 全解锁, 理由在 SectionMod.unlocked_at)。
	# ⚠ `+1` 是因为掷脸发生在 `note_run_started()` **之前** —— 存档里的 `runs_total`
	# 此刻还是「以前玩过几局」, 而这一局是第 `runs_total + 1` 局。
	_begin_run()
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
	hand.reshuffle_pressed.connect(_on_hand_reshuffle)
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
	# ⚠ 必须连在构造**之后** —— 第一版插进了 _build_ui 的信号块(那时 replace 还是 null),
	# 整个 _ready 当场断掉, headless 套件测不到 view, 是截图探针抓到的。
	replace.canceled.connect(_on_replace_canceled)


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


func _on_intro_done() -> void:
	if state == St.INTRO:
		# 主动点掉 vs 等它自己走完 —— 「急着打」和「在读盲注规则」是两回事,
		# 也是教学空间那个待验问题(S1 就是墙、开局就带 Boss 规则)的观测点
		Tape.on("intro", {"skip": intro != null and intro.skipped})
		_start_phrase()


func _start_phrase() -> void:
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
		_play_blind_closeup()
	# 拍首下拍:钟起步的那一刻 kick 归零(Music.sync_beat 文件内有整套推导)。
	# 特写路径除外 —— 那 2 秒 state=INTRO 钟不走, kick 由 _closeup_done 落。
	if state == St.DECISION:
		music.sync_beat()


## 教学关的一行提示 + 分区指向 + 多选解锁。抽成函数是为了**拍中推进后立刻重放**
## (2026-08-18 用户:「应该消失, 进入下一个提示」)。正式局 hint 空串 ⇒ 整块隐身。
func _apply_tutor_hint() -> void:
	# 教学关的一行提示 + 分区指向 —— 正式局 hint 是空串, TutorHint 整块隐身。
	# ⚠ 区域名 → 矩形的翻译在**编排器**这一侧:`core/` 不认识像素(坐标归 ui.json)。
	var h := run.tutorial_hint()
	var rects: Array = []
	if run.tutorial:
		# ⚑ 矩形从**活部件**取, 不再读 `ui.json` 的手抄坐标(见 `Hand.focus_rect` 的文件头:
		# 那三个数是目测的, 而真值是运行时按 stage 常量算的 ⇒ 位置对不上是必然的)。
		# `ui.json` 的 `tutor_focus` 现在只剩「合法区域名」这一个职责。
		for name in Tutorial.focus(run.tutorial_step):
			var q := Rect2()
			if name == "hud":
				var hp: Array = DB.ui()["hud"]["pos"]
				var hs: Array = DB.ui()["hud"]["size"]
				q = Rect2(float(hp[0]), float(hp[1]), float(hs[0]), float(hs[1]))
			elif name == "blind":
				q = Rect2(blind_card.position, blind_card.size)
			elif name == "jokers":
				# 小丑牌四槽的并集 —— 从活部件取(与 hand.focus_rect 同一条纪律)
				q = Rect2(joker_views[0].position, joker_views[0].size)
				for jv in joker_views:
					q = q.merge(Rect2(jv.position, jv.size))
			else:
				q = hand.focus_rect(name)
			if q.size.x > 0.0:
				rects.append(q)
	# ⚑ 把**全部**可高亮区域喂给提示条, 让它自己躲开 —— 而不是我在这里算坐标。
	# 屏幕下半部三块区域占满, 硬贴高亮区必然压住别的字(第一版就是这么糊的)。
	var avoid: Array = []
	if run.tutorial:
		for rn in Tutorial.regions():
			var aq := hand.focus_rect(rn)
			if aq.size.x > 0.0:
				# ⚠ 往上放宽 44px —— 「手 牌 区」「缓 存 区」那两个标签画在**容器矩形之外**
				# (上方 ~35px), 只躲容器会让条正好压住标签。第一版就是这么漏的:
				# 卡片不压了, 标签仍然被盖。**可高亮区 ≠ 它的视觉范围**, 差的正是这一条
				# —— 同 docs/design/ui_meta.md 那句「对齐类反馈要查视觉顶端而不是几何顶端」。
				avoid.append(Rect2(aq.position - Vector2(0, 44), aq.size + Vector2(0, 44)))
		# 手牌框(走圈轨道)整块入避让表(2026-08-24 用户:「教学文字高度不对, 会挡住
		# 读秒的进度条光圈」):进度轨贴着框边发光, 条坐在框顶就把光圈盖了。
		# 往上放宽 20px —— 轨道辉光超出几何边(还是那句「视觉顶端 ≠ 几何顶端」)。
		avoid.append(Rect2(orbit.position - Vector2(0.0, 20.0),
			orbit.size + Vector2(0.0, 20.0)))
	if run.tutorial:
		_stage_tutor_props()
	# ⚑ 压暗层的常亮洞(2026-08-24 用户两条:「倒计时边框也应该在教学的时候被看到」·
	# 「展示小丑牌的时候, 下方整个版面是黑的」):**手牌框顶起往下的整个操作面**
	# (倒计时边框/节拍菱形/读秒/手牌/缓存/理牌弃牌键)教学期间永远不压暗 ——
	# 时钟是 8 秒规则的脸面, 下半屏是玩家的手, 两样都不许黑。提亮与光圈仍只跟焦点走。
	var holes: Array = []
	if run.tutorial:
		holes.append(Rect2(0.0, orbit.position.y, 720.0, 1280.0 - orbit.position.y))
		# 顶栏(分数/目标/金币/拍数)也常亮(2026-08-24 用户:「盲注教学前一轮,
		# 当时积分的数字被挡住了」)—— 教学教的就是拿分, 分数滚动不许发生在暗区里。
		var hp: Array = DB.ui()["hud"]["pos"]
		var hs: Array = DB.ui()["hud"]["size"]
		holes.append(Rect2(float(hp[0]), float(hp[1]), float(hs[0]), float(hs[1])))
	tutor.set_hint(String(h["command"]), String(h["signal"]), rects, avoid, holes)
	# 能力全程全开(用户拍板「取消全部能力压制」;5 步版 unlock 第一步即全解锁)。
	# ⚠ 组件不认识教学关(铁律:组件只发意图, 状态由编排器给), 所以这里翻译成
	# 它听得懂的话:`multi_select`。正式局恒 true, 教学关第一步起也恒 true。
	hand.multi_select = run.tutorial_unlocked("multiselect")


var _tutor_blind_shown := false
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

## 教学的示范道具。⚑ **借展样品已删**(2026-08-24 用户:「第三段不应该直接给满小丑牌,
## 应该跟正常玩普通的一关一样 —— 一开始没有小丑牌, 直接跳出来让玩家选」):
## 第 3 步改为在步首弹**真商店**(首张 Target 免费三选一, `_advance` 里接线),
## 选了什么带什么进正式局, 不再有「转正收回道具」这回事。
## 第 4 轮保留:盲注卡亮样例脸(禁回)+ 放一次特写 —— 盲注的登场时刻本身就是教学。
func _stage_tutor_props() -> void:
	if run.tutorial_step >= 3 and not _tutor_blind_shown:
		_tutor_blind_shown = true
		blind_card.setup(0, SectionMod.by_id("norepeat"), null)
		blind_card.visible = true
		if not SaveState.is_probe():
			_play_blind_closeup()


## 编排器报教学动作 + **拍中回执**:做完动作提示当场收掉(08-18「应该消失」拍板),
## 但**步进等结算**(2026-08-24 用户:「换一下之后立刻就跳到小丑牌了 ——
## 应该等结算完了再到小丑牌」)。下一步的内容属于下一拍;拍中只把这一步的提示
## 熄掉当回执, 高亮一起收(画面回正常), 结算后 `_start_phrase` 才上下一课。
func _note_tutorial(action: String) -> void:
	run.tutorial_note(action)
	if run.tutorial and Tutorial.require(run.tutorial_step) != "" \
			and run.tutorial_pending() == "":
		tutor.set_hint("", "")


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
		wave.on_score(float(gained_score) / 80.0))
	# joker triggers pop over their slots, staggered
	var popups: Array = outcome["popups"]
	for k in range(popups.size()):
		var p: Dictionary = popups[k]
		var slot_view: Control = joker_views[p["slot"]]
		var at: Vector2 = slot_view.get_global_position() + Vector2(slot_view.size.x * 0.28, -6.0)
		var tw := create_tween()
		tw.tween_interval(0.30 + 0.22 * float(k))
		tw.tween_callback(fx.float_text.bind(String(p["text"]), at, StageTheme.GOLD))
	if gained_coins > 0:
		fx.float_text("+%d ◆" % gained_coins, hud.coin_anchor() + Vector2(20, 40), StageTheme.GOLD)


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
	# 每一拍都必然出一手牌(哪怕是高牌), 所以 `play` 恒真:第 1 步的门 = 「把一拍打完」。
	# ⚠ 顺序:先记 play → 再 try_advance → 再 `run.advance()` → 最后才轮到 `tutorial_done()`,
	# 因为 `tutorial_done()` 读的正是 try_advance 推出来的那个下标。
	run.tutorial_note("play")
	run.tutorial_try_advance()
	var out := run.advance()
	# ⚑ 教学关的商店时刻只有一个(2026-08-24 用户:「第三段…一开始就是没有小丑牌,
	# 直接跳出来让玩家选小丑牌」):第 3 步开头弹真商店(首张 Target 免费三选一,
	# 与正式局同一个流程), 选完/继续 ▸ 都回拍;每 3 拍的正式节奏在教学段不再开第二次店 ——
	# 一关只教一次「买」, 商店的完整节奏留给正式局自己展示。
	if run.tutorial and not bool(out["section_done"]):
		if run.tutorial_step == 2 and run.joker_slots[0] == null:
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
		_tutor_blind_shown = false
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
		var loan_out := Joker.slots_loan(run.joker_slots)
		if int(loan_out.repay) > 0:
			if phrase.coins < int(loan_out.repay):
				Tape.close({"ok": false, "sec": run.section_idx,
					"score": run.section_score, "target": run.target(),
					"beats": run.phrase_index, "why": "loan"})
				SaveState.clear_checkpoint()
				SaveState.settle_run_meta(false, run.section_idx, _faces_encountered(),
					String(run.boon()), _final_target_id())
				music.play_jingle(false)
				# 死因行:分数达标却因预支违约死掉, 只念分数会让玩家困惑(文案在
				# ui.json 的 banner 节, DB.ui() 已过语言层, %d = 还不上的还款额)
				run_end.show_fail(run.section_score, run.target(),
					String(DB.ui().get("banner", {}).get("fail_loan", "%d◆")) % int(loan_out.repay))
				return
			phrase.coins -= int(loan_out.repay)
			run.coins = phrase.coins
			Tape.on("loan", {"pay": int(loan_out.repay), "coins": phrase.coins})
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
	run.next_section()
	_loan_borrow()
	_tape_section()
	_open_draft()


## 预支借款(2026-08-26 金融组):段初自动 +borrow, 走 grant 收口(吃穷开心 cap)。
## 开局(S1 初)不接:那时持仓恒空(首张卡最早来自第一次商店), 借款恒 0。
func _loan_borrow() -> void:
	var loan := Joker.slots_loan(run.joker_slots)
	if int(loan.borrow) <= 0:
		return
	if phrase == null:
		run.coins = Economy.grant(run.coins, int(loan.borrow), run.joker_slots)
	else:
		phrase.coins = Economy.grant(phrase.coins, int(loan.borrow), run.joker_slots)
		run.coins = phrase.coins
	Tape.on("loan", {"get": int(loan.borrow), "coins": run.coins})


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
	_begin_run()          # 与开局同一份三步(评审 R2):Director/min_run/局数都要算上这一局
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
	for i in range(joker_views.size()):
		joker_views[i].set_joker(null)
	_shown_score = 0


## 开局三步(2026-08-21 评审 R2 收口):定局数 → 喂 Director(排序表 + 玩家状态 m)→
## 按真实局数掷脸 → 记局数。**开局与「再来一次」必须走同一份。**
## 此前重开路径只调 `_reset_run()`, 而 `Run.reset()` 内部用缺省 `run_index = -1` 掷脸 ⇒
## min_run 门失效(禁回第 2 局重开就能冒出来)、Director 永远第 1 局状态、ctx 用上一局的
## 快照、runs_total/history 分叉 —— 四条全静默。「第二条入口漏掉主路径的步骤」是这个项目
## 最贵的形状之一, 所以收成一个函数, 别再让两条入口各写各的。
## ⚠ `_run_index` 的 `+1`:掷脸发生在 `note_run_started()` 之前, 存档里还是「以前玩过几局」。
func _begin_run() -> void:
	_run_index = 1 if SaveState.is_probe() else SaveState.runs_total() + 1
	_feed_director()
	run.roll_faces(-1, _run_index)
	SaveState.note_run_started()
	music.new_run()   # 一局一首(2026-08-25 拍板):开局清曲, 第一拍重抽


## 从快照恢复半局(2026-08-24)。恢复**不走开局三步** —— 掷脸/喂 Director/记局数
## 都已在原局发生, 产物在快照里(core/run.gd::restore 文件头有整段论证)。
## 返回 false = 没有快照或快照坏了, 调用方照常开首页。
func _resume_run() -> bool:
	var snap := SaveState.checkpoint()
	if snap.is_empty():
		return false
	_reset_run(false)
	if not run.restore(snap):
		SaveState.clear_checkpoint()
		_reset_run(false)     # 半恢复的 run 不能留着 —— 重置回干净初态
		return false
	_run_index = int(snap.get("run_index", 1))
	_front_latch = true
	for i in range(joker_views.size()):
		joker_views[i].set_joker(run.joker_slots[i])
	if not vinyl.tapped.is_connected(_on_vinyl_tapped):
		vinyl.tapped.connect(_on_vinyl_tapped)
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
	shop.open(run.joker_slots, phrase.coins, run.section_idx,
		SectionMod.by_id(String(run.run_faces.get(run.section_idx, ""))),
		run.section_score if mid else -1,
		run.phrases_left() if mid else -1,
		run.target(),      # ⚠ 加码脸乘过的那个目标, 不是原始表(2026-08-09)
		BlindBoon.by_id(run.boon()))
	# 段中/段末两态要分开统计:段中是「已知缺口下的解题」, 段末是「对下一场下注」,
	# 购买行为本来就不该混在一起看(docs/design/levels.md 的核心论证)
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
	# 教学关:挑完那张免费 Target 立刻开拍(2026-08-24 用户流程:「选了之后告诉玩家
	# 最多是 4 个格子」—— 那句话在下一拍的提示条上, 店里不多留)。
	if run.tutorial and j.kind == "target":
		shop.close()
		_start_phrase()
		return
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
## 升级一张已装备的小丑牌 —— **金币的主出口**(2026-08-16)。
##
## ⚠ **钱和等级只在这里动**(CLAUDE.md:金币/装槽等经济动作只发生在编排器)。
## 组件只发意图, 所以 `shop.gd` 里那个按钮不碰 `_coins` 也不碰 `level`。
	_start_phrase()


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
	if state != St.DRAFT or replace.pick == null:
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


## 洗牌(2026-08-26 超级百搭配套):付费整手重掷 + 弃牌堆洗回 —— 钓 JOKER 的实体。
## 金币动作, 所以判定/扣费都在 core(phrase.reshuffle 自守 can_reshuffle);
## 这里只做编排:拒绝要浮原因(键抖动只说「不行」不说「为什么」的教训), 打点记事实。
func _on_hand_reshuffle() -> void:
	if state != St.DECISION:
		if state == St.RESOLVE:
			fx.float_text(String(DB.ui().get("hand", {}).get("deny", {})
				.get("locked", "")),
				hand.discard_key_pos() + Vector2(34, -110), StageTheme.PINK)
		return
	if not phrase.can_reshuffle():
		hand.reshuffle_key.shake()
		fx.float_text(String(DB.ui().get("hand", {}).get("deny", {})
			.get("reshuffle", "")),
			hand.discard_key_pos() + Vector2(34, -110), StageTheme.PINK)
		Tape.on("deny", {"why": "reshuffle", "at": elapsed})
		return
	phrase.reshuffle()
	hand.clear_selection()
	hand.deal_flip()
	Tape.on("rsfl", {"cost": Economy.reshuffle_cost(), "at": elapsed})
	_action_feedback()
	_refresh()


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
		# ⚑ 拖到弃牌键的单张直弃也算数 —— 教学关第 2/3 步问的是「弃没弃」,
		# 不是「用哪个手势弃的」。只记多选那条路会让拖拽玩家永远推进不了。
		_note_tutorial("discard")
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
	# 洗牌键:牌堆里有万能才亮(装了百搭/超级百搭);付不起时压暗但不藏 —— 玩家要看得见价。
	hand.reshuffle_key.visible = decide and not phrase.deck.wild_extra.is_empty()
	hand.reshuffle_key.fee = Economy.reshuffle_cost()
	hand.reshuffle_key.active = phrase.can_reshuffle()
	# 弃牌键亮价(2026-08-27 journey #1):经济 v2 弃牌 1◆/张, 键上必须念价 ——
	# 否则是暗扣钱。fee = 选中张数 × 单价;没选中时念单价(先知道要钱再选)。
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
	vinyl.set_count(run.deck.remaining())
