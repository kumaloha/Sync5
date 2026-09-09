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


## ⚑⚑ 一次进店的**记账** —— 游戏(`view/shop.gd` + `view/phrase.gd` 编排)/ 金样
## (`tools/golden.gd::ShopSim`)/ Lua 镜像(`lua/app/shop.lua`)**共用的一份**
## (2026-09-09,收 docs/design/mirror.md §12 认下的第二个代价)。
##
## 为什么存在:联票名额 / 免费刷新 / 折扣 / 挑高 / 5 选 1 计数 / 帕奇欧一次 / 离店清零
## 这七件事此前住在**三处**,改一条商店规则要三处同改,而整局金样只能证明
## 「ShopSim = Lua」,证明不了「= view」。收成一个实例态之后,三方都消费它,
## 金样的 `visit` 族替它对拍 ⇒ 那条证明覆盖到了 view 用的同一份记账。
##
## **它不拥有什么**(边界,和「经济动作只发生在编排器」同一条线):
## `coins`(扣钱/发钱)· `joker_slots`(装卡/替换)· `deck`(万能牌/规则牌/剪牌)·
## `rule_next`(**跨店**,住在编排器)· `loan`(碰钱与债)· 货架数组本身(组装在
## `Shelf.deal/refill`,持有在调用方)· 渲染。⇒ `apply_action()` 只认那五个记账键,
## 其余键留给调用方。
##
## ⚠ **离店副作用的顺序 —— 真正的不变量是「以 `close()` 收尾」,不是「帕奇欧在前」**
## (2026-09-09 审查改写:原文写的「必须跑在 `stay()` 之前」对 view 是**假的**,
##  而 view 恰恰是三方里唯一反着跑的那一方)。
## `stay()` 判满额时会顺手 `close()`,清掉那四个「本店」授予;帕奇欧那种
## 「离店时还会再发授予」的动作**可以跑在它之后** —— 前提是**离店路径以再一次
## `close()` 收尾**。今天两种顺序都在跑,两种都对:
##   · view:`stay()` 已经 close 过一次 → `_perkeo_on_exit()` → `shop.close()` 收尾。
##     五个离店点全是这个形状:`_on_consumable_bought` · `_on_shop_bought`(教学分支
##     与正常出口两处)· `_on_shop_skipped` · `_on_slot_tapped`。
##   · ShopSim(`tools/golden.gd`)/ Lua(`lua/app/shop.lua`):`perkeo_on_exit()` 再
##     `visit.close()`,一次就够。
## ⇒ 会漏的只有一种写法:帕奇欧跑在**最后一次** `close()` 之后 —— 那时复制出来的授予
##   没人清,下一次 `open()` 只清 `grant_min_rarity`,其余四个**漏进下一店**。
##
## ⚠ **残余风险(认下,别单边修)**:view 的店内重掷没有 `not closed` 这道闸,
## 而 ShopSim / Lua 有(它们的 `apply_action` 跟着一句 `and not closed`)。
## **不要只给 view 补这道闸** —— 不同时把帕奇欧的顺序也改齐,三方就会在这里静默分叉。
class Visit extends RefCounted:
	var reroll_count := 0
	## 联票续买态:还能再买几张(0 = 普通态)。只由 `stay()` 写,`open()` 归零。
	var buys_left := 0
	## 点名的解除奖励:本次开店 +1 货架位(编排器在 `open()` 时灌入并清源)。
	var shelf_bonus := 0
	# ---- 消耗牌授予的一次性商店改动。⚠ 全部**用完即清**:「这次商店」类在 `close()` 清,
	# 「下次货架」类(挑高)在 `open()` 清 —— 忘了清就等于把一次性效果做成了永久 buff。
	var grant_shelf := 0            # 联票:本店货架张数(0 = 无授予)
	var grant_extra_buys := 0       # 联票/本店类三张:本店**额外**成交名额(叠在基础名额之上)
	var grant_price := 0            # 赞助:本店全场价格增量(负数 = 便宜,含刷新价)
	var grant_free_reroll := 0      # 加急:免费刷新次数
	var grant_min_rarity := ""      # 挑高:**下次货架**的最低稀有度("" = 无授予)
	## 本次进店已成交几张(5 选 1 的计数:小丑牌与消耗牌共用这一个数)。
	## ⚠ 换旗不计 —— 由调用方判(与今天三处同)。
	var shop_buys := 0
	var coffer_used := false        # 本店消耗牌货架已成交(名额未满时由调用方放回 false)
	var perkeo_fired := false       # 帕奇欧每次进店只复制一次(离店点不止一个)
	var closed := false

	## 进店归零。⚠ 其余授予(`grant_shelf/extra_buys/price/free_reroll`)**不清** ——
	## 它们是上一店 `close()` 清过的;`grant_min_rarity` 是「下次货架」类,进店时才消费完清。
	func open(run_shelf_bonus: int) -> void:
		shop_buys = 0
		perkeo_fired = false
		reroll_count = 0
		# 续买配额归零只发生在**进店**这一刻 —— 刷新走的是同一次进店,
		# 联票的第二次选择不该被一次刷新吃掉。
		buys_left = 0
		# 挑高同理:保整次进店(含刷新),所以清零也只发生在进店这一刻。
		grant_min_rarity = ""
		coffer_used = false
		closed = false
		shelf_bonus = run_shelf_bonus

	## 货架价(含赞助的本店折扣)—— 展示价与成交价共用这一个函数,不许分家。
	## 地板 1◆;免费(0)只属于首张 Target 那个特例,折扣不许把卡打到 0。
	func price(j, slots: Array) -> int:
		var sp := Economy.shelf_price(j, slots)
		return maxi(1, sp + grant_price) if sp > 0 else 0

	## 这张卡现在拿得动吗。满槽时**最好的一张 Support 回收**算进预算(Support 只在 1..3);
	## 换旗没有退款,所以 Target 只看现钱。
	func affordable(j, slots: Array, coins: int) -> bool:
		var p := price(j, slots)
		if p == 0:
			return true
		if j.kind == "target":
			return coins >= p
		var budget := coins
		if not Joker.has_room_for(slots, String(j.kind)):
			var best_sell := 0
			for k in range(1, slots.size()):
				if slots[k] != null:
					best_sell = maxi(best_sell, Economy.sell_value(slots[k]))
			budget += best_sell
		return budget >= p

	## 本店此刻的刷新价:阶梯价 + 赞助的本店降价(地板与 `price` 同一条,在 Economy 里)。
	func reroll_cost_now() -> int:
		return Economy.reroll_cost(reroll_count, grant_price)

	## 加急的免费刷新:有则减一返回 true。⚠ 免费刷新**不推阶梯**(不调 `note_reroll`)——
	## 加急写的是「免费刷新 N 次」,用完后首刷若跳价就是卡面说谎。
	func take_free_reroll() -> bool:
		if grant_free_reroll <= 0:
			return false
		grant_free_reroll -= 1
		return true

	func note_reroll() -> void:
		reroll_count += 1

	## 本店成交上限 = 基础名额 + 授予的**额外**名额(加法,不是取大 ——
	## 取大时联票买掉的正是它要给的那次成交,净得 0 张)。
	func buy_limit(slots: Array) -> int:
		return Joker.slots_buy_limit(slots) + grant_extra_buys

	func note_buy() -> void:
		shop_buys += 1

	## 一次成交之后还留在店里吗。留 ⇒ 更新「还能再选 N 张」;不留 ⇒ 关店清授予。
	## ⚠ 离店的其它副作用(帕奇欧)由调用方在此**之前**跑,见类头。
	func stay(slots: Array) -> bool:
		var limit := buy_limit(slots)
		if shop_buys < limit:
			buys_left = limit - shop_buys
			return true
		close()
		return false

	## 消耗牌 action 里**属于记账**的那五个键。返回 `{"redeal": bool, "reprice": bool}` ——
	## 改了货架构成(联票撑大 / 挑高过滤)要在店内当场重掷;只动价签与刷新键的
	## (赞助 / 加急)重画即可。两个都由调用方执行(记账在这里,屏幕跟上在视图)。
	## ⚑ `reprice` 2026-09-09 补:此前调用方是靠 `act.has("price_delta")` 自己判的 ——
	## 于是「哪些键属于记账」这条知识在 `view/phrase.gd` 又有了半份,而 `parity.py`
	## 第二层扫的正是函数体里的键名字符串:两处都写着,把这两个键从这里删掉也不会红。
	## ⚠ `rule_guaranteed`(跨店)/ `loan` / `wilds` / `trim_low` / `deck_rule` /
	## `copy_one_destroy_rest` / `ad_coins` **不归它**(碰 deck、coins 或跨店),留在调用方。
	func apply_action(act: Dictionary) -> Dictionary:
		var redeal := false
		var reprice := false
		if act.has("shelf_slots"):
			# ⚠ 货架取大(一店两张联票不叠成 5 张);名额走 `extra_buys`(独立键,独立累加)。
			grant_shelf = maxi(grant_shelf, int(act["shelf_slots"]))
			redeal = true
		if act.has("extra_buys"):
			grant_extra_buys += int(act["extra_buys"])
		if act.has("price_delta"):
			grant_price += int(act["price_delta"])
			reprice = true
		if act.has("free_reroll"):
			grant_free_reroll += int(act["free_reroll"])
			reprice = true
		if act.has("min_rarity"):
			# 挑高:**当场重发一次**,之后整次进店(含刷新)都保持过滤 ——
			# 只设标志位不重发,等于「这张卡什么都没发生」。
			grant_min_rarity = String(act["min_rarity"])
			redeal = true
		return {"redeal": redeal, "reprice": reprice}

	## 离店:清「这次商店」类的四个授予 —— 一次性就是一次性。
	## ⚠ `grant_min_rarity` **不清**:它是「下次货架」类,清零点在 `open()`。
	func close() -> void:
		grant_shelf = 0
		grant_extra_buys = 0
		grant_price = 0
		grant_free_reroll = 0
		closed = true
