class_name RunLoop
extends RefCounted

## **一局的编排 —— 探针共用的那一份**(一局的骨架只此一份)。
##
## ## 为什么有这个文件
##
## `docs/design/tech.md` 把**一拍**的编排从六份合成了一份(`core/beat.gd`),然后我转头在
## **一局**这一层又抄了一遍 —— 实测**14 份**:
##   sim · curve · coin · blind · addit · price 各 1,**gate 3**,**formal 6**。
## (formal 那 6 份是 2026-08-08 我自己加的。写着「别在这里重写规则」的注释,
##  然后在同一个文件里把循环抄了六遍。)
##
## 后果不是事故,是**读数没有单一来源**:`curve.gd`(生成器)就是这 14 份之一,
## 它和 `gate.gd` 判生死的那份如果有任何一处不同,两边的数就不可比 —— 而且不报错。
##
## ## 和 `Beat` 的分工
##
## `Beat` 共用的是**转移**(一拍怎么走完),因为游戏是实时异步、探针是同步,
## **共用不了 `for` 循环**(docs/design/tech.md)。
## 本文件共用的是**循环**,所以它**只给探针用** —— `view/phrase.gd` 不碰它,
## 它照旧从时钟回调里按顺序调 `Beat`。
##
## ## ⚠ 验收判据
##
## **每换一份, 那份探针的输出必须逐字节不变**(除耗时那一行)。
## 手法见 docs/design/tech.md:把原版拷成 `tools/_base_X.gd` 再改原版,两版各跑一次对拍,用完删掉。
## 仓库不是 git 库,所以不依赖 VCS。


## 一局的配置。**14 份的差异全部收敛到这几个键** —— 再出现第 15 种需求时,
## 加键,不要再抄循环。
class Opts extends RefCounted:
	var rng: RandomNumberGenerator      # 外部传入 —— 配对实验靠共用种子, 不许内部 new
	var deck_seed: int = 0
	var faces: Dictionary = {}          # 段号 -> 脸 id。空 = 全程无脸
	var character = null                # null = 由 rng 抽(注意它会消耗一个随机数)
	## 谁在打:
	##   "perfect" —— 直接调 `Bot._play_perfect`(完美玩家, 用下面的 lam/eps)
	##   "none"    —— 不动手, 照发到的牌打(量牌面本身的决策空间时用)
	##   其他任何值 —— **走 `Bot._play_phrase` 的 cfg 分派**, 实际策略由 `cfg["bot"]` 决定。
	##   ⚠ 所以 `player="adaptive"` + `cfg={"bot":"perfect"}` 打的是**完美玩家**,
	##     不是规则 bot —— `curve.gd` 就是这么用的(它的 `BOT` 常量可切两种尺度)。
	##     名字容易误读, 别照字面理解。
	var player: String = "perfect"
	var lam: float = 0.0                # player=perfect 时的跨拍权重
	var eps: float = 0.0                # 决策噪声(docs/design/solving.md 第二部分)
	var lam_samples: int = 3
	var cfg: Dictionary = {}            # 传给 Bot 的队列配置(player=adaptive 用)
	## 这一局的**行为账本**(买牌算法拿它给卡定价)。留空则内部新建一份。
	## ⚠ 调用方要在回调里往里记东西、或者要在 play() 之后读它时,必须自己传一份进来 ——
	## 内部新建的那份只在 play() 的返回值里能拿到。
	## ⚠ `n / score / mult / kinds` 四项由 `_tally` 统一记, **回调里不要再记一遍**(会算两次)。
	var st: Dictionary = {}
	var shop: bool = false              # 开不开商店(构筑值 4.2 倍, 这个开关很重)
	var mortal: bool = false            # true = 真判生死;false = **不死局**打满 24 拍
	var targets: Array = []             # mortal 时判生死用的表
	var coin_delta: int = 0             # 起始金币的偏移(默认 0 = GameConfig.STARTING_COINS 不变)
	## ⚠ 这两个是 2026-08-08 迁 coin/addit/price/gate 时加的口子, **默认值维持原有 8 份的行为不变**。
	## 起因:`_tally` 原本无条件记 score/mult/kinds, 但 coin.gd 只手动记过 `n`(score/mult/kinds
	## 永远是 0, 靠这个"从不更新"的既有行为让买牌算法几乎只信先验), addit/price/gate 只手动记过
	## `n`+`score`+`disc`(mult/kinds 永远是 0)——这些都是 bot._draft 读 st 算牌价时依赖的既有
	## 输入, 不是可以随便"顺手补全"的遗漏。给 `_tally` 加两个开关, 让每份调用方按自己原来的
	## 记账口径接线, **不改默认值就不影响已经验过的 8 份**。
	var tally_score: bool = true
	var tally_mult_kinds: bool = true
	## ⚠ **两个钩子的时机不同, 挂错会静默量错东西**:
	##   on_begin  —— `Beat.begin` 之后、**玩家动手之前**。要量「这一拍的决策空间」
	##                (56 切法的方差分解那类)必须挂这里, 挂到 on_beat 上量的是打完之后的局面。
	##   on_beat   —— `Beat.settle` 之后、`phrase_end` 之前。量结果用这个。
	var on_begin: Callable = Callable()  # (run, p) -> void
	## (run, p, outcome, ctx) -> void。`ctx` 装**结算前**的快照:
	##   flags      —— 玩家这一拍的行为标志(late / early)
	##   prev_kind  —— ⚠ 结算前的上一拍牌型。`Beat.settle` 里就把它更新了,
	##                  在回调里读 `run.prev_kind` 拿到的是**本拍**的牌型。
	##                  `sim.gd` 统计「重复成手」靠的就是这个差, 读错了统计静默偏掉。
	var on_beat: Callable = Callable()
	## 每段末回调 `(run, section, sec_score, coins) -> void`。
	## ⚠ 在**判生死之前**触发 —— 「到达这一段的人数」这类计数在这里记才是对的。
	var on_section: Callable = Callable()


