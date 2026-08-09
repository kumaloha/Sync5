extends SceneTree
func _initialize() -> void:
	for n in ["small", "big", "boss"]:
		var img: Image = load("res://assets/frames/%s.png" % n).get_image()
		var w := img.get_width()
		var h := img.get_height()
		var x0 := w; var y0 := h; var x1 := 0; var y1 := 0
		for y in range(0, h, 2):
			for x in range(0, w, 2):
				var c := img.get_pixel(x, y)
				# the neon rail is bright; the black surround is not
				if maxf(maxf(c.r, c.g), c.b) > 0.55:
					x0 = mini(x0, x); x1 = maxi(x1, x)
					y0 = mini(y0, y); y1 = maxi(y1, y)
		print("%s: %dx%d  frame bbox x[%d..%d] y[%d..%d]  → L%.3f R%.3f T%.3f B%.3f" %
			[n, w, h, x0, x1, y0, y1,
			float(x0)/w, float(x1)/w, float(y0)/h, float(y1)/h])
	quit(0)
