extends Probe

## 钱包探针 —— **钱卡在哪一步?**
##   godot --headless --path . --script res://tools/wallet.gd
##   WALLET_RUNS=200 WALLET_AB=40 WALLET_COHORT=adaptive:twin godot --headless ...
##
## ## 起因(2026-08-09)
##
## `tools/kit.gd` 报出经济卡 `tipjar`/`interest` **在模型里是空气**:金币臂显示钱确实
## 到手了(+9.4◆ / +108.6◆), 行为臂的商店花费却是 −0.0◆ / −2.9◆ —— **钱进了口袋,
## 一分没多花**。而金币在本作**没有终局价值**(段分清零、工资固定、局末余额一文不值),
## 理性玩家应该把能换成分的钱全换掉。基准臂局末还剩 51.8◆ 没花, 说明有东西不对。
## 后果很重:**目标分是在「经济卡贡献为 0」的前提下算出来的**。
##
## ## 只诊断, 不修
##
## 本项目最贵的一类错是「读代码下结论」(`cover` 那次我读代码断定它零效果、退役了它,
## 实测是每局 −518.1 分 ±123)。所以这一轮**不改 bot 的行为**, 只量。
##
## ## 怎么量:**给 Bot 装监听, 不抄 Bot**
##
## 商店的决策全在 `bot._draft` 里, 而它不许改。所以这里用一个 `SpyBot extends Bot`,
## **只覆盖三个方法、每个都先 `super` 再记账**:
##   · `_draft`        —— 记进店余额 / 槽位 / 出店余额 / 槽位变化(= 实际动作)
##   · `_weighted_pick` —— 记货架(它是货架的唯一来源), **调用次数 − 1 = 刷新次数**
##   · `_card_ev`      —— 记 bot 自己算出来的估值(不重算一遍公式, 避免和它漂移)
## 决策的**分类完全由观测推**(动作 + 货架价格 + 进店余额), 不复制 `_draft` 的任何判据。
##
## ⚠ 口径:
##   · 一局的循环走 `RunLoop`(骨架只此一份), 统计走 `Stat`。
##   · **不死局**(打满 24 拍不判生死), 和 `curve.gd`/`coin.gd` 同一个记账约定 ——
##     所以每局恒 8 次商店, 分类的分母是干净的。「通关段数」是在录好的 sec_scores 上
##     **重放 bot_targets 反解**出来的(curve.gd 的既有做法), 不是真判生死。
##     ⚠ 因此它对 solve_draft 略偏乐观(死后本该买不到的牌在不死局里还买得到),
##     但**两条臂同一个偏**, 配对差仍然可比。
##   · 配对实验共用种子;报标准误和 z。
##   · RNG 消耗顺序照抄 `sim.gd`:**先抽主角、后掷脸**, 主角预抽好传进 Opts
##     (RunLoop 内部也会抽, 不预抽就变成「先掷脸后抽主角」, 读数整体漂移且不报错)。


