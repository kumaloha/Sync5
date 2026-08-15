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
