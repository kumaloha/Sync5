extends SceneTree
## 一次性:只跑一个测试域(改完一处不想等 65 分钟全量时用)。
##   SYNC5_DOMAIN=t_consumable godot --headless --path . --script res://tools/_tdomain.gd
func _initialize() -> void:
	var r = load("res://tests/runner.gd").new()
	var doms := OS.get_environment("SYNC5_DOMAIN").split(",")
	for d in doms:
		if d.strip_edges() != "":
			load("res://tests/%s.gd" % d.strip_edges()).new().run(r)
	print("\n=== %s ===" % OS.get_environment("SYNC5_DOMAIN"))
	print("pass=%d fail=%d" % [int(r.get("_pass")), int(r.get("_fail"))])
	quit(1 if int(r.get("_fail")) > 0 else 0)
