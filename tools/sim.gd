extends Probe

## Headless balance simulator — plays full runs with bot policies over core/
## only (no view, no clock). Run:
##   godot --headless --path . --script res://tools/sim.gd
##
## Difficulty intent (2026-08, user-locked: "most runs die, clearing is an
## achievement"):
##   build bot  — section 5 pass ~60-70%, full clear ~15%
##   greedy bot — section 5 pass ~30-40%, full clear <5%
##   random bot — dead by section 3, full clear ~0%
##
## Timing signals (acted_late / early_finish) are clock-derived in the real
## game; here they are behavior probabilities, biased by the bot's own build
## (a player who drafted Finale plays to Finale).

# bot beliefs live in data/sim.json (docs/design/tech.md); card amounts and target
# tiers are read from data/jokers.json so a balance edit reaches the bot too.
# 2026-08-05: run.json targets are HUMAN-anchored (真人产出高出机器人约一个
# 数量级) — the sim measures RELATIVE archetype strength on the bot-scale
# shadow targets in sim.json `bot_targets`, not absolute clear rates.
var RUNS: int = int(DB.sim()["runs"])          # per cohort
var SECTIONS: int = GameConfig.SECTIONS_PER_RUN
var TARGETS: Array = DB.sim().get("bot_targets", GameConfig.SECTION_TARGETS)
var _rng := RandomNumberGenerator.new()
var report := Report.new(RUNS, SECTIONS)
var bot := Bot.new(_rng, report)

