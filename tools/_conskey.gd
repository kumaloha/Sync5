extends SceneTree
## 一次性:把三张消耗牌的方图母版键控成 art512(黑=透明)。
## 键控**借调**唯一那一份(tools/art/build_joker_runtime_art.gd::key_black_to_alpha),
## 与 webslim.gd 同一条路 —— 不许在这里再写一份阈值。
func _initialize() -> void:
	var keyer = load("res://tools/art/build_joker_runtime_art.gd")
	for id in ["anvil", "encorecall", "highroller"]:
		var src := "res://assets/jokers/source/joker_%s.png" % id
		var img := Image.load_from_file(src)
		img.resize(512, 512, Image.INTERPOLATE_LANCZOS)
		keyer.key_black_to_alpha(img)
		img.save_png("res://assets/jokers/art512/joker_%s.png" % id)
		print("keyed ", id)
	quit()
