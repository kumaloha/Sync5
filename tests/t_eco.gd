extends RefCounted

# --- 经济收支账本(tools/report.gd eco;2026-08-27 经济 v2 仪器旁路)---
# 锁三件事:① 累加/定案/清零的算术;② mean±SE 与中位数的数学;
# ③ 账本是**旁路**(begin 前的散写不会混进任何一局 —— bot 在非 sim 探针里也会写)。
func run(t) -> void:
	var rep := Report.new(2, 4)
	rep.reset()

	# ③ 旁路:没人 begin 时的散写只攒在 eco 里, commit 前不属于任何一局。
	rep.eco_add("spend_buy", 7)
	rep.eco_begin_run()                    # begin 清掉散写, 开新账页
	t.eq(rep.eco.get("spend_buy", 0), 0, "eco_begin_run 开新账页(探针散写不串局)")

	# ① 累加与定案。
	rep.eco_add("spend_discard", 3)
	rep.eco_add("spend_discard", 2)
	rep.eco_add("income_kind", 10)
	rep.eco_add("beats", 1)
	rep.eco_commit_run(8, true)
	rep.eco_begin_run()
	rep.eco_add("spend_discard", 1)
	rep.eco_commit_run(2, false)
	t.eq(rep.eco_runs.size(), 2, "两局各一条定案")
	t.eq(int(rep.eco_runs[0]["spend_discard"]), 5, "同键累加")
	t.eq(int(rep.eco_runs[0]["end"]), 8, "局末余额随 commit 入账")
	t.eq(int(rep.eco_runs[0]["cleared"]), 1, "通关标记")
	t.eq(int(rep.eco_runs[1]["cleared"]), 0, "死亡局标记")
	t.eq(int(rep.eco_runs[1].get("income_kind", 0)), 0, "缺键读 0(第二局没记收入)")

	# ② 统计工具的数学(手算锚:[2,4,9] mean=5, sd=√13, SE=√13/√3≈2.0817)。
	var ms: Array = Report.eco_mean_se([2.0, 4.0, 9.0])
	t.check(absf(float(ms[0]) - 5.0) < 1e-9, "mean([2,4,9]) = 5")
	t.check(absf(float(ms[1]) - 2.081666) < 1e-4, "SE([2,4,9]) = sd/√n ≈ 2.0817")
	t.eq(Report.eco_mean_se([]), [0.0, 0.0], "空集 mean±SE = 0")
	t.check(absf(Report.eco_median([3.0, 1.0, 2.0]) - 2.0) < 1e-9, "奇数中位数")
	t.check(absf(Report.eco_median([1.0, 2.0, 3.0, 10.0]) - 2.5) < 1e-9, "偶数中位数取均")
	t.check(absf(Report.eco_median([])) < 1e-9, "空集中位数 = 0")

	# reset 清账(队列间不许串账 —— sim 每个队列 reset 一次)。
	rep.reset()
	t.eq(rep.eco_runs.size(), 0, "reset 清 eco_runs")
	t.eq(rep.eco.size(), 0, "reset 清当前账页")
	t.eq(rep.last_eco.size(), 0, "reset 清跨队列摘要")
