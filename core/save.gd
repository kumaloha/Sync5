class_name SaveState
extends RefCounted

## 跨局存档 —— 教学标记 · 会话/局数 · 语言 · install_id · 玩家状态 m(战绩/见过的脸)。
## (2026-08-24 局外 build 整体删除:券/主角/宝石/资产/终身计数键全部退役,
## 留下的只有局内玩法依赖的跨局事实:教学一次性、Director 的 ctx 原料、会话边界、语言。)
## 写盘 = 原子写 + .bak + 版本键 `v`(见 _flush / _migrate)。
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
## `_on_home_start()` + `start_run()` 驱动游戏 —— 那正是教学关的入口。
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


## 公开读口(view 的纯表现分支用:盲注特写这类动画, 探针不该等)。
static func is_probe() -> bool:
	return _is_probe()


## 教学关看过没有。⚠ 读不到 / 解析失败 = false(当新玩家), 见文件头。
##
## ⚑ 探针缺省当「看过」(不进教学关), **`SYNC5_PROBE_FRESH=1` 时当新玩家**(2026-08-18)——
## 教学关真路径探针要走和真人一样的入口(公示卡闸/掷脸的教学分支/步进都在 start_run
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
## 首页用户明确否过加东西(「别加东西了」)。
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
	_session_gap = int(out["gap"])   # 回归局判定的原料(returning_run)
	_session_runs = 0
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


## 本机安装 id(1.1 回传)。随机生成一次, 从此不变 —— 只用来把同一台机器的局串起来
## (会话边界 D4 的分母), 不含任何 PII。探针恒 "probe":探针日志本来就不该混进真人数据,
## 万一探针闸漏了, 服务端还能按这个字段兜底过滤。
static func install_id() -> String:
	if _is_probe():
		return "probe"
	var d := _data()
	if not d.has("install_id"):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		d["install_id"] = "%08x%08x" % [rng.randi(), rng.randi()]
		_flush()
	return String(d["install_id"])


## ---- 玩家状态 m(1.1, 2026-08-19)----
## m = generating.md §3 的玩家状态向量, 这里存它的两个切片:近期战绩(streak 的原料)
## 与 faces_seen(新鲜感 N 的原料)。**消费端是 Director 的 ctx 入参** —— core 纯逻辑
## 不偷读存档(min_run 那条铁律), 由编排器在开局时取这里的读数传进去。

## 近期战绩, 定长 20 圈。每条只记两件事实:赢没赢 · 死在第几段(-1 = 通关)。
static func run_history() -> Array:
	if _is_probe():
		return []
	return _data().get("history", [])


## 连胜为正 / 连败为负, 从最近一局往回数。
static func streak() -> int:
	var h := run_history()
	var s := 0
	for i in range(h.size() - 1, -1, -1):
		var w := bool(h[i].get("w", false))
		if s == 0:
			s = 1 if w else -1
		elif s > 0 and w:
			s += 1
		elif s < 0 and not w:
			s -= 1
		else:
			break
	return s


## {face_id: 见过几次}。「见过」= 那一段真的打到了(或作为下一场被预告)。
static func faces_seen() -> Dictionary:
	if _is_probe():
		return {}
	return _data().get("faces_seen", {})


static func boons_seen() -> Dictionary:
	if _is_probe():
		return {}
	return _data().get("boons_seen", {})


## {target_id: 用它打完几局}(构筑倾向 —— 探索型货架的分母, context.md 岔 #1)。
static func targets_used() -> Dictionary:
	if _is_probe():
		return {}
	return _data().get("targets_used", {})


## 回归局:这个会话隔了很久才回来, 而且是回来后的**第一局**。
## ⚠ 读的时机必须在 note_run_started 之前(_feed_director 正是), 否则永远 false。
## 隔几天算「回来」:data/director.json `context_tuning.return_gap_days`(口味值, 等留存数据再校)。

static var _session_gap := -1
static var _session_runs := 0

static func returning_run() -> bool:
	if _is_probe():
		return false
	return _session_gap >= Director.return_gap_s() and _session_runs == 0


## 一局收尾的跨局记账(成败两条路都走这一个口):
## 战绩入圈 + faces_seen 累计 —— **全部是 Director ctx 的原料**, 不再有任何货币。
## (2026-08-24 局外 build 删除:宝石收入/终身计数原在这里, 已连系统一起退役。)
## 探针绝不落盘。
static func settle_run_meta(won: bool, sections_cleared: int, faces: Array,
		boon: String = "", target_id: String = "") -> void:
	if _is_probe():
		return
	var d := _data()
	var h: Array = d.get("history", [])
	h.append({"w": won, "d": -1 if won else sections_cleared})
	while h.size() > 20:
		h.pop_front()
	d["history"] = h
	# 累计通关段数 = 首页 EXP 的原料(参与度口径:失败也算打过的段)。
	d["sections_total"] = int(d.get("sections_total", 0)) + maxi(0, sections_cleared)
	var fs: Dictionary = d.get("faces_seen", {})
	for f in faces:
		var s := String(f)
		if s != "":
			fs[s] = int(fs.get(s, 0)) + 1
	d["faces_seen"] = fs
	if boon != "":
		var bs: Dictionary = d.get("boons_seen", {})
		bs[boon] = int(bs.get(boon, 0)) + 1
		d["boons_seen"] = bs
	if target_id != "":
		var tu: Dictionary = d.get("targets_used", {})
		tu[target_id] = int(tu.get(target_id, 0)) + 1
		d["targets_used"] = tu
	_flush()


