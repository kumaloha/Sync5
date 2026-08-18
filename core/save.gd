class_name SaveState
extends RefCounted

## 跨局存档 —— **目前只存一件事:教学关看过没有。**
##
## ⚑ 为什么单开一个文件而不是往 `Run` 上挂:TODO 里挂着的**断点续玩**
## (移动 Web 刚需 —— iOS 内存回收重载后局面全丢)需要的是**同一个存档层**。
## 两件事各写一份 `user://` 读写, 就是这个项目已经踩过四次的形状
## (「一拍」抄 6 份、「一局」抄 14 份、「一次实验」抄 32 处、「一局四张脸」抄 7 份)。
## **所以这里从第一天就是唯一入口, 断点续玩往上加键即可。**
##
## ⚠ 放在 `core/` 但**碰了文件系统** —— 这不违反「core 引擎无关」那条:它说的是
## 不含时钟、不 import view、不认识游戏对象以外的东西。`core/tape.gd` 早有同样的先例
## (它按 `tape.json` 的 `to_file`/`dir` 落盘)。
## ⚠ **读失败一律当「新玩家」**, 不抛错 —— 与 `core/db.gd` 的取舍同源:
## 存档坏掉只该让人多看一次教学, 不该让人开不了机。

const PATH := "user://sync5.save.json"

static var _cache: Dictionary = {}
static var _loaded := false


## ⚑⚑ **探针一律当「老玩家」, 而且绝不落盘。**
##
## 起因是一次真实事故(2026-08-15, 当天就抓到):`tools/flow_probe.gd` 通过
## `_on_home_start()` + `choose_character()` 驱动游戏 —— 那正是教学关的入口。
## 于是 **第一次跑**(机器上没有存档)走教学关、撞破流程不变量报 `1 bugs`,
## **而它自己把存档写了出来**, 第二次跑就绕开教学关报 `0 bugs`。
## **同一棵树两次不同结果, 而差别藏在 `~/Library/.../user://` 里。**
##
## ⚠ 这不是 flaky, 是**实验条件静默地依赖了机器本地状态** —— 新机器/CI 与跑过一次的
## 机器结论不同, 且 `gate.sh` 会变成有顺序依赖的。这个项目对这种形状的判决一向很硬:
## **一道靠运气变绿的门和一道永远红的门一样没用。**
##
## 判据用 `--script`:**每个探针都是 `godot --script res://tools/xxx.gd` 起的,
## 而真游戏是 `godot --path .`(主场景)** —— 一个显式、可 grep、不会被忘掉的分界。
## ⚠ 代价写明白:**教学关这条路径缺省没有探针覆盖**。要覆盖就设 `SYNC5_PROBE_FRESH=1`
## (见 seen_tutorial 的口子, 2026-08-18)—— 它让探针走真人同款入口, 且仍不碰存档。
## ~~直接把 run.tutorial 按上去~~ 已废弃:按晚了会拿到「教学关冒出 BOSS 脸」的错位假象。
static func _is_probe() -> bool:
	return OS.get_cmdline_args().has("--script")


## 教学关看过没有。⚠ 读不到 / 解析失败 = false(当新玩家), 见文件头。
##
## ⚑ 探针缺省当「看过」(不进教学关), **`SYNC5_PROBE_FRESH=1` 时当新玩家**(2026-08-18)——
## 教学关真路径探针要走和真人一样的入口(公示卡闸/掷脸的教学分支/步进都在 choose_character
## 里按 seen_tutorial 分岔), 在编排器外面手按 `run.tutorial` 的探针拿到的是错位的假象
## (交接里两次「教学关截图冒出 BOSS 脸」正是按晚了)。⚠ 只影响这一个读数,
## 券/存档的探针闸不动 —— 教学关本来就不该依赖它们。
static func seen_tutorial() -> bool:
	if _is_probe():
		return OS.get_environment("SYNC5_PROBE_FRESH") != "1"
	return bool(_data().get("seen_tutorial", false))


## 记下「教学关已看过」并落盘。⚠ 幂等 —— 重复调用不会写第二遍。
static func mark_tutorial_seen() -> void:
	if _is_probe() or seen_tutorial():
		return
	_data()["seen_tutorial"] = true
	_flush()


