class_name Pattern
extends RefCounted

## Poker pattern evaluation. Reads a hand (5..7 cards) and returns the
## highest-scoring five-card combination.
##
## 2026-08-05 用户拍板: score = chips × 牌型倍率 (× 小丑倍率, in Settle).
## chips = pattern base chips + sum of best five card ranks (A=14);
## the pattern's own MULT is the first factor of the multiplier chain — a
## rare hand now scales multiplicatively with jokers, Balatro-style.

enum Kind {
	HIGH_CARD, PAIR, TWO_PAIR, THREE_KIND, STRAIGHT, FLUSH,
	FULL_HOUSE, FOUR_KIND, STRAIGHT_FLUSH, ROYAL_FLUSH,
}

const NAMES := {
	Kind.HIGH_CARD: "High Card",
	Kind.PAIR: "Pair",
	Kind.TWO_PAIR: "Two Pair",
	Kind.THREE_KIND: "Three of a Kind",
	Kind.STRAIGHT: "Straight",
	Kind.FLUSH: "Flush",
	Kind.FULL_HOUSE: "Full House",
	Kind.FOUR_KIND: "Four of a Kind",
	Kind.STRAIGHT_FLUSH: "Straight Flush",
	Kind.ROYAL_FLUSH: "Royal Flush",
}

# 2026-08-05 真人试玩二改(用户拍板 chips×mult): the additive ladder — even
# steepened — kept patterns and jokers on separate axes. Splitting each hand
# into (chips, mult) makes the pattern the FIRST multiplier, so rare hands
# scale with targets instead of being replaced by them. Proportions follow
# Balatro; rank_sum (≈30-60 on our A=14 scale) plays the card-chips role.
const BASE_CHIPS := {
	Kind.HIGH_CARD: 5,
	Kind.PAIR: 10,
	Kind.TWO_PAIR: 20,
	Kind.THREE_KIND: 30,
	Kind.STRAIGHT: 30,
	Kind.FLUSH: 35,
	Kind.FULL_HOUSE: 40,
	Kind.FOUR_KIND: 60,
	Kind.STRAIGHT_FLUSH: 100,
	Kind.ROYAL_FLUSH: 140,
}

