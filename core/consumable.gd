class_name Consumable
extends RefCounted

## 消耗牌 —— 一次性、用完即弃(2026-08-29 用户开轴)。
##
## ⚑ **与小丑牌的分界只有一条:这个效果本质是一次性还是持续。**
## 不是「这张卡强不强」, 也不是「它有没有进过赢局」——
## 用户 2026-08-29 原话:「不是为了解决大部分卡没进过赢局而设计消耗牌,
## 是因为他确实就适合一次性而非长期」。
## ⇒ 判据落到实处:**用完之后这张卡还有没有意义**。
##   联票(这次商店 4 选 2)、超级百搭(注入万能牌后卡本身没用了)= 一次性 ⇒ 消耗牌;
##   独狼(每拍给钱)、转型(每次换旗累积)= 持续 ⇒ 留在小丑牌。
## ⚠ 「每段一次」也判一次性 —— 用户:「一局4次毫无意义, 也就4次, 不是每次」。
##   系统定时机 = 玩家被动;转生成消耗牌后玩家自己选哪一拍烧 = 主动决策。
##
## 两类效果, 复用现有机械, **不新增第二套 DSL**:
##   `action` —— 立即动作, 与 `Joker.on_acquire` 同一批键(wilds/trim_low/…)
##               外加商店类(shelf_slots/price_delta/rule_guaranteed/…)
##   `boost`  —— 当拍加成, 由 `core/settle.gd` 的 phrase_boosts 段手写解释(键名与 Fx 一致, 不经过 Fx)
var id: String
var name: String          # EN display name
var cn_name: String
var fx_text: String       # 卡面英文, ≤7 词(与小丑牌同一条门)
var price: int
## ⚑⚑ **触发时机(2026-09-01 用户拍板:消耗牌全部自动触发)**。原来的
## `when: phrase|shop|any` 是「玩家现在能不能点」, 而**点这个动作整个没了** ——
## 用户原话:「现在玩起来有点怪, 比如那个塞 4 张万能卡, 还要自己点一下才生效,
## 完全不用点」。⇒ 判据换成「**它什么时候自己打**」:
##   `"buy"`  —— 买下即触发(13 张 action:改牌堆或改这次商店的, 没有「哪一拍」可选)
##   `"next"` —— 买下后的下一拍(快闪:名字就是「突然」)
##   1..6     —— 买下后遇到的**第一个第 N 拍**(开场① · 副歌④ · 彩头⑥)
## ⚑ 四张时机卡因此收成**一条规则**而不是四条特例, 而且这个数**刻在碟面上**,
## 规则自解释(不用记、不用查、不用点)。
var fire                  # "buy" | "next" | int 1..6
var action: Dictionary    # 立即动作(可空)
var boost: Dictionary     # 当拍加成(可空)
var queued_beats := 0     # 排队至今经过了几拍(`"next"` 判这个)


var _raw: Dictionary = {}   # 建它的那条数据(clone 用)


func _init(e: Dictionary) -> void:
	_raw = e
	id = String(e.get("id", ""))
	name = String(e.get("name", ""))
	cn_name = String(e.get("cn", ""))
	fx_text = String(e.get("fx", ""))
	price = int(e.get("price", 3))
	fire = e.get("fire", "buy")
	# ⚠ **必须 duplicate** —— `e` 来自 `DB.consumables()` 的缓存, 直接引用等于
	# 所有实例共享同一个字典:任何一处改了实例的 action/boost, **会污染全局数据表**,
	# 而且是静默的(下一局、下一张同名卡都跟着变)。
	# ⚑ 与 `Joker` 对 `state` 的处理同一条线(那边也是 `duplicate(true)`)。
	action = (e.get("action", {}) as Dictionary).duplicate(true)
	boost = (e.get("boost", {}) as Dictionary).duplicate(true)


## 买下的那一刻就该生效吗(牌堆手术 / 商店改造 —— 没有「哪一拍」可选)。
func is_instant() -> bool:
	return typeof(fire) == TYPE_STRING and String(fire) == "buy"


## 这一拍轮到它了吗。`beat` = 段内拍号(**1 起**), `queued_beats` = 排队至今经过的拍数。
## ⚠ `"next"` 用「排过一拍」判而不是拍号 —— 它的语义是「下一拍」, 与段内位置无关。
func due_on(beat: int, queued_beats: int) -> bool:
	if is_instant():
		return false
	if typeof(fire) == TYPE_STRING:
		return String(fire) == "next" and queued_beats >= 1
	return int(fire) == beat


## 碟面上刻的那个字 —— 拍号, 或「下一拍」的 ▸。
func fire_label() -> String:
	if typeof(fire) == TYPE_STRING:
		return "▸"
	return str(int(fire))


## 规则牌 = 带 `deck_rule` 的消耗牌(2026-08-30 二批转生:近道/四指/黑调/红调)。
## ⚑ **「规则牌」这个概念整体搬到了消耗牌这一侧** —— 它此前的机械判据是
## 「小丑牌带 `acquire` 键」, 而转生之后**没有任何小丑牌还带 `acquire`**
## ⇒ `Joker.is_rule_card()` 恒为 false, 点唱机(必出规则牌)会**静默变成空操作**。
## 所以点唱机的目标也一起搬:它现在保证的是**下一次商店的消耗牌位出一张规则牌**。
func is_rule_card() -> bool:
	return action.has("deck_rule")


## 显示名 —— 与小丑牌同一条语言层规则(探针恒 cn)。
func display_name() -> String:
	return Lingo.pick({"cn": cn_name, "name": name})


## 深拷贝(RunLoop.fork 推演用):排队年龄一起带走, 但不共享对象 —— 推演把真实局的碟催老了不报错。
func clone() -> Consumable:
	var c := Consumable.new(_raw)
	c.queued_beats = queued_beats
	return c


## 消耗牌货架掷牌 —— 游戏(view/phrase.gd::_roll_consumables)与 bot(tools/bot.gd)共用这一份规则
## (2026-09-06 收口, 此前两边各抄一份):排除已在队列的;第一格在「必出规则牌」时只从规则牌里抽,
## 抽不出退回全池不空手;掷 n 张互不重复。随机源由调用方给(`pick(n)` 返回下标)—— 两侧都传 deck.pick_index。
## 返回原始数据行(或 null = 池空), 调用方自己 `Consumable.new`。
static func roll_shelf(held: Dictionary, rule_first: bool, n: int, pick: Callable) -> Array:
	var pool: Array = []
	for e in DB.consumables():
		if not held.has(String(e["id"])):
			pool.append(e)
	var out: Array = []
	for i in range(n):
		if pool.is_empty():
			out.append(null)
			continue
		var use := pool
		if i == 0 and rule_first:
			var rp: Array = []
			for e in pool:
				if Consumable.new(e).is_rule_card():
					rp.append(e)
			if not rp.is_empty():
				use = rp
		var picked = use[int(pick.call(use.size()))]
		out.append(picked)
		pool.erase(picked)
	return out
