extends SceneTree
## 一次性:唱片位的五个态(空 / 1 / 2 / 3 / 溢出), 1:1 与 2×, 画在纯黑上。
##   godot --path . --script res://tools/_vinyl_sheet.gd
## ⚠ 真实底不是纯黑(音浪层在那儿), 所以**目视要以 shoot.gd 的真机图为准**,
## 这张只用来对齐几何与对比度(上一次「在纯黑上验的稿子搬到音浪上就穿帮」的教训)。
var _n := 0

func _initialize() -> void:
	Shot.canvas(self, 760, 460, Color(0, 0, 0))
	var qs := [[], [{"beat": "4"}], [{"beat": "1"}, {"beat": "4"}],
		[{"beat": "1"}, {"beat": "4"}, {"beat": "6"}],
		[{"beat": "1"}, {"beat": "4"}, {"beat": "6"}, {"beat": "▸"}]]
	for row in range(2):
		for i in range(qs.size()):
			var holder := Node2D.new()
			var sc := 1.0 if row == 0 else 1.6
			holder.position = Vector2(20 + i * (140 * sc * 0.72), 20 + row * 150)
			holder.scale = Vector2(sc, sc)
			get_root().add_child(holder)
			var v := VinylDeck.new()
			v.size = Vector2(132, 132)
			v.set_queue(qs[i])
			holder.add_child(v)

func _process(_d: float) -> bool:
	_n += 1
	if _n < 3:
		return false
	Shot.save(self, "vinyl")
	quit()
	return true
