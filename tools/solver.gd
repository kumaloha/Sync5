class_name Solver
extends RefCounted

## 数学 D 的单拍核心 (design/solver_roadmap.md)。
##
## **铁律:计分绝不在这里重新实现。** 本模块只做模拟器不做的两件事 ——
## **枚举**牌面(而非随机抽)、**求最优**(而非照手写规矩打);算分一律调
## `core/pattern.gd` + `core/settle.gd`。两边共用同一份计分代码, 是「数学与模拟
## 不分家」的唯一保证(design/solver_roadmap.md), 也是一致性测试能成立的前提。
##
## 一拍的决策在真实规则下塌缩成两步:
##   ① 选一个弃牌子集 S ⊆ 8 张可见 (|S| ≤ 金币), 花 |S| 金币, 弃掉的位置随机补牌
##   ② 把 8 张切成 (计分的 5 张, 留缓存的 3 张) —— C(8,5) = 56 种切法
## ② 就是**跨拍权衡本身**:同一次切分同时决定这拍得分与下拍缓存,
## 所以「留一张 A 等下拍」不需要额外建模, 它自动出现在 56 种比较里。
##
## 为什么交换预算不进枚举:缓存 3 张 → **最多 3 次交换就能把任意「8 选 5」搬进手牌**,
## 而手速预算是 5 次(`GameConfig.BEAT_SWAPS`), 所以交换**不构成约束**;
## `core/db.gd` 有断言锁住 `swaps >= cache_cap`, 预算被调低到够不着时会直接红。

## 一个切法的结果。`keep` 是留在缓存的 3 张 —— 它既是下一拍的状态,
## 也参与本拍计分(和弦读缓存花色), 所以必须进 Settle 的 extra。
class Split extends RefCounted:
	var score: int
	var coins: int
	var kind: int
	var hold: Array      # 计分的 5 张
	var keep: Array      # 留缓存的 3 张
	## 玩家**看得见的信息下**这个切法值多少分。没有盖牌时 belief == score;
	## 有盖牌时 belief 是对替身采样取的期望, 而 score 仍是**真值**。
	## 铁律:**用 belief 选, 用 score 记账。** 混用任何一个都会得到一个
	## 「上帝视角的玩家」或者「算错分的账本」。
	var belief: float


## 枚举 8 张可见牌的全部切法。**不含随机性**, 是 DP 的内层原语:
## DP 拿走 56 个 (得分, 剩余缓存) 对, 按「未来过关概率」挑, 而不是按本拍分数挑。
##
## visible: 手牌 + 缓存(共 HAND_SIZE + CACHE_CAP 张)
## slots:   小丑牌 4 槽 (0 = Target)
## extra:   Settle 的上下文 (prev_kind / acted_late / discards / coins /
##          phrase_idx / mod / character)。**cache_cards 由本函数按每个切法覆盖**,
##          调用方不要自己塞。
## hidden:  visible 里**玩家看不见**的下标(盖着的牌)。空 = 完全信息, 老行为。
## subs:    K 组替身, `subs[s][j]` 是第 s 组里给 `hidden[j]` 的假想牌。
##          ⚠ **必须由调用方一次抽好、给全部切法共用**(公共随机数)——
##          和 `cache_value` 那条是同一个教训:独立采样时噪声会吃掉切法之间的真实差异,
##          贪心当场退化成随机挑。这里更凶, 因为盖牌直接改牌型。
static func splits(visible: Array, slots: Array, extra: Dictionary,
		rules: Dictionary = {}, hidden: Array = [], subs: Array = []) -> Array:
	var n: int = visible.size()
	var k: int = GameConfig.HAND_SIZE
	var out: Array = []
	if n < k:
		return out
	# 盖牌时先把 K 份「玩家以为的 8 张」建好, 每份只建一次给 56 个切法共用。
	var beliefs: Array = []
	if not ORACLE and not hidden.is_empty() and not subs.is_empty():
		for sub in subs:
			var v: Array = visible.duplicate()
			for j in range(mini(hidden.size(), sub.size())):
				v[int(hidden[j])] = sub[j]
			beliefs.append(v)
	# ③ 手速预算:把某张缓存牌搬进手牌要一次交换, 所以这个切法需要的交换次数
	# = 落在缓存区(下标 >= HAND_SIZE)的张数。超预算的切法**物理上够不着**, 不该进枚举。
	# ⚠ 现值 swaps=5 >= 上限 cache_cap=3, 所以**当前零变化** —— 机制先接上,
	# 数值等 Tape 量出真人一拍做几次操作再定(那时它既是拟真修正, 又顺带提速)。
	var swap_budget: int = GameConfig.BEAT_SWAPS
	for combo in _combos(n, k):
		var need_swaps := 0
		for i in combo:
			if i >= GameConfig.HAND_SIZE:
				need_swaps += 1
		if need_swaps > swap_budget:
			continue
		var hold: Array = []
		var taken := {}
		for i in combo:
			hold.append(visible[i])
			taken[i] = true
		var keep: Array = []
		for i in range(n):
			if not taken.has(i):
				keep.append(visible[i])
		var res: Dictionary = Pattern.evaluate_best(hold, rules)
		if res.is_empty():
			continue
		# 和弦等谓词读缓存 —— 切法决定了缓存, 所以这里必须用本切法的 keep
		var ctx := extra.duplicate()
		ctx["cache_cards"] = keep
		var outcome: Dictionary = Settle.run(res, slots, ctx)
		var s := Split.new()
		s.score = int(outcome["score"])
		s.coins = int(outcome["coins"])
		s.kind = int(res.get("kind", -1))
		s.hold = hold
		s.keep = keep
		# 信念分:同一个下标组合, 在 K 份「玩家以为的 8 张」上各算一次取平均。
		# 没有盖牌时直接沿用真值 —— 保证完全信息路径**逐位不变**(测试锁着)。
		if beliefs.is_empty():
			s.belief = float(s.score)
		else:
			var acc := 0.0
			for bv in beliefs:
				var bhold: Array = []
				var bkeep: Array = []
				for i in range(n):
					if taken.has(i):
						bhold.append(bv[i])
					else:
						bkeep.append(bv[i])
				var bres: Dictionary = Pattern.evaluate_best(bhold, rules)
				if bres.is_empty():
					continue
				var bctx := extra.duplicate()
				bctx["cache_cards"] = bkeep
				acc += float(Settle.run(bres, slots, bctx)["score"])
			s.belief = acc / float(maxi(1, beliefs.size()))
		out.append(s)
	return out


