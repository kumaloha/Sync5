extends Probe

## 数学 G:通过率曲线 → 反解目标分 (design/solver_roadmap.md ①)。
##   godot --headless --path . --script res://tools/curve.gd
##
## **为什么一次就能算出整条曲线**:平衡贪心**不看缺口**(它只比「本拍得分 + λ·缓存潜力」),
## 所以分数分布**与目标分无关** —— 录一次分数, 任意目标分的通过率都能在同一批数据上算出来。
## 这就是 design/solver_roadmap.md 说的「反解是免费的」:不是迭代求根, 是**查分位数**。
## ⚠ 代价(显式声明):真人**会**看缺口(「差得多就赌」), 贪心不会。所以这条曲线描述的是
## 「一个不会临场改打法的强玩家」。等真人数据进来, 这一项归进发挥系数。
##
## **不死局**:打满 24 拍、不判生死。这样任意一组候选目标都能在**同一批录好的数据**上重放,
## 跨段的幸存者条件因此是**精确**的(死者不进下一段的分位数), 不需要段间独立假设 ——
## `design/history_parametric.md` (F9) 那条「必定低估生还」的系统性偏差在这里结构性地不存在。
## 段末工资照发(假定通过), 这是不死局的记账约定。

# ⚠ 求解器每拍要跑 ~1400 次 Pattern+Settle, 8 队列 × 200 局跑不完 10 分钟。
# 100 局够估分位数(段分位的采样误差 ~±3%), 要更准就单队列加大。
const N_RUNS := 100

## 用哪个玩家来定关卡。**两张表, 两个尺度, 别混用**:
##   "perfect"  → 求解器。产出 `run.json section_targets`(真人面对的表, 完美玩家尺度)
##   "adaptive" → 规则机器人。产出 `sim.json bot_targets`(**影子表**, 只给 sim 判生死用)
## 机器人比完美玩家弱得多, 所以两张表差一个量级 —— 拿错了会让 sim 的通关率整体失真
## (2026-08-07 实测:影子表过期后 random 队列通关 95.3%, 尺子彻底没有区分度)。
## 2026-08-10 起可用 SYNC5_CURVE_BOT=perfect|adaptive 覆盖(SYNC5_KIT_ID 同款先例),
## 两个尺度可以连跑, 不用再改这个常量。默认仍是 adaptive, 行为不变。
var BOT: String = OS.get_environment("SYNC5_CURVE_BOT") \
	if OS.get_environment("SYNC5_CURVE_BOT") in ["perfect", "adaptive"] else "adaptive"

