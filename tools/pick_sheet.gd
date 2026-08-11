extends SceneTree

## 选角屏截图 → `_shot_pick.png`:八砖 + hover 立绘预览(hover 钉在 DJ 上)。
##   godot --path . --script res://tools/pick_sheet.gd

var _n := 0
var _picker: PickWalker


func _initialize() -> void:
	Shot.canvas(self, 720, 1280, Color(0.02, 0.03, 0.07))
	_picker = PickWalker.new()
	get_root().add_child(_picker)


func _process(_d: float) -> bool:
	_n += 1
	if _n == 2:
		# hover 是鼠标态,探针直接钉住它看立绘预览
		_picker._hover = 0
		_picker.queue_redraw()
	if _n >= 14:
		Shot.save(self, "pick")
		quit(0)
		return true
	return false