## 打一局。返回 {total, sec_scores, died_at, beats}。
##
## ⚠ **`died_at` = 死在第几段(0-based),没死是 -1。** 不死局恒为 -1。
## ⚠ **不死局的记账约定**:段末工资照发(假定通过)、段末商店照开。
## 这是 `curve.gd` 的既有约定 —— 反解目标分要在**同一批录好的数据**上重放任意候选目标,
## 所以不能真判生死(死了就没有后续段的分数了)。
static func play(o: Opts, bot: Bot) -> Dictionary:
	var run := Run.new()
	run.deck = Deck.new(o.deck_seed)
	run.cache = []
	run.joker_slots = [null, null, null, null]
	# ⚠ 顺序不许动 —— 配对臂靠的是两边 RNG 消耗序列完全一致。
	run.character = o.character if o.character != null \
		else Character.roster()[o.rng.randi_range(0, 7)]
	run.coins = maxi(0, GameConfig.STARTING_COINS + o.coin_delta)
	run.run_faces = o.faces
	var st: Dictionary = o.st if not o.st.is_empty() else _fresh_st()
	var coins: int = run.coins
	var total := 0
	var beats := 0
	var died_at := -1
	var sec_scores: Array = []
	for section in range(GameConfig.SECTIONS_PER_RUN):
		var mod := String(o.faces.get(section, ""))
		run.section_idx = section
		run.section_score = 0
		run.first_kind = -99              # setlist(定调)锁的是本段第一拍的牌型
		for pidx in range(GameConfig.PHRASES_PER_SECTION):
			run.phrase_in_section = pidx
			run.coins = coins
			var p := Beat.begin(run)      # 脸 / 发牌 / 入场费全在这一句
			if o.on_begin.is_valid():
				o.on_begin.call(run, p)   # ⚠ 决策**之前**
			var flags := _play(o, bot, p, run, section, mod)
			# ⚠ 必须在 `Beat.settle` **之前**抓 —— 它在里面就被更新了。
			var prev_kind_before := run.prev_kind
			var outcome := Beat.settle(run, p, flags)
			coins = run.coins
			total += int(outcome["score"])
			beats += 1
			_tally(st, outcome, o.tally_score, o.tally_mult_kinds)
			if o.on_beat.is_valid():
				o.on_beat.call(run, p, outcome,
					{"flags": flags, "prev_kind": prev_kind_before})
			Beat.phrase_end(run, p, flags)
			# 段中商店:每 PHRASES_PER_SHOP 拍一次, **不结算不判生死**(docs/design/levels.md)
			var done := pidx + 1
			if o.shop and done % GameConfig.PHRASES_PER_SHOP == 0 \
					and done < GameConfig.PHRASES_PER_SECTION:
				coins = bot._draft(run.joker_slots, o.cfg, run.deck, coins, st,
					_left(section, done), section, o.faces, run.cache, done, run)
		var sec_score: int = run.section_score
		sec_scores.append(float(sec_score))
		if o.on_section.is_valid():
			o.on_section.call(run, section, sec_score, coins)
		# 判生死 —— ⚠ 必须走 `Run.section_target_for`, 那是**两处判生死唯一的一份实现**。
		# `sim.gd` 曾在这里直接读表、漏乘 target_mult, 于是 raisedbar 在模型里整个是空气。
		# 曲目税(裁决 #8)同理:`variety_mult` 也是单一真相, 漏乘 = trilogy 在模型里放水
		# (旧硬门时代这里根本没查种数 —— 半个「游戏里活、模型里死」, 2026-08-13 修平)。
		if o.mortal:
			var tgt := int(round(float(Run.section_target_for(o.targets, section, mod))
				* Run.variety_mult(mod, run.section_kinds.size())))
			if sec_score < tgt:
				died_at = section
				break
		coins = Economy.grant(coins, GameConfig.SECTION_CLEAR_REWARD, run.joker_slots)
		# ⚠⚠ **末段没有段末商店** —— 游戏里 `view/phrase.gd` 在 `finale` 那一支直接
		# 走结算成功屏并 return, 根本不开商店。这里原本无条件开, 于是**模型比游戏多一次
		# 商店**(8 vs 7)。2026-08-09 用 Tape 的 `shop` 事件实测:**37/37 完整局都是
		# 「段中 4 + 段末 3 = 7 次」**, 无一例外。
		# 那一次幻影商店的剩余拍是 0(`ev × horizon` 恒为 0, 实测买入率 0%), 所以它
		# 几乎不改读数 —— 但它是**「规则在游戏里、在模型里不一致」的反方向一例**,
		# 而这个形状本项目已经栽过五次。不留。
		if o.shop and section < GameConfig.SECTIONS_PER_RUN - 1:
			coins = bot._draft(run.joker_slots, o.cfg, run.deck, coins, st,
				_left(section, GameConfig.PHRASES_PER_SECTION), section, o.faces,
				run.cache, GameConfig.PHRASES_PER_SECTION, run)
	# ⚠ `run` 也返回 —— 死后的记账(哪些牌在槽里)需要它, 否则调用方只能自己再建一个。
	return {"total": float(total), "sec_scores": sec_scores,
		"died_at": died_at, "beats": beats, "st": st, "coins": coins, "run": run}