## 设计难度谱:每段「到达者中的死亡率」。**2026-08-07 用户拍板挪进 `data/run.json`** ——
## 目标函数已换成「留存最大化」, 所以这条曲线的形状是**待搜索的参数**, 不是我拍的常量。
## 原值 [0.10,0.30,0.45,0.60](来自 `design/history_adversarial.md` §1.2, 乘积 ≈ 13.9% 通关率)留作搜索起点。
var DEATH_SPEC: Array = DB.run()["death_spec"]

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var cohorts: Array = DB.sim()["cohorts"]
	print("\n=== 数学 G · 通过率曲线与反解 (%d 局/队列, 不死局) ===" % N_RUNS)
	print("  设计谱(到达者死亡率) = %s" % [DEATH_SPEC])

	var all_rows: Array = []
	for c in cohorts:
		if String(c.get("bot", "")) == "random" or bool(c.get("no_jokers", false)):
			continue      # random 是回归基线; baseline 不买牌, 不代表真实人群
		var rows := _play(c)
		all_rows.append({"name": String(c["name"]), "rows": rows})
		_report(String(c["name"]), rows)

	# 混合人群:各队列等权(⚠ 真实权重要等真人数据, design/solver_roadmap.md R4)
	var mixed: Array = []
	for e in all_rows:
		mixed.append_array(e["rows"])
	print("\n  ---- 混合人群(等权, 待真人权重) ----")
	_report("mixed", mixed)

	print("\n[curve] %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)


## 打 N 局, 每局录 4 个段分。**不判生死**, 所以每局都有完整 4 段数据。
func _play(cfg: Dictionary) -> Array:
	var rows: Array = []
	var rep := Report.new(N_RUNS, GameConfig.SECTIONS_PER_RUN)
	rep.reset()
	var bot := Bot.new(_rng, rep)
	var pcfg := cfg.duplicate()
	pcfg["bot"] = BOT
	# ⚠ baseline 队列是 `no_jokers` 的**对照组**(不买牌), 漏了这个判断就等于给它发牌,
	# 对照组当场作废 —— 而它恰恰是「商店修复」那次唯一能证明改对了的那条线。
	var no_jokers: bool = bool(cfg.get("no_jokers", false))
	for r in range(N_RUNS):
		_rng.seed = 620000 + r
		# ⚠⚠ **RNG 顺序不许动**:先抽主角、后掷脸。RunLoop 内部也会抽主角, 所以这里
		# 自己抽好传进去(Opts.character 非空时它就不抽了), 否则顺序反过来、读数整体漂移。
		var character: Character = Character.roster()[_rng.randi_range(0, 7)]
		var faces := {}
		for w in GameConfig.WALL_SECTIONS:
			faces[w] = SectionMod.roll(w, _rng)
		var o := RunLoop.Opts.new()
		o.rng = _rng
		o.deck_seed = r * 17 + 5
		o.character = character
		o.faces = faces
		o.player = "adaptive"
		o.cfg = pcfg
		o.shop = not no_jokers
		# ⚠ **不死局**:打满 24 拍、不判生死。这样任意一组候选目标都能在同一批录好的
		# 数据上重放, 跨段的幸存者条件因此是**精确**的 —— 反解那一步的全部前提。
		o.mortal = false
		var res := RunLoop.play(o, bot)
		var totals: Array = []
		for s in res["sec_scores"]:
			totals.append(int(s))
		rows.append(totals)
	return rows


## 按设计谱**逐段反解**目标分。每段只在**上一段的幸存者**里取分位数 ——
## 这就是幸存者条件, 而且因为用的是真实成对数据, 它是精确的而不是建模出来的。
func _report(label: String, rows: Array) -> void:
	print("\n  ▶ %s (n=%d)" % [label, rows.size()])
	var alive: Array = rows.duplicate()
	var targets: Array = []
	var diffs: Array = []
	for s in range(GameConfig.SECTIONS_PER_RUN):
		if alive.is_empty():
			targets.append(0)
			break
		var col: Array = []
		for row in alive:
			col.append(float(row[s]))
		col.sort()
		var d: float = float(DEATH_SPEC[mini(s, DEATH_SPEC.size() - 1)])
		# 死亡率 d ⇒ 目标分落在第 d 分位(低于它的人过不去)
		var idx: int = clampi(int(round(d * float(col.size()))), 0, col.size() - 1)
		var t: int = int(col[idx])
		targets.append(t)
		var survivors: Array = []
		for row in alive:
			if float(row[s]) >= float(t):
				survivors.append(row)
		var pass_rate: float = float(survivors.size()) / float(alive.size())
		diffs.append(1.0 / maxf(0.0001, pass_rate))
		print("    S%d  目标 %7d   到达者 %4d → 过 %4d (%.0f%%)   难度 %.2f   段分中位 %d"
			% [s + 1, t, alive.size(), survivors.size(), 100.0 * pass_rate,
				1.0 / maxf(0.0001, pass_rate), int(col[col.size() / 2])])
		alive = survivors
	var clear: float = float(alive.size()) / float(maxi(1, rows.size()))
	var total_diff := 1.0
	for d in diffs:
		total_diff *= float(d)
	print("    → 反解目标 %s" % [targets])
	print("    → 通关率 %.1f%%  总难度 %.1f (平均打 %.1f 局通一次)"
		% [100.0 * clear, total_diff, total_diff])