## 「重看教学」—— 清掉标记, 下一局就会再进一次教学关。
##
## ⚠⚠ **UI 上还没有入口, 这是有意的**(2026-08-15):三个可能的落点全都是用户的地盘 ——
## 页签轨的几何锁死在「四屏单源」(`Chrome.TAB_W = (672-88)/4`, 加第 5 个会改动全部四个)·
## 荣誉页以 `docs/mockups/荣誉.dc.html` 为权威 · 首页用户明确否过加东西(「别加东西了」)。
## **放哪是口味决定, 不该由我替他拍**, 所以先只留机制:接到哪个按钮上都是一行。
## ⚠ 用户对这件事本身的判断是「**教一把就会了**」—— 所以别默认它一定要有入口。
static func clear_tutorial() -> void:
	if _is_probe():
		return
	_data().erase("seen_tutorial")
	_flush()


## ⚑⚑ **会话边界**(TODO 的 D4)—— 目标函数换成留存之后,**这是唯一能直接观测目标的量**,
## 其余全是代理指标。它必须长在存档层上, 因为「隔多久回来」**跨应用启动**才有意义。
##
## 每次启动调一次, 返回 `{"id": 第几次坐下, "gap": 距上次多少秒, "runs_prev": 历史总局数}`,
## 并就地把 `last_seen` / `sessions` 推进。调用方(编排器)把它塞进 `Tape.begin` 的 meta,
## 于是「**一次坐下玩了几局**」= 按 `id` 分组数局数,「**隔多久回来**」= `gap`。
##
## ⚠ **口径铁律:只记事实, 不记特征**(2026-08-06 用户拍板)。所以这里记的是
## 「距上次 N 秒」这个**事实**, 不是「这是个回流玩家」这种**特征** —— 特征会迭代, 分析侧自己去读。
## ⚠ 首次启动 `gap = -1`(没有上一次, 不是「间隔 0」—— 那是两件事)。
## ⚠ 探针返回 `id = -1` 且不落盘, 分析侧照这个过滤(同 `_is_probe` 那条)。
static func session_start() -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	if _is_probe():
		return {"id": -1, "gap": -1, "runs_prev": 0}
	var d := _data()
	var last := int(d.get("last_seen", 0))
	var out := {
		"id": int(d.get("sessions", 0)) + 1,
		"gap": -1 if last <= 0 else maxi(0, now - last),
		"runs_prev": int(d.get("runs_total", 0)),
	}
	d["sessions"] = out["id"]
	d["last_seen"] = now
	_flush()
	return out


## 一局开始时推进「历史总局数」并盖上时间戳 —— `last_seen` 每局都刷, 这样
## 「隔多久回来」量的是**离开游戏**到**回来**, 而不是从上次启动算起。
## ⚠ 幂等性不做要求:它就是个计数器, 每局一次。
## 历史总局数(不含正在开的这一局)。⚑ **键早就有了** —— `note_run_started()` 一直在写,
## `session_start()` 一直当 `runs_prev` 读出来, 缺的只是一个公开的口(2026-08-16 补)。
## ⚠ 「这是第几局」= `runs_total() + 1`, 因为掷脸发生在 `note_run_started()` **之前**。
static func runs_total() -> int:
	return int(_data().get("runs_total", 0))


## ---- 券(消耗品层)· 2026-08-16 ----
##
## ⚑ 存两个键:`tickets` = {券 id: 张数} · `tickets_day` = 上次结算是第几天。
## **每次读都先结算「今天是不是新的一天」** —— 不靠任何定时器, 因为玩家可能几天不开。
##
## ⚠⚠ **清零只清 `tickets`, 绝不碰别的键。** `runs_total` 是 `min_run`(禁回第 10 局解锁)
## 的依据, 教学关标记也在同一个字典里 —— 顺手 `clear()` 会把解锁进度一起清掉,
## 而那种 bug 只有玩了十局的人才发现得了。
##
## ⚠ 探针一律**没有券也不落盘**(同本文件其余六道闸):券是玩家的日常状态,
## 让探针拿到它就等于让实验条件依赖「这台机器今天领没领」。


## 今天的券。⚠ 会**顺带结算过期**并落盘(所以它不是纯读)。
## ⚑ 逻辑在 `Ticket` 的纯函数里, 这里只负责**盘 + 时钟 + 探针闸**三件不可测的事。
static func tickets() -> Dictionary:
	# ⚑ `not Ticket.enabled()` = 1.0 不上券的总闸(数据开关, 五个入口同一句)——
	# 关掉唯一进水口后其余路径本就死水, 连读口一起闸是为了让**存档里已有的券也隐身**。
	if _is_probe() or not Ticket.enabled():
		return {}
	var d := _data()
	if Ticket.reset_if_new_day(d, Ticket.day_index(int(Time.get_unix_time_from_system()))):
		_flush()
	return d.get("tickets", {})


