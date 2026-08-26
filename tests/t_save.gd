extends RefCounted

## 体力真闸门(2026-08-26 用户拍板「体力是开局扣一点」)—— core/save.gd 体力节的契约。
##
## ⚠ 测试自己是 `--script` 起的 = 探针:公开口(energy/spend_energy)在探针闸后
## **恒满恒放行**, 所以四条契约打的是**纯函数层**(_energy_in/_spend_in/…, 探针闸外、
## 不碰盘)—— 与 t_tutorial 的「探针不落盘」一节互补:那边锁闸, 这边锁算术。
## ⚠ 断言全部从 `energy_max()`(data/profile.json)推导, 不抄死上限数值 ——
## 上限是用户会直接手改的调参位(runner.gd 文件头的老教训)。

func run(t) -> void:
	var cap := SaveState.energy_max()
	t.check(cap >= 1, "体力上限至少 1(data/profile.json)—— 否则闸门把所有人锁在门外")
	var day := "2026-08-27"
	var next_day := "2026-08-28"

	# ---- ① 体力扣减 ----
	var d := {}
	t.check(SaveState._spend_in(d, 1, day, cap), "满值扣 1 成功")
	t.eq(SaveState._energy_in(d, day, cap), cap - 1, "扣完余额 = 上限 − 1")
	t.eq(String(d.get("energy_day", "")), day, "扣减盖上日期章(此后按日判回满)")

	# ---- ② 不足挡开局:spend 返回 false 且一点不扣 ----
	var e := {"energy": 0, "energy_day": day}
	t.check(not SaveState._spend_in(e, 1, day, cap), "0 点扣 1 被拒 —— _begin_run 收到 false 就不开局")
	t.eq(int(e["energy"]), 0, "被拒时余额一点不动(没有负数、没有部分扣)")
	var f := {"energy": 1, "energy_day": day}
	t.check(SaveState._spend_in(f, 1, day, cap), "正好剩 1 点仍能开最后一局(闸是「不够」不是「见底」)")
	t.check(not SaveState._spend_in(f, 1, day, cap), "扣到 0 之后下一局被拒")

	# ---- ③ 教学关不扣(口径:只有「新 run 的正式开局」扣;重开 = 新 run 照扣) ----
	# 消费端 = view/phrase.gd::_begin_run **唯一**入口(开局/重开同一份三步), 它调的是
	# spend_energy_for_run(run.tutorial);教学分支的唯一一份在 _spend_for_run_in, 这里锁它:
	# 0 体力也必须进得了教学关(「起」= 无惩罚地理解机制, 不该被任何资源挡住)。
	var g := {"energy": 0, "energy_day": day}
	t.check(SaveState._spend_for_run_in(g, true, day, cap), "教学关 0 体力也放行")
	t.eq(int(g["energy"]), 0, "教学放行一点不扣(字典原样)")
	t.check(not SaveState._spend_for_run_in(g, false, day, cap),
		"同一字典换成正式开局立刻被拒 —— 免扣只属于教学, 不是这条路恒放行")
	var g2 := {"energy": cap, "energy_day": day}
	t.check(SaveState._spend_for_run_in(g2, false, day, cap), "正式开局走同一口扣 1")
	t.eq(SaveState._energy_in(g2, day, cap), cap - 1,
		"……余额 −1(重开与开局同走 _begin_run 的这一口 = 重开照扣)")
	# 探针闸(公开口):测试自己就是探针, 锁「恒满恒放行」这半边。
	t.check(SaveState.spend_energy_for_run(false), "探针的正式局开局恒放行 —— 探针不许被机器本地状态挡住")
	t.eq(SaveState.energy(), cap, "探针读体力恒满(截图稳定, 与 t_tutorial 的探针闸同款)")

	# ---- ④ 旧存档无体力键 = 满值(别让老玩家更新完开局即卡) ----
	var legacy := {"seen_tutorial": true, "runs_total": 40, "runs_day": day, "runs_today": 3}
	t.eq(SaveState._energy_in(legacy, day, cap), cap,
		"旧档(只有 runs_today 推导键)读作满值 —— 不再从今日局数倒扣")
	t.check(SaveState._spend_in(legacy, 1, day, cap), "旧档第一次扣减照常成功")
	t.eq(SaveState._energy_in(legacy, day, cap), cap - 1, "扣完从满值起算")

	# ---- 跨天回满(既有恢复设计的唯一一条;更细的恢复归后续批) ----
	var h := {"energy": 0, "energy_day": day}
	t.eq(SaveState._energy_in(h, next_day, cap), cap, "隔天读 = 回满(energy_day 过期即视为满)")
	t.check(SaveState._spend_in(h, 1, next_day, cap), "隔天扣减从满值起算")
	t.eq(SaveState._energy_in(h, next_day, cap), cap - 1, "……扣完是上限 − 1")
	t.eq(String(h["energy_day"]), next_day, "日期章跟着推进")

	# ---- 上限封顶(将来看广告/手改存档都不许溢出) ----
	var big := {"energy": 999, "energy_day": day}
	t.eq(SaveState._energy_in(big, day, cap), cap, "存量超上限按上限读(封顶在读口, 写多少都不溢出)")

	# ---- 探针不落盘:公开口跑一遍, 盘上状态一个字节都没动(前后对比, 同 t_tutorial) ----
	var existed := FileAccess.file_exists(SaveState.PATH)
	var mtime := FileAccess.get_modified_time(SaveState.PATH) if existed else 0
	SaveState.spend_energy(1)
	SaveState.spend_energy_for_run(false)
	t.eq(FileAccess.file_exists(SaveState.PATH), existed, "探针 spend 不落盘:文件存在与否没变")
	if existed:
		t.eq(FileAccess.get_modified_time(SaveState.PATH), mtime, "探针 spend 不落盘:修改时间没动")
