class_name Hand
extends Control

## Hand row + cache row + the two DJ keys (design/tech.md view split). Owns the
## pure view state — selection, last-seen cards for flip detection, the
## deal flip — and emits intent signals; the orchestrator validates against
## the Phrase and calls refresh(vm) back. Geometry/copy from data/ui.json.
##
## Note on parity: Phrase.swap_with_cache only fails on bad indices and
## every index here comes from a real card, so the legacy "clear selection
## on success" is equivalent to clearing before the request.

signal sort_pressed()
signal discard_pressed(sel_h: Array, sel_c: Array)
signal single_discard(zone: String, idx: int)
signal swap_requested(hand_i: int, cache_i: int)
signal selection_changed()
## 点选的**意图**信号(打点用), 与上面那条重绘信号分开:selection_changed 是
## 「重画一下」, 它不说发生了什么, 而且连着无参的 _refresh(), 改签名会打断连接。
## on = true 选中 / false 取消。拖拽与弃牌导致的清空**不发这条** —— 那是 swap/disc
## 的必然后果, 从那两个事件可推。
signal card_picked(zone: String, i: int, on: bool)

var _stage: Dictionary = DB.ui()["stage"]
var _cfg: Dictionary = DB.ui()["hand"]
var CARD_W: float = float(_stage["card_w"])
var CARD_H: float = float(_stage["card_h"])
var GAP: float = float(_stage["gap"])
var HAND_X0: float = (720.0 - (CARD_W * 5.0 + GAP * 4.0)) * 0.5
var HAND_CARD_Y: float = float(_stage["hand_card_y"])
var CACHE_Y: float = float(_stage["cache_y"])
var LIFT_BASE: float = float(_stage["lift_base"])
var LIFT_SCORING: float = float(_stage["lift_scoring"])
var LIFT_SELECTED: float = float(_stage["lift_selected"])

var sel_hand: Array = []
var sel_cache: Array = []
var _last_hand: Array = []
var _last_cache: Array = []
var _deal_flip := false
var _decide := false
# Default keeps direct unit/probe construction backward-compatible; every
# runtime refresh immediately replaces it with the current Blind gate.
var _can_swap := true
var _discard_blocked_hand: Dictionary = {}
var _discard_blocked_cache: Dictionary = {}
var _swap_blocked_hand: Dictionary = {}
var _swap_blocked_cache: Dictionary = {}
var _marked_cards: Dictionary = {}
## PaperCard -> 正在跑的翻牌 tween。存着是为了在下一次翻牌前掐掉上一个,
## 见 _flip_reveal 顶部的注释。
var _flips_running: Dictionary = {}
var hand_cells: Array = []
var hand_cards: Array = []
var cache_holder: Control
var sort_key: Widgets.DJKey
var discard_key: Widgets.DJKey


func _ready() -> void:
	var htabp := PanelContainer.new()
	htabp.add_theme_stylebox_override("panel", StageTheme.box(Color("1c2350"), Color(0.63, 0.71, 1.0, 0.35), 1, 14))
	var htab := StageTheme.label(String(_cfg["hand_tab"]), StageTheme.zh(), 16, Color("dfe6ff"), HORIZONTAL_ALIGNMENT_CENTER)
	htab.custom_minimum_size = Vector2(96, 26)
	htabp.add_child(htab)
	add_child(htabp)
	htabp.position = _v2(_cfg["hand_tab_pos"])

	# hand row: five fixed cells, cards re-skinned in place on refresh
	for i in range(5):
		var cell := Control.new()
		cell.position = Vector2(HAND_X0 + i * (CARD_W + GAP), HAND_CARD_Y - LIFT_BASE)
		cell.size = Vector2(CARD_W, CARD_H + LIFT_BASE)
		add_child(cell)
		var pc := PaperCard.new()
		pc.size = Vector2(CARD_W, CARD_H)
		pc.position = Vector2(0, LIFT_BASE)
		pc.pressed.connect(_on_hand_tap.bind(i))
		pc.accept_zones = ["cache"]
		pc.drop_received.connect(_on_hand_drop.bind(i))
		cell.add_child(pc)
		hand_cells.append(cell)
		hand_cards.append(pc)

	var tabp := PanelContainer.new()
	tabp.add_theme_stylebox_override("panel", StageTheme.box(Color("1c2350"), Color(0.63, 0.71, 1.0, 0.35), 1, 14))
	var tab := StageTheme.label(String(_cfg["cache_tab"]), StageTheme.zh(), 15, Color("dfe6ff"), HORIZONTAL_ALIGNMENT_CENTER)
	tab.custom_minimum_size = Vector2(92, 24)
	tabp.add_child(tab)
	add_child(tabp)
	tabp.position = _v2(_cfg["cache_tab_pos"])

	sort_key = Widgets.DJKey.new()
	sort_key.accent = StageTheme.CYAN
	sort_key.zh_label = String(_cfg["sort_label"])
	sort_key.kind = "sort"
	sort_key.position = Vector2(HAND_X0, CACHE_Y)
	sort_key.size = Vector2(CARD_W, CARD_H)
	sort_key.pressed.connect(func() -> void: sort_pressed.emit())
	add_child(sort_key)

	discard_key = Widgets.DJKey.new()
	discard_key.accent = Color("ff5f7e")
	discard_key.zh_label = String(_cfg["discard_label"])
	discard_key.kind = "discard"
	discard_key.position = Vector2(HAND_X0 + 4 * (CARD_W + GAP), CACHE_Y)
	discard_key.size = Vector2(CARD_W, CARD_H)
	discard_key.pressed.connect(func() -> void:
		discard_pressed.emit(sel_hand.duplicate(), sel_cache.duplicate()))
	discard_key.dropped.connect(func(data: Dictionary) -> void:
		single_discard.emit(String(data.get("zone", "")), int(data.get("index", -1))))
	add_child(discard_key)

	cache_holder = Control.new()
	var cw := CARD_W * GameConfig.CACHE_CAP + GAP * (GameConfig.CACHE_CAP - 1)
	cache_holder.position = Vector2((720.0 - cw) * 0.5, CACHE_Y)
	cache_holder.size = Vector2(cw, CARD_H)
	add_child(cache_holder)


