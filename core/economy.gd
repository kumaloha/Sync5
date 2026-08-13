class_name Economy
extends RefCounted

## 2026-08 rules: coin sinks are discarding (flat cost per card, paid at the
## moment of discard) and the priced support draft (shop model). Income comes
## from pattern rewards at settle, plus the draft skip reward.

static func discard_cost(count: int) -> int:
	if count <= 0:
		return 0
	return count * GameConfig.DISCARD_COST


## Shop price of a joker. The FIRST target is free (build direction); a
## target bought while one is installed costs the swap price. Supports are
## priced by rarity (with per-card overrides) — unaffordable cards still
## appear in the draft.
static func joker_price(j: Joker, has_target: bool = false) -> int:
	if j == null:
		return 0
	# 首张 Target 免费三选一 —— 开局引导, 是 Target 唯一保留的特例。
	# 之后它就是货架上一张普通的稀有卡, 走下面同一张价目表(2026-08-06 用户拍板回池)。
	if j.kind == "target" and not has_target:
		return 0
	if GameConfig.JOKER_PRICE_OVERRIDES.has(j.id):
		return int(GameConfig.JOKER_PRICE_OVERRIDES[j.id])
	return int(GameConfig.JOKER_PRICES.get(j.rarity, 4))


## 货架实价 = 基础价 + 装备的 shelf 增减(赞助 −1),**地板 1◆**(免费只属于首张
## Target 那个特例, 折扣不许把卡打到 0 —— 0 价会混进「免费」的打点与文案分支)。
## 货架/替换的展示与成交一律走这里;`sell_value` 故意**不吃折扣**(回收按基础价折半,
## 否则赞助在手时「买 5◆ 卖 2◆」和「买 6◆ 卖 3◆」的差价会随持卡状态漂)。
static func shelf_price(j: Joker, slots: Array) -> int:
	var p := joker_price(j, not slots.is_empty() and slots[0] != null)
	if p <= 0:
		return p
	return maxi(1, p + Joker.slots_price_delta(slots))


## ---- 金币上限(穷开心 skint 的 `hold.coin_cap`)的两个口 ----
##
## ⚑ **所有金币入账都必须走 `grant`** —— 入账点有四处(结算收入 `core/beat.gd`、
## 段工资 `view/phrase.gd` 与 `tools/runloop.gd`、替换回收),漏一处 = 上限对那条
## 收入无效**且不报错**,正是「规则在游戏里、不在模型里」那五次的形状。
##
## 语义:上限**卡住收入**,不没收既有存量 —— 但装卡那一刻要 `cap_held` 修剪一次,
## 否则「金币上限 5」这句卡面文字对一个已有 30◆ 的玩家就是假的(D2:卡面不许说谎)。
## 修剪只在编排器/bot 的购买路径上发生(铁律:经济动作只发生在编排器)。
static func grant(current: int, gain: int, slots: Array) -> int:
	if gain <= 0:
		return current + gain
	var cap := Joker.slots_coin_cap(slots)
	# 已经超过上限时不倒扣 —— 收入被卡住即可, 扣钱是 cap_held 的职责。
	return maxi(current, mini(current + gain, cap))


## 装卡后把存量修剪到上限(见 `grant` 的注释)。
static func cap_held(coins: int, slots: Array) -> int:
	return mini(coins, Joker.slots_coin_cap(slots))


## Selling a support back (replace flow) refunds half its price, rounded down.
static func sell_value(j: Joker) -> int:
	return joker_price(j) / 2


## Cost of the n-th reroll of one draft board (n starts at 0).
static func reroll_cost(n: int) -> int:
	return GameConfig.DRAFT_REROLL_BASE + n * GameConfig.DRAFT_REROLL_STEP
