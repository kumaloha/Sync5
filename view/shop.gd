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
signal reroll_ticket()                # 点唱券的免费刷新:编排器消耗券后调 redeal()
signal denied(why: String)            # 想买/想刷但钱不够 — 编排器打点(购买力压力)
## 升级第 i 个已装槽位。⚠ **只发信号, 不动钱也不动等级** —— 与「金币/装槽等经济动作
## 只发生在编排器」那条铁律同一条线(CLAUDE.md 架构铁律)。
signal upgrade_requested(slot_idx: int, cost: int)

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
## 点唱券的免费刷新余额 —— **编排器注入**(开店时 + 每次消耗后), shop 自己不读存档。
var _free_rerolls := 0
var _upgrade_btns: Array = []
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

	# 联票(doublebill)把货架撑到 4 位, 所以视图建到上限、坐标交给 _layout()
	# 按当拍货架数摆(4 张时用 card_w_4/card_gap_4 的窄版 —— 720 宽放不下 4×200)。
	for i in range(4):
		var dv := JokerSlotView.new()
		dv.tappable = true
		dv.tapped.connect(_on_pick.bind(i))
		_layer.add_child(dv)
		_views.append(dv)
		# price tag under each card (targets read 免费)
		var pl := StageTheme.label("", StageTheme.num("Bold"), 22, StageTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
		_layer.add_child(pl)
		_price_labels.append(pl)
	# ---- 升级行(2026-08-16, 金币的主出口)----
	# ⚑ 它把商店从**一个动词**(换掉谁)变成**三个**(换 / 升 / 攒)。后 3 次商店
	# 100% 是替换场景, 而替换是个二选一;有了升级才谈得上取舍。
	for i in range(4):
		var ub := _button("")
		ub.custom_minimum_size = Vector2(float(_cfg["upgrade_w"]), float(_cfg["upgrade_h"]))
		ub.size = ub.custom_minimum_size
		# 两行(卡名 / 等级·价格)⇒ 字号要小, 160px 宽塞不下一行「黑胶 Lv2 ▸ ◆4」
		ub.add_theme_font_size_override("font_size", 15)
		ub.pressed.connect(_on_upgrade.bind(i))
		_layer.add_child(ub)
		_upgrade_btns.append(ub)
	_layout(3)


## 按货架数摆卡位。改布局 = 改 JSON(card_w/card_gap 管 ≤3 张, card_w_4/card_gap_4 管 4 张)。
func _layout(count: int) -> void:
	var dw: float = float(_cfg["card_w"]) if count <= 3 else float(_cfg.get("card_w_4", 156))
	var dgap: float = float(_cfg["card_gap"]) if count <= 3 else float(_cfg.get("card_gap_4", 14))
	var cy: float = float(_cfg["cards_y"])
	var dx0 := (720.0 - dw * float(count) - dgap * float(count - 1)) * 0.5
	for i in range(_views.size()):
		var x := dx0 + float(i) * (dw + dgap)
		_views[i].position = Vector2(x, cy)
		_views[i].size = Vector2(dw, dw * 1.10)
		_price_labels[i].position = Vector2(x, cy + dw * 1.10 + float(_cfg["price_dy"]))
		_price_labels[i].size = Vector2(dw, 30)

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


## 联票的续买态:一张成交后**同一货架**继续卖(不重掷 —— 重掷就成了免费刷新)。
## 编排器扣完钱装完卡后调它:摘掉售出的那张, 按新的金币/槽位重算价签与可购性。
func sold(j, slots: Array, coins: int) -> void:
	_slots = slots
	_coins = coins
	_candidates.erase(j)
	_render(false)


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
	var shelf_n := Joker.slots_shelf_size(_slots)
	if first_target:
		candidates.shuffle()
		_candidates = candidates.slice(0, 3)
	else:
		_candidates = _weighted_pick(candidates, shelf_n)
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
		# 「必定出规则牌」(点唱机)—— 同 Target 补丁的形状;两个补丁同时要顶位时
		# 各占一头(规则牌顶第一位, Target 顶最后一位), 免得互相覆盖。
		if Joker.slots_rule_guaranteed(_slots):
			var has_r := false
			for j in _candidates:
				if j.is_rule_card():
					has_r = true
			if not has_r:
				var rp: Array = []
				for j in candidates:
					if j.is_rule_card():
						rp.append(j)
				if not rp.is_empty() and not _candidates.is_empty():
					_candidates[0] = rp[randi_range(0, rp.size() - 1)]
	_render(true)


## 渲染当前 _candidates(deal 弹入场动画;sold 后的重渲染不弹)。
func _render(popin: bool) -> void:
	# ⚑ 升级行跟着**每一次**重绘走 —— 等级、金币、槽位任何一个变了它都要跟。
	# 挂在 `_render` 而不是各调用点, 是为了不给「买完卡忘了刷升级行」留口子。
	_render_upgrades()
	_layout(maxi(3, _candidates.size()))
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
			if popin:
				_pop(_views[i])
		else:
			_views[i].visible = false
			_price_labels[i].visible = false
	# 点唱券优先展示:玩家手里有券时, 按钮念的是「这次不花钱」——
	# 价格阶梯(_reroll_count)在券用完之前不动, 文案与分流必须同一个条件。
	if _free_rerolls > 0:
		_reroll_btn.text = String(_cfg["reroll_ticket_text"]) % _free_rerolls
	else:
		_reroll_btn.text = String(_cfg["reroll_text"]) % Economy.reroll_cost(_reroll_count)
	_layer.visible = true


## 当前货架(打点读口)。买不起的牌也要记 —— 「摆出来了但买不起」正是
## 购买力压力的直接证据, 只记成交会把它整个漏掉。
## 升级行的重绘 —— 每次 `redeal`/`sold` 之后调(等级和钱都可能变了)。
##
## ⚠ 四个按钮**恒显示**(不隐藏), 空槽/规则牌/满级各自写明原因。
## 隐藏会让玩家以为「这个位置没有升级这回事」, 而实际是「这一张不能升」——
## 这个项目吃过「按钮消失 = 玩家以为机制不存在」的亏(继续▸ 那次)。
func _render_upgrades() -> void:
	var y := float(_cfg["upgrade_y"])
	var w := float(_cfg["upgrade_w"])
	var gap := float(_cfg["upgrade_gap"])
	var total := w * 4.0 + gap * 3.0
	var x0 := (720.0 - total) * 0.5
	for i in range(_upgrade_btns.size()):
		var b: Button = _upgrade_btns[i]
		b.position = Vector2(x0 + float(i) * (w + gap), y)
		b.size = Vector2(w, float(_cfg["upgrade_h"]))
		var j = _slots[i] if i < _slots.size() else null
		if j == null:
			b.text = String(_cfg["upgrade_empty"])
			b.disabled = true
		elif not j.can_upgrade():
			# 规则牌没有数值可升;满级是另一回事 —— 两种都写清楚, 别都显示成灰
			b.text = (String(_cfg["upgrade_locked"]) if j.is_rule_card() \
				else String(_cfg["upgrade_maxed"])) % j.cn_name
			b.disabled = true
		else:
			var cost: int = j.upgrade_cost()
			b.text = String(_cfg["upgrade_text"]) % [j.cn_name, j.level + 1, cost]
			b.disabled = _coins < cost


func _on_upgrade(i: int) -> void:
	var j = _slots[i] if i < _slots.size() else null
	if j == null or not j.can_upgrade():
		return
	var cost: int = j.upgrade_cost()
	if _coins < cost:
		denied.emit("upgrade_coins")     # 想升但钱不够 —— 与买不起同一类购买力证据
		return
	upgrade_requested.emit(i, cost)


func offers() -> Array:
	var out: Array = []
	for j in _candidates:
		out.append({"id": String(j.id), "kind": String(j.kind),
			"rarity": String(j.rarity), "price": _price(j), "aff": _affordable(j)})
	return out


func reroll_count() -> int:
	return _reroll_count


func _price(j) -> int:
	# 赞助的 −1◆ 在这里生效(Economy.shelf_price 收口, 地板 1◆);
	# 展示价与成交价共用这一个函数, 不许分家。
	return Economy.shelf_price(j, _slots)


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
	# ⚠⚠ 同一个错误谓词曾经也在这里(2026-08-16 与 `_on_pick` 一起修):旧代码写
	# `not _slots.has(null)`(**四个槽**), 而 Support 只能进 1..3。
	# ⇒ **没有 Target(0 号空)+ 三个 Support 满**时条件为真 ⇒ **不把「卖掉旧卡的回收」
	#   算进预算** ⇒ 商店判你买不起、弹个价格提示就没了。
	#   **玩家看到的就是「点替换失效」** —— 这正是真人试玩报上来的那条。
	# ⚑ 顺带:旧写法在 0 号为空时还会把 `null` 传进 `Economy.sell_value` ——
	#   只是它恰好走不到那一支, 属于「靠巧合没崩」。
	if not _has_slot_for(j):
		var best_sell := 0
		for k in range(1, _slots.size()):
			if _slots[k] != null:
				best_sell = maxi(best_sell, Economy.sell_value(_slots[k]))
		budget += best_sell
	return budget >= price


## Rarity-weighted sample without replacement.
## 货架抽卡 —— 算法在 `Economy.weighted_pick`(**唯一真相**,2026-08-15 收口)。
## ⚠ 这里只剩入口:算 `tmult` + 用**全局** `randi_range`(`rng = null`)。
## 原来这个函数体和 `tools/bot.gd` 逐字节相同,而它的注释写着「不许各写一份」——
## **它自己就是第二份**。
func _weighted_pick(candidates: Array, count: int) -> Array:
	# 卡面声明的货架加成(现在只有独狼的 "more Targets")—— 两边都读 `Joker.slots_target_mult`。
	return Economy.weighted_pick(candidates, count, Joker.slots_target_mult(_slots))


func _on_pick(i: int) -> void:
	if not _layer.visible or i >= _candidates.size():
		return
	var j = _candidates[i]
	if not _affordable(j):
		_float(String(_cfg["insufficient"]), _views[i].get_global_position() + Vector2(70, 40))
		denied.emit("price")
		return
	# ⚠⚠ **满不满要按 kind 问**(2026-08-16 真人试玩报的 bug:「第五个小丑牌来的时候,
	# 点替换会失效」)。0 号是 **Target 专用**槽, Support 只能进 1..3 ——
	# 而旧代码问的是 `_slots.has(null)`(**四个槽**里有没有空的)。
	# ⇒ 玩家**没有 Target**(0 号空)+ 三个 Support 已满时买第 4 张 Support:
	#   条件为真 ⇒ 不进替换流程 ⇒ 走购买 ⇒ `_on_shop_bought` 只遍历 1..3 找不到空位
	#   ⇒ **钱扣了、卡没装上、还不报错。**
	# ⚑ 判据:**「有没有空位」这个问题, 答案取决于问的是哪种卡** —— 一个不分 kind 的
	#   `has(null)` 天然会在两种卡里挑错一种。
	if not _has_slot_for(j):
		replace_requested.emit(j)
		return
	bought.emit(j, _price(j))


## 这张卡装得进去吗 —— 规则在 `Joker.has_room_for`(**唯一真相**),这里只是入口。
func _has_slot_for(j) -> bool:
	return Joker.has_room_for(_slots, String(j.kind))


func set_free_rerolls(n: int) -> void:
	_free_rerolls = maxi(0, n)
	# 开着店时余额变了(刚用掉一张)要立刻改按钮念词, 下一次 redeal 不够快
	if _layer != null and _layer.visible and _reroll_btn != null:
		if _free_rerolls > 0:
			_reroll_btn.text = String(_cfg["reroll_ticket_text"]) % _free_rerolls
		else:
			_reroll_btn.text = String(_cfg["reroll_text"]) % Economy.reroll_cost(_reroll_count)


func _on_reroll() -> void:
	if not _layer.visible:
		return
	# 有点唱券先走券(**不推付费阶梯**):shop 只分流, 消耗与打点在编排器 ——
	# 余额也由编排器在消耗后用 set_free_rerolls 重新注入, 这里不自减,
	# 否则「消耗失败但余额已减」会白吞玩家一次免费态。
	if _free_rerolls > 0:
		reroll_ticket.emit()
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
