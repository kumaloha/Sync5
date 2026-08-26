extends SceneTree

## 生成移动端运行时贴图(2026-08-12:iOS 浏览器内存红线杀,页面被回收重载)。
##   小丑 source 1024² → assets/jokers/art512/(512²,槽位/图鉴显示 ≤200px,足够)
## 运行时优先读小图,缺了退回原画 —— 桌面/Web 同一套代码。(主角 portrait 段 2026-08-24 随主角系统删除)
##   godot --headless --path . --script res://tools/art/webslim.gd


func _initialize() -> void:
	var jm: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/jokers/manifest.json"))
	DirAccess.make_dir_recursive_absolute("res://assets/jokers/art512")
	# 黑底转透明的键控**只有一份**, 在横幅工具里 —— 这里借调(2026-08-24 拍板②)
	var keyer = load("res://tools/art/build_joker_runtime_art.gd")
	var n := 0
	for c in jm["cards"]:
		var src := "res://assets/jokers/source/joker_%s.png" % c["id"]
		if not FileAccess.file_exists(src):
			continue
		var img := Image.load_from_file(src)
		img.resize(512, 512, Image.INTERPOLATE_LANCZOS)
		keyer.key_black_to_alpha(img)
		img.save_png("res://assets/jokers/art512/joker_%s.png" % c["id"])
		n += 1
	print("jokers 512²: ", n)
	quit(0)