func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


# ---- selection & input (pure view state; intents go up as signals) ----

func _on_hand_tap(i: int) -> void:
	if not _decide:
		return
	if i >= 0 and i < hand_cards.size() and _discard_blocked_hand.has(hand_cards[i].card):
		return
	var on := not sel_hand.has(i)
	if on:
		sel_hand.append(i)
	else:
		sel_hand.erase(i)
	card_picked.emit("hand", i, on)
	selection_changed.emit()


## 点击 = **纯选择**, 手牌和缓存可以一起选(选来一起弃)。
## 2026-08-06 用户:「点到手牌区的卡和缓存区的卡就直接交换了, 但我有时候只是想
## 同时对他们弃牌」—— 这里原本有一条「已选 1 张手牌 + 点缓存 = 立刻对调」的捷径,
## 它把第二次点击**吞掉**了, 跨区多选根本选不出来。交换有自己的正式手势
## (CLAUDE.md:「拖拽 = 两张对调」), 捷径纯属多余, 删掉。
func _on_cache_card_tap(i: int) -> void:
	if not _decide:
		return
	if i >= 0 and i < _last_cache.size() and _discard_blocked_cache.has(_last_cache[i]):
		return
	var on := not sel_cache.has(i)
	if on:
		sel_cache.append(i)
	else:
		sel_cache.erase(i)
	card_picked.emit("cache", i, on)
	selection_changed.emit()


func _on_hand_drop(data: Dictionary, i: int) -> void:
	# a cache card was dropped onto hand card i -> swap
	if not _decide or not _can_swap:
		return
	if bool(data.get("swap_blocked", false)):
		return
	if i >= 0 and i < hand_cards.size() and _swap_blocked_hand.has(hand_cards[i].card):
		return
	if String(data.get("zone", "")) == "cache":
		sel_hand.clear()
		sel_cache.clear()
		swap_requested.emit(i, int(data.get("index", -1)))


func _on_cache_drop(data: Dictionary, i: int) -> void:
	# a hand card was dropped onto cache card i -> swap
	if not _decide or not _can_swap:
		return
	if bool(data.get("swap_blocked", false)):
		return
	if i >= 0 and i < _last_cache.size() and _swap_blocked_cache.has(_last_cache[i]):
		return
	if String(data.get("zone", "")) == "hand":
		sel_hand.clear()
		sel_cache.clear()
		swap_requested.emit(int(data.get("index", -1)), i)


func selection_total() -> int:
	return sel_hand.size() + sel_cache.size()


func clear_selection() -> void:
	sel_hand.clear()
	sel_cache.clear()


## sort clears only the hand selection (legacy behavior).
func on_sorted() -> void:
	sel_hand.clear()


## Next refresh flips the whole hand in (phrase start).
func deal_flip() -> void:
	_deal_flip = true


## The discard could not be honoured — jolt the key so it is never silent.
func reject_discard() -> void:
	discard_key.shake()


## 拒绝原因浮字的锚点(view/phrase.gd 用):弃牌键 / 某张手牌的全局位置。
func discard_key_pos() -> Vector2:
	return discard_key.get_global_position()


func card_pos(i: int) -> Vector2:
	if i >= 0 and i < hand_cards.size():
		return hand_cards[i].get_global_position()
	return get_global_position()


