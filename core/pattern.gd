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
##
## ⚑ **2026-08-17 两对 2 → 3(恢复用户 08-06 白天的拍板)**:
## 当年覆盖它的是「实测累计 + 0.75 幂」(算出 2.47 → 落回 2), 而那把尺子 08-14 已被
## 用户换成组合口径 —— 同一套压缩在组合累计上 = 2 × (92.88/53.22)^0.75 ≈ **3.04**,
## 与用户当初的 ×3 相符。两对与三条共 mult(原作本来就 2,2/4,4,4/8,8 这么干),
## chips 20 < 30 保扑克序:(20+35)×3 = 165 < (30+35)×3 = 195。
## ⚠ **Target 层从此按各族的组合命中率区分**(阶梯 ×11 / 单色 ×12,
## 见 docs/design/jokers.md「第三次重锚」)—— 旧注释那句「Target 层不再区分顺子/同花(都 ×7)」
## 早在 2026-08-12 就被实装推翻了, **却在这里躺了两天没人发现**。
## ⚑⚑ 倍率 v3(2026-08-27 两轮定稿):公式 = 2×(P_pair/P_k)^0.85 × (1+0.5·(1−P_k)),
## P_k = **带弃牌预算 b=2 的追型达成率**(tools/vol.gd, n=8k, b=0 列与组合口径逐项吻合
## = 采样器自检过;经济 v2 弃牌 1◆/张后 b≈2 是钱包口径)。压缩幂 0.75→0.85 = 用户
## 「曲线可以更陡」;λ=0.5 = 波动溢价(CLAUDE.md Target ④「不奖励波动性谁不玩好凑的」),
## 主载体 = 失败率(实测 CV 窄带 0.62-0.71, 追型失败常捞回别的型, (1−P) 才是离散来源)。
## 数据快照(P_b2):Pair .977 · Two .799 · Three .338 · Str .335(⚑ 带重抽后与三条同难,
## +1 保扑克序)· Flush .254 · Full .176 · Four .010 · SF .002 · Royal .0004。
## 顶端三档超出压缩公式(1/p 会炸), 手压 15/18/18(出现 <1%, 近失爽点方向)。
## ⚠ 整表上浮且目标分未随动 —— 松紧是另一根旋钮;λ 与幂由用户试玩报「高/低」单旋钮重算。
const BASE_MULT := {
	Kind.HIGH_CARD: 1,
	Kind.PAIR: 2,
	Kind.TWO_PAIR: 3,
	Kind.THREE_KIND: 7,
	Kind.STRAIGHT: 8,
	Kind.FLUSH: 9,
	Kind.FULL_HOUSE: 12,
	Kind.FOUR_KIND: 15,
	Kind.STRAIGHT_FLUSH: 18,
	Kind.ROYAL_FLUSH: 18,
}

## ⚑ 经济 v2(2026-08-26 用户拍板 A 案):牌型金币表搬进 data/economy.json `kind_coins`
## (「数值与内容全部在 data」;chips/mult 两表仍是 const —— 另案, 别顺手动)。
## 表意 = 每拍按成牌发钱的**主收入通道**, 尺 = 组合难度 −log₂P(≥k)(levels.md 经济 v2)。
static var BASE_COINS: Dictionary = _load_kind_coins()

static func _load_kind_coins() -> Dictionary:
	var out := {}
	var raw: Dictionary = DB.economy().get("kind_coins", {})
	for n in raw:
		out[int(Kind[String(n)])] = int(raw[n])
	return out

## Evaluate the best five-card combination out of the given cards.
## 大王/小王 are WILD: each stands in for whatever card scores highest.
## `rules` are the run's rule flags (Deck.rules): shortcut (straights may
## skip one rank), fourfingers (four cards make straights AND flushes), twotone
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
	var has_wild := false
	for c in five:
		if c.is_wild():
			has_wild = true
	if not has_wild:
		return _pack(five, five, rules)
	return _score_many_wilds(five, rules)