## **抄 Balatro 的 level-1 表**(2026-08-06 用户拍板:「你看看原作, 牌型的倍率。
## 基本可以抄他的」), 数据核对自 balatrowiki.org/w/Poker_Hands:
##   High 5×1 / Pair 10×2 / TwoPair 20×2 / Three 30×3 / Straight 30×4 /
##   Flush 35×4 / Full 40×4 / Four 60×7 / SF 100×8 / Royal 100×8
##
## 原作**有意让多个牌型共享同一个 mult**(2,2 / 4,4,4 / 8,8), 价值差全部由
## chips 拉开 —— mult 是留给小丑牌的稀缺资源, 早早发完后面就没有梯度了。
##
## 我们只在两处偏离, 都是有理由的:
##   ① **Two Pair 2 → 3**。这是用户自己提的问题(「two pair 和 pair 怎么是
##      一个倍率」):原作把 Two Pair 的溢价全放在 chips 翻倍上, 实算只比 Pair
##      高 25%, 而它稀有 8.9 倍。原作担得起 —— 回合制, 你有时间往更高的牌型
##      走; 我们 8 秒实时, Two Pair 常常就是能拿到的最好结果。
##      仍低于 Three Kind:(20+30)×3=150 < (30+30)×3=180, 扑克序不倒挂。
##   ② **Royal Flush 保留 140 chips**。原作 Royal 和 Straight Flush 完全同分
##      (都 100×8), 等于不给皇家同花顺任何溢价; 我们把它做成了独立牌型, 靠
##      chips 给一点区分, mult 仍照抄 8。
## 难度补偿仍然全部走 Target 层, 不在这张表上做(旧拍板未变)。
## **2026-08-06 晚:按本作实测频率修正两处**(用户:「概率和之前瞎想的不同,
## 按照概率设置牌型倍率吧」)。数据来自 `tools/attrib.gd` 的中性基准
## (完美玩家、八选五、不装 Target、不弃牌)——**这是本作的真实分布, 不是自然扑克分布**:
##
##   高牌 6.1% · 对子 27.2% · **两对 33.5%** · 三条 5.5% · 顺子 11.0% ·
##   同花 10.7% · 葫芦 5.1% · 四条 0.7%
##
## ⚠⚠ **用「出现频率」定价是错的, 我连错两次, 记在这里防第三次。**
## 出现频率 P(恰好是这个牌型) 有**中转站伪影**:高牌只有 1.6%、三条只有 5.6%,
## 但它们稀有**不是因为难** —— 高牌是「凑不出东西」(八选五 + 自由弃牌几乎总能成手),
## 三条是「路过」(有三条就顺手去葫芦了, 很少停在那)。**「路过」不等于「到达」。**
## 照它定价会得出「高牌该排第二贵」这种结论。
##
## ✅ **正确的量是 `P(≥ 这个牌型)`(累计)**:它消掉中转站伪影, **且天生与扑克序单调一致**,
## 所以「保扑克序」和「按概率定价」不再冲突 —— 之前所有的拧巴都来自用错了指标。
## 实测(`tools/attrib.gd` 中性基准:完美玩家/八选五/**弃牌免费**/不装 Target):
##
##   对子 98.4% · 两对 74.2% · 三条 51.6% · 顺子 46.0% · 同花 33.2% · 葫芦 20.7% · 四条以上 <1.6%
##
## 映射 = **0.75 次幂压缩, 锚在对子 = 2**(用户 2026-08-06 选「中等」基调):
## 直接 1/p 会让中高段暴涨 = 普涨 = 构筑价值塌(log₂ 版翻车的根因, baseline 7.9%→41.9%);
## 压得太狠又会让牌型之间没差别。0.75 是两者之间。
##   对子 2.00 · 两对 2.47 · 三条 3.25 · 顺子 3.54 · **同花 4.52** · **葫芦 6.44**
##
## ⚠ **顶端三档(四条/同花顺/皇家)没有数据**(实测全部 <0.4%, 1/p 在那里会炸到 >60×),
## 保持 7/8/8 手拍值不动 —— 没证据的地方别动, 而且抬顶端是普涨风险最高的动作。
## ⚠ **葫芦看着常见(出现 19.1%)其实是天花板**:P(≥葫芦)=20.7%, 因为四条以上几乎不存在,
## 所以它是玩家实际能摸到的最高档。我曾据「出现频率高」要把它降价, 那是第二次用错指标。
##
## ⚠⚠ **上面那些百分比是「策略下的分布」, 不是「牌堆能给什么」** —— attrib 自己的注释就这么写。
## 2026-08-14 起有了第二把尺子(`tools/prior.gd`, 零策略 8 选五取最优, N=20 万):
##
##   高牌 7.12% · 对子 39.66% · 两对 25.98% · 三条 5.13% · **顺子 8.89%** · **同花 6.79%** ·
##   葫芦 5.99% · 四条 0.34% · 同花顺 0.08% · 皇家 0.01%
##
## **⚑ 策略对各牌型的抬升是不均的**:同花 +58%、顺子只 +24%(差 2.4 倍)——
## 因为同花更容易靠弃牌重抽凑出来(缺一张花色 vs 缺中间一张点数)。
## 所以「同花比顺子难多少」有三个互相打架的数:**组合 1.31 · 策略后 1.03 · 旧注释写的 1.4**。
##
## ✅ **2026-08-14 用户拍板:定价一律取组合口径**(理由三条在 `../CLAUDE.md` Target 两层原则 ③:
## 技术溢价归玩家 · 实测口径会漂 · 组合口径零数据可精确算)。
## 本表的 5 vs 4 = 1.25, 落在组合口径 1.31 的手感带内, **维持不动**。
## ⚠ **Target 层从此按各族的组合命中率区分**(阶梯 ×11 / 单色 ×12,
## 见 design/jokers.md「第三次重锚」)—— 旧注释那句「Target 层不再区分顺子/同花(都 ×7)」
## 早在 2026-08-12 就被实装推翻了, **却在这里躺了两天没人发现**。
const BASE_MULT := {
	Kind.HIGH_CARD: 1,
	Kind.PAIR: 2,
	Kind.TWO_PAIR: 2,
	Kind.THREE_KIND: 3,
	Kind.STRAIGHT: 4,
	Kind.FLUSH: 5,
	Kind.FULL_HOUSE: 6,
	Kind.FOUR_KIND: 7,
	Kind.STRAIGHT_FLUSH: 8,
	Kind.ROYAL_FLUSH: 8,
}

