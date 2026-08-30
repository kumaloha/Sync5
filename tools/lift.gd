extends Probe

## 逐卡因果通关率 —— 「**白送 bot 这张卡并占掉一个槽**, 通关率变多少?」
##   godot --headless --path . --script res://tools/lift.gd
##   SYNC5_LIFT_RUNS=400 …            # 每臂局数(默认 1000)
##
## ⚑ **为什么不能用 `report.gd` 的 `support lift`**(那条已有的行):
## 它是**观察性**的 —— `P(通关|持有) − P(通关|未持有)`, 而 bot 的购买是**内生**的:
## 有钱、局面好的时候才买得起卡 ⇒ 「持有它的局赢得多」有一半是反向因果。
## 而且它有 `n >= 50` 的双侧门槛, **把冷门卡整族滤掉了** —— 恰恰是最需要答案的那一批。
##
## ⚑ 治疗 = **把这张卡钉进支援槽 1**(每拍复位, 与 `kit.gd` 同一手法), 其余两个槽 bot 自由买。
## 基准 = 三个槽全由 bot 自己买。两臂**共用种子**。
##
## ⚠⚠ **第一版用的是 `cfg.prefer`(「货架上出现它就优先买」), 不成立** ——
## 一张卡在一局七次商店里被抽到的概率只有约 3/69 × 7 ≈ 30%, 再要求「有空槽 + 买得起」
## ⇒ 实测**持有率 0~7%**, 那样的臂量的是噪声不是卡。
## (`dead:N` 一次强制 11 张正是为了凑命中率, 代价是 11 张混在一起。)
## ⇒ 钉槽位, 持有率 100%, 每张卡各自成臂。
##
## ⚠ **读法(口径必须说清, 否则会被读成「这张卡值多少」)**:
## 治疗臂**白得一张卡**, 同时**少一个可买的槽**。所以 Δ 的含义是
## 「**白送你这张 + 只剩两个槽自己买**」 vs 「**三个槽全自己买**」。
## ⇒ 正数 = 它强过 bot 本来会买进那个槽的东西(还倒赚了那笔钱);
##    负数 = 白送都不如让 bot 自己挑。**看排序与尾巴, 别把绝对值当卡的分值。**
##
## ⚠⚠ 判生死必须传 `o.targets`(2026-08-30 教训:不传 = 每段第一拍就落袋走人,
## 一局只打 4 拍)。这里传 `sim.json bot_targets`, 与 `sim.gd` 同一张表。

var RUNS: int = int(OS.get_environment("SYNC5_LIFT_RUNS")) \
	if OS.get_environment("SYNC5_LIFT_RUNS").is_valid_int() else 1000
