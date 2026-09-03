extends RefCounted

## 求解买牌(`Draft.card_value`)**结构上**看不见的卡, 逐张带理由。
## 三类结构盲区, 每一类都是模型的已知边界, 不是这张卡的接线问题:
##   ① **时间族** —— 求解器没有时钟(docs/design/solving.md:「时间在模型里确实不存在」,
##      b=1 掉 37.8% 那条实测)。压哨/早锁类的条件在推演里永远不成立。
##   ② **前置族** —— 效果以另一张卡为条件, 推演的基准槽位里没有它时按定义为 0
##      (`tools/kit.gd::PREREQ` 是同一件事的另一半)。
##   ③ **动作空间族** —— 求解器一拍只弃「没被握住的那 ≤3 张」, 而游戏允许整手撒出 5 张。
##      ⚠ 2026-08-13 断舍离带着「一次弃 4 张」回池(真人实测最大批量就是 4)——
##      当时**求解器看不到它**:一拍只弃「没被握住的那 ≤3 张」, 4 张在动作空间之外。
##      ✅ **2026-08-14 已解决**:`best_discard` 的枚举扩到全部可见牌(S10),
##      弃 4 张进了动作空间。**「扩求解器的弃牌集是 S5 的活」这句话已经过期。**
##   ⑤ ~~**完美玩家打法族**(2026-08-13)~~ —— ❌ **2026-08-14 整类作废, 无人居住。**
##      旧主张:推演用完美玩家, 它每拍都追得到最优牌型, 于是 `same_as_prev` 恒假,
##      回响/复读**结构上**量不到。
##      ⚑ **证伪**:`best_discard` 的枚举扩到全部可见牌(S10)的当天, 两张当场被量到 ——
##      **保持牌型靠的是主动弃牌塑形**, 而窄枚举只能弃缓存那 3 张, **塑不了形**。
##      ⚠⚠ **这一类的错法值得记住**:它把「**求解器做不到**」写成了
##      「**最优玩家不会这么做**」—— 两者之间差着一整个枚举空间。
##      凡是想往这一类里加卡的, 先问:是最优策略真的不做, 还是我的求解器搜不到?
##   ④ **商店事件族**(2026-08-13 子波 3 新增)—— 成长挂在刷新/购买/换旗上,
##      而 `Draft.card_value` 的推演粒度是**拍**, 商店发生在拍与拍**之间**:
##      推演里永远没有商店事件, 计数器恒 0。要它非零就得让推演跨越商店 ——
##      那是 S5(买牌求解化)的深水区, 不是这三张卡的接线问题。
##      ⚠ 它们的覆盖由 **kit 的 `shop` 通路 + 计数器终值证物**证(零基线机械读数)。
##      ⚠⚠ 我一度在这里写「score 通路量得到」—— **那是错的**:score 通路**关商店**
##      (kit 文件头:开着商店两臂会买到不同的牌, 抽卡运气混进配对), 所以那条臂里
##      根本没有商店事件, 实测三张全部触发 0%。**引用一条纪律之前先确认它说的是什么。**
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
	# ---- 2026-08-25 对抗批四张(kit 侧各有环境/前置臂, 见 tools/kit.gd) ----
	# ⚑ ~~wrecker~~ 2026-08-27 已删:动作粒度修复(beat_discards 改动作次数 +
	# discard_batch 单批上限 8)后弃 6 进了动作空间, 推演当场量到 —— 反向锁喊的,
	# 与 kit.gd UNREACHABLE 同日同因清账。「预算类盲区」随粒度修复整类翻案,
	# 与 ⑤ 类作废是同一个教训:先问是不是求解器的枚举空间挡的。
	"fastforward": "① 时间:提前收工在推演里不成立(与速弹/惯性同因)",
	# ⚑ 2026-08-27 动作粒度的连带(粒度修复的反面):完美玩家推演弃牌不心疼钱
	# (`_play_perfect` 给 best_discard 传 κ=0, 那是「上界不建模金币」的显式选择),
	# 批上限 4→8 后它每拍弃得更多、金币贴地, 「持币 ≥6」在推演里不再成立。
	# 这不是卡断线:adaptive bot 有 κ(discard_kappa)会持币, kit score 通路照常量得到。
	# 要它回来得给完美玩家推演接金币影子价 —— κ 要扫出来不许拍, 归数值批。
	# ⚑⚑ goldenvoice **2026-08-30 又回来了** —— 收入重构(用户「获取太容易」)之后
	# 完美玩家推演里金币更紧, 「持币 ≥6」再次不成立。⚠ 它 08-29 才被删掉(加了 cap 后
	# 当场可量), **一天之内进出两次** —— 这条豁免的成立与否**取决于经济参数**,
	# 而经济参数是会动的。⇒ 不要把它当永久声明:下次经济再松, 反向锁还会喊。
	"goldenvoice": "⑥ 经济:完美玩家推演 κ=0 且收入重构后金币贴地, 「持币 ≥6」不成立(kit/真人无此限)",
	# ⚑ ~~goldenvoice(旧条目)~~ 2026-08-29 曾删(反向锁喊的, 与 wrecker 08-27 同型):
	# 给它补上 `cap: 0.5` 后求解器当场量到 —— 原来的 `mult_add: 0.1 per coins:6`
	# **无上限**, 推演里这个量随持币发散, 估不住;封顶后它成了有界可估的量。
	# ⚠ 原豁免理由(「完美玩家推演 κ=0 ⇒ 金币贴地 ⇒ 持币条件不成立」)**当时成立**,
	# 但它掩盖了真问题:同族两张(铁粉 cap 0.15 / 利息 cap 5)都有上限, 只有它和后台没有
	# —— **是漏的, 不是设计**。豁免把这个漏洞挡了下来, 正是「遮羞布」那条断言要抓的东西。
	"loadeddice": "②③ 前置+概率:没赌卡时恒 0, 且掷点只在 Beat 预掷 —— 推演里 luck_rolls 恒空",
	# ---- 2026-08-26 经济 v2 批 ----
	# ⚑ `advance`(预支)**不进这张表**(2026-08-27 反向锁抓到, 体力批顺手修):
	# 它 proof = shop —— measurable 只收 score/solver 通路, shop/coin 在循环口就被滤掉,
	# 所以它**整个不在本仪器管辖内**;列进来 = 一条永远轮不到检查的过期声明, 与上面
	# 「商店成长族一度列在这里, 已删」同型。原理由(借还在段边界不在结算链, tempo 价值
	# 由 kit 行为臂与 sim 量, 求解器上界不建模金币 —— 偏松安全, levels.md 经济 v2)照旧成立,
	# 只是归属写错了仪器, 不需要任何代码修改。
	"blindplay": "④ 环境:推演世界无盖牌(hidden 恒空), 证物只在信息脸下发生(kit 已配暗场环境)",
	# ⚑⚑ **encore / reprise 已于 2026-08-14 删除** —— 它们**不是**结构盲区, 是被
	# `best_discard` 的窄枚举挡住的。旧理由写的是「完美玩家追最优, 牌型每拍在变,
	# same_as_prev 恒假」, 而真相是:**保持牌型要靠主动弃牌塑形**, 而窄枚举只能弃
	# 缓存那 3 张 —— **塑不了形, 于是看起来像"完美玩家的本性"**。
	# 枚举扩到全部可见牌(docs/design/prior.md §5.6b)的当天, 这两张当场被量到,
	# 是**反向保护**(声明了却量到 ⇒ 报警)把它喊出来的。
	# ⚠ 教训:**第 ⑤ 类"完美玩家的本性"这个说法本身要警惕** ——
	# 它把「求解器做不到」说成了「最优玩家不会这么做」, 两者差着一整个枚举空间。
	# ⚠ 商店成长族(淘碟/收藏家/转型)**一度列在这里**, 已删 —— 它们的 proof 改成 `shop`
	# 之后整个退出了这个仪器的管辖(下面的 measurable 只收 score/solver 通路),
	# 留着就是一条**永远不会被检查的声明**。第 ④ 类的描述保留:那道边界还在,
	# 将来若有 score 通路的卡挂商店事件, 它就该重新有人住。
}

