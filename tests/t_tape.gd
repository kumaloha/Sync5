extends RefCounted

# --- Tape (打点) ---

func run(t) -> void:
	# 全程走内存模式:测试不许在 user:// 里留文件
	var was_enabled := Tape.enabled
	var was_file := Tape.to_file
	Tape.reset()
	Tape.enabled = true
	Tape.to_file = false
	Tape.set_mute([])
	Tape.clock_ms = 0

	# 一条流永远以 run 事件开头, 序号从 0 起
	Tape.begin({"char": 3})
	var ev: Array = Tape.events()
	t.eq(ev.size(), 1, "begin writes exactly the run event")
	t.eq(ev[0]["e"], "run", "stream opens with the run event")
	t.eq(ev[0]["n"], 0, "run event is sequence 0")
	t.eq(ev[0]["char"], 3, "begin carries the meta payload through")
	t.check(Tape.run_id() != "", "begin hands back a run id")
	# 同一秒开两局也必须落到两个 id —— 否则两局会追加进同一个文件
	var id1 := Tape.run_id()
	Tape.begin({})
	t.check(Tape.run_id() != id1, "back-to-back runs get distinct ids")
	Tape.reset()
	Tape.clock_ms = 0
	Tape.begin({"char": 3})

	Tape.on("beat", {"p": 2, "hand": ["AS"]})
	t.eq(Tape.events().size(), 2, "on appends")
	t.eq(Tape.events()[1]["n"], 1, "sequence keeps counting")
	t.eq(Tape.events()[1]["p"], 2, "payload lands on the event")

	# payload 撞名盖不掉元字段 —— 否则日志的时间轴能被一条事件写坏。
	# 但「盖不掉」不能是静默的(disc 的张数字段就这么被吃过一轮), 所以 on() 会
	# push_error —— **下面三条 [Tape] 报错是本用例故意触发的, 不是失败**。
	t.eq(Tape.RESERVED, ["n", "ms", "e"], "the reserved meta keys are declared")
	print("  (以下 3 条 [Tape] 保留字报错是这条用例故意触发的)")
	Tape.on("swap", {"e": "hax", "n": 999, "ms": -5})
	var last: Dictionary = Tape.events()[2]
	t.eq(last["e"], "swap", "payload cannot overwrite the event name")
	t.eq(last["n"], 2, "payload cannot overwrite the sequence")
	t.eq(last["ms"], 0, "payload cannot overwrite the timestamp")

	# 注入时钟:ms 不依赖真实时间, 断言才稳
	Tape.clock_ms = 4200
	Tape.on("sort", {})
	t.eq(Tape.events()[3]["ms"], 4200, "injected clock drives ms")
	Tape.clock_ms = 0

	# 每条事件都要能过 JSON 往返 —— 落盘就是 JSONL
	for e in Tape.events():
		var back = JSON.parse_string(JSON.stringify(e))
		t.check(back is Dictionary and back["e"] == e["e"], "event survives a JSON round trip")

	# mute 只挡被点名的事件
	var before := Tape.events().size()
	Tape.set_mute(["sort"])
	Tape.on("sort", {})
	t.eq(Tape.events().size(), before, "muted events are dropped")
	Tape.on("beat", {})
	t.eq(Tape.events().size(), before + 1, "unmuted events still land")
	Tape.set_mute([])

	# 总开关关掉 = 一条都不进
	Tape.enabled = false
	var quiet := Tape.events().size()
	Tape.on("beat", {})
	t.eq(Tape.events().size(), quiet, "disabled tape records nothing")
	Tape.enabled = true

	# 纯内存模式下超出上限退化成环形缓冲, 长会话不吃内存
	Tape.reset()
	Tape.clock_ms = 0
	var cap := Tape.max_events
	Tape.max_events = 4
	Tape.begin({})
	for i in range(10):
		Tape.on("beat", {"i": i})
	t.eq(Tape.events().size(), 3, "memory mode caps the buffer")
	t.eq(Tape.events()[Tape.events().size() - 1]["i"], 9, "the newest event survives the cap")
	Tape.max_events = cap

	# close 是流的硬边界 —— 之后的事件不许再落进这一局的文件
	Tape.reset()
	Tape.clock_ms = 0
	Tape.begin({})
	t.check(Tape.path() != "", "an open stream has a sink path")
	Tape.close({"ok": true})
	t.eq(Tape.path(), "", "close shuts the sink; later events cannot reopen it")
	t.eq(Tape.events()[Tape.events().size() - 1]["e"], "close", "close is the last event")

	# 序列化助手:日志里只放标签和 id
	t.eq(Tape.cards([t._c(14, 3), t._c(10, 2)]), ["AS", "10H"], "cards serialize to labels")
	var mono := Joker.by_id("mono")
	t.eq(Tape.slots([mono, null]), ["mono", ""], "empty slots keep their place")
	t.eq(Tape.fired([{"slot": 0, "text": "x"}, {"slot": -1, "text": "y"}], [mono, null]),
		["mono"], "popups map back to joker ids; negative slots are dropped(主角已删)")
	t.eq(Tape.fired([{"slot": 2, "text": "x"}], [mono, null]), [],
		"a popup pointing at an empty slot is dropped, not crashed on")

	# data/tape.json 的硬校验
	var good := {"enabled": true, "to_file": false, "dir": "user://logs",
		"max_events": 10, "mute": []}
	t.eq(DB.validate_tape(good), "", "a well-formed tape config validates")
	var bad_key := good.duplicate()
	bad_key["oops"] = 1
	t.check(DB.validate_tape(bad_key) != "", "unknown tape key is rejected")
	var bad_cap := good.duplicate()
	bad_cap["max_events"] = 0
	t.check(DB.validate_tape(bad_cap) != "", "max_events 0 is rejected")
	var bad_mute := good.duplicate()
	bad_mute["mute"] = "sort"
	t.check(DB.validate_tape(bad_mute) != "", "mute must be an array")

	Tape.reset()
	Tape.enabled = was_enabled
	Tape.to_file = was_file