## 装了监听的 Bot。**只记账, 不改决策** —— 每个覆盖都先调 `super` 拿到原始行为。
## ⚠ 分类常量定义在**内部类里**(内部类访问外层脚本常量在 GDScript 里不保证), 外面用 `SpyBot.X`。
class SpyBot extends Bot:
	## 商店决策的互斥分类 —— **全部由观测推出来**(见文件头)。
	const CAT_FREE_TARGET := "free_target"      # 首张 Target 免费三选一(不花钱, 单列)
	const CAT_PIVOT := "pivot"                  # 换旗:买了 Target 顶掉旧的
	const CAT_BUY_EMPTY := "buy_empty"          # ④ 买了, 装进空槽
	const CAT_REPLACE := "replace"              # ④ 买了, 买新替旧
	const CAT_CANT_AFFORD := "cant_afford"      # ① 买不起(余额 < 最便宜的报价)
	const CAT_NOT_WORTH_EMPTY := "not_worth"    # ② 买得起但不值(还有空槽)
	const CAT_NOT_WORTH_FULL := "no_swap"       # ③ 满槽且不愿换
	const CAT_NO_SUPPORT := "no_support"        # 货架 3 张全是 Target(边角, 单列保互斥)

	var shops: Array = []          # 每次商店一条记录
	var _offers: Array = []        # 本次商店里每一次 _weighted_pick 的结果
	var _ev: Dictionary = {}       # id -> bot 自己算的估值(最后一次)

	func _init(rng: RandomNumberGenerator, rep: Report) -> void:
		super(rng, rep)

	func _weighted_pick(candidates: Array, count: int, target_mult: float = 1.0) -> Array:
		var out: Array = super._weighted_pick(candidates, count, target_mult)
		_offers.append(out)
		return out

	func _card_ev(id: String, st: Dictionary, slots: Array, phrases_left: int) -> float:
		var v: float = super._card_ev(id, st, slots, phrases_left)
		_ev[id] = v
		return v

	func _draft(slots: Array, cfg: Dictionary, deck: Deck, coins: int, st: Dictionary,
			phrases_left: int, section: int, faces: Dictionary = {}, cache: Array = [],
			done_phrases: int = 0, run = null) -> int:
		_offers = []
		_ev = {}
		var before: Array = slots.duplicate()
		var coins_in: int = coins
		var out: int = super._draft(slots, cfg, deck, coins, st, phrases_left, section,
			faces, cache, done_phrases, run)
		shops.append(_classify(before, slots, coins_in, out, section, done_phrases,
			phrases_left, st))
		return out

	## **纯观测**:动作看槽位变化, 买不起看最后一张货架的报价 vs 当时的余额。
	## 这里不复制 `_draft` 的任何判据 —— 复制就会漂移。
	func _classify(before: Array, after: Array, coins_in: int, coins_out: int,
			section: int, done: int, phrases_left: int, st: Dictionary) -> Dictionary:
		# **显示用重构** —— 金币的影子价 `lam`, 公式抄自 `bot.gd:208-210`。
		# ⚠ 只进报表, **不参与本探针的任何判定**(分类全部来自观测)。抄它是因为
		#   它在 `_draft` 里是个局部变量, 拦不到 —— 而「买一张牌要多少分才划算」
		#   正是这次诊断要回答的东西。bot.gd 改了公式这一行会静默过时。
		var bw: float = float(EV["blend_w"])
		var score_mean: float = (float(st["score"]) + float(EV["score_prior"]) * bw) \
			/ (maxf(1.0, float(st["n"])) + bw)
		var lam: float = float(EV["coin_score_ratio"]) * score_mean
		var rerolls: int = maxi(0, _offers.size() - 1)
		var empty: int = 0
		for k in range(1, before.size()):
			if before[k] == null:
				empty += 1
		var cat := ""
		if before[0] == null:
			cat = CAT_FREE_TARGET
		elif after[0] != before[0]:
			cat = CAT_PIVOT
		else:
			var changed := -1
			for k in range(1, before.size()):
				if after[k] != before[k]:
					changed = k
			if changed >= 0:
				cat = CAT_BUY_EMPTY if before[changed] == null else CAT_REPLACE
		var shelf: Array = []
		var cheapest := -1
		if not _offers.is_empty():
			# 走人的决定是在**最后一张**货架上做的(刷新过就不是第一张)。
			for j in _offers[_offers.size() - 1]:
				if j.kind == "target":
					continue
				var price: int = Economy.joker_price(j)
				shelf.append({"id": String(j.id), "price": price,
					"ev": float(_ev.get(String(j.id), NAN))})
				if cheapest < 0 or price < cheapest:
					cheapest = price
		if cat == "":
			# 没买 —— 三选一。预算 = 进店余额 − 刷新花掉的, 满槽时还能加上折半回收。
			var budget: int = coins_in - rerolls * Economy.reroll_cost(0)
			if empty == 0:
				budget += Economy.sell_value(before[_weakest_slot(before)])
			if shelf.is_empty():
				cat = CAT_NO_SUPPORT
			elif cheapest > budget:
				cat = CAT_CANT_AFFORD
			elif empty > 0:
				cat = CAT_NOT_WORTH_EMPTY
			else:
				cat = CAT_NOT_WORTH_FULL
		# 替换判据的两个数:货架上最好的 vs 槽里最弱的(bot 自己算的, 不是我重算的)。
		# ⚠ 只有规则 bot(solve_draft=off)会把它们全过一遍 `_card_ev`;
		#   solve 模式下货架用的是 `Draft.card_value`(静态函数, 拦不到) —— 那时是 NAN。
		var best_off := -INF
		for c in shelf:
			if not is_nan(float(c["ev"])):
				best_off = maxf(best_off, float(c["ev"]))
		var weak_own := INF
		for k in range(1, before.size()):
			if before[k] == null:
				continue
			var ov: float = float(_ev.get(String(before[k].id), NAN))
			if not is_nan(ov):
				weak_own = minf(weak_own, ov)
		return {"best_off": best_off, "weak_own": weak_own, "lam": lam,
			"cat": cat, "section": section, "done": done,
			"mid": done < GameConfig.PHRASES_PER_SECTION,
			"coins_in": coins_in, "coins_out": coins_out, "empty": empty,
			"rerolls": rerolls, "cheapest": cheapest, "shelf": shelf,
			"left": phrases_left}