## 假想推演(买牌求解化, docs/design/solving.md 第三部分)**绝不能碰真实局**。
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
	# ⚠ **`prev_kind` 要设成一个推演里够得着的牌型**(2026-08-13 踩到)。
	# 把 `beat_budget.discards` 从 2 校准到 4 之后, 推演里每拍都能追到最优牌型 ——
	# 牌型于是**每拍都在变**, `same_as_prev` 恒假, 回响/复读双双算出 0。
	# 而它们在真实一局里活得好好的(kit:回响 +1242 触发 22%)—— 所以那不是结构盲区,
	# 是**这个单一场景太窄**。锚成对子(P(≥对子)=98%, 推演里最容易重复的牌型),
	# 让「与上一拍相同」这个条件有机会成立。
	# ⚠ 判据:场景不具代表性时, 该修的是场景, 不是往豁免表里加一条。
	run.prev_kind = Pattern.Kind.PAIR
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
	# 反向锁**两条**(同 weak_upper_bound 的反向检查)。⚠ 第二条是 2026-08-13 补的:
	# 商店成长族的 proof 从 score 改成 shop 之后, 它们整个退出了 measurable ——
	# 于是第一条锁**根本不会检查它们**, 三条过期声明就那样静默留在表里。
	# 「过期的豁免是遮羞布」防的正是这个, 而第一版的锁自己漏了这个口。
	for bid in SOLVER_BLIND:
		if measurable.has(bid):
			t.check(zeros.has(bid),
				"'%s' 已经量得到了, 把它从 SOLVER_BLIND 删掉(过期的豁免是遮羞布)" % bid)
		else:
			t.check(false,
				"'%s' 已经不在这个仪器的管辖内(proof 改了 or 卡撤了), 把它从 SOLVER_BLIND 删掉" % bid)
	_t_replay(t)


