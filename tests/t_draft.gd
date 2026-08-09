extends RefCounted

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
	# 跑一批推演
	var nonzero := 0
	for j in Joker.pool():
		if absf(Draft.card_value(j, run, -1, 999, 0.2, 2)) > 0.0001:
			nonzero += 1
	t.eq(_draft_snap(run), before,
		"假想推演之后真实局逐位不变(牌堆/缓存/槽位/成长计数器都不许被碰)")
	# ⚠ 循环外断言一次。判据:求解版给 0 的卡必须**少于**手写表的 6/23,
	# 否则这条修法是把一个盲区换成了更大的盲区(第一版就栽在这里: 14/23)。
	t.check(nonzero >= Joker.pool().size() - 5,
		"求解买牌能给多数卡算出非零价值 (非零 %d / %d)" % [nonzero, Joker.pool().size()])


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