const CATS := [SpyBot.CAT_BUY_EMPTY, SpyBot.CAT_REPLACE, SpyBot.CAT_PIVOT,
	SpyBot.CAT_CANT_AFFORD, SpyBot.CAT_NOT_WORTH_EMPTY, SpyBot.CAT_NOT_WORTH_FULL,
	SpyBot.CAT_NO_SUPPORT, SpyBot.CAT_FREE_TARGET]

const CAT_NAME := {
	SpyBot.CAT_BUY_EMPTY: "④ 买了(装空槽)",
	SpyBot.CAT_REPLACE: "④ 买了(买新替旧)",
	SpyBot.CAT_PIVOT: "④ 买了(Target 换旗)",
	SpyBot.CAT_CANT_AFFORD: "① 买不起",
	SpyBot.CAT_NOT_WORTH_EMPTY: "② 买得起但不值(有空槽)",
	SpyBot.CAT_NOT_WORTH_FULL: "③ 满槽且不愿换",
	SpyBot.CAT_NO_SUPPORT: "· 货架无 support",
	SpyBot.CAT_FREE_TARGET: "· 首张 Target 免费",
}

var _rng := RandomNumberGenerator.new()
var TARGETS: Array = DB.sim().get("bot_targets", GameConfig.SECTION_TARGETS)


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var cfg := _cohort(env_str("WALLET_COHORT", ""))
	var n := env_int("WALLET_RUNS", 200)
	var nab := env_int("WALLET_AB", 40)
	print("\n=== 钱包探针 · 商店决策分解 ===")
	print("  队列 %s   不死局(24 拍, 恒 8 次商店)   起始 %d◆, 段末工资 %d◆"
		% [cfg.get("name", "?"), GameConfig.STARTING_COINS, GameConfig.SECTION_CLEAR_REWARD])
	print("  价目表 %s  (mirror %s)  刷新 %d◆ 起"
		% [GameConfig.JOKER_PRICES, GameConfig.JOKER_PRICE_OVERRIDES,
			Economy.reroll_cost(0)])

	_identity(cfg, 20)

	# ---------- Q1 / Q2:基准臂 ----------
	var base := _arm(cfg, false, n, 620000)
	_report_arm("Q1/Q2 基准臂(solve_draft = off, %d 局)" % n, base)

	# ---------- Q3:solve_draft 配对 A/B ----------
	print("\n\n=== Q3 · solve_draft 关 vs 开(配对, 同种子, %d 局/臂) ===" % nab)
	var a := _arm(cfg, false, nab, 730000)
	var b := _arm(cfg, true, nab, 730000)
	_report_ab(a, b)
	_report_cats("  ---- 关:分类占比 ----", a["shops"])
	_report_cats("  ---- 开:分类占比 ----", b["shops"])

	# ---------- Q4:供给侧 ----------
	_report_supply("Q4 供给侧(基准臂)", base)

	print("\n[wallet] %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)


## **自检:监听器不许改变行为**。
## 整份诊断的效力全压在「SpyBot 只记账」这一句上, 而覆盖方法是最容易悄悄改掉
## RNG 消耗顺序的做法(本项目的老坑)。所以每次跑都先用原厂 `Bot` 和 `SpyBot`
## 各打同样的 N 局, **逐局分数必须相等**。不等就直接以 96 退出, 别看后面的数。
func _identity(cfg: Dictionary, n: int) -> void:
	var plain := _arm(cfg, false, n, 555000, false)
	var spied := _arm(cfg, false, n, 555000, true)
	var bad := 0
	for i in range(n):
		if float(plain["score"][i]) != float(spied["score"][i]):
			bad += 1
	if bad > 0:
		printerr("[wallet] ❌ 监听器改变了行为:%d/%d 局分数不同 —— 后面的数全部不可信" % [bad, n])
		quit(96)
		return
	print("  ✅ 自检:原厂 Bot 与 SpyBot 逐局同分 (%d 局) —— 监听器只记账" % n)


## 默认取第一条真实人群队列(和 `coin.gd` 同一条规则), 可用 WALLET_COHORT 指名。
func _cohort(want: String) -> Dictionary:
	var out := {}
	for c in DB.sim()["cohorts"]:
		if want != "":
			if String(c.get("name", "")) == want:
				return c
			continue
		if String(c.get("bot", "")) == "random" or bool(c.get("no_jokers", false)):
			continue
		if out.is_empty():
			out = c
	return out


## 打 N 局不死局。返回每局的 {spend, balance, score, rerolls, reroll_coins, cleared}
## 以及所有商店记录的平铺数组。
func _arm(cfg: Dictionary, solve: bool, n: int, seed0: int, spy: bool = true) -> Dictionary:
	var rep := Report.new(n, GameConfig.SECTIONS_PER_RUN)
	rep.reset()
	# `spy=false` 只用于自检:换成原厂 `Bot`, 两边的分数必须逐局相等。
	var bot: Bot = SpyBot.new(_rng, rep) if spy else Bot.new(_rng, rep)
	var pcfg := cfg.duplicate()
	pcfg["bot"] = "adaptive"
	pcfg["solve_draft"] = solve
	var out := {"spend": [], "balance": [], "score": [], "rerolls": [],
		"reroll_coins": [], "cleared": [], "shops": [], "full_at": [], "buys_after_full": []}
	for r in range(n):
		# ⚠ 配对的全部意义在这一行:两条臂的第 r 局用完全相同的种子。
		_rng.seed = seed0 + r
		# ⚠ RNG 消耗顺序照抄 sim.gd:先抽主角, 后掷脸。
		var character: Character = Character.roster()[_rng.randi_range(0, 7)]
		var faces := {}
		for w in GameConfig.WALL_SECTIONS:
			faces[w] = SectionMod.roll(w, _rng)
		var st := {"n": 0.0, "disc": 0.0, "rep": 0.0, "late": 0.0, "early": 0.0,
			"zerod": 0.0, "faces": 0.0, "chord": 0.0, "tgt": 0.0,
			"score": 0.0, "mult": 0.0, "kinds": {}}
		var o := RunLoop.Opts.new()
		o.rng = _rng
		o.deck_seed = r * 7 + 1
		o.character = character
		o.faces = faces
		o.player = "adaptive"
		o.cfg = pcfg
		o.shop = true
		o.mortal = false
		o.st = st
		var mark: int = (bot as SpyBot).shops.size() if spy else 0
		var res := RunLoop.play(o, bot)
		var mine: Array = (bot as SpyBot).shops.slice(mark) if spy else []
		var spend := 0
		var rr := 0
		var rc := 0
		var full_at := -1
		var buys_after := 0
		for i in range(mine.size()):
			var s: Dictionary = mine[i]
			spend += int(s["coins_in"]) - int(s["coins_out"])
			rr += int(s["rerolls"])
			rc += int(s["rerolls"]) * Economy.reroll_cost(0)
			if full_at < 0 and int(s["empty"]) == 0:
				full_at = i
			if full_at >= 0 and i > full_at \
					and String(s["cat"]) in [SpyBot.CAT_REPLACE, SpyBot.CAT_PIVOT]:
				buys_after += 1
		out["spend"].append(float(spend))
		out["balance"].append(float(res["coins"]))
		out["score"].append(float(res["total"]))
		out["rerolls"].append(float(rr))
		out["reroll_coins"].append(float(rc))
		out["cleared"].append(float(_cleared(res["sec_scores"], faces)))
		out["full_at"].append(float(full_at))
		out["buys_after_full"].append(float(buys_after))
		out["shops"].append_array(mine)
	return out


## 在录好的段分上**重放 bot_targets** 反解通关段数(curve.gd 的既有做法 ——
## 不死局才能这么做, 真判生死会把后续段的数据整个截掉)。
## ⚠ 判生死只有一份实现:`Run.section_target_for`。
func _cleared(sec_scores: Array, faces: Dictionary) -> int:
	var k := 0
	for i in range(sec_scores.size()):
		var tgt := Run.section_target_for(TARGETS, i, String(faces.get(i, "")))
		if float(sec_scores[i]) < float(tgt):
			break
		k += 1
	return k


func _report_arm(title: String, arm: Dictionary) -> void:
	print("\n\n=== %s ===" % title)
	var shops: Array = arm["shops"]
	print("  每局:商店花费 %.1f◆   局末余额 %.1f◆   总分 %.0f   通关 %.2f 段"
		% [Stat.mean(arm["spend"]), Stat.mean(arm["balance"]),
			Stat.mean(arm["score"]), Stat.mean(arm["cleared"])])
	print("  ⚠ 局末余额 = 一分钱终局价值都没有的那笔钱")
	var lams: Array = []
	for s in shops:
		lams.append(float(s["lam"]))
	var lm := Stat.mean(lams)
	print("  ⚠ 金币有**两把互相矛盾的尺子**:规则 bot 买牌时把 1◆ 记成 %.0f 分"
		% lm)
	print("     (lam = ev.coin_score_ratio × 本局均分), 而求解器 `Draft.COIN_TO_SCORE`"
		+ " 按 coin.gd 实测取 %.1f 分/◆ —— 差 %.0f 倍。"
		% [Draft.COIN_TO_SCORE, lm / maxf(0.001, Draft.COIN_TO_SCORE)])
	print("\n  Q2 刷新:每局 %.2f 次, 花 %.1f◆  (刷新是金币的另一个出口)"
		% [Stat.mean(arm["rerolls"]), Stat.mean(arm["reroll_coins"])])
	_report_cats("\n  Q1 商店决策分类(每局 %.1f 次商店)"
		% (float(shops.size()) / maxf(1.0, float(arm["spend"].size()))), shops)
	_report_by_index(shops, arm["spend"].size())


func _report_cats(title: String, shops: Array) -> void:
	print(title)
	print("    %-26s %6s %6s %6s | %s" % ["类别", "合计", "段中", "段末", "发生时平均余额◆"])
	for cat in CATS:
		var all: Array = []
		var mid: Array = []
		var end: Array = []
		for s in shops:
			if String(s["cat"]) != cat:
				continue
			all.append(float(s["coins_in"]))
			if bool(s["mid"]):
				mid.append(1.0)
			else:
				end.append(1.0)
		if all.is_empty():
			continue
		print("    %-24s %6.1f%% %5.1f%% %5.1f%% | %.1f◆" % [
			CAT_NAME[cat],
			100.0 * float(all.size()) / maxf(1.0, float(shops.size())),
			100.0 * float(mid.size()) / maxf(1.0, float(shops.size())),
			100.0 * float(end.size()) / maxf(1.0, float(shops.size())),
			Stat.mean(all)])
	# 「买不起」到底差多少钱 —— 差 1◆ 和差 5◆ 是两个结论
	var gap: Array = []
	for s in shops:
		if String(s["cat"]) == SpyBot.CAT_CANT_AFFORD and int(s["cheapest"]) > 0:
			gap.append(float(int(s["cheapest"]) - int(s["coins_in"])))
	if not gap.is_empty():
		print("    · 买不起时的缺口 %.1f◆ (最便宜的报价 − 进店余额)" % Stat.mean(gap))
	# 「不值」的时候, bot 给货架的估值有多低
	var zero := 0
	var seen := 0
	for s in shops:
		if not (String(s["cat"]) in [SpyBot.CAT_NOT_WORTH_EMPTY, SpyBot.CAT_NOT_WORTH_FULL]):
			continue
		for c in s["shelf"]:
			var v: float = float(c["ev"])
			if is_nan(v):
				continue
			seen += 1
			if absf(v) < 1.0e-9:
				zero += 1
	if seen > 0:
		print("    · 「不值」那些货架上, bot 估值 = 0 的报价占 %.1f%% (%d/%d)"
			% [100.0 * float(zero) / float(seen), zero, seen])
	# ③ 的判据到底差多少:货架最好的 ev vs 槽里最弱的 ev
	var off: Array = []
	var own: Array = []
	var lose := 0
	for s in shops:
		if String(s["cat"]) != SpyBot.CAT_NOT_WORTH_FULL:
			continue
		var a: float = float(s["best_off"])
		var b: float = float(s["weak_own"])
		if is_inf(a) or is_inf(b):
			continue
		off.append(a)
		own.append(b)
		if a <= b:
			lose += 1
	if not off.is_empty():
		print("    · ③ 的判据:货架最好 ev %.1f  vs  槽里最弱 ev %.1f;新卡打不过旧卡的占 %.1f%%"
			% [Stat.mean(off), Stat.mean(own), 100.0 * float(lose) / float(off.size())])


## 按第几次商店拆开 —— 钱是**在哪一段**开始堆起来的。
## `horizon` = bot 给未来收益的乘数 `min(剩余拍数, 20)`;它逼近 0 时,
## 任何买牌的收益项都被压平, 而**成本项(金币影子价)不跟着降**。
func _report_by_index(shops: Array, runs: int) -> void:
	print("\n  按第几次商店拆(0-based;段中/段末交替)")
	print("  门槛 = 一张 4◆ 普通卡要多少「每拍 ev」才划算 = lam×4 / 剩余拍;")
	print("  lam = bot 心里 1 金币值多少分(= coin_score_ratio × 本局均分, **不随剩余拍数衰减**)")
	print("  ③ 那两列:换一张 4◆ 换 4◆ 需要的 ev 差 = lam×(4−2)/剩余拍, 对比实际的 ev 差。")
	print("    %3s %4s %8s %6s %7s %7s %9s %8s %8s %7s %9s" % ["#", "段", "进店余额◆",
		"剩余拍", "lam分/◆", "门槛ev", "货架最好ev", "③实际差", "③门槛差", "买了", "不愿换/不值"])
	for i in range(2 * GameConfig.SECTIONS_PER_RUN):
		var coins: Array = []
		var left: Array = []
		var lams: Array = []
		var offs: Array = []
		var gaps: Array = []      # ③ 里「货架最好 − 槽里最弱」的实际 ev 差
		var buy := 0
		var no := 0
		var tot := 0
		for k in range(runs):
			var idx: int = k * 2 * GameConfig.SECTIONS_PER_RUN + i
			if idx >= shops.size():
				continue
			var s: Dictionary = shops[idx]
			tot += 1
			coins.append(float(s["coins_in"]))
			left.append(float(s["left"]))
			lams.append(float(s["lam"]))
			if not is_inf(float(s["best_off"])):
				offs.append(float(s["best_off"]))
			var c := String(s["cat"])
			if c == SpyBot.CAT_NOT_WORTH_FULL and not is_inf(float(s["best_off"])) \
					and not is_inf(float(s["weak_own"])):
				gaps.append(float(s["best_off"]) - float(s["weak_own"]))
			if c in [SpyBot.CAT_BUY_EMPTY, SpyBot.CAT_REPLACE, SpyBot.CAT_PIVOT]:
				buy += 1
			elif c in [SpyBot.CAT_NOT_WORTH_EMPTY, SpyBot.CAT_NOT_WORTH_FULL,
					SpyBot.CAT_CANT_AFFORD]:
				no += 1
		if tot == 0:
			continue
		var lm := Stat.mean(lams)
		var lf := Stat.mean(left)
		print("    %3d %4s %8.1f %6.0f %7.1f %7s %9.1f %8s %8s %6.1f%% %8.1f%%" % [i,
			"中" if bool(shops[i]["mid"]) else "末",
			Stat.mean(coins), lf, lm,
			("∞" if lf <= 0.0 else "%.0f" % (lm * 4.0 / lf)),
			Stat.mean(offs),
			("-" if gaps.is_empty() else "%.0f" % Stat.mean(gaps)),
			("∞" if lf <= 0.0 else "%.0f" % (lm * 2.0 / lf)),
			100.0 * float(buy) / float(tot), 100.0 * float(no) / float(tot)])


func _report_ab(a: Dictionary, b: Dictionary) -> void:
	print("    %-14s %10s %10s %10s %9s %7s" % ["指标", "关", "开", "差(开−关)", "±se", "z"])
	for key in [["spend", "商店花费◆"], ["balance", "局末余额◆"], ["score", "总分"],
			["cleared", "通关段数"], ["rerolls", "刷新次数"]]:
		var p := Stat.paired(a[key[0]], b[key[0]])
		var z: float = float(p["d"]) / maxf(1.0e-9, float(p["se"]))
		print("    %-12s %10.1f %10.1f %10.2f %9.2f %7.2f %s" % [
			key[1], Stat.mean(a[key[0]]), Stat.mean(b[key[0]]),
			p["d"], p["se"], z, "显著" if absf(z) > 2.0 else "不显著"])


func _report_supply(title: String, arm: Dictionary) -> void:
	print("\n\n=== %s ===" % title)
	var fa: Array = []
	var never := 0
	for v in arm["full_at"]:
		if float(v) < 0.0:
			never += 1
		else:
			fa.append(v)
	print("  满槽(4 槽全满)第一次发生在第 %.2f 次商店(0-based, 共 8 次);"
		% Stat.mean(fa))
	print("  %d/%d 局全程没满过槽 (%.1f%%)"
		% [never, arm["full_at"].size(),
			100.0 * float(never) / maxf(1.0, float(arm["full_at"].size()))])
	print("  满槽之后还买过 %.2f 次(买新替旧 + 换旗)" % Stat.mean(arm["buys_after_full"]))
	# 满槽之后那些商店都干了什么
	var after: Array = []
	for s in arm["shops"]:
		if int(s["empty"]) == 0:
			after.append(s)
	_report_cats("\n  满槽时的商店分类(%d 次)" % after.size(), after)
