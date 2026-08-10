class_name Shop
extends Control

## The joker draft shop (design/tech.md view split): board, pricing, reroll and
## skip live here; the orchestrator owns the money and the slots (economy
## actions never happen inside a view). 2026-08 shop model: priced supports,
## paid reroll, full-slot replace, pivot-arc Target on the shelf.
## Layout + copy from data/ui.json "shop".

signal bought(j, price: int)          # affordable pick — orchestrator deducts & installs
signal replace_requested(j)           # full slots: orchestrator runs the replace flow
signal skipped()                      # orchestrator pays the skip reward
signal reroll_paid(cost: int)         # orchestrator deducts, then calls redeal()
signal denied(why: String)            # 想买/想刷但钱不够 — 编排器打点(购买力压力)

var _cfg: Dictionary = DB.ui()["shop"]
var _layer: Control
var _views: Array = []
var _price_labels: Array = []
var _kind_label: Label
# blind board on top of the shop (2026-08-05 真人试玩:「盲注可以在选小丑牌的
# 时候出」— Balatro 的商店与盲注本就 1:1 交替,买牌时就看着下一场买)
var _blind_board: Widgets.BlindBoard
var _reroll_btn: Button
var _skip_btn: Button
var _candidates: Array = []
var _reroll_count := 0
var _slots: Array = []
var _coins := 0
var _section := 0


