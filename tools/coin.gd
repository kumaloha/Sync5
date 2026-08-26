extends Probe

## 金币影子价探针 —— **1 金币值多少分?**
##   godot --headless --path . --script res://tools/coin.gd
##
## 起因(2026-08-07):我断言「入场费(cover)对完美玩家零效果」并据此把它退役,
## 依据是 `tools/bot.gd:422` 给求解器传 `coins=999, coin_value=0.0`。
## **那个推断是错的** —— `coins=999` 只关掉了**单拍内**「弃牌要花钱」这条约束,
## 而弃牌 2026-08-06 起本来就免费(`economy.json discard_cost=0`), 那条约束早就是空的。
## 扣掉的钱照样顺着 `coins` 流到 `bot._draft`, 变成买不起的小丑牌, 再变成后面几拍的分。
## **金币的通路一直在, 只是不在求解器里, 而我只看了求解器。**
##
## 教训写在这里, 因为它是这个项目栽过第三次的同一个坑的**反面**:前两次
## (赶场、真·入场费误判)是「规则没进模型」, 这次是「规则进了模型而我没找到」。
## **两种错的解法是同一个:别读代码下结论, 跑一次配对实验。**
##
## 口径(全部按项目铁律):
##   · **配对** —— 每条臂用同一批种子, 逐局作差再统计。非配对时局间方差会淹没效应
##     (λ 扫描那次 n=40 只有 z=1.28, 配对后 z=3.36)。
##   · 报**标准误和 z**, 没有标准误的差值等于没有结论。
##   · 不死局(打满 24 拍不判生死), 和 curve.gd 同一个记账约定, 所以量的是**分数**
##     而不是通关率 —— 分数连续、方差小得多。

const N_RUNS := 300