## ---- 反事实重放估值(2026-09-04)—— 效果卡在**本局已打过的拍**上重放 Settle, 不再手写臂 ----
## 一拍的历史条目:与 `RunLoop._tally` 记进 `st.hist` 的形状一致(res + 结算 ctx)。
func _hist_beat(t, cards: Array, over: Dictionary = {}) -> Dictionary:
	var res := Pattern.evaluate_best(cards)
	res["hidden_scoring"] = 0
	var ctx := {
		"prev_kind": -99, "prev_target_hit": false, "rolled_suit": -1,
		"callout_unsolved": false, "luck_rolls": [], "odds_mult": 1.0,
		"cache_rank_sum": 0, "acted_late": false, "discards": 2, "coins": 5,
		"phrase_idx": 2, "cache_cards": [], "early_finish": false,
		"seconds_left": 0.0, "acted_final": false, "early_discards": false,
		"section_idx": 1, "swaps": 0, "discard_batch_max": 2, "faces_discarded": 0,
		"swapped_scoring": 0, "section_score": 0, "section_target": 600,
		"mod": "", "first_kind": -99, "request_met": true, "patch_restored": false,
		"phrase_boosts": [],
	}
	for k in over:
		ctx[k] = over[k]
	return {"res": res, "ctx": ctx}


func _st_with(hist: Array) -> Dictionary:
	var st := RunLoop._fresh_st()
	for h in hist:
		st["n"] += 1.0
		st["hist"].append(h)
	return st