const BASE_COINS := {
	Kind.HIGH_CARD: 0,
	Kind.PAIR: 1,
	Kind.TWO_PAIR: 2,
	Kind.THREE_KIND: 3,
	Kind.STRAIGHT: 4,
	Kind.FLUSH: 4,
	Kind.FULL_HOUSE: 6,
	Kind.FOUR_KIND: 8,
	Kind.STRAIGHT_FLUSH: 12,
	Kind.ROYAL_FLUSH: 15,
}

## Evaluate the best five-card combination out of the given cards.
## 大王/小王 are WILD: each stands in for whatever card scores highest.
## `rules` are the run's rule flags (Deck.rules): shortcut (straights may
## skip one rank), fourfingers (four-card straights count), twotone
## (flushes by color, not suit).
## Returns {} when fewer than 5 cards, else
## {kind, name, cards, base_score, rank_sum, score, coins, wilds}.
## `cards` is always the ORIGINAL five (so the UI highlights real cards);
## `resolved` holds the substituted set the score was computed from.
static func evaluate_best(cards: Array, rules: Dictionary = {}) -> Dictionary:
	if cards.size() < 5:
		return {}
	var best := {}
	var best_score := -1
	for combo in _combos_indices(cards.size(), 5):
		var five: Array = []
		for i in combo:
			five.append(cards[i])
		var res: Dictionary = _score_five(five, rules)
		if int(res["score"]) > best_score:
			best_score = int(res["score"])
			best = res
	return best


## **只算分数, 不建结果字典。** 求解器内层一拍要调几千次, 而 `_pack` 每次都建一个
## 9 键字典 + `resolved.duplicate()` —— 在 GDScript 里这是纯开销。
## 万能牌照走原路(暴力代入本来就慢, 而且极少见)。
## ⚠ **必须与 `evaluate_best(five)["score"]` 逐位相同**, `tests/runner.gd` 里有随机对拍。
static func score_five(five: Array, rules: Dictionary = {}) -> int:
	if five.size() != 5:
		var r: Dictionary = evaluate_best(five, rules)
		return 0 if r.is_empty() else int(r["score"])
	for c in five:
		if c.is_wild():
			return int(_score_five(five, rules)["score"])
	var kind: int = _classify(five, rules)
	var rsum := 0
	for c in five:
		rsum += c.rank
	return (int(BASE_CHIPS[kind]) + rsum) * int(BASE_MULT[kind])


## 8 选 5 的最高分, **一个数组都不新建**。
##
## 求解器内层一拍要跑 ~2240 次「8 选 5 取最大」, 每次 56 个组合各新建一个 5 元素数组
## —— 一拍 12.5 万次数组分配, 在 GDScript 里这是当前最大的一笔开销。
## 这里用一个复用缓冲填组合(单线程, 且 score_five 不持有传入数组, 所以安全)。
## ⚠ **必须与 `evaluate_best(cards)["score"]` 逐位相同**, tests 里有随机对拍。
static var _buf5: Array = [null, null, null, null, null]

static func best_score_of(cards: Array, rules: Dictionary = {}) -> int:
	if cards.size() < 5:
		return 0
	var best := -1
	for combo in _combos_indices(cards.size(), 5):
		for j in range(5):
			_buf5[j] = cards[combo[j]]
		var s := score_five(_buf5, rules)
		if s > best:
			best = s
	return maxi(0, best)


