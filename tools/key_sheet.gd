extends SceneTree

## Close-up of the two action keys at 2×, both states.
##   godot --path . --script res://tools/key_sheet.gd

var _n := 0

func _initialize() -> void:
	Shot.canvas(self, 900, 460, Color(0.027, 0.035, 0.086))

	var Key = Widgets.DJKey
	var specs := [
		["sort", Color("35e8e0"), "理牌", true, 0],
		["discard", Color("ff5f7e"), "弃牌", true, 2],
		["discard", Color("ff5f7e"), "弃牌", false, 0],
	]
	for i in range(specs.size()):
		var holder := Node2D.new()
		holder.position = Vector2(40 + i * 290, 40)
		holder.scale = Vector2(2, 2)
		get_root().add_child(holder)
		var k = Key.new()
		k.kind = String(specs[i][0])
		k.accent = specs[i][1]
		k.zh_label = String(specs[i][2])
		k.active = bool(specs[i][3])
		k.fee = int(specs[i][4])
		k.size = Vector2(114, 170)
		holder.add_child(k)
		if i == 2:
			k.active = true
			k.shake()      # capture mid-jolt so the reject feedback is visible

func _process(_d: float) -> bool:
	_n += 1
	if _n == 8:   # peak of the shake curve
		Shot.save(self, "keys")
		quit()
	return false
