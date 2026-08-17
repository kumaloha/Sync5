extends RefCounted

# --- 券(消耗品层)—— core/ticket.gd 的纯函数直测 ---
#
# ⚠ 这里**不测 SaveState 的券入口**:探针/测试进程被 `_is_probe()` 闸挡着(by design),
# 测得到的只会是闸本身。逻辑当初特意抽成接字典的纯函数(core/ticket.gd 文件头),
# 本文件测的就是那一层。⚠ 2026-08-17 查证:交接里写的「券 18+24 条断言」**从未存在过**,
# 本文件是第一份 —— 假账的教训记在 LESSONS。
func run(t) -> void:
	# ---- 总开关:1.0 不上券(用户 2026-08-18:「第一版去掉券, 第二版商业化的时候加」)----
	# 这条锁的是**发行决策**:谁在 1.1 之前把开关翻回 true, 这里会响。
	# ⚠ 下面的纯函数照常全测 —— 关的是玩家入口, 不是实现。
	t.check(not Ticket.enabled(), "1.0 ships WITHOUT tickets (flip data/tickets.json enabled in 1.1)")

	# ---- 数据面 ----
	var ids := Ticket.ids()
	t.eq(ids.size(), 5, "five tickets in the roster")
	for tid in ids:
		t.check(["phrase", "shop", "run"].has(Ticket.scope(String(tid))),
			"scope of %s is a known layer" % tid)
	t.eq(Ticket.scope("nosuch"), "", "unknown id has empty scope")
	t.eq(Ticket.max_held(), 5, "max_held from data")

	# ---- 第几天(时钟由调用方注入)----
	var u := 1_700_000_000
	t.eq(Ticket.day_index(u + 86400), Ticket.day_index(u) + 1,
		"one day later is exactly the next day index (any timezone)")
	t.check(Ticket.day_index(u + 3600) - Ticket.day_index(u) <= 1,
		"an hour never advances more than one day")

	# ---- 跨天清零:只动券的三个键 ----
	var data := {"tickets": {"overtime": 2}, "ticket_rolls": {"boost": [1.5]},
		"tickets_day": 10, "runs_total": 7, "seen_tutorial": true}
	t.check(not Ticket.reset_if_new_day(data, 10), "same day: no reset")
	t.eq(int(data["tickets"]["overtime"]), 2, "same day keeps tickets")
	t.check(Ticket.reset_if_new_day(data, 11), "new day resets")
	t.check(data["tickets"].is_empty(), "reset clears tickets")
	t.check(data["ticket_rolls"].is_empty(), "reset clears rolls with the tickets")
	t.eq(int(data["runs_total"]), 7, "reset must NOT touch runs_total (min_run unlock)")
	t.check(bool(data["seen_tutorial"]), "reset must NOT touch the tutorial flag")

	# ---- 发与用 ----
	var held := {}
	t.eq(Ticket.grant_into(held, "overtime", 2), 2, "grant two")
	t.eq(Ticket.grant_into(held, "overtime", 9), 3, "truncated at max_held")
	t.eq(Ticket.grant_into(held, "nosuch", 1), 0, "unknown id grants nothing")
	t.eq(Ticket.grant_into(held, "redeal", 0), 0, "n<=0 grants nothing")
	t.check(Ticket.consume_from(held, "overtime"), "consume works")
	t.eq(int(held["overtime"]), 4, "count decremented")
	held["redeal"] = 1
	Ticket.consume_from(held, "redeal")
	t.check(not held.has("redeal"), "zero count erases the key (no zero residue)")
	t.check(not Ticket.consume_from(held, "redeal"), "consuming what you lack fails")

	# ---- 获得时掷值(boost)----
	t.check(Ticket.rollable("boost"), "boost rolls at grant")
	t.check(not Ticket.rollable("overtime"), "overtime does not roll")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for _i in range(20):
		var v := Ticket.roll_for("boost", rng)
		t.check(v >= 1.2 and v <= 2.5, "roll stays inside [mult_min, mult_max]")
		t.check(absf(v - snappedf(v, 0.1)) < 0.0001, "roll snapped to 0.1 (card must read aloud)")
	t.eq(Ticket.roll_for("overtime", rng), 0.0, "non-rollable rolls 0")

	# 不变量:rolls 的长度 == 持有张数(截断时不多掷)
	var d2 := {}
	rng.seed = 7
	t.eq(Ticket.grant_with_roll(d2, "boost", 3, rng), 3, "grant three boosts")
	t.eq(d2["ticket_rolls"]["boost"].size(), 3, "one roll per granted ticket")
	t.eq(Ticket.grant_with_roll(d2, "boost", 9, rng), 2, "only 2 fit under max_held")
	t.eq(d2["ticket_rolls"]["boost"].size(), 5, "truncated grant rolls only what landed")
	var first := float(d2["ticket_rolls"]["boost"][0])
	var second := float(d2["ticket_rolls"]["boost"][1])
	t.eq(Ticket.peek_roll(d2, "boost"), first, "peek reads the queue head")
	t.eq(Ticket.pop_roll(d2, "boost"), first, "pop returns the head (FIFO: 用掉的正是看到的)")
	t.eq(Ticket.peek_roll(d2, "boost"), second, "next in line moves up")
	t.eq(d2["ticket_rolls"]["boost"].size(), 4, "pop shrinks the queue")
	for _i in range(4):
		Ticket.pop_roll(d2, "boost")
	t.check(not d2["ticket_rolls"].has("boost"), "empty roll queue erases the key")
	t.eq(Ticket.pop_roll(d2, "boost"), 0.0, "pop on empty is 0, not a crash")
	t.eq(Ticket.peek_roll(d2, "overtime"), 0.0, "peek on non-rollable is 0")

	# ---- 每日发放 ----
	var d3 := {}
	rng.seed = 99
	var got := Ticket.settle_daily_grant(d3, 100, rng)
	t.check(Ticket.ids().has(got), "daily grant hands out a real ticket")
	t.eq(int(d3["grant_day"]), 100, "grant day stamped")
	t.eq(Ticket.settle_daily_grant(d3, 100, rng), "", "same day never grants twice")
	if got == "boost":
		t.eq(d3["ticket_rolls"]["boost"].size(), 1, "daily boost rolls its value at grant")
	else:
		t.check(not d3.get("ticket_rolls", {}).has(got), "non-boost daily grant rolls nothing")
	# 满仓那天也要盖章, 否则同一天反复掷点
	var d4 := {"tickets": {}}
	for tid in Ticket.ids():
		d4["tickets"][tid] = Ticket.max_held()
	rng.seed = 5
	t.eq(Ticket.settle_daily_grant(d4, 200, rng), "", "full wallet grants nothing")
	t.eq(int(d4["grant_day"]), 200, "…but the day is still stamped")