## 「按信念挑, 按真值记分」的**零分配**版本 —— 和 `best_score` 之于 `best_split`
## 是同一层关系, 存在的理由也一样:内层只要一个数字, 而 `splits()` 会给 56 个切法
## 各建一个 Split 对象 + 复制一份 extra 字典。
##
## ⚠ 这不是过早优化, 是**已经踩过的坑**:首版在 `best_discard` 的盲路径里直接调
## `best_split`, 于是最内层循环(7 子集 × 采样 × 56 切法 × K 信念)每次都在建
## 56 个对象 —— 探针 12 局跑了 10 分钟还没完。LESSONS.md 测量纪律 #7 早写着这是全场最大的一笔开销,
## 而我在最内层用了最贵的入口。
static func best_blind_score(visible: Array, slots: Array, extra: Dictionary,
		rules: Dictionary, hidden: Array, subs: Array) -> float:
	var n: int = visible.size()
	var k: int = GameConfig.HAND_SIZE
	if n < k:
		return 0.0
	if ORACLE or hidden.is_empty() or subs.is_empty():
		return best_score(visible, slots, extra, rules)
	var beliefs: Array = []
	for sub in subs:
		var v: Array = visible.duplicate()
		for j in range(mini(hidden.size(), sub.size())):
			v[int(hidden[j])] = sub[j]
		beliefs.append(v)
	var ctx: Dictionary = extra.duplicate()
	var best_combo: Array = []
	var best_b := -1.0e30
	for combo in _combos(n, k):
		var taken := {}
		for i in combo:
			taken[i] = true
		var acc := 0.0
		for bv in beliefs:
			var bhold: Array = []
			var bkeep: Array = []
			for i in range(n):
				if taken.has(i):
					bhold.append(bv[i])
				else:
					bkeep.append(bv[i])
			var bres: Dictionary = Pattern.evaluate_best(bhold, rules)
			if bres.is_empty():
				continue
			ctx["cache_cards"] = bkeep
			acc += float(Settle.run(bres, slots, ctx)["score"])
		if acc > best_b:
			best_b = acc
			best_combo = combo
	if best_combo.is_empty():
		return 0.0
	# 信念选出了切法, 现在按**真牌**给它记分
	var taken2 := {}
	for i in best_combo:
		taken2[i] = true
	var hold: Array = []
	var keep: Array = []
	for i in range(n):
		if taken2.has(i):
			hold.append(visible[i])
		else:
			keep.append(visible[i])
	var res: Dictionary = Pattern.evaluate_best(hold, rules)
	if res.is_empty():
		return 0.0
	ctx["cache_cards"] = keep
	return float(Settle.run(res, slots, ctx)["score"])


