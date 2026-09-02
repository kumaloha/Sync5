class_name Shop
extends Control

## The joker draft shop (docs/design/tech.md view split): board, pricing, reroll and
## skip live here; the orchestrator owns the money and the slots (economy
## actions never happen inside a view). 2026-08 shop model: priced supports,
## paid reroll, full-slot replace, pivot-arc Target on the shelf.
## Layout + copy from data/ui.json "shop".

signal bought(j, price: int)          # affordable pick — orchestrator deducts & installs
signal replace_requested(j)           # full slots: orchestrator runs the replace flow
signal skipped()                      # orchestrator pays the skip reward
signal reroll_paid(cost: int)         # orchestrator deducts, then calls redeal()
signal denied(why: String)            # 想买/想刷但钱不够 — 编排器打点(购买力压力)
signal consumable_bought(c, price: int)   # 买下货架上那张消耗牌 — 编排器扣钱并收进栏位
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
## 联票续买态:还能再买几张(0 = 普通态)。只由 `sold()` 写, `_deal()` 归零。
var _buys_left := 0
## 点名的解除奖励:本次开店 +1 货架位(编排器在 open 前灌入并清源, 联票封顶 4)。
var shelf_bonus := 0
## Director 的稀有度乘数 —— 编排器开店时注入(探针一律 {} = 中性, 掷法逐字节不变)。
var _rarity_mult: Dictionary = {}
## 探索型货架用的「玩家用过的 Target」—— 编排器开店时注入(探针 / 零历史 = {} ⇒ 不偏置)。
## ⚠ shop 自己不读存档(2026-08-21 评审:此前在 _weighted_pick 里直接读 SaveState, 破了注入制)。
var _explore_used: Dictionary = {}


func set_explore_used(used: Dictionary) -> void:
	_explore_used = used


## 巡演路线行(journey #4)—— 编排器在 open 前注入([{name, state}], 见
## phrase.gd::_shop_route)。空数组 = 不画(教学关);画法在 Widgets.BlindBoard。
func set_route(r: Array) -> void:
	_blind_board.route = r
	_blind_board.queue_redraw()


func set_shelf_rarity_mult(m: Dictionary) -> void:
	_rarity_mult = m


var _slots: Array = []
var _cshelf: Array = []         # 货架上的消耗牌按钮 ×2(2026-08-31:1 → 2)
var _cshelf_price: Array = []
var _cshelf_name: Array = []
var _cshelf_desc: Array = []
var _coffer: Array = []         # 当前货架上的 Consumable ×2(可含 null)
# ---- 消耗牌授予的一次性商店改动(2026-08-29)。⚠ 全部**用完即清**:
# 「这次商店」类在 close() 清, 「下次货架」类在 _deal() 消费后清 —— 忘了清
# 就等于把一次性效果做成了永久 buff, 而那正是这些牌当初该被挪出小丑牌的理由。
var _grant_shelf := 0           # 联票:本店货架张数(0 = 无授予)
var _grant_extra_buys := 0      # 联票:本店**额外**成交张数(叠在基础名额之上)
var _grant_price := 0           # 赞助:本店全场价格增量(负数 = 便宜)
var _grant_free_reroll := 0     # 加急:免费刷新次数
var _grant_min_rarity := ""       # 挑高:下次货架的最低稀有度("" = 无授予)
var _coins := 0


func _ready() -> void:
	# explicit rects, not anchor presets — the preset sets anchors without
	# offsets and a nested chain resolves to 0×0 (docs/design/ui_meta.md 渲染手法)
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
	# 升级行(2026-08-16 金币主出口)→ **2026-08-18 用户拍板撤掉底部行**:
	# 「正式局也不要, 升级也是放三个大的卡片上」—— 升级改为货架商品(见 _deal 尾)。
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
	# ⚠ 按钮只建一次(2026-08-21 审查:此前每次 _render → _layout 都 new 一对, 旧的不删 ——
	# 一局几十个泄漏节点叠在同一矩形, 0.9 alpha 底板透出下层旧价签)。08-13 把摆位抽成
	# _layout 时把原本只在 _ready 跑的创建块一起卷了进来。
	if _reroll_btn == null:
		_reroll_btn = _button("")
		_reroll_btn.pressed.connect(_on_reroll)
		_layer.add_child(_reroll_btn)
		# 2026-08-06 用户:「还看到有跳过按钮, 不要, 只需要刷新」—— 跳过**奖励**已删,
		# 但这个按钮本身是商店的**唯一免费出口**: 买不起又刷不起时没有它会卡死在商店里,
		# 所以它留下来, 只是不再是一笔收入, 措辞也从「跳过」改成「继续」。
		_skip_btn = _button(String(_cfg["skip_text"]))
		_skip_btn.pressed.connect(_on_skip)
		_layer.add_child(_skip_btn)
	# ⚠ **只建一次** —— `_layout()` 每次 `_render` 都会跑, 不守就会每刷一次货架
	# 就多出一对格子叠在原处(实测第二次开店时货架格变成 4 个, 而
	# `set_consumables` 只更新前两个 ⇒ 屏幕上是新旧混着的错乱)。
	if _cshelf.is_empty():
		_build_consumable_row()
	_reroll_btn.position = Vector2(360.0 - 220.0 - 12.0, by)
	_skip_btn.position = Vector2(360.0 + 12.0, by)


