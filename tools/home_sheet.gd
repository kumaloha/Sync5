extends SceneTree

## Screenshot probe for the home screen (resources/home.html). Run NON-headless:
##   godot --path . --script res://tools/home_sheet.gd
## Captures _shot_home.png (小盲) and _shot_home_wall.png (BOSS 墙 card).

var _scene: Node
var _frames := 0

func _initialize() -> void:
	_scene = Shot.stage(self)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 60:
		Shot.save(self, "home")
	elif _frames == 64:
		_scene._home.section_idx = 2      # a BOSS wall card
	elif _frames == 120:
		Shot.save(self, "home_wall")
		quit(0)
	return false