## 抽 `count` 组替身, 每组 `n_hidden` 张。牌从**牌堆 + 弃牌堆**里设想抽取
## (`peek_many` 不消耗牌堆), 也就是「所有不在我手上/缓存里的牌」。
##
## ⚠ **显式近似**(design/solver_roadmap.md):真正的信念应当是「所有我看不见的牌」, 那还包括
## 盖着的那几张自己 —— 它们物理上在手里, 所以不在 peek 的池子里。后果是求解器
## **永远猜不中真值**, 它对自己的估计因此偏保守。|hidden| ≤ 5 而池子 ≈44,
## 偏差在个位数百分比, 但它是**单向**的, 记在这里别忘了。
static func make_subs(deck: Deck, rng: RandomNumberGenerator, n_hidden: int,
		count: int) -> Array:
	var out: Array = []
	if n_hidden <= 0 or count <= 0:
		return out
	for _s in range(count):
		var pick: Array = deck.peek_many(rng, n_hidden)
		if pick.size() == n_hidden:
			out.append(pick)
	return out


## 在候选值上加噪声再取 argmax —— **决策质量**这一维(design/solving.md 第二部分)。
##
## ε 是**无量纲**的:噪声尺度 = ε × 这一拍候选值的标准差, 所以同一个 ε 在
## 不同配置、不同分数量级下含义相同 —— 这是它能跨配置比较的前提。
##   ε = 0    精确 argmax(完美玩家)
##   ε ≈ 1    噪声与切法之间的真实差异同量级
##   ε → ∞    随机挑
##
## ⚠⚠ **ε=0 时一个随机数都不许消耗。** 否则全部历史读数会整体漂移**而且不报错**
## —— `Deck.peek_many` 那次改的只是消耗个数, 探针输出就从 +19.9 漂到 +23.3,
## 而它一点速度都没换来, 已整条撤回。tests/runner.gd 里锁着这条。
##
## ⚠ 噪声必须来自**调用方传进来的** rng —— 配对实验靠两臂共用种子, 这里自己
## new 一个 RNG 就把配对破坏了, 而破坏得很安静。
static func _noisy_argmax(vals: Array, eps: float, rng: RandomNumberGenerator) -> int:
	var n := vals.size()
	if n == 0:
		return -1
	var bi := 0
	if eps <= 0.0 or rng == null:
		for i in range(1, n):
			if float(vals[i]) > float(vals[bi]):
				bi = i
		return bi
	var m := 0.0
	for v in vals:
		m += float(v)
	m /= float(n)
	var acc := 0.0
	for v in vals:
		acc += (float(v) - m) * (float(v) - m)
	var sd: float = sqrt(acc / float(maxi(1, n - 1)))
	var best := -1.0e30
	for i in range(n):
		var x: float = float(vals[i]) + eps * sd * rng.randfn(0.0, 1.0)
		if x > best:
			best = x
			bi = i
	return bi


## 本拍最好能打多少分(只看当下, 不含跨拍)。给一致性测试和冒烟用。
## ⚠ 挑的是 **belief** 最高的那个, 返回的 Split 里 `score` 仍是**真值**。
## 没有盖牌时 belief == score, 所以完全信息下的行为逐位不变。
static func best_split(visible: Array, slots: Array, extra: Dictionary,
		rules: Dictionary = {}, hidden: Array = [], subs: Array = [],
		eps: float = 0.0, rng: RandomNumberGenerator = null) -> Split:
	var all := splits(visible, slots, extra, rules, hidden, subs)
	if all.is_empty():
		return null
	# ⚠ 一律按 belief 选(用信念选, 用真值记账) —— 混用会得到一个上帝视角的玩家。
	var vals: Array = []
	for s in all:
		vals.append(s.belief)
	var bi := _noisy_argmax(vals, eps, rng)
	return all[bi]