func _t_replay(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var bot := Bot.new(rng, Report.new(1, GameConfig.SECTIONS_PER_RUN))
	var pair := [t._c(10, 3), t._c(10, 2), t._c(3, 0), t._c(7, 1), t._c(13, 3)]
	var straight := [t._c(5, 3), t._c(6, 2), t._c(7, 0), t._c(8, 1), t._c(9, 3)]
	var empty: Array = [null, null, null, null]
	var only_pairs: Array = []
	var mixed: Array = []
	for i in range(24):
		only_pairs.append(_hist_beat(t, pair))
		mixed.append(_hist_beat(t, straight if i % 4 == 0 else pair))
	# ① 条件均值:全员(五张牌型 ×1.2)在「有顺子」的历史里必须比「全是对子」的历史里值钱。
	#    这正是 2026-09-04 定位到的 3 倍低估:手写臂用全局均分, 而它只在大牌上触发。
	var ev_pairs: float = bot._card_ev("fullcast", _st_with(only_pairs), empty, 12)
	var ev_mixed: float = bot._card_ev("fullcast", _st_with(mixed), empty, 12)
	t.check(ev_mixed > ev_pairs + 1.0,
		"全员:历史里有顺子时估值必须高于全是对子(%.1f vs %.1f)" % [ev_mixed, ev_pairs])
	# ② 逐位契约:重放 EV = (Σ 装/不装差值 + blend_w × 先验) / (n + blend_w)。
	var fc := Joker.by_id("fullcast")
	var sum := 0.0
	for h in mixed:
		sum += float(Settle.run(h["res"], [null, fc, null, null], h["ctx"])["score"]) \
			- float(Settle.run(h["res"], empty, h["ctx"])["score"])
	var bw := float(DB.sim()["ev"]["blend_w"])
	var want: float = (sum + bw * bot._prior_ev("fullcast")) / (24.0 + bw)
	t.check(absf(ev_mixed - want) < 1e-6,
		"重放 EV 的收缩公式逐位(got %.4f want %.4f)" % [ev_mixed, want])
	# ③ 扁平奖励不吃倍率链:灯牌(目标分百分比, 乘法链**之后**落地)装不装 Target 估值不变。
	#    手写臂曾把它乘了一遍均倍率 —— 全池对照实测整族高估 3.5 倍(evcmp 2026-09-04)。
	var twin := Joker.by_id("twin")
	var neon0: float = bot._card_ev("neonsign", _st_with(mixed), empty, 12)
	var neon1: float = bot._card_ev("neonsign", _st_with(mixed), [twin, null, null, null], 12)
	t.check(absf(neon0 - neon1) < 1e-6, "灯牌是乘法链之后的扁平奖励, 装不装 Target 估值不变")
	# ④ 乘法卡吃真实构筑:全员装在顺子 Target 旁边比空构筑值钱(条件拍上链更长)。
	var stair := Joker.by_id("stair")
	var fc_stair: float = bot._card_ev("fullcast", _st_with(mixed), [stair, null, null, null], 12)
	t.check(fc_stair > ev_mixed + 1.0, "全员装在顺子 Target 旁边必须比空构筑值钱")
	# ⑤ 纯函数:重放不许碰历史与槽位状态(与 Draft.card_value 的「推演不碰真实局」同一条契约)。
	var st5 := _st_with(mixed)
	var snap: String = JSON.stringify(st5["hist"][0]["ctx"]) + JSON.stringify(stair.state) + str(st5["n"])
	bot._card_ev("fullcast", st5, [stair, null, null, null], 12)
	t.eq(JSON.stringify(st5["hist"][0]["ctx"]) + JSON.stringify(stair.state) + str(st5["n"]), snap,
		"重放不碰历史与槽位状态")
	# ⑥ 无历史 = 先验(首店之前的估值全靠它)。
	t.check(absf(bot._card_ev("fullcast", _st_with([]), empty, 12) - bot._prior_ev("fullcast")) < 1e-6,
		"无历史时估值 = 先验")
	# ⑦ 账本:RunLoop 一局记满 24 拍历史, 每拍带结算时的 section_target(bonus_target_pct 按段算)。
	var st7 := RunLoop._fresh_st()
	var o := RunLoop.Opts.new()
	o.rng = rng
	o.deck_seed = 3
	o.player = "none"
	o.st = st7
	RunLoop.play(o, bot)
	t.eq(st7["hist"].size(), GameConfig.SECTIONS_PER_RUN * GameConfig.PHRASES_PER_SECTION,
		"RunLoop 每拍往 st.hist 记一条")
	t.check(st7["hist"].size() > 0 and int(st7["hist"][0]["ctx"].get("section_target", 0)) > 0,
		"历史条目带着结算时的 section_target")


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
