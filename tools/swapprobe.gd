extends SceneTree

## 二连换探针(2026-08-18 用户:「教学时好几轮只能换一张」)。NON-headless:
##   godot --path . --script res://tools/swapprobe.gd
## 走**编排器的完整视图路径**(_on_hand_swap ×3), 分清「规则层限制」还是「触控层丢手势」。

var _frames := 0
var _scene: Node


func _initialize() -> void:
	OS.set_environment("SYNC5_PROBE_FRESH", "1")
	_scene = Shot.stage(self)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 4:
		_scene.choose_character(1)
		return false
	if _frames < 120:
		return false
	if _frames == 120:
		# 摆到第 3 步(交换步)再连换三次 —— 中间隔帧, 模拟真实节奏
		_scene.run.tutorial_step = 2
		_scene._start_phrase()
	elif _frames in [130, 140, 150]:
		var before: int = _scene.phrase.swap_actions_used
		_scene._on_hand_swap(0, 0)
		var after: int = _scene.phrase.swap_actions_used
		print("swap #%d: used %d -> %d  step=%d  %s" % [
			(_frames - 120) / 10, before, after, _scene.run.tutorial_step,
			"OK" if after == before + 1 else "❌ 被挡"])
	elif _frames == 160:
		print("done: swap_actions_used=%d(逻辑层若=3, 手机上的「只能换一张」在触控层)"
			% _scene.phrase.swap_actions_used)
		return true
	return false
