extends SceneTree

## 结算乘区分解的目视探针(2026-08-18)。NON-headless:
##   godot --path . --script res://tools/settlesheet.gd
## 两张:满配(基础×牌型×小丑×加成+奖励)与朴素(高牌, 无小丑)。

var _frames := 0
var _scene: Node


func _initialize() -> void:
	_scene = Shot.stage(self)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 4:
		_scene.start_run()
		return false
	if _frames < 120:
		return false
	match _frames:
		120:
			# 8 万分那种拍:四条 ×7 · 小丑 ×10 · 加成 +75% · 奖励 240
			_scene.settle_fx.play(112, 122.5, 96285, Vector2(60, 60), 240, 7.0, 10.0, 0.75, 7)
		155:   # merge 相(帧率实测 <60, 早点截)
			Shot.save(self, "settle_full")
			print("settle_full: 六框全家福")
		210:
			_scene.settle_fx.play(40, 1.0, 40, Vector2(60, 60), 0, 1.0, 1.0, 0.0, 0)
		245:
			Shot.save(self, "settle_plain")
			print("settle_plain: 高牌朴素拍(基础×高牌=分)")
			return true
	return false
