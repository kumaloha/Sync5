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
	for c in cohorts:
		_run_cohort(c)
		rates[String(c.get("name", "?"))] = report.last_clear
	var bad := _sanity(rates)
	print("\n[sim] total %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(1 if bad else 0)


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
	var slots: Array = res["run"].joker_slots
	var died: int = int(res["died_at"])
	if died >= 0:
		report.died_at.append(died)
		report.record_run(slots, died)
		if mkeys.has(died):
			report.wall_mod[mkeys[died]][1] += 1
	else:
		report.died_at.append(SECTIONS)
		report.record_run(slots, SECTIONS)
