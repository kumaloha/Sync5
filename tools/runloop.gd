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
const BOON_AUTO := "<auto>"


## 探针的 boon 掷法:与游戏同一份 `BlindBoon.roll`, 但喂它一条从 deck_seed 派生的**独立** RNG ——
## 共享主流(脸/补牌)一个数都不多消耗。seen 恒空:探针是老玩家世界, 不做 novelty。
static func roll_boon(deck_seed: int) -> String:
	var brng := RandomNumberGenerator.new()
	brng.seed = deck_seed * 53 + 11
	return BlindBoon.roll(brng)


class Opts extends RefCounted:
	var rng: RandomNumberGenerator      # 外部传入 —— 配对实验靠共用种子, 不许内部 new
	var deck_seed: int = 0
	var faces: Dictionary = {}          # 段号 -> 脸 id。空 = 全程无脸
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
	## 本局的 boon id。**缺省 AUTO = 像游戏一样掷一张**(从 deck_seed 派生的独立流, 不碰共享主流 ⇒
	## 配对臂的 RNG 消耗序列逐字节不变);传 "" = 明确无 boon(旧世界, A/B 用);传真 id = 指定。
	## 2026-08-21 评审 R6:探针此前从不设 boon, 四张 boon 在所有仪器里不存在 —— 本批把缺省翻成「有」,
	## ⇒ sim/curve/gate/price 的下一次读数是**新基线**。
	var boon: String = RunLoop.BOON_AUTO
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
	run.coins = maxi(0, GameConfig.STARTING_COINS + o.coin_delta)
	run.run_faces = o.faces
	run.run_boon = roll_boon(o.deck_seed) if o.boon == BOON_AUTO else o.boon
	# ⚠ 盲注掷点流要有种子(2026-08-21 评审 R11):`Run.new()` 的 `_blind_rng` 构造即随机,
	# 唯一消费者 `next_request_goal`(request 脸当值时每拍一掷)⇒ 约 1/8 的局随进程变,
	# 正是 sim A/A「1000 局翻 1 局」的形状。派生自 deck_seed, 不碰共享主流。
	run._blind_rng.seed = o.deck_seed * 31 + 7
	var st: Dictionary = o.st if not o.st.is_empty() else _fresh_st()
	var coins: int = run.coins
	var total := 0
	var beats := 0
	var died_at := -1
	var sec_scores: Array = []
	var sec_kinds: Array = []   # 每段打出的牌型种数(曲目税的输入)
	for section in range(GameConfig.SECTIONS_PER_RUN):
		var mod := String(o.faces.get(section, ""))
		run.section_idx = section
		run.reset_section_state()          # 与游戏 next_section 同一份清单(段内状态不许跨段继承)
		# ⚠ **段初自动借款已删(2026-08-30 三批转生)** —— 预支从「循环贷小丑牌」
		# 变成消耗牌:玩家在商店主动烧, 当场借、下一个段边界还。段初不再有任何自动动作。
		for pidx in range(GameConfig.PHRASES_PER_SECTION):
			run.phrase_in_section = pidx
			run.coins = coins
			var p := Beat.begin(run)      # 脸 / 发牌 / 入场费全在这一句
			if o.on_begin.is_valid():
				o.on_begin.call(run, p)   # ⚠ 决策**之前**
			var flags := _play(o, bot, p, run, section, mod)
			# ⚑ 拍内消耗牌(2026-08-29):在**看过手牌、做完动作之后**决定烧不烧 ——
			# 这正是「实时可点」相对「商店里用」的全部价值(用户拍板:商店里用
			# 「有点怪」)。放在 settle 之前, 所以加成能进这一拍的乘法链。
			bot._consumable_in_beat(run, p, section, pidx)
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
			# 达标即收工(2026-08-27 A 案, 两界镜像):bot 的判据 = 段分已达标 + 剩余拍的
			# 落袋 ≥ 继续打的期望收入(牌型金币 ~2.1◆/拍 —— 用 cashout 单价直接比,
			# 高于它就落袋)。⚠ 只在**拍边界**判, 与游戏侧同一时机。
			#
			# ⚠⚠⚠ **`o.targets` 为空时绝不收工**(2026-08-30 修, 这条漏了整整三天)。
			# `Run.section_target_for([], …)` 返回 **0**, 而 `section_score >= 0` **恒真**
			# ⇒ 不传目标表的探针**每段打完第一拍就落袋走人**。实测:默认 Opts 一局
			# **4.0 拍**, 传了 targets 才 17.6 拍(应有 24)。
			# **全仓只有 `sim.gd` 和 `dpcheck.gd` 传 `o.targets`** —— 其余十几个探针
			# (curve / kit / price / gate / coin / addit / lam / wallet / decay …)
			# 从 08-27 起量的都是**四拍的局**:
			#   · `curve.gd` 反解的关卡分 `[64,106,345,1422]` 是四拍局的分位数 ——
			#     「curve 段分中位 228/153/345/882 vs sim 500~3500 差 3~4 倍」那个
			#     一直归给「不死局 vs 幸存者偏差」的口径谜题, **真身就是这个 bug**;
			#   · `coin.gd` 量 κ 时一局只收 7.7◆(四拍), 于是 κ 读成 0.0;
			#   · `kit.gd` 的消耗牌永远烧不掉(它的启发式要 `pidx >= 4`, 而 pidx 只到 0)。
			# ⚑ **它一次都没报错, 每个探针都还在输出合理的数。**
			# ⇒ 这里的判据不是「达标了吗」而是**「有没有一条生死线可言」** ——
			# 没有目标表 = 不死局 = 打满(`curve.gd` 的记账约定原文:「不死局:打满 24 拍」)。
			if not o.targets.is_empty() \
					and run.section_score >= Run.section_target_for(o.targets, section, mod) \
					and pidx + 1 < GameConfig.PHRASES_PER_SECTION \
					and GameConfig.CASHOUT_PER_PHRASE > 2:
				var left: int = GameConfig.PHRASES_PER_SECTION - (pidx + 1)
				coins = Economy.grant(coins, Economy.cashout(left), run.joker_slots)
				break
			# 段中商店:每 PHRASES_PER_SHOP 拍一次, **不结算不判生死**(docs/design/levels.md)
			var done := pidx + 1
			if o.shop and done % GameConfig.PHRASES_PER_SHOP == 0 \
					and done < GameConfig.PHRASES_PER_SECTION:
				coins = bot._draft(run.joker_slots, o.cfg, run.deck, coins, st,
					_left(section, done), section, o.faces, run.cache, done, run)
		var sec_score: int = run.section_score
		sec_scores.append(float(sec_score))
		sec_kinds.append(run.section_kinds.size())   # 事后判生死要算曲目税(gate.gd 用)
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
		# 预支还款:工资入账后判, 付不起 = run 死(含 S4 —— 通关那刻也得先还钱)。
		# 预支还款:工资入账后判 —— 付不起 = run 死(含 S4, 卡面写着 "or die")。
		# ⚠ 读的是 `run.debt`(消耗牌记下的待还), 不再是持仓里的循环贷。
		if run.debt > 0:
			if coins < run.debt:
				died_at = section
				break
			coins -= run.debt
			run.debt = 0
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
	return {"total": float(total), "sec_scores": sec_scores, "sec_kinds": sec_kinds, "boon": run.run_boon,
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
	r.run_faces = run.run_faces.duplicate()
	r.section_idx = run.section_idx
	r.phrase_in_section = run.phrase_in_section
	r.section_score = run.section_score
	r.phrase_index = run.phrase_index
	r.prev_kind = run.prev_kind
	r.first_kind = run.first_kind
	# 2026-08-21 外部审查:fork 此前漏了下面七样 ⇒ 买牌推演里 boon 不存在、配给预算归零、
	# 缓存年龄归零、曲目税消失、余响的上一拍分丢失、盲注流不可复现。显式逐字段拷 —— 新加 Run
	# 字段时这里要跟(t_run 锁了一条「fork 字段完备」断言)。
	r.run_boon = run.run_boon
	r.cache_meta = run.cache_meta.duplicate(true)
	r.section_kinds = run.section_kinds.duplicate()
	r.section_discards_used = run.section_discards_used
	r.request_last = run.request_last
	r.previous_raw_score = run.previous_raw_score
	r.tutorial = run.tutorial
	r._blind_rng.seed = seed_value * 131 + 17   # 派生种子:推演可复现, 不碰本尊的流
	r.stage = Run.Stage.DECISION         # Beat 的状态机从"可以开拍"起步
	return r
