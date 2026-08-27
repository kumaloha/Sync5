extends SceneTree
## 倍率 v3 的两列先验(2026-08-27 用户:「重新估计概率,拍波动性,重新给倍率」):
##   P_b(≥k) —— **带弃牌预算 b 的追型达成率**(旧组合口径是零弃牌, 免费时代的
##               attrib 又是无限弃 —— 经济 v2 弃牌 1◆/张后, 真实口径在两者之间);
##   CV(k)  —— 追型策略单拍得分的变异系数(波动性, CLAUDE.md Target ④ 的输入)。
## 口径:发 8 张(手 5 + 缓存 3 视为可用池)→ 按型的保留判据一次性批量弃 ≤b 张
## 重抽 → 8 选 5 取该型最优;失败时按残手实际牌型计分(这正是方差的来源)。
## 理想化追型(不是 bot 不是真人)—— 与「按牌堆给不给算」同一哲学。
##   godot --headless --path . --script res://tools/vol.gd   (SYNC5_VOL_N 覆盖样本量)
const N := 20000
const BUDGETS := [0, 2, 4]

func _initialize() -> void:
	var n := N
	if OS.get_environment("SYNC5_VOL_N") != "":
		n = int(OS.get_environment("SYNC5_VOL_N"))
	var kinds := [Pattern.Kind.PAIR, Pattern.Kind.TWO_PAIR, Pattern.Kind.THREE_KIND,
		Pattern.Kind.STRAIGHT, Pattern.Kind.FLUSH, Pattern.Kind.FULL_HOUSE,
		Pattern.Kind.FOUR_KIND, Pattern.Kind.STRAIGHT_FLUSH, Pattern.Kind.ROYAL_FLUSH]
	print("k, b, P_b(≥k), mean_score, sd, CV")
	for k in kinds:
		for b in BUDGETS:
			var hit := 0
			var sum := 0.0
			var sum2 := 0.0
			var rng := RandomNumberGenerator.new()
			rng.seed = 90000 + int(k) * 10 + int(b)
			for i in range(n):
				var deck := Deck.new(rng.randi())
				var cards: Array = []
				for _j in range(8):
					cards.append(deck.draw())
				var keep := _keep_for(cards, int(k))
				# 弃 non-keep 里的 toss 张换新;**其余旧牌保留**(b=0 = 原 8 张原样,
				# 第一版把没弃的也丢了 = 白拿整手新牌, b 失效、顺子 P 虚高到 0.46)。
				var toss: int = mini(b, 8 - keep.size())
				var pool: Array = keep.duplicate()
				var kept_set := {}
				for c in keep:
					kept_set[c] = true
				var dropped := 0
				for c in cards:
					if kept_set.has(c):
						continue
					if dropped < toss:
						dropped += 1
						var nc := deck.draw()
						if nc != null:
							pool.append(nc)
					else:
						pool.append(c)
				var best: Dictionary = Pattern.evaluate_best(pool)
				var got: int = int(best.get("kind", 0))
				var sc: float = float(best.get("score", 0))
				if got >= int(k):
					hit += 1
				sum += sc
				sum2 += sc * sc
			var mean := sum / float(n)
			var varr: float = maxf(0.0, sum2 / float(n) - mean * mean)
			var cv: float = sqrt(varr) / maxf(1.0, mean)
			print("%s, %d, %.4f, %.1f, %.1f, %.3f" % [Pattern.NAMES[k], b,
				float(hit) / float(n), mean, sqrt(varr), cv])
	quit(0)


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