## 尺子自检的两条边界。random 队列是**哨兵**:它乱打, 通关率必须接近 0;
## 它一旦爬起来, 说明 `sim.json bot_targets` 已经跟不上分数膨胀了。
const RANDOM_MAX := 5.0     # 随机 bot 通关率上限 —— 超了 = 尺子太松
const BEST_MIN := 3.0       # 最强队列通关率下限 —— 低了 = 尺子太紧

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var cohorts: Array = DB.sim()["cohorts"]
	var rates := {}
	var ecos := {}
	for c in cohorts:
		_run_cohort(c)
		rates[String(c.get("name", "?"))] = report.last_clear
		ecos[String(c.get("name", "?"))] = report.last_eco
	var bad := _sanity(rates)
	_eco_bands(rates, ecos)
	print("\n[sim] total %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(1 if bad else 0)


## 经济 v2 四条健康带对照(docs/design/levels.md「怎么调」)。**只读不判死**:
## 健康带按**真人口径**标(levels.md:bot 恒比真人松, 免费时代 bot 弃 0.6 张/拍 vs
## 真人 1.5-3), 这里是 bot 尺 —— 看方向与相对变化, 不拿这里的数字直接调 economy.json。
## ① 用「有商店的对局队列」(adaptive:*);random 乱打、baseline 无商店, 只当 ④ 的参照系。
func _eco_bands(rates: Dictionary, ecos: Dictionary) -> void:
	var shop_named: Array = []
	for k in ecos:
		if String(k).begins_with("adaptive:") and not (ecos[k] as Dictionary).is_empty():
			shop_named.append(String(k))
	shop_named.sort()
	if shop_named.is_empty():
		return
	print("\n=== 经济健康带对照(levels.md 经济 v2「怎么调」;bot 尺读数, 只看方向)===")
	# ① 紧度:局末余额中位数落在个位数
	var meds: Array = []
	var med_line := "  ① 局末余额中位数(带=个位数): "
	for k in shop_named:
		var e: Dictionary = ecos[k]
		meds.append(float(e["end_med"]))
		med_line += "%s:%.0f " % [String(k).trim_prefix("adaptive:"), float(e["end_med"])]
	print(med_line)
	var med_of_meds := Report.eco_median(meds)
	print("     → 队列中位数的中位数 %.0f◆ —— %s" % [med_of_meds,
		"达标(≤9)" if med_of_meds <= 9.0 else "偏离 +%.0f◆(> 个位数带)" % (med_of_meds - 9.0)])
	# ② 弃牌:下移不塌零(免费时代 bot 实测 0.6 张/拍, levels.md 经济 v2 注)
	var FREE_ERA := 0.6
	var dsum := 0.0
	var zsum := 0.0
	for k in shop_named:
		dsum += float(ecos[k]["disc_per_beat"])
		zsum += float(ecos[k]["zerod_pct"])
	var davg := dsum / float(shop_named.size())
	var zavg := zsum / float(shop_named.size())
	var verdict2 := ""
	if davg >= FREE_ERA:
		verdict2 = "未下移(1◆ 对 bot 无感)"
	elif 100.0 - zavg < 2.0:
		verdict2 = "塌零(几乎没有拍在弃牌)"
	else:
		verdict2 = "达标(下移 %.0f%% 且未塌零)" % (100.0 * (FREE_ERA - davg) / FREE_ERA)
	print("  ② 弃牌 %.2f 张/拍 vs 免费时代 0.60 · 零弃牌拍 %.0f%% —— %s" % [davg, zavg, verdict2])
	# ③ 软破产率:上限 15%(真人口径的初拍值, levels.md)
	var bmax := 0.0
	var bmax_name := ""
	for k in shop_named:
		if float(ecos[k]["broke_pct"]) > bmax:
			bmax = float(ecos[k]["broke_pct"])
			bmax_name = String(k)
	print("  ③ 软破产拍(决策时 0◆)最高 %.2f%%(%s;带 ≤15%%)—— %s"
		% [bmax, bmax_name, "达标" if bmax <= 15.0 else "偏离 +%.1fpt" % (bmax - 15.0)])
	# ④ 收入/水平斜率:不同强度队列的牌型金币收入(random < baseline < 最强 = 斜率为正)
	var rnd_e: Dictionary = ecos.get("random", {})
	var base_e: Dictionary = ecos.get("baseline(no jokers, adaptive)", {})
	var best_name := ""
	var best_rate := -1.0
	for k in shop_named:
		if float(rates.get(k, 0.0)) > best_rate:
			best_rate = float(rates.get(k, 0.0))
			best_name = k
	if not rnd_e.is_empty() and not base_e.is_empty() and best_name != "":
		var a := float(rnd_e["income_beat"])
		var b := float(base_e["income_beat"])
		var c2 := float(ecos[best_name]["income_beat"])
		var ar := float(rnd_e["income_run"])
		var br := float(base_e["income_run"])
		var cr := float(ecos[best_name]["income_run"])
		var mono := a < b and b < c2
		print("  ④ 牌型金币收入/拍: random %.2f → baseline %.2f → 最强(%s) %.2f(/局: %.0f → %.0f → %.0f)—— %s"
			% [a, b, best_name.trim_prefix("adaptive:"), c2, ar, br, cr,
			"达标(斜率为正)" if mono else "偏离(未单调递增)"])


## **尺子自检**(2026-08-07 加, 用户要的)。
## 起因:`bot_targets` 失效了整整一天没人发现 —— 它**坏得很安静**, 通关率只是越来越高,
## 不报错、不崩溃, 直到 random 队列通关 **95.3%**(乱打都能过)才被看出来。
## 而那一整天里所有基于 sim 的平衡判断都建立在坏表上。
## 所以给它加一条会喊的边界:**random 是哨兵**, 它乱打, 通关率必须接近 0。
## 非零退出, 和 flow_probe 同一条纪律 —— 不然警告还是会被无视。
func _sanity(rates: Dictionary) -> bool:
	var bad := false
	var rnd := -1.0
	var best := -1.0
	var best_name := ""
	for k in rates:
		var v: float = float(rates[k])
		if String(k).begins_with("random"):
			rnd = v
		elif v > best:
			best = v
			best_name = String(k)
	print("\n=== 尺子自检 ===")
	if rnd >= 0.0 and rnd > RANDOM_MAX:
		print("  ❌ random 队列通关 %.1f%% > %.1f%% —— **bot_targets 太松, 已经失效**" % [rnd, RANDOM_MAX])
		print("     乱打的机器人不该通关。重算: 把 tools/curve.gd 的 BOT 设成 \"adaptive\" 跑一遍,")
		print("     把混合人群那行的反解目标写回 data/sim.json 的 bot_targets。")
		bad = true
	if best >= 0.0 and best < BEST_MIN:
		print("  ❌ 最强队列(%s)只有 %.1f%% < %.1f%% —— **bot_targets 太紧**" % [best_name, best, BEST_MIN])
		print("     同样用 curve.gd 重算。")
		bad = true
	if not bad:
		print("  ✅ random %.1f%% ≤ %.1f%%, 最强(%s) %.1f%% ≥ %.1f%% —— 尺子有区分度"
			% [rnd, RANDOM_MAX, best_name, best, BEST_MIN])
	return bad


# ============================== COHORT ==============================

func _run_cohort(cfg: Dictionary) -> void:
	report.reset()
	for r in range(RUNS):
		_rng.seed = 90000 + r
		_one_run(cfg, r)
	report.print_report(cfg)


## ⚠ 2026-08-07: 这个循环原来是**六份编排之一**(docs/design/tech.md)。现在它持有一个真的
## `Run`, 结算走 `Beat.settle` / `Beat.phrase_end` —— 和游戏是同一份实现。
## 局部的 deck/cache/slots/coins 只是 run 里那几个字段的别名, 留着是为了少改行。
func _one_run(cfg: Dictionary, run_idx: int) -> void:
	report.eco_begin_run()
	var no_jokers: bool = bool(cfg.get("no_jokers", false))
	# ⚑ 一局四张脸走 SectionMod.roll_run 这一份(2026-08-14 收口, 原来 7 份)——
	# 保证「一局之内不偶然重复」。RNG 消耗与旧代码逐次相同。
	var faces := SectionMod.roll_run(_rng)
	# 这一局自己的行为账本 —— 买牌算法拿它给卡定价
	var st := {"n": 0.0, "disc": 0.0, "rep": 0.0, "late": 0.0, "early": 0.0,
		"zerod": 0.0, "faces": 0.0, "chord": 0.0, "tgt": 0.0,
		"score": 0.0, "mult": 0.0, "kinds": {}}
	var mkeys := {}          # 段号 -> "S3 rerun", 死亡时要用

	var o := RunLoop.Opts.new()
	o.rng = _rng
	o.deck_seed = run_idx * 7 + 1
	o.faces = faces
	o.player = "adaptive"
	o.cfg = cfg
	o.shop = not no_jokers
	o.mortal = true
	o.targets = TARGETS
	o.st = st

	o.on_begin = func(run: Run, _p: Phrase) -> void:
		# 经济账本:软破产拍 = **决策时**(发牌后、动手前)0◆ —— 一张都弃不起。
		# 牌型金币在结算才入账, 所以约束弃牌的是拍首余额, 不是拍末。
		if run.coins == 0:
			report.eco_add("broke_beats", 1)
		if run.phrase_in_section != 0:
			return
		var mod := String(faces.get(run.section_idx, ""))
		if mod == "":
			return
		var mkey := "S%d %s" % [run.section_idx + 1, mod]
		mkeys[run.section_idx] = mkey
		if not report.wall_mod.has(mkey):
			report.wall_mod[mkey] = [0, 0]
		report.wall_mod[mkey][0] += 1

	o.on_beat = func(run: Run, p: Phrase, outcome: Dictionary, ctx: Dictionary) -> void:
		var res: Dictionary = outcome["res"]
		var flags: Dictionary = ctx["flags"]
		var section: int = run.section_idx
		# ⚠ 「重复成手」比的是**结算前**的上一拍牌型 —— ctx 里那个。
		# 读 run.prev_kind 拿到的已经是本拍的牌型, 统计会静默变成恒真。
		if int(res.get("kind", -99)) == int(ctx["prev_kind"]):
			st["rep"] += 1.0
		report.phrase_score_sum[section] += float(outcome["score"])
		report.phrase_score_n[section] += 1
		var kk := int(res.get("kind", -1))
		report.kind_count[kk] = int(report.kind_count.get(kk, 0)) + 1
		report.discards_sum += p.discards_used
		report.discards_n += 1
		report.track_triggers(run.joker_slots, outcome)
		# 经济账本(旁路只记事实, 口径见 report.gd eco 注释):
		report.eco_add("beats", 1)
		report.eco_add("disc_cards", p.discards_used)
		report.eco_add("spend_discard", p.discards_used * GameConfig.DISCARD_COST)
		if p.discards_used == 0:
			report.eco_add("zerod_beats", 1)
		# 牌型金币收入 = res.coins(**只看牌型**, 小丑加成/系数在 outcome.coins 那层)。
		report.eco_add("income_kind", int(res.get("coins", 0)))
		st["disc"] += float(p.discards_used)
		if p.discards_used == 0:
			st["zerod"] += 1.0
		if flags["late"]:
			st["late"] += 1.0
		if flags["early"]:
			st["early"] += 1.0
		for c in res.get("resolved", []):
			if c.rank >= 11 and c.rank <= 13:
				st["faces"] += 1.0
		var cs := {}
		for c in run.cache:
			if not c.is_wild():
				cs[c.suit] = true
		if not run.cache.is_empty() and cs.size() <= 1:
			st["chord"] += 1.0
		for pu in outcome["popups"]:
			if int(pu["slot"]) == 0:
				st["tgt"] += 1.0

	o.on_section = func(_run: Run, section: int, _sec_score: int, coins: int) -> void:
		report.coins_at_section[section] += float(coins)
		report.coins_at_n[section] += 1

	var res := RunLoop.play(o, bot)
	report.eco_commit_run(int(res["coins"]), int(res["died_at"]) < 0)
	var slots: Array = res["run"].joker_slots
	var died: int = int(res["died_at"])
	# 「持有过奖励换旗的卡」的局数 —— 分列口径的分母(见 report.gd 的两列说明)。
	# ⚠ 用**局末**槽位近似「本局持有过」:中途卖掉/换掉会漏记, 但装备只增不减是常态。
	for hj in slots:
		if hj != null and hj.swap_bonus_pct() > 0.0:
			report.swap_runs_held += 1
			break
	if died >= 0:
		report.died_at.append(died)
		report.record_run(slots, died)
		if mkeys.has(died):
			report.wall_mod[mkeys[died]][1] += 1
	else:
		report.died_at.append(SECTIONS)
		report.record_run(slots, SECTIONS)