func _ready() -> void:
	# explicit rects, not anchor presets — the preset sets anchors without
	# offsets and a nested chain resolves to 0×0 (design/ui_meta.md 渲染手法)
	position = Vector2.ZERO
	size = Vector2(720, 1280)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer = Control.new()
	_layer.position = Vector2.ZERO
	_layer.size = size
	_layer.visible = false
	add_child(_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.10, 0.90)
	dim.position = Vector2.ZERO
	dim.size = size
	_layer.add_child(dim)

	# blind board: what you are shopping FOR — populated per open()
	_blind_board = Widgets.BlindBoard.new()
	_blind_board.position = _v2(_cfg["blind_pos"])
	_blind_board.size = _v2(_cfg["blind_size"])
	_layer.add_child(_blind_board)

	var title := StageTheme.label(String(_cfg["title"]), StageTheme.zh(), 34, StageTheme.INK, HORIZONTAL_ALIGNMENT_CENTER)
	title.position = _v2(_cfg["title_pos"])
	title.size = Vector2(720, 48)
	_layer.add_child(title)

	_kind_label = StageTheme.label("", StageTheme.num("Medium"), 18, StageTheme.DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_kind_label.position = _v2(_cfg["kind_pos"])
	_kind_label.size = Vector2(720, 26)
	_layer.add_child(_kind_label)

	var dw: float = float(_cfg["card_w"])
	var dgap: float = float(_cfg["card_gap"])
	var cy: float = float(_cfg["cards_y"])
	var dx0 := (720.0 - dw * 3.0 - dgap * 2.0) * 0.5
	for i in range(3):
		var dv := JokerSlotView.new()
		dv.tappable = true
		dv.position = Vector2(dx0 + float(i) * (dw + dgap), cy)
		dv.size = Vector2(dw, dw * 1.10)
		dv.tapped.connect(_on_pick.bind(i))
		_layer.add_child(dv)
		_views.append(dv)
		# price tag under each card (targets read 免费)
		var pl := StageTheme.label("", StageTheme.num("Bold"), 22, StageTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
		pl.position = Vector2(dx0 + float(i) * (dw + dgap), cy + dw * 1.10 + float(_cfg["price_dy"]))
		pl.size = Vector2(dw, 30)
		_layer.add_child(pl)
		_price_labels.append(pl)

	var by: float = float(_cfg["btn_y"])
	_reroll_btn = _button("")
	_reroll_btn.position = Vector2(360.0 - 220.0 - 12.0, by)
	_reroll_btn.pressed.connect(_on_reroll)
	_layer.add_child(_reroll_btn)

	# 2026-08-06 用户:「还看到有跳过按钮, 不要, 只需要刷新」—— 跳过**奖励**已删,
	# 但这个按钮本身是商店的**唯一免费出口**: 买不起又刷不起时没有它会卡死在商店里,
	# 所以它留下来, 只是不再是一笔收入, 措辞也从「跳过」改成「继续」。
	_skip_btn = _button(String(_cfg["skip_text"]))
	_skip_btn.position = Vector2(360.0 + 12.0, by)
	_skip_btn.pressed.connect(_on_skip)
	_layer.add_child(_skip_btn)


func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", StageTheme.zh())
	b.add_theme_font_size_override("font_size", 20)
	b.custom_minimum_size = Vector2(220, 58)
	b.focus_mode = Control.FOCUS_NONE
	var sb := StageTheme.box(Color(0.16, 0.19, 0.4, 0.9), Color(0.63, 0.71, 1.0, 0.4), 1, 16)
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, sb)
	return b


## Enter the shop: fresh reroll counter, blind board for the section being
## entered (`mod` = its boss face), then deal.
##
## `score`/`left` >= 0 marks a MID-SECTION shop (2026-08-06 商店与盲注解耦):
## the blind is still running, so the board reports this blind's progress
## (还差 N 分 · 还剩 N 拍) instead of previewing the next one. Buying against a
## known deficit is the whole reason the shop was decoupled from the blind.
## ⚠⚠ `target` **由编排器传进来**(2026-08-09 修的真 bug):这里曾经自己索引
## `GameConfig.SECTION_TARGETS`, 漏掉了 `SectionMod.target_mult` —— `raisedbar` 进池后
## 盲注板会显示未加码的目标, 而「还差多少分」正是段中商店买牌的唯一依据。
## **乘法只写一处**(`Run.section_target_for`), 展示侧一律消费 `run.target()`。
func open(slots: Array, coins: int, section_idx: int, mod = null,
		score: int = -1, left: int = -1, target: int = -1, boon = null) -> void:
	_reroll_count = 0
	_blind_board.setup(section_idx,
		target if target >= 0 else Run.section_target_for(
			GameConfig.SECTION_TARGETS, section_idx,
			"" if mod == null else String(mod.id)),
		mod, "下一场", score, left, boon)
	redeal(slots, coins, section_idx)


## Re-deal after a reroll (counter survives; coins already deducted).
func redeal(slots: Array, coins: int, section_idx: int) -> void:
	_slots = slots
	_coins = coins
	_section = section_idx
	_deal()


func close() -> void:
	_layer.visible = false


## Replace-mode cancel path: show the same board again, no re-deal.
func show_board() -> void:
	_layer.visible = true


func _deal() -> void:
	var want := "target" if _slots[0] == null else "support"
	_kind_label.text = String(_cfg["target_line"]) if want == "target" \
		else String(_cfg["support_line"]) % _coins
	var owned: Array = []
	for j in _slots:
		if j != null:
			owned.append(j.id)
	var candidates: Array = []
	# 首张 Target = 免费三选一(开局引导, 唯一特例);之后 **Target 与 Support 同池**,
	# 一律按稀有度权重抽(2026-08-06 用户拍板:「不应该有任何卡有固定概率, 大家都是一样的。
	# 除了第一轮有 target 之外, 其他都是随机的」)。换旗的专属骰子与专属价格已删 ——
	# Target 现在是 rarity=rare, 出现率是**池子组成的推论**而不是一个凭空的常数。
	var first_target: bool = want == "target"
	for j in Joker.pool():
		if owned.has(j.id):
			continue
		if first_target:
			if j.kind == "target":
				candidates.append(j)
		else:
			candidates.append(j)
	if first_target:
		candidates.shuffle()
		_candidates = candidates.slice(0, 3)
	else:
		_candidates = _weighted_pick(candidates, 3)
		# 「必定出 Target」—— 与 tools/bot.gd 同一套规则, 别各写一份
		if Joker.slots_guarantee_target(_slots):
			var has_t := false
			for j in _candidates:
				if j.kind == "target":
					has_t = true
			if not has_t:
				var tp: Array = []
				for j in candidates:
					if j.kind == "target":
						tp.append(j)
				if not tp.is_empty() and not _candidates.is_empty():
					_candidates[_candidates.size() - 1] = tp[randi_range(0, tp.size() - 1)]
	for i in range(_views.size()):
		if i < _candidates.size():
			var j = _candidates[i]
			var price := _price(j)
			var afford := _affordable(j)
			_views[i].visible = true
			_views[i].set_joker(j)
			# unaffordable cards still show, dimmed — envy is the saving motivation
			_views[i].modulate.a = 1.0 if afford else 0.45
			_price_labels[i].visible = true
			if price == 0:
				_price_labels[i].text = String(_cfg["free_text"])
				_price_labels[i].add_theme_color_override("font_color", StageTheme.CYAN)
			else:
				_price_labels[i].text = "◆ %d" % price
				_price_labels[i].add_theme_color_override("font_color",
					StageTheme.GOLD if afford else Color("8a5560"))
			_pop(_views[i])
		else:
			_views[i].visible = false
			_price_labels[i].visible = false
	_reroll_btn.text = String(_cfg["reroll_text"]) % Economy.reroll_cost(_reroll_count)
	_layer.visible = true


## 当前货架(打点读口)。买不起的牌也要记 —— 「摆出来了但买不起」正是
## 购买力压力的直接证据, 只记成交会把它整个漏掉。
func offers() -> Array:
	var out: Array = []
	for j in _candidates:
		out.append({"id": String(j.id), "kind": String(j.kind),
			"rarity": String(j.rarity), "price": _price(j), "aff": _affordable(j)})
	return out


func reroll_count() -> int:
	return _reroll_count


func _price(j) -> int:
	return Economy.joker_price(j, _slots[0] != null)


## Can the player take joker j right now? With full slots the best sell-back
## among owned supports counts toward a SUPPORT price; a target swap has no
## refund, so it is coins-only.
func _affordable(j) -> bool:
	var price := _price(j)
	if price == 0:
		return true
	if j.kind == "target":
		return _coins >= price
	var budget: int = _coins
	if not _slots.has(null):
		var best_sell := 0
		for k in range(1, _slots.size()):
			best_sell = maxi(best_sell, Economy.sell_value(_slots[k]))
		budget += best_sell
	return budget >= price


## Rarity-weighted sample without replacement.
func _weighted_pick(candidates: Array, count: int) -> Array:
	# 卡面声明的货架加成(现在只有独狼的 "more Targets")—— 与 tools/bot.gd 同一套算法,
	# 两边都读 `Joker.slots_target_mult`, 不许各写一份。
	var tmult := Joker.slots_target_mult(_slots)
	var pool := candidates.duplicate()
	var picked: Array = []
	while picked.size() < count and not pool.is_empty():
		var total := 0
		for j in pool:
			total += _shelf_weight(j, tmult)
		var roll := randi_range(1, maxi(1, total))
		for k in range(pool.size()):
			roll -= _shelf_weight(pool[k], tmult)
			if roll <= 0:
				picked.append(pool[k])
				pool.remove_at(k)
				break
	return picked


func _shelf_weight(j, target_mult: float) -> int:
	var w := int(GameConfig.DRAFT_RARITY_WEIGHTS.get(j.rarity, 1))
	if j.kind == "target":
		w = int(round(float(w) * target_mult))
	return maxi(1, w)


func _on_pick(i: int) -> void:
	if not _layer.visible or i >= _candidates.size():
		return
	var j = _candidates[i]
	if not _affordable(j):
		_float(String(_cfg["insufficient"]), _views[i].get_global_position() + Vector2(70, 40))
		denied.emit("price")
		return
	if j.kind != "target" and not _slots.has(null):
		replace_requested.emit(j)
		return
	bought.emit(j, _price(j))


func _on_reroll() -> void:
	if not _layer.visible:
		return
	var cost := Economy.reroll_cost(_reroll_count)
	if _coins < cost:
		_float(String(_cfg["insufficient"]), _reroll_btn.get_global_position() + Vector2(84, 8))
		denied.emit("reroll")
		return
	_reroll_count += 1
	reroll_paid.emit(cost)


func _on_skip() -> void:
	if not _layer.visible:
		return
	skipped.emit()


func _float(text: String, at: Vector2) -> void:
	var l := StageTheme.label(text, StageTheme.num("Bold"), 26, Color("ff5f7e"))
	l.position = at
	l.z_index = 60
	add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", at.y - 46.0, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.chain().tween_callback(l.queue_free)


func _pop(node: Control) -> void:
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2(1.3, 1.3)
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector2.ONE, 0.35)
