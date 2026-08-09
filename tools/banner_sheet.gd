extends SceneTree

## Screenshot probe for the blind-clear banner. Run NON-headless:
##   godot --path . --script res://tools/banner_sheet.gd
## Captures _shot_banner.png mid-hold, when the strip is fully lit.

var _banner: BlindBanner
var _frames := 0

func _initialize() -> void:
	Shot.canvas(self, 720, 1280, Color("070a1a"))
	_banner = BlindBanner.new()
	get_root().add_child(_banner)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 6:
		_banner.pop(286, 260, 3)
	elif _frames == 6 + 30:
		Shot.save(self, "banner")
		quit()
	return false