## Settle 是否是**恒等变换** —— 没有小丑牌、没有主角、没有 Boss 脸时,
## score 就等于 `chips × 牌型倍率`, 也就是 Pattern 已经算好的那个数。
## 这个判断值钱是因为:中性基准、空槽一致性探针、λ 扫描**全都是这种情况**,
## 而 Settle 会建一个 15 键字典 + 复制数组 + 遍历四槽, 全是白工。
static func _settle_identity(slots: Array, extra: Dictionary) -> bool:
	for j in slots:
		if j != null:
			return false
	if extra.get("character") != null:
		return false
	# ⚠ 曾经写的是 `mod == ""` —— 于是**任何一张脸**都会关掉这条快路径, 实测
	# 8.4 → 36 ms/拍(4.3×), 而 2026-08-07 那批脸里大多数根本不进 Settle
	# (驱逐缓存 / 改容量 / 盖牌 / 收过路费 / 砍时间 / 抬目标分)。
	# 现在按**这张脸有没有 Settle 会读的参数**判, 分类在 db.gd, 测试锁着。
	return not SectionMod.affects_settle(String(extra.get("mod", "")))


## **只要最高分, 不要对象。**
##
## `cache_value` / `best_discard` 调内层求解只为拿一个数字, 而 `splits()` 会给 56 种切法
## 各建一个 Split 对象 + 复制一份 extra 字典 —— 一拍约 2240 个对象、2240 次字典复制,
## 全部当场扔掉。GDScript 里对象分配和字典复制都很贵, 这是全场最大的一笔开销。
##
## ⚠ **必须与 `best_split(...).score` 逐位相同**, `tests/runner.gd` 里有随机对拍锁着。
## **优化改结果是最坏的一种 bug** —— 它不报错, 只让所有读数悄悄偏掉。
static func best_score(visible: Array, slots: Array, extra: Dictionary,
		rules: Dictionary = {}) -> float:
	var n: int = visible.size()
	var k: int = GameConfig.HAND_SIZE
	if n < k:
		return 0.0
	var plain := _settle_identity(slots, extra)
	# Settle 恒等时整个「8 选 5 取最大」交给 Pattern 的零分配版本 ——
	# 省掉 56 次数组分配 + 56 次结果字典, 这是内层热点的最后一笔白工。
	if plain:
		return float(Pattern.best_score_of(visible, rules))
	var ctx: Dictionary = extra.duplicate()
	var best := -1.0
	for combo in _combos(n, k):
		var hold: Array = []
		for i in combo:
			hold.append(visible[i])
		var res: Dictionary = Pattern.evaluate_best(hold, rules)
		if res.is_empty():
			continue
		var taken := {}
		for i in combo:
			taken[i] = true
		var keep: Array = []
		for i in range(n):
			if not taken.has(i):
				keep.append(visible[i])
		ctx["cache_cards"] = keep
		var sc := float(Settle.run(res, slots, ctx)["score"])
		if sc > best:
			best = sc
	return maxf(0.0, best)


