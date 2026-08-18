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
## ⚑⚑ **货架抽卡的算法 —— 唯一真相**(2026-08-15 收口)。
##
## 原来 `view/shop.gd` 与 `tools/bot.gd` **各一份**, 而 shop 那份的注释写着
## 「与 tools/bot.gd 同一套算法……**不许各写一份**」—— **它自己就是第二份**。
## 这是本项目第 5 次「注释承诺了一个不存在的机制」(前四:`beat.gd` 漏步=崩 ·
## `db.gd` 直接红 · `shop.gd` 这句 · `price.gd` 指向从未存在的 `pool.gd`)。
##
## ⚠ **收的是算法, 不是入口** —— 两个调用方的入口必须各自保留:
##   · `shop` 用**全局** `randi_range`(玩家侧);
##   · `bot` 用**自己的种子 rng**(探针复现性), 而且 `tools/wallet.gd` 的 SpyBot
##     靠 `super._weighted_pick(...)` **覆盖它**来记货架 —— 抽成静态会打断那个覆盖点。
## ⚠ 逐字节不变:`rng == null` 时走全局 `randi_range`, 与 shop 原实现同一个函数。
##
## ⚑ 2026-08-15 曝光轴改动(70/25/5 → 35/30/25)**正好流经这两份** ——
## 保持同步比以前更要紧, 这也是现在才收口的理由。
## `rarity_mult` = Director 的稀有度乘数(局外节奏, 2026-08-18 接线)。
## 缺省 {} = 逐字节等于旧行为 —— bot 与全部既有调用方不传, 只有真商店传
## (「接上 Director 不改变现状」的机器可读版, 与 director.gd 的承诺同一条)。
static func shelf_weight(j, target_mult: float, rarity_mult: Dictionary = {}) -> int:
	var w := int(GameConfig.DRAFT_RARITY_WEIGHTS.get(j.rarity, 1))
	if j.kind == "target":
		w = int(round(float(w) * target_mult))
	if not rarity_mult.is_empty():
		w = int(round(float(w) * float(rarity_mult.get(j.rarity, 1.0))))
	return maxi(1, w)


## 按每卡权重**不放回**抽 `count` 张。⚠ `rng = null` ⇒ 全局 `randi_range`。
static func weighted_pick(candidates: Array, count: int, target_mult: float,
		rng: RandomNumberGenerator = null, rarity_mult: Dictionary = {}) -> Array:
	var pool := candidates.duplicate()
	var picked: Array = []
	while picked.size() < count and not pool.is_empty():
		var total := 0
		for j in pool:
			total += shelf_weight(j, target_mult, rarity_mult)
		# ⚠⚠ **刻意不用三元表达式**:第一版写成 `(A if rng != null else B)`,
		# sim 九个队列里有一个从 41.9% 变成 41.8%(1000 局翻了 1 局)。sim 是**确定性**的
		# (`_rng.seed = 90000 + r`), 所以那不是噪声 —— 唯一的嫌疑就是**没被走到的那一支
		# 也求了值**, 于是全局 `randi_range` 每轮被多调一次, 把全局随机流推偏。
		# **显式 if 把这个疑点整个消掉**, 而不是去赌语言的求值规则。
		var roll := 0
		if rng != null:
			roll = rng.randi_range(1, maxi(1, total))
		else:
			roll = randi_range(1, maxi(1, total))
		for k in range(pool.size()):
			roll -= shelf_weight(pool[k], target_mult, rarity_mult)
			if roll <= 0:
				picked.append(pool[k])
				pool.remove_at(k)
				break
	return picked


static func reroll_cost(n: int) -> int:
	return GameConfig.DRAFT_REROLL_BASE + n * GameConfig.DRAFT_REROLL_STEP
