class_name Ads
extends Node

## 激励视频适配层(2026-09-08, 规格 docs/superpowers/specs/2026-09-08-ads-design.md §4.1)。
## 对外只有三件事:**有没有货(has_ad)/ 放(show_ad)/ 回调发奖(rewarded 信号)**。
## 游戏其余部分只认这三个方法三个信号;插件 API 只许出现在 view/admob.gd 里。
##
## 后端选一次(_ready, 见 pick_mode_for —— 纯函数, 测试直打):
##   · 显式 `SYNC5_ADS=off|fake|fail|dismiss` **最优先**(adsprobe 用 fake 驱动真流;off = 离线玩家看到的游戏);
##   · 探针(SaveState.is_probe)缺省 **off** —— 探针日志与截图零广告痕迹(两台机器的日志必须长一样);
##   · Android 且插件在(res://addons/admob/plugin.cfg)—— view/admob.gd(动态查类, 桌面不解析它);
##   · 其余 = fake:show 下一帧发奖(桌面点着玩)。
## ⚠ 回调一律 call_deferred 回主线程再发信号(Godot 4 非主线程不得 emit_signal)。
## ⚠ 方法不叫 preload / show —— 前者是 GDScript 关键字, 后者与 CanvasItem 撞名。

signal rewarded(kind: String)
signal failed(kind: String, why: String)
signal closed(kind: String)

const KINDS := ["coins", "energy"]
const ADMOB_PLUGIN_CFG := "res://addons/admob/plugin.cfg"
const ENV_MODES := ["off", "fake", "fail", "dismiss"]

var _mode := "fake"          # off | fake | fail | dismiss | admob
var _backend = null          # view/admob.gd 实例(只在 admob 模式非空)


func _ready() -> void:
	_mode = pick_mode_for(SaveState.is_probe(), OS.get_environment("SYNC5_ADS"),
		OS.has_feature("android") and ResourceLoader.exists(ADMOB_PLUGIN_CFG))
	if _mode == "admob":
		_backend = load("res://view/admob.gd").new()
		add_child(_backend)
		_backend.rewarded.connect(func(k: String) -> void: rewarded.emit(k))
		_backend.failed.connect(func(k: String, why: String) -> void: failed.emit(k, why))
		_backend.closed.connect(func(k: String) -> void: closed.emit(k))


## 模式选择的算术(纯函数):显式环境变量 > 探针 off > android+插件 admob > fake。
static func pick_mode_for(probe: bool, env: String, android_plugin: bool) -> String:
	if ENV_MODES.has(env):
		return env
	if probe:
		return "off"
	if android_plugin:
		return "admob"
	return "fake"


func mode() -> String:
	return _mode


func has_ad(kind: String) -> bool:
	if not KINDS.has(kind):
		return false
	if _mode == "admob":
		return _backend.has_ad(kind)
	return _mode != "off"


func load_ad(kind: String) -> void:
	if _mode == "admob":
		_backend.load_ad(kind)


func show_ad(kind: String) -> void:
	if not has_ad(kind):
		failed.emit(kind, "not_ready")
		return
	if _mode == "admob":
		_backend.show_ad(kind)
		return
	call_deferred("_fake_finish", kind)


## 假后端的一次播放:按模式收尾(与真后端同序:先奖后关)。测试直打, 不等帧。
func _fake_finish(kind: String) -> void:
	match _mode:
		"fail":
			failed.emit(kind, "fake")
		"dismiss":
			pass
		_:
			rewarded.emit(kind)
	closed.emit(kind)
