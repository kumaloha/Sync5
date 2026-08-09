extends SceneTree

## Contact sheet of the eight crew members, so the walk cycle and each prop
## animation can be eyeballed side by side.
##   godot --path . --script res://tools/crew_sheet.gd

var _n := 0

func _initialize() -> void:
	Shot.canvas(self, 720, 400, Color(0.027, 0.039, 0.102))
	for i in range(Walker.CREW.size()):
		var w := Walker.new()
		w.set_character(i)
		w.show_name = true
		w.facing = 1.0 if i % 2 == 0 else -1.0
		w.position = Vector2(70 + (i % 4) * 190, 150 + int(i / 4) * 190)
		get_root().add_child(w)

func _process(_d: float) -> bool:
	_n += 1
	if _n == 90:
		Shot.save(self, "crew")
		quit()
	return false
