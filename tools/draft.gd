class_name Draft
extends RefCounted

## **买牌的边际价值 —— 用求解器算,不手写**(design/solving.md 第三部分)。
##
## ## 为什么
##
## `tools/bot.gd::_card_ev` 是一个 `match id:`,**每张小丑牌一条手写公式**,
## 而**新卡默认 `return 0.0`** —— 加第 24 张牌,机器人永远不买它,
## 它在所有基于模型的读数里**完全隐形,且不报错**。
## 更糟的是它是**循环论证**:尺子是「我手写的这张牌值多少」,量的是「这张牌值多少」。
## 而 `coin.gd` 实测**整个构筑值 4.2 倍** —— 分数的大头压在最粗的这一层。
##
## ## 前提:脸是**已知**的(design/solving.md §2.2)
##
## 用户 2026-08-08:「**没有脸信息就没有选牌策略**」。
## 四段的脸开局一次掷定且**全部可见**,所以「接下来 M 拍在什么规则下打」是**已知量**。
## 手写公式的根本困难正是这个 —— 「这张牌接下来能触发多少次」取决于接下来的规则。
## **规则已知,就能直接算。**
##
## ## 式子
##
##     value(j) = E[接下来 M 拍 | 槽位 = S ⊕ j] − E[接下来 M 拍 | 槽位 = S]
##
## ## ⚑ 三条设计决定(每条都是被一次错误换来的)
##
## **① 推演走真实的 `Beat`,不自己写简化版。**
## 第一版我手搓了一份简化"一拍",结果它给 0 的卡有 **14/23** —— 比它要取代的
## 手写表(6/23)还盲。原因是简化切掉了整整一类卡:不弃牌 → 吃弃牌的卡看不见;
## 不推进成长计数器 → 成长牌恒为 0;不结算金币 → 经济卡看不见;不跑拍末钩子 → 那一族全丢。
## **今天刚把一局的编排从 14 份收成 1 份,转头我又手搓了第 15 份。**
## 现在推演 = `fork` 一份真的 `Run` + 调真的 `Beat`,规则只有一份。
##
## **② 推演里的每一拍用跨拍最优(λ 前瞻),不是单拍贪心。**
## 用户 2026-08-08:「**求解的时候要考虑多轮的最优,而不是眼前的最优**」。
## 第一版用 `best_split`(λ=0),理由是「前瞻对两臂影响一致、差里会抵消」——
## **那个理由没验证过而且很可能是错的**:一张改变缓存价值的牌(比如和弦读缓存花色),
## 它的价值**恰恰只体现在跨拍**。单拍贪心推演会把这一类系统性低估。
##
## **③ 视野跟着剩余拍数走,不是固定值。**
## 一张牌买了会用到局尾,固定 M 会在中段低估、在末段高估。
## 现在 `M = min(剩余拍数, MAX_BEATS)`,上限由成本定。
##
## ## ⚠⚠ 推演绝不能碰真实局
##
## 三处会被污染且都不报错:**牌堆的随机数序列** / **成长牌的计数器** / **缓存**。
## 全部由 `RunLoop.fork` 隔离(它有自己的 Deck+RNG、`Joker.clone()` 深拷贝 state)。
## 推演用的 `Bot` 也必须是**独立实例持独立 RNG** —— `bot._play_perfect` 内部要抽替身牌,
## 用真实局那个 rng 就把序列消耗掉了。
## **验收判据:推演之后真实局逐位不变**(`tests/runner.gd` 锁着)。

## 视野上限。**不是拍脑袋,是被池子里的卡定死的**:`bassline` 的触发条件是
## `counter >= 12`,M<12 时它**结构上不可能**被看到(实测 M=6 下它恒为 0)。
## 实测成本:M=6 约 0.48 秒/局、**M=12 约 0.95 秒/局** —— 完美玩家路径(curve 100 局)
## 约 95 秒,可接受。**视野该由内容决定,不是由预算决定。**
## ⚠ 以后加了触发周期更长的卡, 这个数要跟着改, 否则那张卡静默隐形。
const MAX_BEATS := 12