func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## ⚑ 商店的消耗牌区(2026-08-29):**货架一格 + 栏位两格**, 摆在按钮下方那片空白
## (btn_y 806 以下原有约 470px 没人用)——一寸现有布局都不用抢。
##
## ⚠ **货架位独立, 不参与三选一** —— 让消耗牌混进小丑牌的三选一, 等于用它换掉
## 小丑牌的多样性;而且那正是 2026-08-29 修过的形状:**奖励某件事的东西不能和
## 那件事抢同一个资源**(转型 vs 换旗抢购买名额)。
func _build_consumable_row() -> void:
	# ⚑ 货架 **1 → 2 格**(2026-08-31 用户:「每次出 3 小丑 2 消耗给用户选」)。
	# ⚠⚠ **5 选 1**(2026-08-31 用户拍板):这两张与三张小丑牌是**同一个池子**,
	# 一次进店只成交 1 张 —— 消耗牌**不再有专属名额**, 它和小丑牌抢同一次购买。
	# 计数在编排器的 `_shop_buys`(经济动作只发生在编排器), 视图不自己数。
	# ⚑ 这是**收紧**:此前消耗牌每店白送一格, 而这一层实测值 **+18.8pt 通关率**。
	# ⚑ 联票(本店 4 选 2)因此变成「买完还能再挑」——用户:「点完那个 4 选 2, 可以直接再选 2 张」。
	# ⚠ 卡形与局内一致(62×104 的红卡), 不再是 88×88 的方块。
	# ⚑ **描述只在商店给**(2026-09-01 用户:「在商店里显示的消耗牌, 我们应该在牌的下面
	# 加入描述, 关卡内就不用描述了」)。分工与小丑牌一致:**商店是决策点**(要读懂再买),
	# **局内是执行点**(已经买过了, 认插画就够)—— 而 62×104 的卡本来也塞不下三段。
	# 版式跟着小丑牌三选一:卡 → 描述 → 价格, **价格永远是最后一行**。
	# ⚑⚑ **2026-09-02 放大 + 右移**(用户:「消耗卡在商店页面的位置应该靠右一点,
	# 也应该大一点, 跟光碟一样大 …… 右边总体页面现在压的比较紧, 最右侧一大块是空的」)。
	# 病根是**一条过期的约束**:原注释写「右边 x>470 是栏位」—— 而**栏位 2026-09-01
	# 随「消耗牌全部自动触发」整块退役了**, 那块地已经空出来, 版式却还躲着它。
	# ⇒ 碟径 84 → **132(= 局内唱片 `VinylDeck` 的尺寸)**, 两列在
	#   「盲注卡右缘 → 右边距」这段里**居中**, 而不是贴着左边挤成一堆。
	# ⚠ 坐标全部搬进 `data/ui.json` 的 shop 节(cons_*)—— 改布局 = 改 JSON。
	var cy: float = float(_cfg.get("cons_y", 912))
	var dd: float = float(_cfg.get("cons_disc", 132))
	var cw: float = float(_cfg.get("cons_col_w", 190))
	var cg: float = float(_cfg.get("cons_gap", 24))
	var lx: float = float(_cfg.get("cons_left", 190))
	var rx: float = float(_cfg.get("cons_right", 692))
	var x0: float = lx + ((rx - lx) - (cw * 2.0 + cg)) * 0.5
	for i in range(2):
		var col := x0 + float(i) * (cw + cg)
		var sh := Widgets.ConsumableSlot.new()
		sh.idx = -1 - i                   # -1/-2 = 货架位(买;栏位那两格已退役)
		sh.size = Vector2(dd, dd)
		sh.position = Vector2(col + (cw - dd) * 0.5, cy)
		sh.pressed.connect(_on_cshelf_pressed.bind(i))
		_layer.add_child(sh)
		_cshelf.append(sh)
		# 碟上不写名字(84px 的圆里放了插画就没地方了), 名字单独一行 ——
		# ⚑ 名字是玩家**记得住、说得出**的把手, 描述是「它干什么」, 两者都要。
		var nl := Label.new()
		nl.position = Vector2(col, cy + dd + 12.0)
		nl.size = Vector2(cw, 20)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.add_theme_font_override("font", StageTheme.zh())
		nl.add_theme_font_size_override("font_size", 15)
		nl.add_theme_color_override("font_color", Color(1, 1, 1, 0.94))
		_layer.add_child(nl)
		_cshelf_name.append(nl)
		var dl := Label.new()
		dl.position = Vector2(col, cy + dd + 36.0)
		dl.size = Vector2(cw, 36)
		dl.custom_minimum_size = Vector2(cw, 36)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dl.add_theme_font_override("font", StageTheme.zh())
		dl.add_theme_font_size_override("font_size", 12)
		dl.add_theme_color_override("font_color", Color(0.81, 0.84, 0.90, 0.88))
		_layer.add_child(dl)
		_cshelf_desc.append(dl)
		var pl := Label.new()
		pl.position = Vector2(col, cy + dd + 76.0)
		pl.size = Vector2(cw, 22)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pl.add_theme_font_override("font", StageTheme.num("SemiBold"))
		pl.add_theme_font_size_override("font_size", 17)
		_layer.add_child(pl)
		_cshelf_price.append(pl)


