class_name Joker
extends RefCounted

## Data shell over data/jokers.json (design/tech.md). Target jokers define WHAT a
## good answer is (pattern-family ×mult); support jokers define HOW to get
## there. All passive.
##
## Hook contract unchanged (design principle D1 — fixed set):
##   apply(ctx)        settle-time effect, returns popup text ("" = none)
##   on_acquire(deck)  once when installed (rule-change cards)
##   on_discard(n)     player discarded n cards (growth counters)
##   on_swap()         reserved — swaps are free, counters never hang on them
##   on_phrase_end(x)  phrase boundary (decay ticks, timing-growth)
##   on_section_end()  reserved
##
## Behaviors are DSL effects interpreted by core/fx.gd; growth counters are
## fed by the generic hooks reading the entry's `counters` spec. Channel ×
## rarity binding (principle B2) is a data convention now — see design/jokers.md/13.

var id: String
var name: String        # EN display name (US market)
var cn_name: String     # 中文名, used in design docs and dev tooling
var kind: String        # "target" | "support"
var rarity: String      # "common" | "uncommon" | "rare" | "" for targets
var fx_text: String     # card text — EN, ≤7 words (principle D2)
var state: Dictionary = {}   # per-run counters for growth/decay cards

## ---- 升级(2026-08-16, 金币的主出口)----
##
## ⚑ **一局内的等级, 1 起。** 和 `state` 同性质:属于**这一局的这张卡**, 不是卡的定义,
## 所以不进 `data/jokers.json`, 也不跨局保留。
## ⚠ **它必须被求解器/bot 读到** —— 升级是一条**改数值的规则**, 而 `tools/bot.gd` 与
## solver 一直是从 jokers.json 直接读数额的。漏了它就是第 7 次「规则在游戏里、不在模型里」,
## 这个项目最贵的一类错。所以放大发生在 `Joker.apply()` 这**一处**, 谁调 apply 谁自动拿到。
var level := 1


## 这一级把**增量**放大多少倍。Lv1 = 1.0(原样), 每级 +`step`。
##
## ⚠⚠ **是「增量」不是「整个数」** —— ×1.5 的卡按整数升会变成 ×3.05(4 级指数爆炸),
## 按增量升满级正好翻倍(增量 0.5 → 1.0 ⇒ ×2.0)。`tests/t_joker.gd` 锁着这条。
func increment_scale() -> float:
	return 1.0 + GameConfig.UPGRADE_STEP * float(level - 1)


## 还能不能升。⚠ **规则牌一律不能** —— 它们没有数值可升(改的是判定规则),
## 而这正好是红调/黑调的平衡杠杆:开局 5.3× 很强, 但**吃不到升级红利**。
func can_upgrade() -> bool:
	return not is_rule_card() and has_effects() and level < GameConfig.UPGRADE_MAX_LEVEL


## 升到下一级要多少钱;−1 = 升不了(满级或规则牌)。
func upgrade_cost() -> int:
	if not can_upgrade():
		return -1
	var costs: Array = GameConfig.UPGRADE_COSTS
	var i := level - 1
	return int(costs[i]) if i >= 0 and i < costs.size() else -1
var _effects: Array
var _counters: Dictionary
var _acquire: Dictionary
var _shelf: Dictionary   # 持续的**货架**影响(不是计分, 也不是一次性的 acquire)
var _hold: Dictionary    # 持有期恒生效的经济/规则参数(穷开心的 coin_cap)


func _init(e: Dictionary) -> void:
	id = String(e["id"])
	name = String(e["name"])
	cn_name = String(e["cn"])
	kind = String(e["kind"])
	rarity = String(e["rarity"])
	fx_text = String(e["fx"])
	_effects = e.get("effects", [])
	_counters = e.get("counters", {})
	_acquire = e.get("acquire", {})
	_shelf = e.get("shelf", {})
	_hold = e.get("hold", {})
	state = Fx.init_state(_counters)