## Ghost-fly the hand card at i (discard feedback).
func ghost(i: int) -> void:
	if i >= 0 and i < hand_cards.size():
		_ghost_fly(hand_cards[i])


# ---- render ----

## vm keys: hand:Array[Card], cache:Array[Card], scoring:Dictionary,
##          decide:bool, can_swap:bool, fee:int, can_discard_sel:bool, can_drop:bool
func refresh(vm: Dictionary) -> void:
	_decide = bool(vm["decide"])
	_can_swap = _decide and bool(vm.get("can_swap", true))
	_discard_blocked_hand = vm.get("discard_blocked_hand", {})
	_discard_blocked_cache = vm.get("discard_blocked_cache", {})
	_swap_blocked_hand = vm.get("swap_blocked_hand", {})
	_swap_blocked_cache = vm.get("swap_blocked_cache", {})
	_marked_cards = vm.get("marked_cards", {})
	var cards_hand: Array = vm["hand"]
	var cards_cache: Array = vm["cache"]
	var scoring_set: Dictionary = vm["scoring"]
	# Cards the player cannot see (the hiding faces), keyed by Card object.
	# Defaulted so the screenshot probes that build a vm by hand keep working.
	var hidden: Dictionary = vm.get("hidden", {})

	var flips := 0
	for i in range(hand_cards.size()):
		if i >= cards_hand.size():
			continue
		var card: Card = cards_hand[i]
		var pc: PaperCard = hand_cards[i]
		var was: Card = _last_hand[i] if i < _last_hand.size() else null
		pc.setup(card)
		# 盖牌脸:牌背朝上。它仍然照常计分, 也仍然能选能弃能对调 ——
		# 拿走的只有「你知道它是什么」。结算时 Phrase 清空 hidden, 下一次
		# refresh 自然就翻开了(用户 2026-08-07 拍板的时机)。
		pc.set_back(hidden.has(card))
		pc.set_states(scoring_set.has(card), sel_hand.has(i))
		var hand_mark := ""
		if _marked_cards.has(card):
			hand_mark = "丢"
		if _discard_blocked_hand.has(card):
			hand_mark = "弃"
		if _swap_blocked_hand.has(card):
			hand_mark = "锁" if hand_mark != "" else "换"
		pc.set_blocked(hand_mark)
		# 2026-08-11 用户反馈「默认高度经常不同」:计分五张的抬升被读成噪音而不是信息 ——
		# 高度从此只区分「选中」,「哪五张在计分」交给 set_states 的 scoring 光效表达。
		var ty := LIFT_BASE
		if sel_hand.has(i):
			ty = LIFT_SELECTED
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(pc, "position:y", ty, 0.18)
		var hand_can_swap := _can_swap and not _swap_blocked_hand.has(card)
		pc.drag_payload = {"zone": "hand", "index": i,
			"discard_blocked": _discard_blocked_hand.has(card),
			"swap_blocked": not hand_can_swap} if _decide else {}
		pc.accept_zones = ["cache"] if hand_can_swap else []
		if _deal_flip or (was != null and was != card):
			_flip_reveal(pc, 0.09 * float(flips), not hidden.has(card))
			flips += 1
	_last_hand = cards_hand.duplicate()

	# Cache slots. Normally every slot holds a card, but the `smallstage` face
	# takes one away for a whole section — and a slot that just renders as blank
	# space reads as "a card went missing", not as "this blind sealed a slot".
	# So any slot the cache is short of gets an explicit sealed marker.
	for child in cache_holder.get_children():
		child.queue_free()
	for i in range(cards_cache.size(), GameConfig.CACHE_CAP):
		var seal := SealedSlot.new()
		seal.size = Vector2(CARD_W, CARD_H)
		seal.position = Vector2(float(i) * (CARD_W + GAP), 0)
		cache_holder.add_child(seal)
	for i in range(cards_cache.size()):
		var x := float(i) * (CARD_W + GAP)
		var pc := PaperCard.new()
		pc.size = Vector2(CARD_W, CARD_H)
		pc.position = Vector2(x, 0)
		pc.violet = true
		pc.setup(cards_cache[i])
		pc.set_back(hidden.has(cards_cache[i]))
		pc.set_states(false, sel_cache.has(i))
		var cache_card: Card = cards_cache[i]
		var cache_mark := "丢" if _marked_cards.has(cache_card) else ""
		if _discard_blocked_cache.has(cache_card):
			cache_mark = "弃"
		if _swap_blocked_cache.has(cache_card):
			cache_mark = "锁" if cache_mark != "" else "换"
		pc.set_blocked(cache_mark)
		pc.pressed.connect(_on_cache_card_tap.bind(i))
		var cache_can_swap := _can_swap and not _swap_blocked_cache.has(cache_card)
		pc.drag_payload = {"zone": "cache", "index": i,
			"discard_blocked": _discard_blocked_cache.has(cache_card),
			"swap_blocked": not cache_can_swap} if _decide else {}
		pc.accept_zones = ["hand"] if cache_can_swap else []
		pc.drop_received.connect(_on_cache_drop.bind(i))
		cache_holder.add_child(pc)
		var was_c: Card = _last_cache[i] if i < _last_cache.size() else null
		if was_c != null and was_c != cards_cache[i]:
			_flip_reveal(pc, 0.09 * float(flips), not hidden.has(cards_cache[i]))
			flips += 1
	_last_cache = cards_cache.duplicate()
	_deal_flip = false

	discard_key.fee = int(vm["fee"])
	discard_key.active = _decide and bool(vm["can_discard_sel"])
	discard_key.accept_drop = _decide and bool(vm["can_drop"])
	discard_key.queue_redraw()
	sort_key.active = _decide
	sort_key.queue_redraw()


