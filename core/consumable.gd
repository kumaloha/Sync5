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
##   `boost`  —— 当拍加成, 直接喂给 `core/fx.gd` 的效果解释器
var id: String
var name: String          # EN display name
var cn_name: String
var fx_text: String       # 卡面英文, ≤7 词(与小丑牌同一条门)
var price: int
var when: String          # "phrase" | "shop" | "any"
var action: Dictionary    # 立即动作(可空)
var boost: Dictionary     # 当拍加成(可空)


func _init(e: Dictionary) -> void:
	id = String(e.get("id", ""))
	name = String(e.get("name", ""))
	cn_name = String(e.get("cn", ""))
	fx_text = String(e.get("fx", ""))
	price = int(e.get("price", 3))
	when = String(e.get("when", "any"))
	# ⚠ **必须 duplicate** —— `e` 来自 `DB.consumables()` 的缓存, 直接引用等于
	# 所有实例共享同一个字典:任何一处改了实例的 action/boost, **会污染全局数据表**,
	# 而且是静默的(下一局、下一张同名卡都跟着变)。
	# ⚑ 与 `Joker` 对 `state` 的处理同一条线(那边也是 `duplicate(true)`)。
	action = (e.get("action", {}) as Dictionary).duplicate(true)
	boost = (e.get("boost", {}) as Dictionary).duplicate(true)


## 这张牌**现在**能不能点。`ctx` = "phrase" | "shop"。
func usable_in(ctx: String) -> bool:
	return when == "any" or when == ctx


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
