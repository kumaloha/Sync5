extends SceneTree

## 完美玩家 + 商店的一局**逐拍计时**(2026-09-04)—— 回答「price / curve 的单局为什么贵」。
##   godot --headless --path . --script res://tools/pace.gd
##   SYNC5_PT_N=<n>        跑几局(默认 1)
##   SYNC5_PT_NOSHOP=1     关商店(对照:不装小丑牌时的每拍成本)
## 每拍打印:耗时 ms · 分数 · 弃牌数 · 槽位 · 牌堆里的万能牌数。
##
## 09-04 首跑的答案(price 队列 adaptive:twin, 完美玩家):
##   前三拍无小丑牌 **~70 ms/拍**;第一家店买了 twin + 超级百搭(3 张万能进牌堆)之后
##   **2000~2500 ms/拍**, 单局 45 s。两笔账:
##   ① 装了任何小丑牌, `Solver.best_score` 对每个 8 选 5 组合各跑一次 `Settle.run`
##      (弃牌枚举 × 补牌采样 ≈ 1.8 万次/拍)—— 求解器精确枚举 × 完整结算的**固有成本**;
##   ② 万能牌让每次 `Pattern` 解析贵 5~10 倍(候选构造)。
##   ⇒ 不是 bug, 是量级;price 全表只能靠分片并行(`SYNC5_PRICE_SHARD`)。
##   `score_five` 的分数记忆把无小丑牌的拍从 112 → 70 ms(gate 的 solver 脸门直接受益)。

func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	var rep := Report.new(1, GameConfig.SECTIONS_PER_RUN)
	rep.reset()
	var bot := Bot.new(rng, rep)
	var cfg: Dictionary = {}
	for c in DB.sim()["cohorts"]:
		if String(c.get("bot", "")) == "random" or bool(c.get("no_jokers", false)):
			continue
		cfg = c.duplicate()
		break
	print("[pricetime] cohort=%s" % String(cfg.get("name", "?")))
	cfg["bot"] = "perfect"
	var n := int(OS.get_environment("SYNC5_PT_N")) if OS.get_environment("SYNC5_PT_N") != "" else 1
	var shop := OS.get_environment("SYNC5_PT_NOSHOP") == ""
	for r in range(n):
		rng.seed = 620000 + r
		var st := {"n": 0.0, "disc": 0.0, "rep": 0.0, "late": 0.0, "early": 0.0,
			"zerod": 0.0, "faces": 0.0, "chord": 0.0, "tgt": 0.0,
			"score": 0.0, "mult": 0.0, "kinds": {}}
		var o := RunLoop.Opts.new()
		o.rng = rng
		o.deck_seed = r * 17 + 5
		o.faces = {}
		o.player = "adaptive"
		o.cfg = cfg
		o.shop = shop
		o.mortal = false
		o.st = st
		o.tally_mult_kinds = false
		var t_last := [Time.get_ticks_msec()]
		var t_run := Time.get_ticks_msec()
		o.on_beat = func(run: Run, p: Phrase, outcome: Dictionary, _ctx: Dictionary) -> void:
			var now := Time.get_ticks_msec()
			var ids: Array = []
			for j in run.joker_slots:
				ids.append("-" if j == null else String(j.id))
			var wilds := 0
			for c in run.deck.draw_pile:
				if c != null and c.is_wild():
					wilds += 1
			for c in run.deck.discard_pile:
				if c != null and c.is_wild():
					wilds += 1
			print("  S%d p%d  %5d ms  score=%6d  disc=%d  slots=%s  wilds=%d" % [
				run.section_idx, run.phrase_in_section, now - t_last[0],
				int(outcome.get("score", 0)), p.discards_used, str(ids), wilds])
			t_last[0] = now
		var res := RunLoop.play(o, bot)
		print("[pricetime] run %d total=%d  %d ms  shop=%s" % [r, int(res["total"]), Time.get_ticks_msec() - t_run, str(shop)])
	quit(0)
