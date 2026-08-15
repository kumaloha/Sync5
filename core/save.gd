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
## ⚠ 代价写明白:**教学关这条路径因此没有探针覆盖**。要覆盖就像 `tools/tutorsheet.gd`
## 那样**直接把 `run.tutorial` 按上去**, 别去依赖存档状态。
static func _is_probe() -> bool:
	return OS.get_cmdline_args().has("--script")


## 教学关看过没有。⚠ 读不到 / 解析失败 = false(当新玩家), 见文件头。
static func seen_tutorial() -> bool:
	if _is_probe():
		return true
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
## 荣誉页以 `resources/荣誉.dc.html` 为权威 · 首页用户明确否过加东西(「别加东西了」)。
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


static func _data() -> Dictionary:
	if _loaded:
		return _cache
	_loaded = true
	_cache = {}
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
