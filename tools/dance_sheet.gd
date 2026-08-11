extends SceneTree

## 八人舞步帧联络表 → `_shot_dance.png`(crew_sheet 的 dancing 版):
## 结算庆祝用的 dance 条此前从未被渲染实证过 —— 走路帧亮了不等于舞步帧亮了。
##   godot --path . --script res://tools/dance_sheet.gd

var _n := 0


func _initialize() -> void:
	Shot.canvas(self, 720, 400, Color(0.027, 0.039, 0.102))
	for i in range(Walker.CREW.size()):
		var w := Walker.new()
		w.set_character(i)
		w.show_name = true
		w.dancing = true
		w.facing = 1.0 if i % 2 == 0 else -1.0
		w.position = Vector2(70 + (i % 4) * 190, 150 + int(i / 4) * 190)
		get_root().add_child(w)


func _process(_d: float) -> bool:
	_n += 1
	if _n >= 30:
		Shot.save(self, "dance")
		quit(0)
		return true
	return false