## 缓存潜力 = **E[留下这 3 张, 下一拍最好能打多少分]**。
##
## **刻意不手写启发式**(「同花势 / 对子势 / 高点」那一套):那是每来一张新 Target
## 就要补一条规则的老病 —— 正是本项目要根除的东西。让同一套 Solver 去采样,
## 它就**自动读 Target**(经 Settle 的倍率链)、**新卡零改代码**。
## ⚠ **`futures` 必须由调用方一次抽好、给全部切法共用**(公共随机数)。
## 首版给每个切法**独立**采样, 结果是灾难:cache_value 的量级和本拍得分一样大(≈180),
## 独立采样 + samples=2 → 每个切法带 ±70 噪声, 乘 λ 后灌进比较里,
## 而 56 个切法之间真实差距本来只有几十分 —— **贪心退化成随机挑**,
## 实测 λ 越大分越低(189.8 → 180.0 → 169.3), 看起来像"想法不成立",
## 其实测的是我自己的噪声。共用补牌后噪声成对抵消, 比较的是**真实差异**。
static func cache_value(keep: Array, slots: Array, extra: Dictionary,
		futures: Array, rules: Dictionary = {}) -> float:
	if futures.is_empty():
		return 0.0
	# ⚑ **真实跨拍转移**(design/solving.md 第三部分):留下的 3 张**不一定**留到下一拍 ——
	# `Beat.phrase_end` → `Phrase.cleanup()` 会按 cache_evict 随机弃掉 n 张,
	# 下一拍开局补满。前瞻假设它们原样留着, 就会在缓存驱逐族下**高估缓存**,
	# 而那正是 2026-08-07 把「丢谱测出正分」误读成「这张脸没用」的根。
	#
	# ⚠⚠ **不许"取前 n 张"** —— 驱逐在游戏里是**均匀随机**的, 而 `keep` 的顺序来自
	# 切法枚举顺序。按位置删会让 cache_value 依赖枚举顺序, 于是某些切法纯因为
	# 排在前面而显得好 —— 那是一个**不报错的排序偏置**。
	# 缓存只有 3 张, 所以**精确枚举全部 C(3,n) 种驱逐结果取期望**就行:
	#   evict 0→1 种(与原实现完全相同) · 1→3 种 · 2→3 种 · 3→1 种。
	# 精确期望既没有采样噪声, 也不消耗任何随机数。
	# ⚠ `futures` 的每一份长度是 `HAND_SIZE + evict`:前 HAND_SIZE 张是下一拍的手牌,
	# 多出来的 `evict` 张是**缓存补牌** —— 驱逐之后 `Phrase.start()` 会把缓存补满,
	# 所以下一拍照样是 8 张可见。漏掉补牌 = 前瞻在驱逐族下系统性悲观(静默偏置)。
	var evict: int = SectionMod.cache_evict(String(extra.get("mod", "")))
	var survivor_sets := _survivor_sets(keep, evict)
	var acc := 0.0
	var n := 0
	for f in futures:
		for sv in survivor_sets:
			var trial: Array = (sv as Array).duplicate()
			trial.append_array(f)          # 手牌 + 补牌一起进, 凑回 8 张
			if trial.size() < GameConfig.HAND_SIZE:
				continue
			acc += best_score(trial, slots, extra, rules)   # 只要数字, 不建 56 个对象
			n += 1
	return acc / float(maxi(1, n))


## 从 keep 里随机弃掉 evict 张之后, **全部可能的幸存集合**。
## 缓存 ≤3 张所以直接位掩码枚举, 最多 8 次循环。
## evict=0 → 恰好一种(= keep 本身), 所以老路径逐位不变。
static func _survivor_sets(keep: Array, evict: int) -> Array:
	var n := keep.size()
	if evict <= 0:
		return [keep.duplicate()]
	if evict >= n:
		return [[]]
	var want := n - evict
	var out: Array = []
	for mask in range(1 << n):
		var cnt := 0
		for b in range(n):
			if (mask >> b) & 1:
				cnt += 1
		if cnt != want:
			continue
		var sub: Array = []
		for b in range(n):
			if (mask >> b) & 1:
				sub.append(keep[b])
		out.append(sub)
	return out


