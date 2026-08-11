extends SceneTree

## 从 glass.png 里裁「玻璃膜」候选区(顶栏光泽用),存两张对照:
##   _shot_film_a.png = 上部斜向反光带区  _shot_film_b.png = 中部纯膜区
##   godot --headless --path . --script res://tools/art/glassfilm.gd


func _initialize() -> void:
	var img := Image.load_from_file("res://assets/frames/glass.png")
	img.convert(Image.FORMAT_RGBA8)
	print("src ", img.get_width(), "x", img.get_height())
	# 候选 A:反光带穿过的上部(避开 40px 轨:x 70..772)
	var a := img.get_region(Rect2i(70, 90, 702, 150))
	a.save_png("res://_shot_film_a.png")
	# 候选 B:中部
	var b := img.get_region(Rect2i(70, 500, 702, 150))
	b.save_png("res://_shot_film_b.png")
	# 整卡 1/4 缩略,看反光带走向
	var o := img.duplicate()
	o.resize(421, 677, Image.INTERPOLATE_LANCZOS)
	o.save_png("res://_shot_film_all.png")
	print("saved film_a / film_b / film_all")
	quit(0)