## 语言覆写(1.1 英文化)。"" = 没设过, 跟系统语言走(解析顺序在 core/lingo.gd 文件头)。
## ⚠ 探针不读存档语言 —— Lingo 在 SaveState 之前就把探针钉死在 cn 了, 这里只兜真人。
static func lang() -> String:
	if _is_probe():
		return ""
	return String(_data().get("lang", ""))


## 给未来设置页的口(UI 还没有)。写 "" = 清覆写, 回到跟系统语言走。
static func set_lang(l: String) -> void:
	if _is_probe():
		return
	if l == "":
		_data().erase("lang")
	else:
		_data()["lang"] = l
	_flush()
	Lingo.force("")   # 清语言缓存, 下次 lang() 重新解析


static func note_run_started() -> void:
	if _is_probe():
		return
	_session_runs += 1
	var d := _data()
	d["runs_total"] = int(d.get("runs_total", 0)) + 1
	# 今日局数(体力显示的分母)。跨天第一局先清零再计 —— 不靠定时器, 玩家可能几天不开。
	if String(d.get("runs_day", "")) != _day_key():
		d["runs_day"] = _day_key()
		d["runs_today"] = 0
	d["runs_today"] = int(d.get("runs_today", 0)) + 1
	d["last_seen"] = int(Time.get_unix_time_from_system())
	_flush()


## ---- 首页顶栏(2026-08-24 用户:「顶部保持样式 · 体力可以存在 · 金币/宝石去掉」)----
##
## ⚑⚑ **体力目前只显示、不拦人**:它 = `energy_max − 今日已开局数`(每天回满),
## 是从真实局数**推导**的余额, 不是独立资源 —— 没有假进度(08-22「首页数字全真」拍板)。
## 要不要用它拦开局、拦了怎么回(等时间/看广告/买), 全归用户拍;在那之前局内玩法不受它影响。
## ⚠ 探针恒满且不落盘(截图稳定, 实验条件不依赖机器本地状态 —— 本文件的一贯闸)。

static func energy_max() -> int:
	return int(DB.profile().get("energy_max", 5))


static func energy() -> int:
	if _is_probe():
		return energy_max()
	var d := _data()
	if String(d.get("runs_day", "")) != _day_key():
		return energy_max()
	return maxi(0, energy_max() - int(d.get("runs_today", 0)))


## 参与度等级(EXP = 累计通关段数, 不挂分数)。返回 {level, xp, xp_max}。
## 探针 = 新玩家同值(LV.1 · 0/x)。
static func profile() -> Dictionary:
	var per := maxi(1, int(DB.profile().get("xp_per_level", 4)))
	var xp := 0 if _is_probe() else int(_data().get("sections_total", 0))
	return {"level": xp / per + 1, "xp": xp % per, "xp_max": per}


## 本地日历日(体力/今日局数的跨天判据)。用本地时区 —— 「新的一天」对玩家是本地半夜。
static func _day_key() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [int(t["year"]), int(t["month"]), int(t["day"])]


## ---- 断点续玩(2026-08-24 用户:「没有断点续玩」)----
## 快照内容由 core/run.gd 组装(纯事实);这里只管盘 + 探针闸。
## ⚠ 探针不存不读:恢复路径依赖机器本地状态, 正是探针纪律要挡的形状(flow_probe 事故同款)。
static func checkpoint() -> Dictionary:
	if _is_probe():
		return {}
	return _data().get("resume", {})


static func save_checkpoint(d: Dictionary) -> void:
	if _is_probe():
		return
	_data()["resume"] = d
	_flush()


static func clear_checkpoint() -> void:
	if _is_probe():
		return
	if _data().has("resume"):
		_data().erase("resume")
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
	var parsed = _read_json(PATH)
	# 主档坏了(半截 JSON / 非对象)退回 .bak —— 两份都坏才当新玩家
	if not parsed is Dictionary:
		parsed = _read_json(BAK_PATH)
		if parsed is Dictionary:
			push_warning("[SaveState] 主存档损坏, 已从 .bak 恢复")
	if parsed is Dictionary:
		_cache = _migrate(parsed)
	return _cache


static func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed


## 存档格式版本(2026-08-21 审查加版本键;v2 = 2026-08-24 局外 build 删除, 清退役键)。
## 读到更高版本 = 别的构建写的, 照读不丢;读到更低版本 = 走 _migrate 逐级升。
const SAVE_VERSION := 2
const BAK_PATH := "user://sync5.save.bak.json"


## 原子写:先写 .tmp 再 rename 盖上去;盖之前把上一份挪成 .bak。
## 断电/崩溃落在任一步, 盘上要么是完整的旧档要么是完整的新档, 不会是半截 JSON。
static func _flush() -> void:
	_cache["v"] = SAVE_VERSION
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SaveState: 写不了 %s —— 教学关会重复出现, 但不影响游戏" % tmp)
		return
	f.store_string(JSON.stringify(_cache))
	f.close()
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	if dir.file_exists(PATH.get_file()):
		dir.rename(PATH.get_file(), BAK_PATH.get_file())
	dir.rename(tmp.get_file(), PATH.get_file())


## 逐级迁移(每段只负责 n → n+1)。
static func _migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("v", 0))
	if v < 1:
		d["v"] = 1   # v0 = 08-21 前的无版本档, 键形状与 v1 相同
	if v < 2:
		# v2(2026-08-24):局外 build 整体删除 —— 券/主角/宝石/资产的键清掉,
		# 免得死键在存档里一直背着。留下的键(教学/会话/战绩圈/faces_seen/语言)原样。
		# ⚠ `sections_total` **不清**:同日用户要回顶栏 EXP, 它就是原料, 老档进度直接接上。
		for k in ["tickets", "tickets_day", "grant_day", "ticket_rolls",
				"hero", "gems", "assets", "wins_total"]:
			d.erase(k)
		d["v"] = 2
	return d
