extends Probe

## 金币影子价衰减 `sim.json ev.coin_decay` 的扫描探针。
##   godot --headless --path . --script res://tools/decay.gd
##   DECAY_RUNS=300 DECAY_COHORT=adaptive:twin godot --headless ...
##
## ## 扫什么
##
## `bot.gd` 的 `lam` = 「bot 心里一枚金币值多少分」。旧算法
## `lam = coin_cost_ratio × 本局均分` **随本局均分上涨、不随剩余机会衰减**,
## 而收益边是 `ev × horizon`, 随 `phrases_left` 收缩 —— 两边同时朝「别买」走,
## 后半程购买完全停止(`tools/wallet.gd` 实测:满槽后整局只再买 0.27 次,
## 78% 不愿换, 局末余额 34.7◆ 一分终局价值没有)。
##
## 新算法给它一个衰减因子:`lam ×= (horizon / cap)^coin_decay`。
##   · `coin_decay = 0` —— `pow(x, 0) == 1`, **精确复现旧行为**(默认值)
##   · `coin_decay = 1` —— lam 严格正比于 horizon, 此时 horizon 从买/不买的
##     判据里整个约掉(`ev·h > lam₀·(h/cap)·price` ⇔ `ev/price > lam₀/cap`)
##   · 更大 —— 一出满 horizon 就几乎归零
## `coin_decay > 0` 时 horizon → 0 ⇒ lam → 0, 这就是「剩余购买机会趋零时
## 金币必须一文不值」。
##
## ## 口径(和 `tools/wallet.gd` 完全一致, 不另立一套)
##
##   · 一局的循环走 `RunLoop`, 统计走 `Stat`, 商店的观测复用 wallet 的 `SpyBot`
##     (**只记账不改决策**, 那边每次跑都有逐局同分自检)。
##   · **不死局**打满 24 拍, 所以每局恒 8 次商店, 分类的分母是干净的;
##     「通关段数」在录好的 sec_scores 上重放 `bot_targets` 反解(curve.gd 的既有做法)。
##   · ⚠ **目标分是这次实验的固定量**, 一个字都没动。
##   · **配对 + 公共随机数**:每条臂的第 r 局用同一个 `_rng.seed` 和同一个
##     `deck_seed`(牌堆自带 RNG, 所以发牌几乎完全对齐)。独立采样会让噪声
##     吃掉真实差异 —— 本项目栽过多次。
##   · 每条臂都和 **decay=0 那条(= 当前行为)** 配对比, 报 ±se 与 z。
##
## ⚠ **参数是在 Bot 实例上换的, 不在生产代码里加开关**:`Bot.EV` 是个普通成员,
## 探针 duplicate 一份再改那一个键。生产侧只有 `ev.coin_decay` 一个数, 没有第二套机制。

const Wallet := preload("res://tools/wallet.gd")

## 扫描点。必须覆盖「完全不衰减(= 当前行为)」到「几乎立刻归零」两端。
## horizon 在 8 次商店上依次是 20/18/15/12/9/6/3/0(第一次商店被 cap 压到 20,
## 所以**任何 decay 下首店都不变** —— 这让参数单调可读)。
const POINTS := [0.0, 0.25, 0.5, 1.0, 1.5, 2.0, 4.0, 8.0]