## 持有这张牌时, Target 在货架上的权重要乘多少 (design/solver_roadmap.md, 2026-08-06 用户批 A 案)。
##
## **为什么是卡面效果而不是暗改概率**:用户既拍板过「不应该有任何卡有固定概率, 大家都是
## 一样的」, 又要求「独狼一定要换旗」—— 两者只有一种活法:把那条保证**写到卡上**,
## 让玩家看得见(独狼卡面第二句就是 "more Targets")。规则出现在动作空间里, 不藏在掷点里。
## 声明式字段, 所以将来任何卡都能用, 不是给独狼开的后门。
func shelf_target_mult() -> float:
	return float(_shelf.get("target_weight_mult", 1.0))


## 持有这张牌时, 货架**必定**有一张 Target (2026-08-07 用户批 A 案)。
## 为什么从「×3 权重」升级成「必定」:独狼重做成经济/节奏卡之后,
## **拖的代价是确定的**(每拍少几百分), 而**换的回报只有 52% 会发生** ——
## 确定的代价配概率的回报, 期望上必然吃亏。做成必定, 两头就对称了:
## 前几段拖着攒钱, 到点必定能换成好构筑。
func shelf_target_guaranteed() -> bool:
	return bool(_shelf.get("target_guaranteed", false))


## ⚑⚑ **槽位归属 —— 唯一真相**(2026-08-16,真人试玩报 bug 后收口)。
##
## **0 号槽是 Target 专用,Support 只能进 1..3。** 这条规则原本没有单一出处:
## `view/shop.gd` 用 `_slots.has(null)`(**四个槽**)判满,而 `tools/bot.gd` 用
## `range(1, size)`(**只看 1..3**)。⇒ 两处**答案不同**,而游戏那处是错的:
##
## > 玩家**没有 Target**(0 号空)+ 三个 Support 已满时买第 4 张 Support:
## > ① `_affordable` 不把「卖旧卡的回收」算进预算 ⇒ 判你买不起 ⇒ **点了没反应**;
## > ② 万一过了 ①,`_on_pick` 也不进替换流程 ⇒ **钱扣了、卡没装上、不报错**。
##
## ⚠⚠ **这次是「规则在模型里、不在游戏里」—— 与本项目此前五次的方向相反。**
## 后果:`gate.sh` / `kit.gd` 这类**覆盖门证明的是「模型看得见游戏做的事」**,
## **没有任何东西证明「游戏做了模型假设的事」** —— 所以这个 bug 只有真人玩才发现得了。
static func first_free_support(slots: Array) -> int:
	for k in range(1, slots.size()):
		if slots[k] == null:
			return k
	return -1


## 这张卡装得进去吗。Target 永远装得进(0 号就地换旗),Support 只看 1..3。
static func has_room_for(slots: Array, kind: String) -> bool:
	return kind == "target" or first_free_support(slots) >= 0


static func slots_guarantee_target(slots: Array) -> bool:
	for j in slots:
		if j != null and j.shelf_target_guaranteed():
			return true
	return false


## 当前装备下的合计倍率(多张就相乘)。
static func slots_target_mult(slots: Array) -> float:
	var m := 1.0
	for j in slots:
		if j != null:
			m *= j.shelf_target_mult()
	return m


## ---- 2026-08-12 流派批二波:货架结构卡的 shelf 键(design/archetypes.md §3.8) ----
## 与 target_guaranteed 同一条原则:保证写在卡面上, 规则出现在动作空间里, 不藏在掷点里。
## 读法一律 slots_* 静态口 —— **游戏侧(view/shop.gd)与 bot 侧(tools/bot.gd)必须
## 消费同一个口**, 各读各的 shelf 字典就是下一个「游戏里活、模型里死」。

## 货架位数(联票 doublebill: 3 → 4)。多张取最大, 不叠加 —— 5 张卡 720 宽摆不下。
static func slots_shelf_size(slots: Array) -> int:
	var n := 3
	for j in slots:
		if j != null:
			n = maxi(n, int(j._shelf.get("shelf_slots", 3)))
	return n


## 一次商店最多成交几张(联票: 1 → 2)。买入联票后**当店即刻生效**(限额随槽位实时读)。
static func slots_buy_limit(slots: Array) -> int:
	var n := 1
	for j in slots:
		if j != null:
			n = maxi(n, int(j._shelf.get("buy_limit", 1)))
	return n


## 货架价格增减(赞助 sponsor: −1)。多张求和;地板由 Economy.shelf_price 收口。
static func slots_price_delta(slots: Array) -> int:
	var d := 0
	for j in slots:
		if j != null:
			d += int(j._shelf.get("price_delta", 0))
	return d