## ⚠ **仅测试参照, 生产路径不再用**(2026-08-27 全域候选构造替代)。
## 旧的 k≤2 暴力:每张万能试 52 张实牌(允许与实牌重复 —— 万能可以「变成你已有的那张」,
## 这是万能语义的权威口径, 候选构造必须与它逐分相等, tests/t_pattern.gd 对拍锁着)。
## 超级百搭上市后它曾是热路径主开销(bot 大盘装卡局单局 0.6s→~3.6s, 52² 在 best_score_of 内层)。
static func _score_five_brute(five: Array, rules: Dictionary = {}) -> Dictionary:
	var wild_idx: Array = []
	for i in range(five.size()):
		if five[i].is_wild():
			wild_idx.append(i)
	if wild_idx.is_empty():
		return _pack(five, five, rules)
	assert(wild_idx.size() <= 2, "brute 参照只支持 k<=2(k>=3 用缩减域对拍)")
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


## 万能牌解析 = **全域候选构造**(2026-08-27 推广到 k=1..5;此前 k≤2 走 52^k 暴力、
## k≥3 走候选构造两条路)。推广的动因是性能:超级百搭上市后 bot 大盘装卡局
## 单局 0.6s→~3.6s —— 52² 暴力在 best_score_of 的热路径里(08-27 全量门因此每门慢一倍)。
## 实测(1000 次 8 选 5 含 2 万能, 同机同批, 2026-08-27):候选构造 vs 旧暴力 = **91×**
## (3.29s vs 299.7s, tools/_benchwild.gd 临时基准, 跑完即删;1000 手逐手分数全等)。
##
## 做法 = 把最优解可能落的形态**直接造出来**, 打分仍走 _pack → _classify(rules)
## —— 近道/四指/红调/黑调**自动生效**, 规则不开第二份(「规则只准有一份」)。
## 三个候选族(无规则时总数 O(30) 内;完备性由 tests/t_pattern.gd 的
## k=1/2 全域 52^k 对拍 + k=3 缩减域对拍锁着):
##   ① **顺子/同花顺窗**:5 连窗 + 轮子;近道加「6 宽窗去一内点」、四指加 4 连窗
##      (窗表按规则组合静态缓存)。实牌若有重复 rank, 多出的那张当免费旁观位
##      (只有四指的 4 连窗有旁观位, 5 连窗自然滤掉 —— 账恒等:旁观数 = 5 − 窗长)。
##      wild 补窗内缺口, 花色对 suits_pool 各出一版;多余 wild 变同花色 A(最高 kicker)。
##   ② **点数族**(对/两对/三条/满堂/四条全形态):wild 逐张从 {实牌各 rank, A, K}
##      取值的多重组合。K 是唯一需要的额外 kicker(4 张 A 时第五张不能再 A ——
##      5 张同 rank 会被判成高牌);任何点数形态都是其中一个组合。
##   ③ **同花兜底**:wild 全变 A(同花色)。⚠ 不许「避开实牌 rank 往下取」——
##      A♠A♠ 这种**与实牌同 rank 的重复牌是合法且更优的**(暴力语义允许,
##      k=2 时四条常配不齐, 带对的同花就是最优解, 对拍抓过这个形态)。
##      实牌混花时它退化成普通高牌候选 = 全场保底(任何输入 ≥1 候选)。
static func _score_many_wilds(five: Array, rules: Dictionary) -> Dictionary:
	var reals: Array = []
	for c in five:
		if not c.is_wild():
			reals.append(c)
	var k: int = five.size() - reals.size()
	var suits_pool: Array = []
	var real_ranks: Array = []
	for c in reals:
		if not suits_pool.has(c.suit):
			suits_pool.append(c.suit)
		if not real_ranks.has(c.rank):
			real_ranks.append(c.rank)
	if suits_pool.is_empty():
		suits_pool = [0]
	var cands: Array = []
	# ① 顺子/同花顺窗
	for w in _run_sets(rules):
		var gaps: Array = []
		for r in w:
			if not real_ranks.has(r):
				gaps.append(r)
		if gaps.size() > k:
			continue
		# gaps ≤ k 即充要:5 连窗时它自动排掉「实牌重 rank / 实牌在窗外」
		# (那会让 gaps 变大;账恒等:旁观位 = 5 − 窗长, 5 连窗旁观位为零)。
		var spare: int = k - gaps.size()
		for s in suits_pool:
			var cand: Array = reals.duplicate()
			for r in gaps:
				cand.append(Card.new(r, s))
			for i in range(spare):
				cand.append(Card.new(14, s))
			cands.append(cand)
	# ② 点数族
	var targets: Array = real_ranks.duplicate()
	if not targets.has(14):
		targets.append(14)
	if not targets.has(13):
		targets.append(13)
	var assigns: Array = []
	_rank_multisets(targets, k, 0, [], assigns)
	for asg in assigns:
		var cand: Array = reals.duplicate()
		for i in range(asg.size()):
			cand.append(Card.new(asg[i], i % 4))
		cands.append(cand)
	# ③ 同花兜底
	for s in suits_pool:
		var cand: Array = reals.duplicate()
		for i in range(k):
			cand.append(Card.new(14, s))
		cands.append(cand)
	# 全部候选交给 _pack, 判型与算分照旧 —— 这里只负责"猜得全", 不负责"判得对"。
	var best := {}
	var best_score := -1
	for cand in cands:
		var res: Dictionary = _pack(five, cand, rules)
		if int(res["score"]) > best_score:
			best_score = int(res["score"])
			best = res
	return best