## Real card flip: the card lands face-DOWN and is clearly readable as a back,
## then turns over — squash to an edge, swap to the face, open out.
##
## ⚠ `reveal = false` 时**停在背面**(盖牌脸)。这条不是为探针加的:动画原本
## 无条件以 `set_back(false)` 收尾, 于是每张新发/新补的牌都会被翻开 ——
## 盖牌脸在真实游戏里等于**画面上根本不生效**, 而逻辑侧已经把它当盲的在算。
## 那正是「规则只改了一半」的经典形态, 只不过这次反过来: 模型认了, 画面没认。
func _flip_reveal(pc: PaperCard, delay: float, reveal: bool = true) -> void:
	# ⚠ 掐掉这张卡上还没跑完的上一个翻牌 —— 它结尾那句 `set_back(false)` 会在
	# 之后才落地, 把新的状态**悄悄盖掉**。探针里就是这么撞上的:卡明明标着
	# hidden=true, 画出来却是正面, 因为上一轮的 tween 后到一步。
	if _flips_running.has(pc):
		var old: Tween = _flips_running[pc]
		if old != null and old.is_valid():
			old.kill()
	pc.set_back(true)
	pc.pivot_offset = pc.size * 0.5
	pc.scale = Vector2(0.82, 0.82)
	pc.modulate.a = 0.0
	var tw := create_tween()
	_flips_running[pc] = tw
	tw.tween_interval(delay)
	# 1. the back drops in and settles
	tw.set_parallel(true)
	tw.tween_property(pc, "modulate:a", 1.0, 0.12)
	tw.tween_property(pc, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	# 2. hold on the back so it actually reads as a card back
	tw.tween_interval(0.30)
	if not reveal:
		return                      # 盖牌脸:落下就完了, 不翻
	# 3. turn over
	tw.tween_property(pc, "scale:x", 0.04, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(pc.set_back.bind(false))
	tw.tween_property(pc, "scale:x", 1.0, 0.19).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _ghost_fly(pc: PaperCard) -> void:
	if pc.card == null:
		return
	var g := PaperCard.new()
	g.size = pc.size
	g.setup(pc.card)
	g.global_position = pc.global_position
	g.z_index = 50
	add_child(g)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(g, "position:y", g.position.y + 160.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(g, "rotation_degrees", 14.0, 0.4)
	tw.tween_property(g, "modulate:a", 0.0, 0.4)
	tw.chain().tween_callback(g.queue_free)


## A cache slot the section's Boss face has sealed (`smallstage`). Drawn in the
## SAME language as the empty joker slot (view/joker_slot.gd::_draw_empty):
## dim fill + four corner brackets. Two deliberate differences:
## ① violet, because that is the cache row's colour;
## ② the word is 「封」 not 「空」 — an empty slot invites you to fill it, and
##    this one cannot be filled until the blind is over.
class SealedSlot extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var s := h / 172.0
		var col := Color(0.72, 0.52, 1.0, 0.30)
		draw_rect(Rect2(0, 0, w, h), Color(0.72, 0.52, 1.0, 0.05), true)
		var l := 20.0 * s
		for corner in [Vector2(0, 0), Vector2(w, 0), Vector2(0, h), Vector2(w, h)]:
			var dx: float = 1.0 if corner.x == 0.0 else -1.0
			var dy: float = 1.0 if corner.y == 0.0 else -1.0
			draw_line(corner, corner + Vector2(dx * l, 0), col, 2.0)
			draw_line(corner, corner + Vector2(0, dy * l), col, 2.0)
		draw_string(StageTheme.zh(), Vector2(0, h * 0.5 + 9.0 * s), "封",
			HORIZONTAL_ALIGNMENT_CENTER, w, int(26.0 * s), Color(0.72, 0.52, 1.0, 0.5))
