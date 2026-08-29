extends SceneTree
## 倍率 v3 的两列先验(2026-08-27 用户:「重新估计概率,拍波动性,重新给倍率」):
##   P_b(≥k) —— **带弃牌预算 b 的追型达成率**(旧组合口径是零弃牌, 免费时代的
##               attrib 又是无限弃 —— 经济 v2 弃牌 1◆/张后, 真实口径在两者之间);
##   CV(k)  —— 追型策略单拍得分的变异系数(波动性, CLAUDE.md Target ④ 的输入)。
## ⚑⚑ **口径修正(2026-08-28)**:旧口径「发 8 张(手 5 + 缓存 3 视为可用池)→ 8 选 5」
## **算的是另一个游戏** —— `core/phrase.gd::_scoring_cards()` 默认计分池只有**手牌 5 张**,
## 缓存不上台(除非装「合奏」)。要用上缓存得**逐张换进手牌**,而 `τ_swap`=1.44s
## 是所有动作里最贵的(tools/tau.py 真人实测),**不是免费的**。
## 旧口径的高估**随牌型难度单调递增**(共用随机数并排跑,b=2):
## 对子 1.4× · 两对 4.0× · 三条 4.8× · **顺子 10.6×** · 同花 9.8× · 葫芦 15.3×
## —— 所以它不是一个平移,是**把倍率排序拧歪**。
##
## 现口径:**手牌 5 张计分** + 缓存 m 次交换(m 取真人实测 1.0 次/拍)+ 弃 ≤b 张。
##   手牌 5 + 缓存 3 → ① 从缓存挑对追型最有用的 ≤m 张换进手 → ② 弃手里没用的 ≤b 张
##   → ③ **只按手上这 5 张**评牌型;失败时按残手实际牌型计分(方差的来源)。
## 理想化追型(不是 bot 不是真人)—— 与「按牌堆给不给算」同一哲学。
##
## ⚠ **旧口径用 `SYNC5_VOL_POOL=8` 复现** —— 倍率 v3 的两列先验是用它算的,
## 那批读数要能复算, 不然等于把已落地的定价悬空了。
##   godot --headless --path . --script res://tools/vol.gd   (SYNC5_VOL_N 覆盖样本量)
const N := 20000
const BUDGETS := [0, 2, 4]
## 缓存交换预算:真人实测 1.0 次/拍(tools/tau.py)。0 = 完全不用缓存。
const SWAPS := 1

func _initialize() -> void:
	var n := N
	if OS.get_environment("SYNC5_VOL_N") != "":
		n = int(OS.get_environment("SYNC5_VOL_N"))
	var legacy := OS.get_environment("SYNC5_VOL_POOL") == "8"
	print("口径:%s" % ("旧 8 选 5(复现 v3)" if legacy else "手牌 5 张 + 缓存 %d 次交换" % SWAPS))
	var kinds := [Pattern.Kind.PAIR, Pattern.Kind.TWO_PAIR, Pattern.Kind.THREE_KIND,
		Pattern.Kind.STRAIGHT, Pattern.Kind.FLUSH, Pattern.Kind.FULL_HOUSE,
		Pattern.Kind.FOUR_KIND, Pattern.Kind.STRAIGHT_FLUSH, Pattern.Kind.ROYAL_FLUSH]
	print("k, b, P_b(≥k), mean_score, sd, CV")
	for k in kinds:
		for b in BUDGETS:
			var hit := 0
			var sum := 0.0
			var sum2 := 0.0
			var hist := {}
			var sum_hit := 0.0
			var sum_miss := 0.0
			var rng := RandomNumberGenerator.new()
			rng.seed = 90000 + int(k) * 10 + int(b)
			for i in range(n):
				var deck := Deck.new(rng.randi())
				var cards: Array = []
				for _j in range(8):
					cards.append(deck.draw())
				var pool: Array
				if legacy:
					pool = _legacy_pool(cards, int(k), b, deck)
				else:
					pool = _hand_pool(cards, int(k), b, deck)
				var best: Dictionary = Pattern.evaluate_best(pool)
				var got: int = int(best.get("kind", 0))
				var sc: float = float(best.get("score", 0))
				if got >= int(k):
					hit += 1
					sum_hit += sc
				else:
					sum_miss += sc
				hist[got] = int(hist.get(got, 0)) + 1
				sum += sc
				sum2 += sc * sc
			var mean := sum / float(n)
			# ⚑ 落点直方图(2026-08-29 加):Target 的条件是「落在它的覆盖集里」而**不是
			# 「≥ 某型」** —— triplet 覆盖 三条/葫芦/四条, 顺子与同花插在中间不算。
			# 有了直方图, 任意覆盖集的命中率都从同一份数据算, 不用为每张 Target 各跑一次。
			var hist_s := ""
			for kk in hist:
				hist_s += "%s=%.4f " % [Pattern.NAMES[kk], float(hist[kk]) / float(n)]
			var varr: float = maxf(0.0, sum2 / float(n) - mean * mean)
			var cv: float = sqrt(varr) / maxf(1.0, mean)
			print("%s, %d, %.4f, %.1f, %.1f, %.3f | %s" % [Pattern.NAMES[k], b,
				float(hit) / float(n), mean, sqrt(varr), cv,
				"hit=%.1f miss=%.1f | %s" % [sum_hit / maxf(1.0, float(hit)),
					sum_miss / maxf(1.0, float(n - hit)), hist_s]])
	quit(0)


