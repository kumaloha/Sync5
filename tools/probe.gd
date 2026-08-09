class_name Probe
extends SceneTree

## 实验骨架 —— 只解决一件事:**探针空转不再是静默的**。
##
## 本项目最贵的一类事故不是算错, 是**看起来跑完了**:GDScript 的运行时错误
## 不终止 `SceneTree` 脚本, `_initialize()` 在半路报错就直接返回, 末尾那句
## `quit()` 永远跑不到, 进程于是挂在主循环里空转 —— 退出码没有、输出截在半截,
## 而**截断的输出常常长得像正常输出**。CLAUDE.md 的「跑完必须确认退出码」这条
## 纪律就是为它加的, 但纪律靠人记, 记漏了没人喊。
##
## 这里把它变成机制:探针把工作全放在 `_initialize()` 里同步做完(本仓库所有
## 数值探针都是这个形状), 所以**主循环本该一帧都不转**。一旦转起来并且超过
## `watchdog_sec()`, 就是出事了 —— 喊出来并以 97 退出。
##
## ⚠ 计时从**第一帧**开始, 不是从进程启动开始:`_initialize()` 跑十分钟是正常的,
## 那期间主循环根本没在转, 看门狗一秒也没走。所以慢探针不需要调这个值。
## ⚠ 用 `_process` 的探针(截图那一类)不要继承它 —— 覆盖了 `_process` 就等于
## 关掉了看门狗, 而它们的循环本来就该转。截图探针走 `tools/shot.gd`。

const EXIT_STALL := 97

var _stall := 0.0


## 主循环允许空转多久。默认 20 秒 —— 探针在 `_initialize()` 里同步做完,
## 正常情况是 0 帧, 20 秒纯粹是给 quit() 生效留的余量。
func watchdog_sec() -> float:
	return 20.0


func _process(delta: float) -> bool:
	_stall += delta
	if _stall < watchdog_sec():
		return false
	push_error(("[probe] 主循环空转 %.0fs 仍未 quit() —— _initialize() 多半在半路报错了。"
		+ "往上翻找第一条 SCRIPT ERROR;输出到那里为止就是截断的, 别当结果用。") % _stall)
	printerr("[probe] STALLED — 见上面的 SCRIPT ERROR, 本次输出不完整")
	quit(EXIT_STALL)
	return true


## 读一个整数环境变量, 没设就用默认值。
static func env_int(key: String, def: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else def


## 读一个字符串环境变量, 没设就用默认值。
static func env_str(key: String, def := "") -> String:
	var v := OS.get_environment(key)
	return v if v != "" else def


## 开关型环境变量:只有 "1" 算开。
static func flag(key: String) -> bool:
	return OS.get_environment(key) == "1"