## ---- 消耗牌的授予口(编排器调用, 见 phrase.gd::_apply_shop_action) ----
func grant_shelf(n: int, extra_buys: int) -> void:
	# ⚠ 货架取大、名额**累加** —— 一次进店买到第二张联票时, 它该再给一次成交,
	# 而不是把上一张的授予覆盖掉。bot 侧 `_g_extra_buys` 同款(parity)。
	_grant_shelf = maxi(_grant_shelf, n)
	_grant_extra_buys += extra_buys
	_deal()
	_render(true)


func grant_price_delta(d: int) -> void:
	_grant_price += d
	_render(false)


func grant_free_reroll(n: int) -> void:
	_grant_free_reroll += n
	_draw_refill()


## 挑高:**当场重发一次**, 之后整次进店(含刷新)都保持过滤。
## ⚠⚠ 只设标志位是不够的 —— 玩家点它的时候货架**已经发过了**, 不重发就等于
## 「这张卡什么都没发生」, 而它正是因为这个而输给「直接刷新」(用户 2026-08-30)。
## ⚠ 重发不收费也不计刷新次数:钱在买这张卡的时候已经付过了。
func grant_min_rarity(r: String) -> void:
	_grant_min_rarity = r
	_deal()
	_render(true)


## 本店还剩几次免费刷新(编排器算刷新价时读)。
## 续买态的剩余次数 —— **消耗牌路径专用**。
##
## ⚠ 联票自己是从**消耗牌货架**买走的, 那条路径不经过 `sold()`, 而 `_buys_left`
## 只在 `sold()` 里写过 ⇒ 买完联票副标题还念着「SUPPORT · ◆ N」, **玩家看不到
## 「还能再选 2 张」**。配额对了但没人告诉他, 等于没做(2026-09-02)。
func set_buys_left(left: int, coins: int) -> void:
	_buys_left = left
	_coins = coins
	_refresh_kind_line()


