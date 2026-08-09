extends SceneTree

## Screenshot probe for the section-end screens. Run NON-headless:
##   godot --path . --script res://tools/end_sheet.gd
## Captures _shot_end_success.png and _shot_end_fail.png at ~2.1s in,
## when the entrance animations have settled.

var _scene: RunEndScreen
var _frames := 0

func _initialize() -> void:
	Shot.canvas(self, 720, 1280)
	_scene = RunEndScreen.new()
	get_root().add_child(_scene)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 6:
		_scene.show_success(186, 150, 3, false, 2)   # after _ready — buttons exist
	elif _frames == 6 + 300:
		Shot.save(self, "end_success")
		_scene.show_fail(112, 150)
	elif _frames == 6 + 640:
		Shot.save(self, "end_fail")
		quit()
	return false