## **平衡贪心**(2026-08-06 用户拍板, 取代跨拍 DP)。
##
## 理由(用户): 缓存只有 3 张、未来的小丑牌没有任何信息(商店是随机的, 根本不在状态里,
## DP 假装能算等于自欺)。而 `tools/agree.gd` 实测整个跨拍视野的赌注**只有 3.8%** ——
## 拿最大的一块工程换 ≤3.8%, 是坏买卖。
##
## 权衡写成一条式子:
##     value(切法) = 本拍得分 + λ · E[下一拍得分 | 留下的 3 张]
## λ = 0 就退化成单拍贪心(现在的 v1);λ 越大越"养牌"。
## ⚠ **λ 不许拍脑袋** —— 用 `tools/lam.gd` 扫出来, 判据是探针里那条 −3.8% 的缺口
## 收窄到多少(design/solver_roadmap.md 的近似 3b)。λ 还应随剩余拍数衰减:最后一拍缓存一文不值。
##
## **盖牌(不完全信息)**:排序、剪枝、取 argmax 一律走 `belief`;返回值里的
## `score` 是真值, 由调用方记账。⚠ **缓存潜力那一层不受盖牌影响** ——
## 用户 2026-08-07 拍板「盖着的牌结算时翻开」, 所以留进缓存的牌**下一拍就是已知的**,
## `cache_value` 用真值是对的, 不是近似。
static func best_split_lookahead(visible: Array, slots: Array, extra: Dictionary,
		deck: Deck, rng: RandomNumberGenerator, lam: float, samples: int,
		rules: Dictionary = {}, hidden: Array = [], subs: Array = [],
		eps: float = 0.0) -> Split:
	var all := splits(visible, slots, extra, rules, hidden, subs)
	if all.is_empty():
		return null
	if lam <= 0.0 or samples <= 0:
		var vals0: Array = []
		for s2 in all:
			vals0.append(s2.belief)
		return all[_noisy_argmax(vals0, eps, rng)]
	# 公共随机数: 一次抽好 samples 组「下一拍的牌」, 全部候选切法共用。
	# 见 cache_value 的注释 —— 独立采样会让噪声吃掉真实差异。
	# 每组 = HAND_SIZE 张手牌 + evict 张缓存补牌(驱逐后下一拍会补满)。
	var f_evict: int = SectionMod.cache_evict(String(extra.get("mod", "")))
	var futures: Array = []
	for _i in range(samples):
		# ⚠ 多抽 `evict` 张:缓存被驱逐后, 下一拍 `Phrase.start()` 会**把缓存补满**,
		# 所以真实的下一拍仍然是 8 张可见。只留幸存者会让前瞻在驱逐族下过度悲观
		# (lostpage 下变成 7 张), 那是一个静默的偏置。
		# evict=0 时张数 = HAND_SIZE, **RNG 消耗个数与老路径完全相同** —— 这条要紧,
		# 改了消耗个数会让全部历史读数漂移而不报错(`peek_many` 那次已撤回)。
		var f: Array = deck.peek_many(rng, GameConfig.HAND_SIZE + f_evict)
		if f.size() == GameConfig.HAND_SIZE + f_evict:
			futures.append(f)
	all.sort_custom(func(a: Split, b: Split) -> bool: return a.belief > b.belief)
	# ② 前瞻早停(**精确剪枝, 不改结果**):缓存潜力有上界 —— 下一拍最多打出皇家同花顺。
	# 即时分落后超过 λ×上界 的切法, 前瞻再好也翻不了盘, 直接不算。
	# 算一次未来 = samples × 56 次内层求解, 是全场最贵的一步, 能跳就跳。
	var ub := _cache_ub(slots, extra, rules)
	var k: int = mini(TOP_K, all.size())
	var cand: Array = []          # 算过前瞻的候选
	var cand_v: Array = []
	var best_v := -1.0e30
	for i in range(k):
		var s3: Split = all[i]
		# ⚠ 早停判据仍然用**无噪声**的 best_v —— 拿噪声后的值去剪会把真正的好切法
		# 误剪掉, 那就从"加噪声"变成"算错了"。
		# ⚠ 但注意:ε=0 时这条剪枝是**精确的**(不改结果);ε>0 时它只保证
		# 「被剪掉的在无噪声意义下翻不了盘」, 噪声本可以让它们翻盘 ——
		# 也就是说 **ε>0 下候选集被截断到 TOP_K 再剪枝**, 噪声只在这个子集里抖。
		# 这是显式的建模近似, 不是 bug:噪声玩家也不会把 56 种都认真比一遍。
		if not cand.is_empty() and s3.belief + lam * ub < best_v:
			break
		var v := s3.belief + lam * cache_value(s3.keep, slots, extra, futures, rules)
		cand.append(s3)
		cand_v.append(v)
		if v > best_v:
			best_v = v
	if cand.is_empty():
		return null
	return cand[_noisy_argmax(cand_v, eps, rng)]


## 缓存潜力的**上界** = 下一拍理论最高分(皇家同花顺过一遍当前构筑)。
## 松但**有效**, 而且一拍只算一次 —— 用它做 ② 的早停判据, 剪掉的都是真翻不了盘的。
static var _ub_cache: Dictionary = {}

static func _cache_ub(slots: Array, extra: Dictionary, rules: Dictionary) -> float:
	var key := ""
	for j in slots:
		key += ("-" if j == null else String(j.id)) + ","
	key += String(extra.get("mod", ""))
	if _ub_cache.has(key):
		return _ub_cache[key]
	var royal: Array = []
	for r in [10, 11, 12, 13, 14]:
		royal.append(Card.new(int(r), 0))
	var res: Dictionary = Pattern.evaluate_best(royal, rules)
	var ctx := extra.duplicate()
	ctx["cache_cards"] = []
	var v := float(Settle.run(res, slots, ctx)["score"])
	_ub_cache[key] = v
	return v


## 算未来时只考察立即得分最高的这么多个切法(见 best_split_lookahead 的剪枝)。
const TOP_K := 12