## 三条臂, 全部共用种子。`per_phrase` = 每拍金币增减。
## toll  = cover 的效果(每拍 −1)
## rich  = 它的镜像(每拍 +1), 用来取斜率的另一侧 —— 只测一侧会把非线性当成噪声
## 后两条臂是**机制的 A/B**:关掉商店再扣同样的钱。如果效应消失, 通路就确认是
## 「金币 → 商店 → 小丑牌 → 后续得分」; 如果还在, 说明另有通路(比如吃金币的小丑牌),
## 那定价就不能只按商店算。**只报效应不验通路, 等于知道疼不知道哪疼。**
const ARMS := [
	{"name": "base", "per_phrase": 0, "shop": true},
	{"name": "toll(cover −1/拍)", "per_phrase": -1, "shop": true},
	{"name": "rich(+1/拍)", "per_phrase": 1, "shop": true},
	{"name": "base·无商店", "per_phrase": 0, "shop": false},
	{"name": "toll·无商店", "per_phrase": -1, "shop": false},
]

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var cohorts: Array = DB.sim()["cohorts"]
	var cfg := {}
	for c in cohorts:
		if String(c.get("bot", "")) == "random" or bool(c.get("no_jokers", false)):
			continue
		cfg = c        # 第一条真实人群队列就够 —— 这里量的是金币, 不是流派
		break

	print("\n=== 金币影子价 κ · 配对实验 (%d 局/臂, 队列 %s) ===" % [N_RUNS, cfg.get("name", "?")])
	print("  问题:每拍 ±1 金币, 一局总分差多少?  κ = Δ分 / Δ金币")

	var results := {}
	for arm in ARMS:
		results[arm["name"]] = _play(cfg, int(arm["per_phrase"]), bool(arm["shop"]))

	var base: Array = results["base"]["score"]
	var base_coins: Array = results["base"]["coins"]
	print("\n  基准总分 %.0f, 一局总收入 %.1f◆" % [Stat.mean(base), Stat.mean(base_coins)])
	print("  无商店基准总分 %.0f  (差额 = 整个构筑值多少分)"
		% Stat.mean(results["base·无商店"]["score"]))

	for arm in ARMS:
		var nm: String = arm["name"]
		if not String(nm).begins_with("toll") and not String(nm).begins_with("rich"):
			continue
		var ref: Array = base if bool(arm["shop"]) else results["base·无商店"]["score"]
		var ref_c: Array = base_coins if bool(arm["shop"]) else results["base·无商店"]["coins"]
		var s: Array = results[nm]["score"]
		var c: Array = results[nm]["coins"]
		var ds := Stat.paired(ref, s)          # {d, se}
		var dc := Stat.paired(ref_c, c)
		var z: float = ds["d"] / maxf(0.001, ds["se"])
		print("\n  ---- %s ----" % nm)
		print("    总分   %+.1f  ±%.1f   z = %+.2f   %s"
			% [ds["d"], ds["se"], z, "显著" if absf(z) > 2.0 else "**不显著**"])
		print("    金币   %+.1f◆" % dc["d"])
		if absf(dc["d"]) > 0.5:
			print("    ⭐ κ = %.1f 分/金币" % (ds["d"] / dc["d"]))

	print("\n  判据:")
	print("    · toll 那条**必须显著为负**。不为负 = 金币真的没有通路,")
	print("      那 cover 该退役, 而且整个经济系统需要重新审视。")
	print("    · κ 是把「脸扣了多少钱」换算成难度的系数, 定价时直接用,")
	print("      **不要**把它传进 Solver 的 coin_value —— 弃牌免费后那个参数")
	print("      的语义(弃 d 张花 d 金币)已经失效, 传非零值会让求解器少弃牌。")
	print("\n[coin] %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)


## 打 N 局不死局, 返回 {score: 每局总分, coins: 每局总收入}。
##
## ⚠ 2026-08-08 迁到 `RunLoop`(一局的骨架只此一份)。**st 的记账口径必须原样保留**:
## 原实现只手动记过 `st["n"]`(score/mult/kinds 永远是 0), `bot._draft` 靠这个"从不更新"
## 的既有状态让买牌算法几乎只信先验 —— 这不是遗漏, 是这份探针一直以来的既有行为,
## 换成 `RunLoop._tally` 的默认全记会让抽卡决策整个跑偏。所以两个 tally 开关都关掉。
func _play(cfg: Dictionary, per_phrase: int, shop: bool) -> Dictionary:
	var scores: Array = []
	var incomes: Array = []
	var rep := Report.new(N_RUNS, GameConfig.SECTIONS_PER_RUN)
	rep.reset()
	var bot := Bot.new(_rng, rep)
	var pcfg := cfg.duplicate()
	pcfg["bot"] = "adaptive"
	for r in range(N_RUNS):
		# ⚠ 配对的全部意义在这一行:每条臂的第 r 局用完全相同的种子。
		_rng.seed = 620000 + r
		var st := {"n": 0.0, "disc": 0.0, "rep": 0.0, "late": 0.0, "early": 0.0,
			"zerod": 0.0, "faces": 0.0, "chord": 0.0, "tgt": 0.0,
			"score": 0.0, "mult": 0.0, "kinds": {}}
		var income := {"v": 0}      # 闭包要累加, 装进 Dictionary(int 按值捕获)
		var o := RunLoop.Opts.new()
		o.rng = _rng
		o.deck_seed = r * 17 + 5
		o.player = "adaptive"
		o.cfg = pcfg
		o.shop = shop
		o.mortal = false
		o.st = st
		o.tally_score = false
		o.tally_mult_kinds = false
		o.on_begin = func(_run: Run, p: Phrase) -> void:
			if per_phrase < 0:
				p.coins = maxi(0, p.coins + per_phrase)
			elif per_phrase > 0:
				p.coins += per_phrase
				income["v"] += per_phrase
		o.on_beat = func(_run: Run, _p: Phrase, outcome: Dictionary, _ctx: Dictionary) -> void:
			income["v"] += int(outcome["coins"])
		o.on_section = func(_run: Run, _section: int, _sec_score: int, _coins: int) -> void:
			income["v"] += GameConfig.SECTION_CLEAR_REWARD
		var res := RunLoop.play(o, bot)
		scores.append(res["total"])
		incomes.append(float(income["v"]))
	return {"score": scores, "coins": incomes}
