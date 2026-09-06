class_name Shelf
extends RefCounted

## 货架组装 —— **游戏(view/shop.gd)/ 金样(tools/golden.gd)/ Lua 镜像共用的一份**(2026-09-06 从
## `view/shop.gd::_deal` / `_draw_refill` 抽出, docs/design/mirror.md §11 第 3 段)。
## 只做「候选 → 这次上架的几张」这一步纯函数;授予的记账(联票名额 / 免费刷新 / 折扣)与
## 成交仍在 view/shop.gd + 编排器。⚠ `rng == null` ⇒ 全局随机(游戏侧, 逐字节保持旧行为);
## 探针/金样传种子 rng。


## 候选池:首张 Target 免费三选一(只放 Target), 之后 Target 与 Support 同池, 排除已持有。
static func candidates(slots: Array) -> Array:
	var first_target: bool = slots[0] == null
	var owned: Array = []
	for j in slots:
		if j != null:
			owned.append(j.id)
	var out: Array = []
	for j in Joker.pool():
		if owned.has(j.id):
			continue
		if first_target:
			if j.kind == "target":
				out.append(j)
		else:
			out.append(j)
	return out


## 这次上架的几张。`shelf_bonus` = 点名解除奖励;`grant_shelf` = 联票的本店货架数(0 = 无);
## `min_rarity` = 挑高("" = 无)。
static func deal(slots: Array, shelf_bonus: int, grant_shelf: int, min_rarity: String,
		rng: RandomNumberGenerator = null, rarity_mult: Dictionary = {}, boost: Dictionary = {}) -> Array:
	var cands := candidates(slots)
	var first_target: bool = slots[0] == null
	var shelf_n := Joker.slots_shelf_size(slots, shelf_bonus)
	if grant_shelf > 0:
		shelf_n = maxi(shelf_n, grant_shelf)
	var offer: Array = []
	if first_target:
		if rng == null:
			cands.shuffle()
		else:
			for i in range(cands.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var tmp = cands[i]
				cands[i] = cands[j]
				cands[j] = tmp
		offer = cands.slice(0, 3)
	else:
		offer = Economy.weighted_pick(cands, shelf_n, Joker.slots_target_mult(slots), rng, rarity_mult, boost)
		# 「必定出 Target」(独狼)—— 与 tools/bot.gd 同一套规则
		if Joker.slots_guarantee_target(slots):
			var has_t := false
			for j in offer:
				if j.kind == "target":
					has_t = true
			if not has_t:
				var tp: Array = []
				for j in cands:
					if j.kind == "target":
						tp.append(j)
				if not tp.is_empty() and not offer.is_empty():
					var k: int = randi_range(0, tp.size() - 1) if rng == null else rng.randi_range(0, tp.size() - 1)
					offer[offer.size() - 1] = tp[k]
	# 挑高:这次商店不出普通卡(含刷新与续买后的重发);候选不够就保留原样
	if min_rarity != "":
		offer = rich_only(offer, cands)
	return offer


static func rich_only(offer: Array, cands: Array) -> Array:
	var rich: Array = []
	for j in offer:
		if j.rarity != "common":
			rich.append(j)
	if rich.size() < offer.size():
		for j in cands:
			if rich.size() >= offer.size():
				break
			if j.rarity != "common" and not rich.has(j):
				rich.append(j)
		if rich.size() == offer.size():
			return rich
	return offer


## 续买补货一张:排除已持有与在架的, 按稀有度权重;挑高时先过滤普通卡(池空退回全池)。池空返回 null。
static func refill(slots: Array, on_shelf: Array, min_rarity: String,
		rng: RandomNumberGenerator = null, rarity_mult: Dictionary = {}, boost: Dictionary = {}):
	var taken := {}
	for jj in slots:
		if jj != null:
			taken[jj.id] = true
	for c in on_shelf:
		if c != null and not (c is Dictionary):
			taken[c.id] = true
	var pool: Array = []
	for cand in Joker.pool():
		if not taken.has(cand.id) and not (min_rarity != "" and String(cand.rarity) == "common"):
			pool.append(cand)
	if pool.is_empty():
		for cand in Joker.pool():
			if not taken.has(cand.id):
				pool.append(cand)
	if pool.is_empty():
		return null
	var picked: Array = Economy.weighted_pick(pool, 1, Joker.slots_target_mult(slots), rng, rarity_mult, boost)
	return picked[0] if not picked.is_empty() else null
