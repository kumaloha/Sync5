class_name Joker
extends RefCounted

## Data shell over data/jokers.json (docs/design/tech.md). Target jokers define WHAT a
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
## rarity binding (principle B2) is a data convention now — see docs/design/jokers.md/13.

var id: String
var name: String        # EN display name (US market)
var cn_name: String     # 中文名, used in design docs and dev tooling
var kind: String        # "target" | "support"
var rarity: String      # "common" | "uncommon" | "rare" | "" for targets
var fx_text: String     # card text — EN, ≤7 words (principle D2)
var state: Dictionary = {}   # per-run counters for growth/decay cards

## ~~升级系统~~(2026-08-16 曾是金币的主出口) 2026-08-26 用户拍板整体删除(路线 ③):「升级太复杂等于要做好几套
## 经济……删掉是为了减负,不太会影响游戏乐趣」—— level/increment_scale/can_upgrade/
## upgrade_cost 与 Fx 的 scale 放大通道一并退役,金币出口回到「买牌 + 洗牌」。
var _effects: Array
var _counters: Dictionary
var _acquire: Dictionary
var _shelf: Dictionary   # 持续的**货架**影响(不是计分, 也不是一次性的 acquire)
var _hold: Dictionary    # 持有期恒生效的经济/规则参数(穷开心的 coin_cap)


func _init(e: Dictionary) -> void:
	id = String(e["id"])
	name = String(e["name"])
	# ⚠ 名字带语言:en 模式挑数据里现成的 name 字段(1.1 英文化)。消费者全是渲染点,
	# Tape 不记小丑牌的 cn_name, 打点事实不受语言影响。
	cn_name = Lingo.pick(e)
	kind = String(e["kind"])
	rarity = String(e["rarity"])
	fx_text = String(e["fx"])
	_effects = e.get("effects", [])
	_counters = e.get("counters", {})
	_acquire = e.get("acquire", {})
	_shelf = e.get("shelf", {})
	_hold = e.get("hold", {})
	state = Fx.init_state(_counters)


## 持有这张牌时, Target 在货架上的权重要乘多少 (docs/design/solver_roadmap.md, 2026-08-06 用户批 A 案)。
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


## 帕奇欧:离开商店时复制一张消耗牌(2026-08-29)。
## ⚑ 它是**持续**效果(每次离店都触发), 所以留在小丑牌而不是转生成消耗牌 ——
## 与「一次性 ⇒ 消耗牌」是同一条判据的两面。原作里它也是 Joker 不是消耗品。
static func slots_copy_consumable(slots: Array) -> bool:
	for j in slots:
		if j != null and bool(j._shelf.get("copy_consumable", false)):
			return true
	return false


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


## ---- 2026-08-12 流派批二波:货架结构卡的 shelf 键(docs/design/archetypes.md §3.8) ----
## 与 target_guaranteed 同一条原则:保证写在卡面上, 规则出现在动作空间里, 不藏在掷点里。
## 读法一律 slots_* 静态口 —— **游戏侧(view/shop.gd)与 bot 侧(tools/bot.gd)必须
## 消费同一个口**, 各读各的 shelf 字典就是下一个「游戏里活、模型里死」。

## 货架位数(联票 doublebill: 3 → 4)。多张取最大, 不叠加 —— 5 张卡 720 宽摆不下。
## bonus = 点名的解除奖励(下次商店 +1 货架位), 与联票同受 4 的上限(布局硬约束)。
static func slots_shelf_size(slots: Array, bonus: int = 0) -> int:
	var n := 3
	for j in slots:
		if j != null:
			n = maxi(n, int(j._shelf.get("shelf_slots", 3)))
	return mini(4, n + maxi(0, bonus))


## 合奏 ensemble(2026-08-25):缓存也上台, 结算从 8 张里挑最好 5 张。
static func slots_cache_scoring(slots: Array) -> bool:
	for j in slots:
		if j != null and bool(j._hold.get("cache_scoring", false)):
			return true
	return false


## 灌铅骰 loadeddice(2026-08-25):全场掷点概率乘数(多张取最大, 不叠加)。
static func slots_odds_mult(slots: Array) -> float:
	var m := 1.0
	for j in slots:
		if j != null:
			m = maxf(m, float(j._hold.get("odds_mult", 1.0)))
	return m


## 客串(2026-08-25):段寿命计数 —— 每段末 +1 岁, 到寿返回 true(调用方清槽)。
## 顺带把 reserved 的 on_section_end 钩子接上;寿命状态在 Joker.state(随快照)。
func tick_section_life() -> bool:
	on_section_end()
	var life := int(_hold.get("section_life", 0))
	if life <= 0:
		return false
	state["ages"] = int(state.get("ages", 0)) + 1
	return int(state["ages"]) >= life


## 这张卡有几个掷点谓词 —— Beat 预掷按它数, RNG 消耗量与持仓一一对应(可复现)。
func chance_rolls_needed() -> int:
	var n := 0
	for e in _effects:
		if (e.get("when", {}) as Dictionary).has("chance"):
			n += 1
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


## 预支 advance(2026-08-26, 金融组):持仓的循环贷合计 —— 段初借 borrow, 段末还 repay,
## 付不起 = run 失败。多张自然叠加(借 20 还 24)。两界(runloop / 编排器)共用这一口。
static func slots_loan(slots: Array) -> Dictionary:
	var borrow := 0
	var repay := 0
	for j in slots:
		if j != null and j._hold.has("loan"):
			borrow += int(j._hold["loan"].get("borrow", 0))
			repay += int(j._hold["loan"].get("repay", 0))
	return {"borrow": borrow, "repay": repay}


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
		# 值 = 张数, 统一走按来源记账的注入(卖卡再买不翻倍, deck 侧挡)。
		# 大小王开关(enable_wilds)已随百搭退役 —— 2026-08-26 用户拍板超级百搭**取代**百搭,
		# 万能牌唯一来源 = superwild 的 4 张 JOKER 注入。
		deck.add_wilds(id, int(_acquire["wilds"]))
	if _acquire.has("deck_rule"):
		deck.rules[String(_acquire["deck_rule"])] = true
	if _acquire.has("trim_low"):
		deck.trim_low_ranks()


## Player discarded `n` cards (hand or cache) in one paid action.
func on_discard(n: int) -> void:
	Fx.on_discard(_counters, state, n)


## ⚑ 换一次旗, 这张卡额外给多少「加成 %」(2026-08-29)。
## 用途:让**决策方**(bot 的换旗判据 / 未来的提示 UI)看得见「换旗动作本身的回报」——
## 转型这类卡的价值与「新旗比旧旗好多少」无关, 漏算它就等于这条打法不存在。
## 通用实现:任何挂 `on_target_swap` 计数、且效果按 `per: counter:<n>` 放大的卡都算得出,
## **新卡自动生效, 不在这里点名任何 id**。
func swap_bonus_pct() -> float:
	var total := 0.0
	for e in _effects:
		var d: Dictionary = e.get("do", {})
		if not d.has("bonus_pct"):
			continue
		var per := String(d.get("per", ""))
		if not per.begins_with("counter:"):
			continue
		var spec: Dictionary = _counters.get(per.substr(8), {})
		if spec.has("on_target_swap"):
			total += float(d["bonus_pct"]) * float(spec["on_target_swap"])
	return total


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


func apply(ctx: Dictionary) -> String:
	return Fx.apply_effects(_effects, state, ctx)


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
