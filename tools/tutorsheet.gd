extends SceneTree

## 教学关的目视对账探针(design/difficulty.md §4)。NON-headless 跑:
##   godot --path . --script res://tools/tutorsheet.gd
## 产物:根目录 `_shot_tutor_step<N>.png`,一步一张。
##
## ⚠ **不依赖 `user://` 存档**:直接把 `run.tutorial` 按上去。
## 否则这个探针的产物会取决于「这台机器上有没有玩过」—— 那是一个会静默漂的实验条件。
## ⚑ 骨架走 `Shot`(2026-08-09 收口),排帧是这个实验自己的设计,不共用。

var _scene: Node
var _frames := 0
var _idx := 0
## 每一步停几帧再截 —— 教学关的拍长是 12/12/10/10/8/8 秒,而探针不等真钟走完:
## 直接改 `phrase_in_section` 再重进一拍,拿到的就是那一步的提示与拍长。
const HOLD := 40


func _initialize() -> void:
	_scene = Shot.stage(self)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 4:
		_scene.choose_character(1)          # 跳过选角
		_scene.run.tutorial = true
		return false
	if _frames < 120:
		return false
	var tick := _frames - 120
	# ⚠⚠ **摆状态与截图必须分在不同帧。** `TutorHint.set_hint` 走 `queue_redraw()`
	# —— 下一帧才画;而 HUD 是 Label, 当帧就更新。同一帧截图会得到
	# 「PHRASE 03 配着第 2 步的提示」这种**探针自己造出来的错位**(第一版就是这样,
	# 我差点当成 off-by-one 去查游戏)。**一个会说谎的截图探针比没有更糟。**
	if tick % HOLD == 0:
		if _idx >= Tutorial.steps():
			print("saved %d shots" % _idx)
			return true
		# 摆到第 _idx 步:改计数器 → 重进一拍, 走游戏自己的 `_start_phrase` 路径,
		# 所以提示行/拍长都是真实渲染出来的, 不是探针拼的。
		_scene.run.phrase_in_section = _idx
		_scene._start_phrase()
		var h := Tutorial.hint(_idx)
		print("step %d  %.0fs  %s | %s  → 已解锁 %s"
			% [_idx + 1, Tutorial.seconds(_idx), h["command"], h["signal"],
				str(Tutorial.unlocked(_idx))])
	elif tick % HOLD == 4 and _idx < Tutorial.steps():
		Shot.save(self, "tutor_step%d" % (_idx + 1))
		_idx += 1
	return false
