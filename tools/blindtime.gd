extends Probe

## 一次性计时器:一拍在各条路径上各花多少毫秒。
## 建它的理由:blind.gd 12 局跑了 10 分钟没完, 而我**两次凭直觉猜瓶颈都猜错了**。
## LESSONS.md 测量纪律 #7 写着「找性能瓶颈要短路模块量占比, 别照调用次数推」。
##   godot --headless --path . --script res://tools/blindtime.gd

const BEATS := 24


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	var rep := Report.new(BEATS, GameConfig.SECTIONS_PER_RUN)
	rep.reset()
	var bot := Bot.new(rng, rep)
	var cfg := {}
	for c in DB.sim()["cohorts"]:
		if String(c.get("bot", "")) == "random" or bool(c.get("no_jokers", false)):
			continue
		cfg = c.duplicate()
		break
	cfg["bot"] = "perfect"

	print("\n=== 一拍耗时 (完美玩家, %d 拍/档) ===" % BEATS)
	for probe in [
		{"mod": "", "oracle": false, "label": "base 无脸"},
		{"mod": "facedown", "oracle": true, "label": "facedown · 上帝视角"},
		{"mod": "facedown", "oracle": false, "label": "facedown 蒙面"},
		{"mod": "blindspot", "oracle": true, "label": "blindspot · 上帝视角"},
		{"mod": "blindspot", "oracle": false, "label": "blindspot 暗补"},
	]:
		Solver.ORACLE = bool(probe["oracle"])
		var mod := String(probe["mod"])
		rng.seed = 4242
		var deck := Deck.new(99)
		var cache: Array = []
		var slots: Array = [null, null, null, null]
		var t0 := Time.get_ticks_msec()
		for i in range(BEATS):
			var p := Phrase.new(deck, cache, 20)
			p.mod = mod
			p.start()
			bot._play_phrase(p, cfg, slots, 0, mod)
			p.lock_and_settle()
			p.cleanup()
		var ms := Time.get_ticks_msec() - t0
		print("  %-24s %6d ms   (%.1f ms/拍)" % [probe["label"], ms, float(ms) / float(BEATS)])
	Solver.ORACLE = false
	quit(0)
