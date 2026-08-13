extends RefCounted

## 求解买牌(`Draft.card_value`)**结构上**看不见的卡, 逐张带理由。
## 三类结构盲区, 每一类都是模型的已知边界, 不是这张卡的接线问题:
##   ① **时间族** —— 求解器没有时钟(design/solving.md:「时间在模型里确实不存在」,
##      b=1 掉 37.8% 那条实测)。压哨/早锁类的条件在推演里永远不成立。
##   ② **前置族** —— 效果以另一张卡为条件, 推演的基准槽位里没有它时按定义为 0
##      (`tools/kit.gd::PREREQ` 是同一件事的另一半)。
##   ③ **动作空间族** —— 求解器一拍只弃「没被握住的那 ≤3 张」, 而游戏允许整手撒出 5 张。
##      现役空缺(断舍离因此撤出 json 挂仪器债), 类别留着 —— 那道边界还在。
## ⚠ 加条目前先问一遍:是真的结构盲区, 还是**信号没接进 `tools/solver.gd`**?
## 后者是 bug —— 2026-08-13 这一批里 stilllife/stageexit 就属于后者, 接上后当场量到。
const SOLVER_BLIND := {
	"finale": "① 时间:压哨(acted_late)在推演里不成立",
	"momentum": "① 时间:早锁成长, 计数器在推演里恒 0",
	"shredder": "① 时间:早锁 Target",
	"freeze": "① 时间:早锁脉冲, 装卡当拍未武装",
	"curtain": "① 时间:压哨到最后一秒, 推演里不成立",
	"stopwatch": "① 时间:剩余秒数在推演里恒 0(没有时钟就没有'剩下多少')",
	"earlyout": "① 时间:弃牌时刻在推演里不存在",
	"mirror": "② 前置:没有 Target 时复制半个 0",
}

## 假想推演(买牌求解化, design/solving.md 第三部分)**绝不能碰真实局**。
## 三处会被污染且都不报错:牌堆的随机数序列 / 成长牌的计数器 / 缓存。
## ⚠ 这条契约破了的症状是「算一下买哪张牌」这个动作**本身改变了这一局** ——
## 一局悄悄变成另一局, 而所有读数看起来都很正常。
func run(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var run := Run.new()
	run.deck = Deck.new(3)
	run.cache = []
	run.joker_slots = [null, null, null, null]
	run.character = Character.roster()[0]
	run.coins = GameConfig.STARTING_COINS
	run.run_faces = {0: "", 1: "setlist", 2: "unplugged", 3: "rush"}
	var bot := Bot.new(rng, Report.new(1, GameConfig.SECTIONS_PER_RUN))
	# 先打两拍, 让局面有内容(缓存有牌、牌堆消耗过、计数器动过)
	for i in range(2):
		run.phrase_in_section = i
		var p := Beat.begin(run)
		bot._play_perfect(p, run.joker_slots, "", 0.2, 2, 0)
		Beat.settle(run, p, {})
		Beat.phrase_end(run, p, {})
	# 装一张**成长牌** —— 它的计数器最容易被推演推进
	for j in Joker.pool():
		if j.id == "vinyl":
			run.joker_slots[1] = j
	run.phrase_in_section = 2
	var before := _draft_snap(run)
	# 跑一批推演。⚠ coin/shop 通路的卡**按定义**在分数推演里恒 0(不产分:金币卡
	# 走金币臂、货架卡走商店臂, 各有专属仪器)—— 把它们计入会让这条判据随经济卡
	# 扩批而假红, 所以只对 score/solver 通路的卡要求非零(2026-08-12 shelf 三件套起)。
	var proof_of := {}
	for e in DB.jokers():
		proof_of[String(e["id"])] = String(e.get("proof", ""))
	var measurable: Array = []
	var zeros: Array = []
	for j in Joker.pool():
		if String(proof_of.get(j.id, "")) in ["coin", "shop"]:
			continue
		measurable.append(j.id)
		if absf(Draft.card_value(j, run, -1, 999, 0.2, 2)) <= 0.0001:
			zeros.append(j.id)
	t.eq(_draft_snap(run), before,
		"假想推演之后真实局逐位不变(牌堆/缓存/槽位/成长计数器都不许被碰)")
	# ⚠ 循环外断言一次。判据从「魔法数 −5」改成**具名豁免表**(2026-08-13):
	# 照脸的 `weak_upper_bound` 先例 —— **豁免必须是有意的, 不能是漏掉的**。
	# 数字余量会被新卡悄悄吃掉(这一批就吃了 4 格), 具名表则让「又多一张看不见的卡」
	# 当场变成一次红, 作者必须回答它属于哪一类结构盲区、或者去把信号接进求解器。
	for zid in zeros:
		t.check(SOLVER_BLIND.has(zid),
			"求解买牌给 '%s' 算出 0 —— 要么把它的信号接进 tools/solver.gd, 要么在 SOLVER_BLIND 里声明理由" % zid)
	# 反向也锁:声明了却其实量得到 = 表过期了, 该删条目(同 weak_upper_bound 的反向检查)
	for bid in SOLVER_BLIND:
		if measurable.has(bid):
			t.check(zeros.has(bid),
				"'%s' 已经量得到了, 把它从 SOLVER_BLIND 删掉(过期的豁免是遮羞布)" % bid)


## 一局的全部可变状态压成一个字符串 —— 用来断言"没被碰过"。
func _draft_snap(run: Run) -> String:
	var s := "%d|%d|%d|" % [run.deck.draw_pile.size(), run.deck.discard_pile.size(), run.coins]
	for c in run.deck.draw_pile:
		s += c.label() + ","
	s += "|cache:"
	for c in run.cache:
		s += c.label() + ","
	s += "|slots:"
	for j in run.joker_slots:
		s += ("-" if j == null else "%s%s" % [j.id, JSON.stringify(j.state)]) + ","
	return s