## Score exactly five cards, resolving any wilds to their best substitution.
static func _score_five(five: Array, rules: Dictionary = {}) -> Dictionary:
	var wild_idx: Array = []
	for i in range(five.size()):
		if five[i].is_wild():
			wild_idx.append(i)
	if wild_idx.is_empty():
		return _pack(five, five, rules)

	# brute force: every wild tries all 52 real cards, keep the best result.
	# The hand is five cards and at most two wilds exist, so this stays small.
	var best := {}
	var best_score := -1
	var subs: Array = []
	for s in range(4):
		for r in range(2, 15):
			subs.append(Card.new(r, s))
	var trial: Array = five.duplicate()
	if wild_idx.size() == 1:
		for a in subs:
			trial[wild_idx[0]] = a
			var res: Dictionary = _pack(five, trial, rules)
			if int(res["score"]) > best_score:
				best_score = int(res["score"])
				best = res
	else:
		for a in subs:
			trial[wild_idx[0]] = a
			for b in subs:
				trial[wild_idx[1]] = b
				var res: Dictionary = _pack(five, trial, rules)
				if int(res["score"]) > best_score:
					best_score = int(res["score"])
					best = res
	return best


static func _pack(original: Array, resolved: Array, rules: Dictionary = {}) -> Dictionary:
	var kind: int = _classify(resolved, rules)
	var rsum := 0
	for c in resolved:
		rsum += c.rank
	var chips: int = int(BASE_CHIPS[kind]) + rsum
	return {
		"kind": kind,
		"name": NAMES[kind],
		"cards": original,
		"resolved": resolved.duplicate(),
		"chips": chips,
		"pmult": int(BASE_MULT[kind]),
		"rank_sum": rsum,
		"score": chips * int(BASE_MULT[kind]),
		"coins": int(BASE_COINS[kind]),
	}

## Classify exactly five cards into a Kind.
##
## **热点**:求解器一拍要调它 ~12 万次, 实测占探针总时间 **63%**(短路它 58.4s → 21.6s)。
## 原实现每次分配 7-9 个容器 + 2-3 次排序 + O(n²) 顺子检测。
## 所以**无规则牌时**走下面的位运算快路径:点数存进一个 13 位掩码, 顺子 = 连续 5 位,
## 计数用一个复用的定长数组 —— 零分配、零排序。
## ⚠ **带规则牌(近道/四指/双色调)时仍走原实现** —— 那几条规则的边角(跳一位、四张算顺、
## 按颜色同花, 还要和 A2345 轮子叠加)分支多, 重写风险不值当, 而且规则牌本来就少见。
## ⚠ 两条路径必须**逐位相同**, `tests/runner.gd` 里有大样本随机对拍 + 边角用例。
static func _classify(five: Array, rules: Dictionary = {}) -> int:
	if rules.is_empty():
		return _classify_fast(five)
	return _classify_ref(five, rules)


static var _rank_cnt := PackedInt32Array()

static func _classify_fast(five: Array) -> int:
	if _rank_cnt.size() != 15:
		_rank_cnt.resize(15)
	for i in range(15):
		_rank_cnt[i] = 0
	var mask := 0
	var suit0: int = five[0].suit
	var is_flush := true
	for c in five:
		var r: int = c.rank
		_rank_cnt[r] += 1
		mask |= 1 << r
		if c.suit != suit0:
			is_flush = false
	var pairs := 0
	var has3 := false
	var has4 := false
	for r in range(2, 15):
		var n := _rank_cnt[r]
		if n == 2:
			pairs += 1
		elif n == 3:
			has3 = true
		elif n == 4:
			has4 = true
	# 顺子 = 掩码里有连续 5 位。5 张牌若有对子就凑不出 5 个不同点数, 所以这一条足够。
	var is_straight := false
	for lo in range(2, 11):
		if (mask >> lo) & 0x1F == 0x1F:
			is_straight = true
			break
	# 轮子 A2345:A(bit14) + 2..5(bits 2-5 = 0x3C)
	if not is_straight and (mask & (1 << 14)) != 0 and (mask & 0x3C) == 0x3C:
		is_straight = true

	if is_straight and is_flush:
		# 皇家 = 10..A 全在(bits 10-14)
		return Kind.ROYAL_FLUSH if (mask >> 10) & 0x1F == 0x1F else Kind.STRAIGHT_FLUSH
	if has4:
		return Kind.FOUR_KIND
	if has3 and pairs >= 1:
		return Kind.FULL_HOUSE
	if is_flush:
		return Kind.FLUSH
	if is_straight:
		return Kind.STRAIGHT
	if has3:
		return Kind.THREE_KIND
	if pairs >= 2:
		return Kind.TWO_PAIR
	if pairs >= 1:
		return Kind.PAIR
	return Kind.HIGH_CARD


