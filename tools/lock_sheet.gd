extends SceneTree

## 「点唱片提前收工」的视觉验收(2026-08-13 用户拍板的交互)。NON-headless:
##   godot --path . --script res://tools/lock_sheet.gd
## 两张:_shot_lock_off(还不能收工 —— 唱片素颜)/ _shot_lock_on(armed —— 金环呼吸)。
## ⚠ armed 的三个条件都要造齐:决策态 + elapsed ≥ EARLY_LOCK_MIN + 动过至少一次手。

var _scene: Node
var _f := 0
var _staged := false

func _initialize() -> void:
	_scene = Shot.stage(self)

func _process(_d: float) -> bool:
	_f += 1
	if _f == 4:
		_scene.choose_character(1)
		return false
	if _f == 8 and _scene.intro != null and is_instance_valid(_scene.intro):
		_scene.intro._dismiss()
		return false
	if _f < 40:
		return false
	if not _staged:
		_staged = true
		var ids := ["shredder", "stopwatch", "momentum", "freeze"]   # 全套时机卡
		for i in range(4):
			var j = Joker.by_id(ids[i])
			_scene.run.joker_slots[i] = j
			_scene.joker_views[i].set_joker(j)
		# ① 还不能收工:时间没到下限, 也没动过手
		_scene.elapsed = 0.5
		_scene.last_action_time = -1.0
		_scene.vinyl.set_armed(_scene._can_early_lock(), maxf(0.0, _scene.cur_lock - _scene.elapsed))
		return false
	if _f == 46:
		Shot.save(self, "lock_off")
	elif _f == 50:
		# ② 可以收工:过了下限 + 动过手 → 金环该亮
		_scene.elapsed = 4.2
		_scene.last_action_time = 1.8
		_scene.vinyl.set_armed(_scene._can_early_lock(), maxf(0.0, _scene.cur_lock - _scene.elapsed))
	elif _f == 70:
		Shot.save(self, "lock_on")
		print("[lock] armed=%s (can=%s)" % [_scene.vinyl.armed, _scene._can_early_lock()])
		quit(0)
	return false