## 联票授予的本店**额外**成交张数(0 = 无授予)。编排器把它**加**在基础名额上。
##
## ⚑⚑ **2026-09-02 用户拍板改口径**:此前它是「本店成交上限」, 与基础名额**取大** ——
## 于是买联票花掉的正是它要给你的那次成交, 净得 0 张、净亏 3◆。用户原话:
## 「相当于 4 选 2 那张卡本身也算一张, 那用户不如不选这张;实际我的设想应该是
## 选了那张卡后, 剩余卡可以选两张」。
## ⇒ 改成**加法**:基础 1 + 联票 2 = 本店 3 次成交, 联票自己占掉第 1 次 ⇒ **还能再选 2 张**,
##   与卡面「本店:四选二」逐字对上。⚠ 联票**照常占一张名额**, 不开特例 ——
##   「不占名额」是第二套计数规则, 而加法只是把 `maxi` 换成 `+`。
## ⚠ 这正是 LESSONS「奖励某件事的东西不能和那件事抢同一个资源」的**第三次**
##   (前两次:转型 vs 换旗抢购买名额 · 消耗牌专属名额)。
func granted_extra_buys() -> int:
	return _grant_extra_buys


func free_rerolls_left() -> int:
	return _grant_free_reroll


func consume_free_reroll() -> bool:
	if _grant_free_reroll <= 0:
		return false
	_grant_free_reroll -= 1
	return true


func _on_cshelf_pressed(i: int = 0) -> void:
	var _c = _coffer[i] if i < _coffer.size() else null
	if _c == null:
		return
	if _coins < _c.price:
		denied.emit("consumable")
		_cshelf[i].shake()
		return
	consumable_bought.emit(_c, _c.price)


## 编排器在开店/买卖后调这个刷新货架。
## ⚑ 2026-09-01:**没有「栏位」参数了** —— 消耗牌全部自动触发, 商店里不再有我的两格。
## `effective` = 「买了有没有用」(砧座在 support ≤1 时买了等于白花钱), 门从
## 「点得动吗」搬到了「买得动吗」。
func set_consumables(offer: Array, coins: int, effective: Array = []) -> void:
	_coffer = offer
	_coins = coins
	for i in range(_cshelf.size()):
		var o = offer[i] if i < offer.size() else null
		_cshelf[i].filled = o != null
		_cshelf[i].label = o.display_name() if o != null else ""
		_cshelf[i].art_id = String(o.id) if o != null else ""
		# 碟标上刻的字 = 它在第几拍自己打;`buy` 类不刻(它买下就打完了)。
		_cshelf[i].stamp = "" if o == null or o.is_instant() else o.fire_label()
		var ok: bool = true if i >= effective.size() else bool(effective[i])
		_cshelf[i].armed = o != null and coins >= o.price and ok
		# ⚑ 货架位用**金**(它是"待售"), 栏位用**卡牌红**(它是"我的") —— 两者要分得开。
		_cshelf[i].accent = StageTheme.GOLD
		_cshelf[i].queue_redraw()
		_cshelf_price[i].text = ("◆ %d" % o.price) if o != null else ""
		# 文案优先 ui.json consumablecard(游戏文案归游戏数据, 与小丑牌 jokercard 同一条路),
		# 缺了退卡面英文 fx_text。⚠ 不许在这里写中文字面量(`t_lingo` 会红)。
		_cshelf_name[i].text = o.display_name() if o != null else ""
		_cshelf_desc[i].text = (String(DB.ui().get("consumablecard", {})
			.get(String(o.id), {}).get("trigger", o.fx_text)) if o != null else "")


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
	# 续买配额归零只发生在**进店**这一刻 —— 刷新(redeal)走的是同一次进店, 联票的
	# 第二次选择不该被一次刷新吃掉。
	_buys_left = 0
	# 挑高同理:保整次进店(含刷新), 所以清零也只发生在进店这一刻。
	_grant_min_rarity = ""
	_blind_board.setup(section_idx,
		target if target >= 0 else Run.section_target_for(
			GameConfig.SECTION_TARGETS, section_idx,
			"" if mod == null else String(mod.id)),
		mod, Lingo.t("下一场"), score, left, boon)
	redeal(slots, coins, section_idx)


## Re-deal after a reroll (counter survives; coins already deducted).
func redeal(slots: Array, coins: int, section_idx: int) -> void:
	_slots = slots
	_coins = coins
	_deal()