static func _classify_ref(five: Array, rules: Dictionary = {}) -> int:
	var ranks: Array = []
	var suits := {}
	var rank_count := {}
	for c in five:
		ranks.append(c.rank)
		suits[c.suit] = true
		rank_count[c.rank] = int(rank_count.get(c.rank, 0)) + 1
	ranks.sort()
	var is_flush: bool = suits.size() == 1
	# ⚑⚑ **双色调 2026-08-16 拆成两张**(用户拍板:「可以分成两张, 黑色可以认为同花色,
	# 红色可以认为同花色」)。旧的 `twotone` 一张管两色, 先验层实测它把同花从 6.79%
	# 抬到 **66.3%(9.8 倍)** —— 它把一个 ×5 的稀有牌型变成了常驻, 而整张倍率表
	# 正建立在「同花很难打」这个前提上。
	# ⚑ 拆开之后单张约 **4.4 倍**, 两张都要才回到原强度 —— 而那要占 4 个槽里的 2 个,
	# **定价由槽位自然完成, 不用给它加任何特例**。
	# ⚠ 拆分**也把选择前移到了货架上**:玩家看到的是两张不同的卡, 而不是一张卡加个弹窗。
	if not is_flush:
		var red_on: bool = rules.get("redtone", false)
		var black_on: bool = rules.get("blacktone", false)
		if red_on or black_on:
			var colors := {}
			for c in five:
				colors[c.is_red()] = true
			# 五张同色才谈得上;然后看这一色的那张卡装了没有。
			if colors.size() == 1:
				is_flush = red_on if colors.has(true) else black_on
	var is_straight: bool = _is_straight(ranks, rules)
	var counts: Array = rank_count.values()
	counts.sort()
	counts.reverse()  # descending

	if is_straight and is_flush:
		if ranks[0] == 10 and ranks[4] == 14:
			return Kind.ROYAL_FLUSH
		return Kind.STRAIGHT_FLUSH
	if counts[0] == 4:
		return Kind.FOUR_KIND
	if counts[0] == 3 and counts.size() > 1 and counts[1] == 2:
		return Kind.FULL_HOUSE
	if is_flush:
		return Kind.FLUSH
	if is_straight:
		return Kind.STRAIGHT
	if counts[0] == 3:
		return Kind.THREE_KIND
	if counts[0] == 2 and counts.size() > 1 and counts[1] == 2:
		return Kind.TWO_PAIR
	if counts[0] == 2:
		return Kind.PAIR
	return Kind.HIGH_CARD

## ranks: sorted ascending, exactly five entries. Rule flags widen the net:
## shortcut allows one gap, fourfingers accepts a four-card run (both stack).
static func _is_straight(ranks: Array, rules: Dictionary = {}) -> bool:
	var shortcut: bool = rules.get("shortcut", false)
	var four: bool = rules.get("fourfingers", false)
	for ace_low in [false, true]:
		var distinct := {}
		for r in ranks:
			distinct[1 if (ace_low and r == 14) else r] = true
		var ds: Array = distinct.keys()
		ds.sort()
		if _run_exists(ds, 5, 0):
			return true
		if shortcut and _run_exists(ds, 5, 1):
			return true
		if four and _run_exists(ds, 4, 0):
			return true
		if four and shortcut and _run_exists(ds, 4, 1):
			return true
	return false


## Do `need` distinct ranks fit inside a window of width need+gaps?
static func _run_exists(ds: Array, need: int, gaps: int) -> bool:
	if ds.size() < need:
		return false
	for lo in ds:
		var cnt := 0
		for v in ds:
			if v >= int(lo) and v <= int(lo) + need - 1 + gaps:
				cnt += 1
		if cnt >= need:
			return true
	return false

## All k-sized index combinations of range(n). n<=7, k=5 -> at most 21 combos.
static func _combos_indices(n: int, k: int) -> Array:
	var res: Array = []
	_combo_helper(0, n, k, [], res)
	return res

static func _combo_helper(start: int, n: int, k: int, combo: Array, res: Array) -> void:
	if combo.size() == k:
		res.append(combo.duplicate())
		return
	for i in range(start, n):
		combo.append(i)
		_combo_helper(i + 1, n, k, combo, res)
		combo.pop_back()