var _rng := RandomNumberGenerator.new()
var TARGETS: Array = DB.sim().get("bot_targets", GameConfig.SECTION_TARGETS)


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var cfg := _cohort(env_str("DECAY_COHORT", ""))
	var n := env_int("DECAY_RUNS", 300)
	var seed0 := env_int("DECAY_SEED", 810000)
	print("\n=== coin_decay 扫描 · 金币影子价的衰减 ===")
	print("  队列 %s   不死局(24 拍, 恒 8 次商店)   %d 局/点, 配对同种子(seed0=%d)"
		% [cfg.get("name", "?"), n, seed0])
	print("  lam = coin_cost_ratio × 本局均分 × (horizon/%.0f)^coin_decay"
		% Bot.DRAFT_HORIZON)
	print("  ⚠ 目标分 = %s(sim.json bot_targets, **本次实验的固定量, 未改**)" % [TARGETS])

	var arms: Array = []
	for d in POINTS:
		arms.append(_arm(cfg, float(d), n, seed0))
		print("  · decay=%.2f 跑完" % float(d))

	_report(arms)
	print("\n[decay] %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)


## 默认取第一条真实人群队列(和 `wallet.gd`/`coin.gd` 同一条规则)。
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


func _arm(cfg: Dictionary, decay: float, n: int, seed0: int) -> Dictionary:
	var rep := Report.new(n, GameConfig.SECTIONS_PER_RUN)
	rep.reset()
	var bot: Bot = Wallet.SpyBot.new(_rng, rep)
	# ⚠ 只换这一个键, 且换在**实例**上 —— `SIM["ev"]` 是 DB 的缓存, 直接改会污染全局。
	bot.EV = bot.EV.duplicate()
	bot.EV["coin_decay"] = decay
	var pcfg := cfg.duplicate()
	pcfg["bot"] = "adaptive"
	var out := {"decay": decay, "spend": [], "balance": [], "score": [],
		"cleared": [], "buys_after_full": [], "noswap": [], "full_shops": [],
		"drafted": rep.support_drafted}
	for r in range(n):
		# ⚠ 配对的全部意义在这一行:每条臂的第 r 局用完全相同的种子。
		_rng.seed = seed0 + r
		# ⚑ 一局四张脸走 SectionMod.roll_run 这一份(2026-08-14 收口, 原来 7 份)——
		# 保证「一局之内不偶然重复」。RNG 消耗与旧代码逐次相同。
		var faces := SectionMod.roll_run(_rng)
		var o := RunLoop.Opts.new()
		o.rng = _rng
		o.deck_seed = r * 7 + 1
		o.faces = faces
		o.player = "adaptive"
		o.cfg = pcfg
		o.shop = true
		o.mortal = false
		o.st = {"n": 0.0, "disc": 0.0, "rep": 0.0, "late": 0.0, "early": 0.0,
			"zerod": 0.0, "faces": 0.0, "chord": 0.0, "tgt": 0.0,
			"score": 0.0, "mult": 0.0, "kinds": {}}
		var mark: int = bot.shops.size()
		var res := RunLoop.play(o, bot)
		var mine: Array = bot.shops.slice(mark)
		var spend := 0
		var full_at := -1
		var buys_after := 0
		var full_n := 0
		var noswap := 0
		for i in range(mine.size()):
			var s: Dictionary = mine[i]
			spend += int(s["coins_in"]) - int(s["coins_out"])
			if int(s["empty"]) == 0:
				full_n += 1
				if String(s["cat"]) == Wallet.SpyBot.CAT_NOT_WORTH_FULL:
					noswap += 1
			if full_at < 0 and int(s["empty"]) == 0:
				full_at = i
			if full_at >= 0 and i > full_at \
					and String(s["cat"]) in [Wallet.SpyBot.CAT_REPLACE, Wallet.SpyBot.CAT_PIVOT]:
				buys_after += 1
		out["spend"].append(float(spend))
		out["balance"].append(float(res["coins"]))
		out["score"].append(float(res["total"]))
		out["cleared"].append(float(_cleared(res["sec_scores"], faces)))
		out["buys_after_full"].append(float(buys_after))
		out["noswap"].append(float(noswap))
		out["full_shops"].append(float(full_n))
	return out


## 在录好的段分上重放 `bot_targets` 反解通关段数(curve.gd 的既有做法)。
## ⚠ 判生死只有一份实现:`Run.section_target_for`。
func _cleared(sec_scores: Array, faces: Dictionary) -> int:
	var k := 0
	for i in range(sec_scores.size()):
		var tgt := Run.section_target_for(TARGETS, i, String(faces.get(i, "")))
		if float(sec_scores[i]) < float(tgt):
			break
		k += 1
	return k


func _report(arms: Array) -> void:
	var base: Dictionary = arms[0]
	print("\n\n=== 主目标(每行 vs decay=0 配对, ±se / z) ===")
	print("  %8s | %10s %9s %8s %7s | %9s %9s %8s %7s" % ["decay",
		"总分", "Δ vs 0", "±se", "z", "通关段数", "Δ vs 0", "±se", "z"])
	for a in arms:
		var ps := Stat.paired(base["score"], a["score"])
		var pc := Stat.paired(base["cleared"], a["cleared"])
		print("  %8.2f | %10.1f %9.1f %8.1f %7.2f | %9.3f %9.3f %8.3f %7.2f" % [
			float(a["decay"]),
			Stat.mean(a["score"]), float(ps["d"]), float(ps["se"]),
			float(ps["d"]) / maxf(1.0e-9, float(ps["se"])),
			Stat.mean(a["cleared"]), float(pc["d"]), float(pc["se"]),
			float(pc["d"]) / maxf(1.0e-9, float(pc["se"]))])

	print("\n=== 辅助量(每局平均;Δ 都是 vs decay=0 的配对差) ===")
	print("  %8s | %9s %8s | %9s %8s | %9s %8s | %9s" % ["decay",
		"商店花费◆", "Δ", "局末余额◆", "Δ", "满槽后买", "Δ", "不愿换%"])
	for a in arms:
		var pp := Stat.paired(base["spend"], a["spend"])
		var pb := Stat.paired(base["balance"], a["balance"])
		var pf := Stat.paired(base["buys_after_full"], a["buys_after_full"])
		var fs := Stat.mean(a["full_shops"])
		print("  %8.2f | %9.2f %8.2f | %9.2f %8.2f | %9.2f %8.2f | %8.1f%%" % [
			float(a["decay"]),
			Stat.mean(a["spend"]), float(pp["d"]),
			Stat.mean(a["balance"]), float(pb["d"]),
			Stat.mean(a["buys_after_full"]), float(pf["d"]),
			100.0 * Stat.mean(a["noswap"]) / maxf(1.0e-9, fs)])
	print("  (「不愿换%%」= 满槽的那些商店里判成「买得起也不换」的占比;"
		+ " 分母 = 每局 %.2f 次满槽商店)" % Stat.mean(base["full_shops"]))
	print("  ⚠ z 的分母是**配对差的**标准误 —— 公共随机数已经吃掉大部分共同噪声。")

	# **多买的那些钱买了什么** —— 局末余额不降反升, 得看是不是买了产币的卡。
	# `interest` 每持有 4◆ 生 1◆(上限 5/拍)= 复利引擎, `tipjar` 零弃牌 +2◆:
	# 它们的产出**同样没有终局价值**, 所以"多买了产币卡"不算把钱花掉。
	var n := float(base["score"].size())
	var ids: Array = []
	for k in base["drafted"]:
		ids.append(String(k))
	ids.sort()
	print("\n=== 多买的钱买了什么(每局装备次数;⚑ = 产币卡, 它的产出照样没有终局价值) ===")
	print("  %8s | %s" % ["decay", " ".join(ids)])
	for a in arms:
		var row: Array = []
		for k in ids:
			row.append("%.2f" % (float(a["drafted"].get(k, 0)) / maxf(1.0, n)))
		print("  %8.2f | %s" % [float(a["decay"]), " ".join(row)])
	print("  ⚑ 产币卡 = interest(每 4◆ 生 1◆, 封顶 5/拍) / tipjar(零弃牌 +2◆)")