static func _play(o: Opts, bot: Bot, p: Phrase, run: Run, section: int, mod: String) -> Dictionary:
	match o.player:
		"perfect":
			bot._play_perfect(p, run.joker_slots, mod, o.lam, o.lam_samples, section, o.eps)
			return {}
		"none":
			# 不动手 —— 照发到的牌打。用来量「这一拍本身有多少决策空间」,
			# 那种测量必须在**玩家没介入**的局面上做, 否则量的是玩家的选择而不是牌面。
			return {}
		_:
			return bot._play_phrase(p, o.cfg, run.joker_slots, section, mod)


## 剩余拍数 —— 买牌决策的视野。抄错这个数会让机器人在末段乱买。
static func _left(section: int, done: int) -> int:
	return (GameConfig.SECTIONS_PER_RUN - 1 - section) * GameConfig.PHRASES_PER_SECTION \
		+ (GameConfig.PHRASES_PER_SECTION - done)


static func _fresh_st() -> Dictionary:
	return {"n": 0.0, "disc": 0.0, "rep": 0.0, "late": 0.0, "early": 0.0,
		"zerod": 0.0, "faces": 0.0, "chord": 0.0, "tgt": 0.0,
		"score": 0.0, "mult": 0.0, "kinds": {}}


static func _tally(st: Dictionary, outcome: Dictionary, tally_score: bool = true,
		tally_mult_kinds: bool = true) -> void:
	st["n"] += 1.0
	if tally_score:
		st["score"] += float(outcome["score"])
	if tally_mult_kinds:
		st["mult"] += float(outcome["mult"])
		var res: Dictionary = outcome.get("res", {})
		var kk := int(res.get("kind", -1))
		st["kinds"][kk] = float(st["kinds"].get(kk, 0.0)) + 1.0


## **把一局 fork 一份给假想推演用**(docs/design/solving.md 第三部分)。
##
## ⚠⚠ 推演**绝不能碰真实局**。三处会被污染, 每一处都不报错:
##   ① **牌堆** —— fork 出来的 Deck 有自己的 RNG(`Deck.fork`), 否则"算一下买哪张牌"
##      这个动作本身会消耗真实局的随机数序列, 这一局悄悄变成另一局;
##   ② **成长牌的计数器** —— `Joker.clone()` 深拷贝 `state`, 否则推演把真实牌养大了;
##   ③ **缓存** —— duplicate 一份数组(Card 本身不改, 共享安全)。
##
## ⚠ 两条对照臂用**同一个 seed** fork —— 公共随机数, 噪声成对抵消。
## 这是全项目第五处公共随机数;前四处的教训都是「独立采样让噪声吃掉真实差异」。
static func fork(run: Run, seed_value: int) -> Run:
	var r := Run.new()
	r.deck = run.deck.fork(seed_value)
	r.cache = run.cache.duplicate()
	r.joker_slots = []
	for j in run.joker_slots:
		r.joker_slots.append(null if j == null else j.clone())
	r.coins = run.coins
	r.character = run.character          # 无状态, 共享安全
	r.run_faces = run.run_faces.duplicate()
	r.section_idx = run.section_idx
	r.phrase_in_section = run.phrase_in_section
	r.section_score = run.section_score
	r.phrase_index = run.phrase_index
	r.prev_kind = run.prev_kind
	r.first_kind = run.first_kind
	r.stage = Run.Stage.DECISION         # Beat 的状态机从"可以开拍"起步
	return r
