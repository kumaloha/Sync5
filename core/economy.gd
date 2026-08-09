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


## Selling a support back (replace flow) refunds half its price, rounded down.
static func sell_value(j: Joker) -> int:
	return joker_price(j) / 2


## Cost of the n-th reroll of one draft board (n starts at 0).
static func reroll_cost(n: int) -> int:
	return GameConfig.DRAFT_REROLL_BASE + n * GameConfig.DRAFT_REROLL_STEP