## 每天第一次打开时结算发放。返回发到的券 id(空串 = 今天已领 / 满仓 / 探针)。
## ⚠ 调用方 = 编排器启动时一次(同 `session_start`), 别在别处调。
static func settle_daily_ticket() -> String:
	if _is_probe() or not Ticket.enabled():
		return ""
	var d := _data()
	var today := Ticket.day_index(int(Time.get_unix_time_from_system()))
	Ticket.reset_if_new_day(d, today)          # 先清过期, 再发今天的
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var got := Ticket.settle_daily_grant(d, today, rng)
	_flush()
	return got


static func tickets_held(tid: String) -> int:
	return int(tickets().get(tid, 0))


## 发一张券(看广告/每日领取的出口)。返回实际发到的张数。
static func grant_ticket(tid: String, n: int = 1) -> int:
	if _is_probe() or not Ticket.enabled():
		return 0
	tickets()                      # ← 顺带结算跨天
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var got := Ticket.grant_with_roll(_data(), tid, n, rng)
	if got > 0:
		_flush()
	return got


## 队首掷值(boost 的「下一张是 ×几」)。UI 展示与使用前的确认都读这里。
static func ticket_roll(tid: String) -> float:
	if _is_probe() or not Ticket.enabled():
		return 0.0
	return Ticket.peek_roll(_data(), tid)


## 用掉一张。返回是否真的用掉了。
## ⚑ 掷值与张数**必须同步弹**(FIFO)—— 只减张数不弹值, 下一张会「继承」用掉那张的值。
static func consume_ticket(tid: String) -> bool:
	if _is_probe() or not Ticket.enabled():
		return false
	var held := tickets()
	if not Ticket.consume_from(held, tid):
		return false
	_data()["tickets"] = held
	Ticket.pop_roll(_data(), tid)
	_flush()
	return true


## 当前主角(2026-08-18 用户拍板:「不要在局内开局选角色, 在角色页面选了谁就是谁」)。
## 角色页每次点选即落盘;开局直接读这里, 局内选角屏(PickWalker)从流程上退役。
## ⚠ 探针返回 1 —— 历史上所有探针都 choose_character(1), 探针世界保持逐字节不变。
static func hero() -> int:
	if _is_probe():
		return 1
	return int(_data().get("hero", 0))


static func set_hero(i: int) -> void:
	if _is_probe():
		return
	_data()["hero"] = i
	_flush()


static func note_run_started() -> void:
	if _is_probe():
		return
	var d := _data()
	d["runs_total"] = int(d.get("runs_total", 0)) + 1
	d["last_seen"] = int(Time.get_unix_time_from_system())
	_flush()


## ⚠ 只给测试用:把内存态清掉并重读。**不删盘上的文件** ——
## 测试误删玩家存档是一种很贵的意外。
static func _reset_cache_for_tests() -> void:
	_cache = {}
	_loaded = false


## ⚑ **`-- --fresh` = 这次启动当新玩家**(2026-08-16 用户要一条「按这个命令启动就去掉存档」)。
##
## ⚠ **用 `--` 之后的用户参数, 不是 `OS.get_cmdline_args()`** —— 后者混着 Godot 自己的
## 参数, 塞个它不认识的进去要看引擎脸色;`--` 之后的部分引擎保证原样交给游戏。
## ⚑ **删盘上的文件, 不是只清内存** —— 只清内存的话这一局结束照样写回去,
## 下次启动又跳过教学关, 「去掉存档」就成了一句没兑现的话。
## ⚠ 它**只在这里生效一次**(`_loaded` 守着), 所以同一次运行里后面的读写照常。
static func _wants_fresh() -> bool:
	return OS.get_cmdline_user_args().has("--fresh")


static func _data() -> Dictionary:
	if _loaded:
		return _cache
	_loaded = true
	_cache = {}
	if _wants_fresh():
		if FileAccess.file_exists(PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
		print("[SaveState] --fresh:已清空存档, 这次按新玩家跑(会进教学关)")
		return _cache
	if not FileAccess.file_exists(PATH):
		return _cache
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return _cache
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_cache = parsed
	return _cache


static func _flush() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveState: 写不了 %s —— 教学关会重复出现, 但不影响游戏" % PATH)
		return
	f.store_string(JSON.stringify(_cache))
	f.close()
