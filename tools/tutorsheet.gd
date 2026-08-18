extends SceneTree

## 教学关的目视对账探针(docs/design/difficulty.md §4)。NON-headless 跑:
##   godot --path . --script res://tools/tutorsheet.gd
## 产物:根目录 `_shot_tutor_step<N>.png`,一步一张。
##
## ⚠ **不依赖 `user://` 存档**:设 `SYNC5_PROBE_FRESH=1` 走真人同款入口(2026-08-18 起,
## 旧办法「事后手按 run.tutorial」已废弃 —— 按晚了会截到「教学关冒出 BOSS 脸」的错位假象)。
## 不走存档是因为探针产物不许取决于「这台机器上有没有玩过」—— 那是会静默漂的实验条件。
## ⚑ 骨架走 `Shot`(2026-08-09 收口),排帧是这个实验自己的设计,不共用。

var _scene: Node
var _frames := 0
var _idx := 0
## 每一步停几帧再截 —— 教学关拍长统一 8 秒(2026-08-18 拍板),而探针不等真钟走完:
## 直接改 `tutorial_step` 再重进一拍,拿到的就是那一步的提示与拍长。
## ⚠ **2026-08-16 从 `phrase_in_section` 改过来** —— 动作门上线后步骤下标与拍数解耦,
## 还按拍数驱动会让这个探针每一张都截到第 1 步(而且**不报错**)。
const HOLD := 40


func _initialize() -> void:
	# ⚑ 真路径(2026-08-18):环境变量让 seen_tutorial() 在探针里返回 false ——
	# choose_character 于是走**和真人一样**的教学分岔(公示卡闸/掷脸教学分支/步进),
	# 不再需要事后手按 run.tutorial(那正是两次「教学关冒出 BOSS 脸」假象的来源)。
	OS.set_environment("SYNC5_PROBE_FRESH", "1")
	_scene = Shot.stage(self)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 4:
		_scene.choose_character(1)          # 跳过选角;教学分岔由 SYNC5_PROBE_FRESH 触发
		assert(_scene.run.tutorial, "真路径没生效 —— seen_tutorial 的探针口子被动过?")
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
		_scene.run.tutorial_step = _idx
		_scene._start_phrase()
		var h := Tutorial.hint(_idx)
		print("step %d  %.0fs  %s | %s  → 已解锁 %s"
			% [_idx + 1, Tutorial.seconds(_idx), h["command"], h["signal"],
				str(Tutorial.unlocked(_idx))])
	elif tick % HOLD == 4 and _idx < Tutorial.steps():
		Shot.save(self, "tutor_step%d" % (_idx + 1))
		_idx += 1
	return false