## 顺子候选的 rank 集合表, 按 (近道, 四指) 规则组合缓存(内容只依赖规则, 不依赖手牌)。
## A 恒以 14 表示(轮子/低 A 窗构造时先按 1 排再换回)。
static var _runsets_cache := {}

static func _run_sets(rules: Dictionary) -> Array:
	var shortcut: bool = rules.get("shortcut", false)
	var four: bool = rules.get("fourfingers", false)
	var key: int = (1 if shortcut else 0) | (2 if four else 0)
	if _runsets_cache.has(key):
		return _runsets_cache[key]
	var sets: Array = []
	# 基础:5 连窗(顶 6..14)+ 轮子 A2345。
	for t in range(6, 15):
		sets.append([t - 4, t - 3, t - 2, t - 1, t])
	sets.append([14, 2, 3, 4, 5])
	# 近道:5 个互异 rank 落在 6 宽窗内(= 去掉一个内点;去端点退化为基础窗)。
	# lo=1 是低 A 窗(A,2..6 去一内点)。
	if shortcut:
		for lo in range(1, 10):
			for drop in range(lo + 1, lo + 5):
				var s5: Array = []
				for r in range(lo, lo + 6):
					if r != drop:
						s5.append(14 if r == 1 else r)
				sets.append(s5)
	# 四指:4 连窗(lo=1 是 A234);叠近道 = 4 个互异 rank 落在 5 宽窗内。
	if four:
		for lo in range(1, 12):
			var s4: Array = []
			for r in range(lo, lo + 4):
				s4.append(14 if r == 1 else r)
			sets.append(s4)
		if shortcut:
			for lo in range(1, 11):
				for drop in range(lo + 1, lo + 4):
					var s4: Array = []
					for r in range(lo, lo + 5):
						if r != drop:
							s4.append(14 if r == 1 else r)
					sets.append(s4)
	_runsets_cache[key] = sets
	return sets


## targets 的 k 元多重组合(不计顺序), 递归填 out。k≤5、targets≤7 → 最多几十个。
static func _rank_multisets(targets: Array, k: int, start: int, cur: Array, out: Array) -> void:
	if cur.size() == k:
		out.append(cur.duplicate())
		return
	for i in range(start, targets.size()):
		cur.append(targets[i])
		_rank_multisets(targets, k, i, cur, out)
		cur.pop_back()


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
	# ⚑ **四指的同花半边**(2026-08-18 补上):原作 Four Fingers 本来就是「4 张即可成
	# 同花/顺子」, 首版只实装了顺子那半 —— 砍掉的恰好是它与近道的**区别**, 用户在
	# 货架上看到的是两张几乎一样的卡(「这俩太像了」)。判据 = 五张里**任一花色 ≥4 张**;
	# 黑调/红调在场时按**颜色类**合并计数(与五张路径同一套口径, 组合不加特例)。
	# ⚠ 已知近似:四张顺与四张花可以是**不同**的四张, 也会读成同花顺 —— 对玩家有利的
	# 罕见角落, 模型与游戏共用本函数, 不会分叉。
	if not is_flush and rules.get("fourfingers", false):
		var tally := {}
		for c in five:
			var key: String
			if rules.get("redtone", false) and c.is_red():
				key = "red"
			elif rules.get("blacktone", false) and not c.is_red():
				key = "black"
			else:
				key = str(c.suit)
			tally[key] = int(tally.get(key, 0)) + 1
			if int(tally[key]) >= 4:
				is_flush = true
				break
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