## 联票的续买态:一张成交后**同一货架**继续卖(不重掷 —— 重掷就成了免费刷新)。
## 编排器扣完钱装完卡后调它:摘掉售出的那张, 按新的金币/槽位重算价签与可购性。
## 成交:卖掉的位**补一张新的**(2026-08-27 用户:「4 张可以选 2,买完只剩 3 张还能选,
## 其实应该变出一个新的来,否则就是 3 选 2」)—— 联票买的是**两次完整的选择**,
## 不是「第二次将就剩下的」;买第一张反而缩窄第二次的池子是反直觉的惩罚。
## ⚠ 补的牌从同一个候选池按同一套权重抽(不重复已在架/已持有),用**当前**槽位重算
## —— 刚买的那张若改了货架规则(联票/赞助/点唱机), 补货立刻按新规则走。
##
## `left` = **还能再买几张**(配额是编排器的账, 视图不自己算 —— 经济动作只发生在
## 编排器)。它只喂副标题那一行:续买态要明说「还能选几张 · 不想买就点继续」
## (2026-08-28 用户:「至多可以选 2 个, 如果钱只够选 1 个或者没有, 要点跳过」)。
func sold(j, slots: Array, coins: int, left: int = 0) -> void:
	_slots = slots
	_coins = coins
	_buys_left = left
	var at: int = _candidates.find(j)
	_candidates.erase(j)
	var refill = _draw_refill()
	if refill != null:
		if at >= 0 and at <= _candidates.size():
			_candidates.insert(at, refill)      # 补在原位:视线不跳
		else:
			_candidates.append(refill)
	_render(false)


## 补货抽一张:排除已持有与在架的,按稀有度权重(与 _deal 同一口径)。
## 池子抽空(极端:全持有)返回 null —— 那时货架就少一张, 与旧行为一致。
func _draw_refill():
	var taken := {}
	for jj in _slots:
		if jj != null:
			taken[jj.id] = true
	for c in _candidates:
		if not (c is Dictionary):
			taken[c.id] = true
	var pool: Array = []
	for cand in Joker.pool():
		if not taken.has(cand.id):
			pool.append(cand)
	if pool.is_empty():
		return null
	var picked: Array = _weighted_pick(pool, 1)   # 与 _deal 同一口径(签名/注入全一致)
	return picked[0] if not picked.is_empty() else null


func close() -> void:
	# ⚠ 「这次商店」类的授予随离店清零 —— 一次性就是一次性。
	_grant_shelf = 0
	_grant_extra_buys = 0
	_grant_price = 0
	_grant_free_reroll = 0
	_layer.visible = false


## Replace-mode cancel path: show the same board again, no re-deal.
func show_board() -> void:
	_layer.visible = true


func _deal() -> void:
	var want := "target" if _slots[0] == null else "support"
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
	var shelf_n := Joker.slots_shelf_size(_slots, shelf_bonus)
	if _grant_shelf > 0:
		shelf_n = maxi(shelf_n, _grant_shelf)
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
		# ⚠⚠ **「必定出规则牌」的货架补丁已删(2026-08-30 二批转生)** ——
		# 规则牌(近道/四指/黑调/红调)全部转生为消耗牌, 而它们是**仅有的**带 `acquire`
		# 的小丑牌 ⇒ 这段补丁在小丑牌货架上**永远找不到目标, 静默什么都不做**。
		# 点唱机的目标已搬到消耗牌位(`view/phrase.gd::_roll_consumable` 的 `_rule_next`)。
	# (升级上架段 2026-08-26 随升级系统整体删除 —— 路线 ③。)
	# ⚑ 挑高(消耗牌):**这次商店**不再出普通卡 —— 含刷新与续买后的重发。
	# ⚠⚠ 2026-08-30 用户改判:旧版只管**下一次发牌**, 而「用户宁愿走刷新」——
	# 花 3◆ 买一次性的过滤, 不如同样的钱去刷新, 于是这张卡**买了还不如不买**
	# (实测总分 −1556, z=−5.96)。⇒ 保证期改成**整次进店**, 刷新出来的也必是好卡,
	# 它才真的比「多刷一次」值钱。清零点搬到 `open()`(进店)。
	# ⚠ 「必出 8 以上」在货架上没有对应物(货架摆的是小丑牌不是扑克牌),
	# 所以语义是「没有普通卡」, 卡面同步 —— **卡面必须说实话**。
	if _grant_min_rarity != "":
		var rich: Array = []
		for j in _candidates:
			if j.rarity != "common":
				rich.append(j)
		if rich.size() < _candidates.size():
			for j in candidates:
				if rich.size() >= _candidates.size():
					break
				if j.rarity != "common" and not rich.has(j):
					rich.append(j)
			if rich.size() == _candidates.size():
				_candidates = rich
	# ⚠ 挑高的授予**不在这里清零** —— 它保整次进店(含刷新), 清零点在 `open()`。
	# 点唱机的 `_grant_rule` 已随规则牌转生搬走(现在管的是消耗牌位)。
	_render(true)