## **A/B 开关:上帝视角。** 打开后 `splits()` 无视 `hidden`, 求解器照样看得见盖着的牌。
##
## 它存在的唯一理由是**证明信念机制真的在起作用**:同一局、同一批随机数,
## 只有求解器的知识不同 —— 两条臂的分差就是**这几张牌的信息值**。
## 差值 ≈ 0 就说明盖牌只是画面上的事, 模型里根本没发生 ——
## 而那正是这个项目栽过三次的同一个坑(赶场 / 入场费误判 / 差点又一次)。
## ⚠ **只有探针能开它**;生产路径必须保持 false, 开着跑出来的数全是上帝视角的。
static var ORACLE := false


## 弃牌头 (design/solver_roadmap.md ①)。返回该弃掉 `keep` 里的哪几张(下标, 相对 keep)。
##
## **只考虑弃 `keep`(留缓存的那 3 张)**:计分的 5 张是当前最优解, 弃掉它们等于自伤;
## 真实玩家弃的也正是"这拍用不上、留着也没用"的那几张。8 个子集, 便宜。
##
## ⚠ **`coin_value`(κ, 金币影子价)不能省。** 孤立一拍地看金币没有下一拍, 最优解永远是
## 把钱花光 —— 那正是 `design/history_adversarial.md` §7 亲口警告的幻想区(一拍弃 8 张要 8◆, 一局总收入才 45-70◆)。
## κ 和 λ 一样**扫出来**, 不许拍。
##
## futures_per: 每个子集采样几组补牌。**同一批补牌给所有子集共用**(公共随机数)——
## 独立采样的教训见 cache_value 的注释, 那次让整个设计看起来像不成立。
## `base` 可由调用方传入复用 —— `_play_perfect` 刚算过一遍最优切法, 不传就是白算两次。
##
## **blind_samples > 0 = 补进来的牌是盖着的**(`blindspot` 脸)。这一条不改也能跑,
## 但**跑出来的是错的**:默认路径假设「弃完能看见新牌再挑最优切法」, 而这张脸拿走的
## 恰恰就是那个。不改的话求解器会系统性**高估弃牌的价值**, 于是狂弃牌 ——
## 而这张脸整个的意义就在弃牌决策上, 建模错了等于把脸测成了另一张脸。
## 正确口径:**新牌按信念挑切法, 按真值记分**(和 splits 的 belief/score 分工一致)。
static func best_discard(visible: Array, slots: Array, extra: Dictionary,
		deck: Deck, rng: RandomNumberGenerator, coins: int, max_cards: int,
		coin_value: float, samples: int, lam: float, rules: Dictionary = {},
		base_in: Split = null, blind_samples: int = 0) -> Array:
	var base: Split = base_in if base_in != null else best_split(visible, slots, extra, rules)
	if base == null:
		return []
	var budget: int = mini(coins, max_cards)
	if budget <= 0:
		return []
	# 公共随机数:一次抽好最多 budget 张的补牌池, 所有子集从同一批里取前 k 张
	var pool: Array = []
	for _i in range(samples):
		pool.append(deck.peek_many(rng, budget))
	# 盖牌时的信念替身, 同样一次抽好全局共用(第三处公共随机数, 同一个理由)。
	# ⚠ 这是一个**嵌套**期望(外层猜真牌, 内层猜玩家怎么想), 成本是乘起来的 ——
	# 内层刻意压到 2 组:它只决定弃不弃, 不决定最终怎么打, 精度需求低一档。
	var bsubs: Array = []
	if not ORACLE:
		for _i in range(mini(blind_samples, 2)):
			bsubs.append(deck.peek_many(rng, budget))
	var best_gain := 0.0
	var best_sub: Array = []
	for sub in _subsets(base.keep.size()):
		var d: int = sub.size()
		if d == 0 or d > budget:
			continue
		var acc := 0.0
		for f in pool:
			var trial: Array = []
			for c in base.hold:
				trial.append(c)
			for i in range(base.keep.size()):
				if not sub.has(i):
					trial.append(base.keep[i])
			for j in range(d):
				trial.append(f[j])
			var ctx := extra.duplicate()
			ctx["discards"] = int(extra.get("discards", 0)) + d
			if bsubs.is_empty():
				acc += best_score(trial, slots, ctx, rules)  # 只要数字, 见 best_score 的注释
			else:
				# 新牌落在 trial 的末 d 位, 它们就是玩家看不见的那几张。
				var hid: Array = []
				for j in range(d):
					hid.append(trial.size() - d + j)
				var sub_d: Array = []
				for bs in bsubs:
					sub_d.append(bs.slice(0, d))
				acc += best_blind_score(trial, slots, ctx, rules, hid, sub_d)
		var mean: float = acc / float(maxi(1, pool.size()))
		var gain: float = mean - float(base.score) - coin_value * float(d)
		if gain > best_gain:
			best_gain = gain
			best_sub = sub.duplicate()
	return best_sub