## 持有点唱机 jukebox 时, 货架必定有一张规则牌(概率线的定向搜索,
## 独狼 target_guaranteed 的同款机制)。
static func slots_rule_guaranteed(slots: Array) -> bool:
	for j in slots:
		if j != null and bool(j._shelf.get("rule_guaranteed", false)):
			return true
	return false


## 持有期金币上限(穷开心 skint: 5;无卡 = 不设限)。多张取最小(最紧的约束赢)。
## ⚠ 收口原则同 shelf:**所有金币入账点都必须过这一口**(Beat 结算入账 / 段工资
## 两侧 / 替换回收), 漏一处 = 上限对那条收入无效且不报错。
static func slots_coin_cap(slots: Array) -> int:
	var cap := 999999
	for j in slots:
		if j != null and j._hold.has("coin_cap"):
			cap = mini(cap, int(j._hold["coin_cap"]))
	return cap


## 「规则牌」的机械判据 = 带 acquire 键(shortcut/fourfingers/twotone/wildcard/trim)。
## 点唱机的「必出规则牌」与 numbers.md §2 的「概率放大器」用的是同一个集合 ——
## 判据挂在数据形状上, 加新规则牌不用改这里。
func is_rule_card() -> bool:
	return not _acquire.is_empty()


## Called once when the joker is installed.
func on_acquire(deck: Deck) -> void:
	if deck == null:
		return
	if _acquire.has("wilds"):
		deck.enable_wilds()
	if _acquire.has("deck_rule"):
		deck.rules[String(_acquire["deck_rule"])] = true
	if _acquire.has("trim_low"):
		deck.trim_low_ranks()


## Player discarded `n` cards (hand or cache) in one paid action.
func on_discard(n: int) -> void:
	Fx.on_discard(_counters, state, n)


func on_swap() -> void:
	pass


## 商店里发生了一件有代价的事:`kind` = "reroll" | "buy" | "target_swap"。
## 淘碟/收藏家/转型的成长挂在这里(见 `Fx.on_shop_event` 的 D1 理由)。
func on_shop_event(kind: String) -> void:
	Fx.on_shop_event(_counters, state, kind)


## ⚑ **所有商店事件都走这一个静态口。**
## 调用点天然分散(游戏侧编排器 3 处 + bot 侧 3 处 —— 铁律「经济动作只发生在编排器」
## 决定了它没法收成一处), 所以退一步:**让调用形式统一到一行**,
## `grep -n 'notify_shop' ` 就能一眼数清两侧是否对齐。
## ⚠ 漏一侧就是「规则在游戏里、不在模型里」的第六次 —— 这个形状本项目栽过五次。
static func notify_shop(slots: Array, kind: String) -> void:
	for j in slots:
		if j != null:
			j.on_shop_event(kind)


## Phrase boundary. x: {early_finish: bool}
func on_phrase_end(x: Dictionary) -> void:
	Fx.on_phrase_end(_counters, state, x)


func on_section_end() -> void:
	pass


## ⚑ 升级的放大**只发生在这一处** —— 游戏、bot、求解器全都走 `apply()`,
## 所以谁都不会拿到没放大的数(见 `level` 那条注释里说的第 7 次)。
func apply(ctx: Dictionary) -> String:
	return Fx.apply_effects(_effects, state, ctx, increment_scale())


## 有无 effects 决定 kit 的 solver 臂用哪把判据(证物率 vs 分差)—— 见 tools/kit.gd::_run_solver。
func has_effects() -> bool:
	return not _effects.is_empty()


static func by_id(p_id: String) -> Joker:
	for j in pool():
		if j.id == p_id:
			return j
	return null


static func pool() -> Array:
	var out: Array = []
	for e in DB.jokers():
		out.append(Joker.new(e))
	return out


## 复制一张小丑牌给**假想推演**用。
## ⚠ `state` 是成长牌的计数器(黑胶/贝斯线/周转), **必须深拷贝** ——
## 共享它会让「算一下买哪张牌」把真实牌的成长进度也推进了, 而且不报错。
func clone() -> Joker:
	for e in DB.jokers():
		if String(e["id"]) == id:
			var j := Joker.new(e)
			j.state = state.duplicate(true)
			return j
	return null
