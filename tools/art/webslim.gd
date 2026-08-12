extends SceneTree

## 生成移动端运行时贴图(2026-08-12:iOS 浏览器内存红线杀,页面被回收重载)。
##   小丑 source 1024² → assets/jokers/art512/(512²,槽位/图鉴显示 ≤200px,足够)
##   主角 portrait 1536×2048 → 各自目录 portrait768.png(选角预览 270×360)
## 运行时优先读小图,缺了退回原画 —— 桌面/Web 同一套代码。
##   godot --headless --path . --script res://tools/art/webslim.gd


func _initialize() -> void:
	var jm: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/jokers/manifest.json"))
	DirAccess.make_dir_recursive_absolute("res://assets/jokers/art512")
	var n := 0
	for c in jm["cards"]:
		var src := "res://assets/jokers/source/joker_%s.png" % c["id"]
		if not FileAccess.file_exists(src):
			continue
		var img := Image.load_from_file(src)
		img.resize(512, 512, Image.INTERPOLATE_LANCZOS)
		img.save_png("res://assets/jokers/art512/joker_%s.png" % c["id"])
		n += 1
	print("jokers 512²: ", n)
	var cm: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/manifest.json"))
	var np := 0
	for e in cm["characters"]:
		var p := "res://assets/characters/%s/portrait.png" % e["id"]
		if not FileAccess.file_exists(p):
			continue
		var img2 := Image.load_from_file(p)
		img2.resize(768, 1024, Image.INTERPOLATE_LANCZOS)
		img2.save_png("res://assets/characters/%s/portrait768.png" % e["id"])
		np += 1
	print("portraits 768: ", np)
	quit(0)