var TARGETS: Array = DB.sim().get("bot_targets", GameConfig.SECTION_TARGETS)
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	# 基准队列 = 自由选旗 + 允许换旗(与 sim 的 `anytarget` 同配置), 因为逐卡实验要的是
	# 「在一个不被旗子钉死的世界里」的边际值。⚠ 不用 `no_jokers`:那是另一个问题。
	var base_cfg := {"bot": "adaptive", "target": "", "pivot": true}
	print("\n=== 逐卡因果通关率(钉槽随机分配 · 配对 · %d 局/臂)===" % RUNS)
	print("  治疗 = 这张卡钉进支援槽 1(每拍复位), 另两个槽 bot 自由买;基准 = 三个槽全自己买。")
	print("  两臂共用种子。⚠ Δ 的口径 = 「白送这张 + 只剩两个槽」vs「三个槽全自己买」")
	print("     ⇒ **读排序与尾巴, 别把绝对值当卡的分值**(口径全文见文件头)。")

	var base := _arm(base_cfg, [])
	var base_clear := 100.0 * _mean(base["cleared"])
	print("\n  基准(bot 自选)通关率 %.1f%%" % base_clear)

	var ids: Array = []
	for j in Joker.pool():
		if j.kind != "target":
			ids.append(String(j.id))
	ids.sort()
	var rows: Array = []
	for id in ids:
		var arm := _arm(base_cfg, [id])
		var p: Dictionary = Stat.paired(base["cleared"], arm["cleared"])
		rows.append({
			"id": id,
			"d": 100.0 * float(p["d"]),
			"se": 100.0 * float(p["se"]),
			"clear": 100.0 * _mean(arm["cleared"]),
			"held": 100.0 * _mean(arm["held"]),
		})
	rows.sort_custom(func(a, b) -> bool: return float(a["d"]) > float(b["d"]))

	print("\n  %-13s %8s %8s %7s %7s %7s  %s"
		% ["id", "Δ通关", "±SE", "z", "通关率", "持有率", "判定"])
	for r in rows:
		var z: float = float(r["d"]) / maxf(0.01, float(r["se"]))
		var tag := "·"
		if absf(z) >= 2.0:
			tag = "显著正" if z > 0.0 else "显著负"
		# 钉槽位之后持有率**应当恒 100%** —— 低于它说明钉的手法在某条路径上被绕过了
		# (砧座会毁掉其余槽 / 换旗会顶掉槽 0 …), 那一行的 Δ 不能按「一直持有」读。
		if float(r["held"]) < 95.0:
			tag += "  ⚠ 持有率 %.0f%% < 100%%, 钉槽被绕过, 按「部分持有」读" % float(r["held"])
		print("  %-13s %+8.1f %8.1f %+7.2f %7.1f %7.1f  %s"
			% [r["id"], float(r["d"]), float(r["se"]), z,
				float(r["clear"]), float(r["held"]), tag])

	var ds: Array = []
	for r in rows:
		ds.append(float(r["d"]))
	ds.sort()
	print("\n  分布:中位 %+.1f pt · 最强 %s %+.1f · 最弱 %s %+.1f · 极差 %.1f pt"
		% [ds[ds.size() / 2], String(rows[0]["id"]), float(rows[0]["d"]),
			String(rows[rows.size() - 1]["id"]), float(rows[rows.size() - 1]["d"]),
			float(rows[0]["d"]) - float(rows[rows.size() - 1]["d"])])
	print("  ⚑ 判据:**看排序与离散度**, 不看绝对值的正负(口径见文件头「读法」)。")
	print("     显著负的那些 = **白送都不如让 bot 自己挑**, 那才是要动的卡。")
	print("\n[lift] %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)


## 一条臂。`pin` 非空 = 把那张卡钉进支援槽 1(每拍复位)。
## 返回 {cleared: 每局 0/1, held: 每局 0/1(局末它还在不在槽里)}。
func _arm(cfg: Dictionary, pin: Array) -> Dictionary:
	var cleared: Array = []
	var held: Array = []
	var rep := Report.new(RUNS, GameConfig.SECTIONS_PER_RUN)
	rep.reset()
	var bot := Bot.new(_rng, rep)
	for r in range(RUNS):
		# ⚠ 配对的全部意义在这一行:每条臂的第 r 局用完全相同的种子(与 sim.gd 同源)。
		_rng.seed = 90000 + r
		var faces := SectionMod.roll_run(_rng)
		var st := {"n": 0.0, "disc": 0.0, "rep": 0.0, "late": 0.0, "early": 0.0,
			"zerod": 0.0, "faces": 0.0, "chord": 0.0, "tgt": 0.0,
			"score": 0.0, "mult": 0.0, "kinds": {}}
		var o := RunLoop.Opts.new()
		o.rng = _rng
		o.deck_seed = r * 7 + 1
		o.faces = faces
		o.player = "adaptive"
		o.cfg = cfg
		o.shop = true
		o.mortal = true
		o.targets = TARGETS
		o.st = st
		if not pin.is_empty():
			# ⚠ **每拍复位**, 不是装一次 —— bot 的「买新替旧」会挑最弱的槽换掉,
			# 而被钉的卡在它眼里往往就是最弱那张(kit.gd 同款处理)。
			# ⚠ 每局新建实例:成长牌的计数器不许跨局累积(Joker.pool() 是共享实例)。
			var card = Joker.by_id(String(pin[0]))
			var first := {"done": false}
			o.on_begin = func(run: Run, _p: Phrase) -> void:
				if run.joker_slots[1] != card:
					run.joker_slots[1] = card
					if not first["done"]:
						first["done"] = true
						card.on_acquire(run.deck)
		var res := RunLoop.play(o, bot)
		cleared.append(1.0 if int(res["died_at"]) < 0 else 0.0)
		var has := 0.0
		if not pin.is_empty():
			for j in (res["run"] as Run).joker_slots:
				if j != null and String(j.id) == String(pin[0]):
					has = 1.0
					break
		held.append(has)
	return {"cleared": cleared, "held": held}


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())
