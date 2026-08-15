extends RefCounted

## 教学关脚本的契约(design/difficulty.md §4 · core/tutorial.gd)。
## ⚠ 锁的是**结构**, 不是内容 —— 拍长多少、教哪几步是设计, 用户直接改 data/tutorial.json。
## 所以这里一个死数字都不抄:全部从 DB 推导(CLAUDE.md 的老教训 ——
## 抄死的断言等于给每次调参加一道无意义的返工)。

func run(t) -> void:
	var steps: Array = DB.tutorial()["steps"]
	t.eq(Tutorial.steps(), steps.size(), "steps() 跟着 data/tutorial.json 走")

	# --- 给时间:拍长必须收敛到正式局的 8 秒, 而且一路不回头 ---
	# ⚑ 这是教学关的主手段(新手的敌人是「8 秒内来不及想」), 所以它是契约不是装饰。
	var normal := GameConfig.phrase_duration(0)
	t.check(Tutorial.seconds(0) > normal, "第一拍比正式局长 —— 教学关的主手段是给时间")
	t.eq(Tutorial.seconds(steps.size() - 1), normal,
		"最后一拍已经收到正式局的拍长(过渡发生在教学关之内, 不留错误的肌肉记忆)")
	for i in range(1, steps.size()):
		t.check(Tutorial.seconds(i) <= Tutorial.seconds(i - 1),
			"第 %d 拍不比上一拍长 —— 拍长只收不放" % (i + 1))
	# ⚠ 越界返回正式拍长, 不是 0 —— 用 0 表达「没有这一拍」会让调用方的时钟静默停摆。
	t.eq(Tutorial.seconds(steps.size()), normal, "越界的拍长退回正式局, 不是 0")
	t.eq(Tutorial.seconds(-1), normal, "负数下标同上")

	# --- 部件:累积解锁, 走完全亮 ---
	var comps: Array = Tutorial.components()
	t.check(comps.size() > 0, "components 白名单非空")
	for i in range(steps.size()):
		var now: Array = Tutorial.unlocked(i)
		if i > 0:
			for c in Tutorial.unlocked(i - 1):
				t.check(now.has(c), "第 %d 拍仍然亮着上一拍已亮的 '%s'(解锁是累积的)" % [i + 1, c])
	var last: Array = Tutorial.unlocked(steps.size() - 1)
	for c in comps:
		t.check(last.has(c), "走完教学关 '%s' 已解锁 —— 否则它会一直是灰的(静默死锁)" % c)
	t.eq(Tutorial.unlocked(steps.size()).size(), comps.size(), "越界 = 全部解锁")
	t.check(Tutorial.is_unlocked(String(comps[0]), steps.size() - 1),
		"is_unlocked 与 unlocked 一致")

	# --- 提示行:两种文字都在, 英文守卡面那条 ≤7 词 ---
	for i in range(steps.size()):
		var h: Dictionary = Tutorial.hint(i)
		t.check(String(h["command"]) != "", "第 %d 拍有中文提示" % (i + 1))
		t.check(String(h["signal"]) != "", "第 %d 拍有英文短标" % (i + 1))
		t.check(String(h["signal"]).split(" ", false).size() <= 7,
			"第 %d 拍的英文短标 ≤7 词(与卡面同一条 1.5 秒规矩)" % (i + 1))
	t.eq(String(Tutorial.hint(steps.size())["command"]), "", "越界的提示是空串, 不是 null")

	# --- schema 门禁(结构错的脚本必须红) ---
	var ok := {"components": ["hand"],
		"steps": [{"seconds": 9.0, "unlock": ["hand"], "command": "中", "signal": "EN"}]}
	t.eq(DB.validate_tutorial(ok), "", "最小合法脚本通过(fixture 自检)")
	var dup := {"components": ["hand"], "steps": [
		{"seconds": 9.0, "unlock": ["hand"], "command": "中", "signal": "EN"},
		{"seconds": 8.0, "unlock": ["hand"], "command": "中", "signal": "EN"}]}
	t.check(DB.validate_tutorial(dup) != "", "同一个部件解锁两次被拒(unlock 是累积的, 第二次是死行)")
	var unknown := {"components": ["hand"],
		"steps": [{"seconds": 9.0, "unlock": ["nope"], "command": "中", "signal": "EN"}]}
	t.check(DB.validate_tutorial(unknown) != "", "解锁白名单外的部件被拒")
	var orphan := {"components": ["hand", "shop"],
		"steps": [{"seconds": 9.0, "unlock": ["hand"], "command": "中", "signal": "EN"}]}
	t.check(DB.validate_tutorial(orphan) != "", "有部件从没被解锁过被拒 —— 那是个静默死锁")
	var zero := {"components": ["hand"],
		"steps": [{"seconds": 0.0, "unlock": ["hand"], "command": "中", "signal": "EN"}]}
	t.check(DB.validate_tutorial(zero) != "", "拍长 <= 0 被拒")
	var wordy := {"components": ["hand"], "steps": [{"seconds": 9.0, "unlock": ["hand"],
		"command": "中", "signal": "one two three four five six seven eight"}]}
	t.check(DB.validate_tutorial(wordy) != "", "英文短标超过 7 词被拒")

	# --- 存档:探针一律当老玩家, 且绝不落盘 ---
	# ⚑ 这条锁的是 2026-08-15 那次真实事故(见 LESSONS 六):flow_probe 第一次跑走了
	# 教学关、撞破流程不变量、还把存档写了出来, 第二次就绿了 —— **同一棵树两次不同结果**。
	# ⚠ 测试自己就是 `--script` 起的, 所以这里断言的正是探针侧的行为。
	t.check(SaveState._is_probe(), "测试自身被认作探针(--script 起的)")
	t.check(SaveState.seen_tutorial(), "探针一律当老玩家 —— 否则每个从首页驱动的探针都会先走一遍教学关")
	SaveState.mark_tutorial_seen()
	SaveState.clear_tutorial()
	t.check(SaveState.seen_tutorial(), "探针里读写都是 no-op, clear 之后仍然是老玩家(没碰盘)")
	t.check(not FileAccess.file_exists(SaveState.PATH),
		"探针不落盘 —— 实验条件不许依赖机器本地状态")

	# --- Run 的教学关模式 ---
	var r := Run.new()
	r.reset(1)
	r.tutorial = true
	t.eq(r.target(), 0, "教学关目标分恒 0 = 不判生死(起 = 无惩罚)")
	# ⚑ **顺序无关**:这里刻意在 `reset()`(它内部就掷了脸)**之后**才设 `tutorial` ——
	# 第一版契约是「必须先设 tutorial 再 roll_faces」, 而我写完不到一小时就在这条测试里
	# 自己违反了它。**一条我自己都记不住的顺序契约是个坏契约**, 于是 `face()` 也挡一道。
	t.eq(r.face(), "", "教学关没有 Boss 脸 —— 挂一张 Boss 规则直接违背「安全地理解机制」")
	var r2 := Run.new()
	r2.tutorial = true
	r2.reset(1)
	t.eq(r2.run_faces, {}, "先设 tutorial 再 reset:连掷都不掷(提前返回, 省一次掷点)")
	t.eq(r2.face(), "", "两种顺序结果一致 —— 正确性不依赖调用顺序")
	t.eq(r.phrase_duration(), Tutorial.seconds(0), "教学关拍长走脚本, 不走 gig_clocks")
	t.check(r.tutorial_unlocked(String(comps[0])), "第一步已解锁的部件是开的")
	t.check(not r.tutorial_done(), "第 0 拍还没走完")
	r.phrase_in_section = Tutorial.steps()
	t.check(r.tutorial_done(), "走满脚本步数 = 教学关结束")
	# ⚠ 正式局必须**逐字节不受影响** —— 这是「加功能不许改既有行为」的机器可读版本。
	var n := Run.new()
	n.reset(1)
	t.check(n.target() > 0, "正式局仍有目标分")
	t.check(not n.run_faces.is_empty(), "正式局照常掷脸")
	t.eq(n.phrase_duration(), Run.phrase_duration_for(0, n.face()), "正式局拍长仍走原口")
	t.check(n.tutorial_unlocked("multiselect"), "正式局所有部件恒解锁")
	t.eq(String(n.tutorial_hint()["command"]), "", "正式局没有提示行")