## 非空子集的下标组合(n ≤ 缓存格数, 所以最多 7 个)。
static func _subsets(n: int) -> Array:
	var out: Array = []
	for mask in range(1, 1 << n):
		var s: Array = []
		for i in range(n):
			if mask & (1 << i):
				s.append(i)
		out.append(s)
	return out


## 一拍的完整最优(含弃牌), 期望值靠采样补牌。
##
## ⚠ **`coin_value` 不能省。** 单拍孤立地看, 金币没有下一拍, 最优解永远是「把钱花光」
## —— 那正是 `design/history_adversarial.md` §7 警告的幻想区(一拍弃 8 张要 8◆, 一局总收入才 45-70◆)。
## 金币的真实价值是**跨拍的**, 由 DP 给出影子价; 这里以「每 1◆ 值多少分」传进来。
## coin_value = 0 就是"钱不要钱"的上界, 只应在诊断时用。
##
## budget_cards: 本拍最多弃几张(受金币与手速预算共同限制)
## samples:      每个弃牌子集采样几次补牌
## 返回 {score: 期望净分, discard: Array[int] 弃掉的 visible 下标, split: Split 或 null}
static func best_beat(visible: Array, slots: Array, extra: Dictionary,
		deck: Deck, coins: int, coin_value: float, rng: RandomNumberGenerator,
		samples: int = 16, rules: Dictionary = {}) -> Dictionary:
	var n: int = visible.size()
	var budget_cards: int = mini(coins, _max_discard_cards())
	var best := {"score": -1.0, "discard": [], "split": null}

	# d = 0: 不弃牌, 精确, 无需采样
	var s0 := best_split(visible, slots, extra, rules)
	if s0 != null:
		best = {"score": float(s0.score), "discard": [], "split": s0}

	# d >= 1: 对补牌取期望。牌是从牌堆抽的, 抽完要放回去 —— 我们只是在"设想",
	# 不能真的消耗牌堆(那会让求解本身改变游戏状态)。
	for d in range(1, budget_cards + 1):
		for sub in _combos(n, d):
			var kept: Array = []
			var drop := {}
			for i in sub:
				drop[i] = true
			for i in range(n):
				if not drop.has(i):
					kept.append(visible[i])
			var acc := 0.0
			for _r in range(samples):
				var trial: Array = kept.duplicate()
				trial.append_array(deck.peek_many(rng, d))
				if trial.size() < n:
					continue
				var ctx := extra.duplicate()
				ctx["discards"] = int(extra.get("discards", 0)) + d
				var bs := best_split(trial, slots, ctx, rules)
				if bs != null:
					acc += float(bs.score)
			var mean: float = acc / float(samples)
			# 弃牌的代价 = 金币的跨拍影子价, 不是 0
			var net: float = mean - coin_value * float(d)
			if net > float(best["score"]):
				# 记录一次代表性切法(用当前手牌重算一次, 只为返回结构完整)
				best = {"score": net, "discard": sub.duplicate(), "split": null}
	return best


## 手速预算换算成"本拍最多弃几张"。
## 预算是 `BEAT_DISCARDS` **次**动作, 而一次动作可以跨手牌+缓存多选 ——
## 所以能弃几张的上界是可见牌数, 次数限制真正约束的是**自适应轮数**
## (弃完看到补牌再决定要不要再弃), 那一层留给 DP。这里取保守上界。
static func _max_discard_cards() -> int:
	return GameConfig.HAND_SIZE + GameConfig.CACHE_CAP


static var _combo_cache: Dictionary = {}

## n 选 k 的全部下标组合, 带缓存(同一局里会被调用几十万次)。
static func _combos(n: int, k: int) -> Array:
	var key := n * 100 + k
	if _combo_cache.has(key):
		return _combo_cache[key]
	var res: Array = []
	_combo_helper(0, n, k, [], res)
	_combo_cache[key] = res
	return res


static func _combo_helper(start: int, n: int, k: int, cur: Array, res: Array) -> void:
	if cur.size() == k:
		res.append(cur.duplicate())
		return
	for i in range(start, n):
		cur.append(i)
		_combo_helper(i + 1, n, k, cur, res)
		cur.pop_back()