## 渲染当前 _candidates(deal 弹入场动画;sold 后的重渲染不弹)。
func _render(popin: bool) -> void:
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
	_reroll_btn.text = String(_cfg["reroll_text"]) % Economy.reroll_cost(_reroll_count)
	_refresh_kind_line()
	_layer.visible = true


## 副标题那一行:货架在卖哪一种卡 · 你手上还有多少钱。
##
## ⚠⚠ **必须挂在 `_render()` 上, 不许只在 `_deal()` 里写一次**(2026-08-28 修的真 bug):
## 联票的续买态走的是 `sold() → _render()` 而**不经过** `_deal()`, 于是这一行的 ◆
## 数额一直念着**进店那一刻**的余额。实测:进店 9◆ → 买掉 3◆ 的卡 → 这行还写 ◆ 9。
## 玩家看到的是「我有 9◆」配上「四张 3◆ 的卡全是暗红买不起」—— 一个说谎的数字
## 配一排买不起的卡, 是最容易被读成「游戏坏了」的组合。
##
## 续买态另说一句话:联票买的是**至多**两次, 不是必须两次 —— 所以要同时给出
## 「还能选几张」和「不想买就点继续」(2026-08-28 用户)。出口一直都在(继续 ▸ 是
## 商店的唯一免费出口, 见 `_layout`), 缺的只是没人告诉玩家它此刻也算数。
func _refresh_kind_line() -> void:
	if _buys_left > 0:
		_kind_label.text = String(_cfg["encore_line"]) % [_buys_left, _coins]
		return
	_kind_label.text = String(_cfg["target_line"]) if _slots[0] == null \
		else String(_cfg["support_line"]) % _coins


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


## ---- 教学分镜 D 的几何读口(v6)。活取, 不抄坐标 —— `Hand.focus_rect` 同一条纪律:
## 价签行的位置是 `_layout()` 按当拍货架数算的, 抄进 ui.json 就是会漂的第二份。
## shop 铺满全屏且在 (0,0), 局部坐标 = 全屏坐标, 编排器直接用。

## 货架价签行(可见价签的并集)—— D 分镜的 focus。
func price_row_rect() -> Rect2:
	var out := Rect2()
	for pl in _price_labels:
		if pl.visible:
			var q := Rect2(pl.position, pl.size)
			out = q if out.size.x == 0.0 else out.merge(q)
	return out


## 商店顶部的盲注板 —— D 分镜的条锚在它下面。
func board_rect() -> Rect2:
	return Rect2(_blind_board.position, _blind_board.size)


## 货架操作面(卡 + 价签 + 两个按钮)—— 教学压暗层的常亮洞:玩家要挑的卡不许黑。
func shelf_zone_rect() -> Rect2:
	var top: float = float(_cfg["cards_y"]) - 16.0
	var bot: float = float(_cfg["btn_y"]) + 58.0 + 16.0
	return Rect2(0.0, top, 720.0, bot - top)


func _price(j) -> int:
	# 赞助的 −1◆ 在这里生效(Economy.shelf_price 收口, 地板 1◆);
	# 展示价与成交价共用这一个函数, 不许分家。
	# 赞助(消耗牌)的本店降价叠在这里, 地板仍是 1◆ —— 免费只属于首张 Target 那个特例。
	return maxi(1, Economy.shelf_price(j, _slots) + _grant_price) \
		if Economy.shelf_price(j, _slots) > 0 else 0


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
	# 探索型货架(context.md 岔 #1, 批「探索型 ≤1.5×」):你**没用过**的 Target 权重上浮。
	# 三道闸都在编排器/Director:数据开关 · 探针恒空(截图/回归稳定)· 零历史的新玩家不动。
	return Economy.weighted_pick(candidates, count, Joker.slots_target_mult(_slots), null,
		_rarity_mult, Director.explore_boost(candidates, _explore_used))


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


func _on_reroll() -> void:
	if not _layer.visible:
		return
	# ⚑ 加急(消耗牌)的免费刷新在这里兑现(2026-08-30 code review 补:
	# `consume_free_reroll()` 此前**没有任何调用者** —— 那张卡在游戏里是空白的)。
	if consume_free_reroll():
		_reroll_count += 1
		reroll_paid.emit(0)
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
