class_name Ads
extends Node

## 激励视频适配层(2026-09-08, 规格 docs/superpowers/specs/2026-09-08-ads-design.md §4.1)。
## 对外只有三件事:**有没有货(has_ad)/ 放(show_ad)/ 回调发奖(rewarded 信号)**。
## 游戏其余部分只认这三个方法与它的信号;插件 API 只许出现在 view/admob.gd 里。
## ⚑ 外加一个**到货**信号 `loaded`(2026-09-09):has_ad 是拉, 它是推 —— 见下。
##
## 后端选一次(_ready, 见 pick_mode_for —— 纯函数, 测试直打):
##   · 显式 `SYNC5_ADS=off|fake|fail|dismiss` **最优先**(adsprobe 用 fake 驱动真流;off = 离线玩家看到的游戏);
##   · 探针(SaveState.is_probe)缺省 **off** —— 探针日志与截图零广告痕迹(两台机器的日志必须长一样);
##   · Android 且插件在(**按全局类表查 RewardedAdLoader**, 见 has_plugin_class)—— view/admob.gd(动态查类, 桌面不解析它);
##   · 其余:debug 构建 = fake(桌面点着玩, show 下一帧发奖), **导出的正式包 = off** ——
##     没有真广告就绝不发奖(2026-09-08 质量审查:探测写错时真机会静默落到假后端白发奖)。
## ⚠ 回调一律 call_deferred 回主线程再发信号(Godot 4 非主线程不得 emit_signal)。
## ⚠ 方法不叫 preload / show —— 前者是 GDScript 关键字, 后者与 CanvasItem 撞名。

signal rewarded(kind: String)
signal failed(kind: String, why: String)
signal closed(kind: String)
## 到货 —— **推**给调用方(2026-09-09 审查抓的):`has_ad` 只回答「此刻有没有」, 而 Android 上
## 它是异步变真的(load + 退避重试)⇒ 只在进店那一刻问一次的界面永远等不到那批货。
signal loaded(kind: String)

const KINDS := ["coins", "energy"]
const ENV_MODES := ["off", "fake", "fail", "dismiss"]

var _mode := "fake"          # off | fake | fail | dismiss | admob
var _backend = null          # view/admob.gd 实例(只在 admob 模式非空)


func _ready() -> void:
	var admob_ready := OS.has_feature("android") and has_plugin_class("RewardedAdLoader")
	_mode = pick_mode_for(SaveState.is_probe(), OS.get_environment("SYNC5_ADS"),
		admob_ready, OS.is_debug_build())
	if _mode == "admob":
		_backend = load("res://view/admob.gd").new()
		add_child(_backend)
		_backend.rewarded.connect(func(k: String) -> void: rewarded.emit(k))
		_backend.failed.connect(func(k: String, why: String) -> void: failed.emit(k, why))
		_backend.closed.connect(func(k: String) -> void: closed.emit(k))
		_backend.loaded.connect(func(k: String) -> void: loaded.emit(k))


## 插件在不在 = 它的脚本类进了全局类表(导出包里也在;`.cfg` 文件用 ResourceLoader.exists 探测恒 false —— 09-08 质量审查抓到)
static func has_plugin_class(cls_name: String) -> bool:
	for c in ProjectSettings.get_global_class_list():
		if String(c["class"]) == cls_name:
			return true
	return false


## 模式选择的算术(纯函数):显式环境变量 > 探针 off > 插件在 admob > debug 才 fake, 否则 off。
## ⚠ 最后那一档是**导出包不许假发奖**:没有真广告就什么都不给, 白发奖比不给钱贵得多。
static func pick_mode_for(probe: bool, env: String, admob_ready: bool, debug: bool) -> String:
	if ENV_MODES.has(env):
		return env
	if probe:
		return "off"
	if admob_ready:
		return "admob"
	return "fake" if debug else "off"


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
		return
	# ⚑ 假后端本来就"有货", 但它也发一次 loaded —— **桌面必须走一遍编排器的补上架那条路**,
	#   否则那条路只有真机才执行, 而真机是最难看见问题的地方(2026-09-09 审查)。
	if has_ad(kind):
		_fake_loaded.call_deferred(kind)


func show_ad(kind: String) -> void:
	if not has_ad(kind):
		failed.emit(kind, "not_ready")
		return
	if _mode == "admob":
		_backend.show_ad(kind)
		return
	_fake_finish.call_deferred(kind)


## 假后端的一次到货(与 `_fake_finish` 同款:测试直打, 不等帧)。
func _fake_loaded(kind: String) -> void:
	loaded.emit(kind)


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