## 旧口径:8 张一起追型、一起弃、8 选 5(倍率 v3 用的就是它, 保留以便复算)。
func _legacy_pool(cards: Array, k: int, b: int, deck) -> Array:
	var keep := _keep_for(cards, k)
	# 弃 non-keep 里的 toss 张换新;**其余旧牌保留**(b=0 = 原 8 张原样,
	# 第一版把没弃的也丢了 = 白拿整手新牌, b 失效、顺子 P 虚高到 0.46)。
	var toss: int = mini(b, 8 - keep.size())
	var pool: Array = keep.duplicate()
	var kept := {}
	for c in keep:
		kept[c] = true
	var dropped := 0
	for c in cards:
		if kept.has(c):
			continue
		if dropped < toss:
			dropped += 1
			var nc = deck.draw()
			if nc != null:
				pool.append(nc)
		else:
			pool.append(c)
	return pool


## 现口径:**只有手牌 5 张计分**。缓存 3 张要先换进手(每次一个动作, 预算 SWAPS),
## 再弃手里没用的 ≤b 张。返回的就是结算看到的那 5 张。
##
## ⚑ 换牌的挑法 = **拿缓存里「属于 keep」的去顶手里「不属于 keep」的** ——
## 这正是玩家追型时做的事, 且换不动就不换(缓存里没有有用的牌时 m 白给也没用,
## 那恰恰是「缓存不是免费的 8 选 5」的量化体现)。
func _hand_pool(cards: Array, k: int, b: int, deck) -> Array:
	var hand: Array = cards.slice(0, 5)
	var cache: Array = cards.slice(5, 8)
	for _m in range(SWAPS):
		var want := _keep_for(hand + cache, k)
		var wset := {}
		for c in want:
			wset[c] = true
		var ci := -1
		for j in range(cache.size()):
			if wset.has(cache[j]):
				ci = j
				break
		if ci < 0:
			break                                  # 缓存里没有对追型有用的牌
		var hi := -1
		for j in range(hand.size()):
			if not wset.has(hand[j]):
				hi = j
				break
		if hi < 0:
			break                                  # 手里全是要保的, 换出去反而亏
		var tmp = hand[hi]
		hand[hi] = cache[ci]
		cache[ci] = tmp
	# 弃手牌里不属于 keep 的 ≤b 张
	var keep := _keep_for(hand, k)
	var kept := {}
	for c in keep:
		kept[c] = true
	var out: Array = []
	var dropped := 0
	for c in hand:
		if kept.has(c):
			out.append(c)
		elif dropped < b:
			dropped += 1
			var nc = deck.draw()
			if nc != null:
				out.append(nc)
		else:
			out.append(c)
	return out


## 追型 k 的保留判据(理想化:只为凑 k 保牌, 其余全弃)。
func _keep_for(cards: Array, k: int) -> Array:
	var by_rank := {}
	var by_suit := {}
	for c in cards:
		if not by_rank.has(c.rank):
			by_rank[c.rank] = []
		by_rank[c.rank].append(c)
		if not by_suit.has(c.suit):
			by_suit[c.suit] = []
		by_suit[c.suit].append(c)
	match k:
		Pattern.Kind.PAIR, Pattern.Kind.TWO_PAIR, Pattern.Kind.THREE_KIND, \
		Pattern.Kind.FULL_HOUSE, Pattern.Kind.FOUR_KIND:
			# 成组族:保所有 ≥2 张的组;不足时保最高单张组的一对候选(最高两张同留无益, 只保组)
			var keep: Array = []
			for r in by_rank:
				if by_rank[r].size() >= 2:
					keep.append_array(by_rank[r])
			if keep.is_empty():
				# 没有任何对:保最高一张当配对种子
				var hi = cards[0]
				for c in cards:
					if c.rank > hi.rank:
						hi = c
				keep.append(hi)
			return keep
		Pattern.Kind.FLUSH:
			var best_s := 0
			for su in by_suit:
				if by_suit[su].size() > by_suit.get(best_s, []).size():
					best_s = su
			return by_suit.get(best_s, [])
		Pattern.Kind.STRAIGHT, Pattern.Kind.STRAIGHT_FLUSH, Pattern.Kind.ROYAL_FLUSH:
			# 顺族:保「张数最多的 5 宽窗」内各 rank 一张(SF/Royal 再偏同花窗)
			var flushy: bool = k != Pattern.Kind.STRAIGHT
			var pool: Array = cards
			if flushy:
				var best_s2 := 0
				for su in by_suit:
					if by_suit[su].size() > by_suit.get(best_s2, []).size():
						best_s2 = su
				if by_suit.get(best_s2, []).size() >= 2:
					pool = by_suit[best_s2]
			var best_keep: Array = []
			for lo in range(2, 11):
				var win: Array = []
				var seen := {}
				for c in pool:
					var r2: int = 14 if (lo == 10 and c.rank == 14) else c.rank
					if r2 >= lo and r2 <= lo + 4 and not seen.has(c.rank):
						seen[c.rank] = true
						win.append(c)
				if win.size() > best_keep.size():
					best_keep = win
			return best_keep
	return cards