## 金币折算成分数的汇率。`tools/coin.gd` 实测 **κ 极度不对称**:
## 拿走 36.3 分/金币, 给 0.3 分/金币 —— 因为机器人**金币过剩**(段末余 16→31◆,
## 4 槽 × 8 商店的花钱能力封顶), 多给的钱买不到东西。
## **所以 κ 不是常数是一道阈值**, 这里取"给"的那一侧(保守)。
## ⚠ 后果:经济卡(小费罐/利息/独狼)在推演里价值很低。**那多半是真的** ——
## 按 design/solving.md §8 的铁律, 测出近零只能标注「上界不动, 真人待定」, 不许改内容。
const COIN_TO_SCORE := 0.3


## 一张候选牌在当前局面下,平均每拍值多少分。
##
## cand:      候选牌(null 无意义, 调用方必须给)
## run:       **真实的局** —— 本函数只读它, 通过 fork 隔离
## replace_k: >0 = 换掉第 k 槽;-1 = 装进空槽
## lam:       跨拍权重。**别传 0** —— 那是单拍贪心, 见设计决定 ②
static func card_value(cand: Joker, run: Run, replace_k: int, sim_seed: int,
		lam: float, lam_samples: int) -> float:
	var left: int = _beats_left(run)
	var m: int = mini(left, MAX_BEATS)
	if m <= 0 or cand == null:
		return 0.0
	# ⚠ 两条臂用**同一个 sim_seed** —— 公共随机数, 噪声成对抵消。
	var with_arm := _forward(run, cand, replace_k, sim_seed, m, lam, lam_samples)
	var without := _forward(run, null, -1, sim_seed, m, lam, lam_samples)
	return (with_arm - without) / float(m)


## 从当前局面往前推演 m 拍, 返回总分。**走真实的 `Beat`, 在 fork 出来的局上。**
static func _forward(run: Run, cand: Joker, replace_k: int, sim_seed: int,
		m: int, lam: float, lam_samples: int) -> float:
	var f := RunLoop.fork(run, sim_seed)
	if cand != null:
		var c := cand.clone()
		if replace_k >= 0:
			f.joker_slots[replace_k] = c
		else:
			for k in range(f.joker_slots.size()):
				if f.joker_slots[k] == null:
					f.joker_slots[k] = c
					break
		# ⚠ 装备时的一次性效果(比如百搭开万能牌)要在 fork 的牌堆上跑, 不是真牌堆。
		c.on_acquire(f.deck)
	# ⚠ 独立 Bot + 独立 RNG:`_play_perfect` 内部要抽替身牌, 用真实局的 rng 会消耗它的序列。
	var srng := RandomNumberGenerator.new()
	srng.seed = sim_seed
	var sbot := Bot.new(srng, Report.new(1, GameConfig.SECTIONS_PER_RUN))
	var total := 0.0
	for _i in range(m):
		if f.section_idx >= GameConfig.SECTIONS_PER_RUN:
			break
		if f.phrase_in_section >= GameConfig.PHRASES_PER_SECTION:
			f.phrase_in_section = 0
			f.section_idx += 1
			f.first_kind = -99        # 段首重置(setlist 锁的是本段第一拍)
			if f.section_idx >= GameConfig.SECTIONS_PER_RUN:
				break
		var mod := f.face()
		var p := Beat.begin(f)
		# ⚑ 跨拍最优, 不是眼前最优(设计决定 ②)
		sbot._play_perfect(p, f.joker_slots, mod, lam, lam_samples, f.section_idx)
		var outcome := Beat.settle(f, p, {})
		total += float(outcome["score"])
		Beat.phrase_end(f, p, {})     # 缓存驱逐 + 成长牌计数器都在这里
		f.phrase_in_section += 1
	# ⚠ 金币也要计入 —— 否则**只给金币的卡(小费罐/利息/独狼)恒为 0**, 而那是
	# "推演只数分数"造成的假 0, 不是这些卡真的没用。汇率见 COIN_TO_SCORE。
	total += float(f.coins - run.coins) * COIN_TO_SCORE
	return total


## 这一局还剩几拍 —— 视野跟着它走(设计决定 ③)。
static func _beats_left(run: Run) -> int:
	var done: int = run.section_idx * GameConfig.PHRASES_PER_SECTION + run.phrase_in_section
	return maxi(0, GameConfig.SECTIONS_PER_RUN * GameConfig.PHRASES_PER_SECTION - done)
