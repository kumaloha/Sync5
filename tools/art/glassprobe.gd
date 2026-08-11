extends SceneTree

## 玻璃卡素材体检(2026-08-12 换素材前的剖面):四张候选 PNG 各量
##   · alpha 直方 · α=0 处 RGB 是否还活着(能否无损重建) · 中线剖面
## 结论(已写进 assets/frames/README.md):四张同源,α=0 处 RGB 全灭(0.00%),
## 坏遮罩不可修;但显示尺寸 + 黑底下伪像读不出来,直接贴(LESSONS.md 判据 5)。
##   godot --headless --path . --script res://tools/art/glassprobe.gd


func _initialize() -> void:
	for name in ["card_glass_full", "card_glass_face", "card_glass_pink_source",
			"../assets/frame-glass4"]:
		var img := Image.load_from_file("res://resources/godot-handoff/%s.png" % name)
		if img == null:
			print(name, ": 读不到")
			continue
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		var h := img.get_height()
		var n_a0 := 0            # α = 0
		var n_a0_lit := 0        # α = 0 但 RGB 亮度 > 8/255(数据还活着)
		var n_mid := 0           # 0 < α < 255
		var n_full := 0
		var lit_max := 0.0
		for y in range(0, h, 3):        # 1/9 采样够统计
			for x in range(0, w, 3):
				var c := img.get_pixel(x, y)
				var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
				if c.a == 0.0:
					n_a0 += 1
					if lum > 8.0 / 255.0:
						n_a0_lit += 1
						lit_max = maxf(lit_max, lum)
				elif c.a >= 1.0:
					n_full += 1
				else:
					n_mid += 1
		var tot := n_a0 + n_mid + n_full
		print("%s %dx%d  α0=%.1f%%  α中=%.1f%%  α满=%.1f%%  | α0且RGB亮 %.2f%%(峰值 %.2f)" %
			[name, w, h, 100.0 * n_a0 / tot, 100.0 * n_mid / tot, 100.0 * n_full / tot,
			100.0 * float(n_a0_lit) / maxf(1.0, float(n_a0)), lit_max])
		# 中线横剖:α 与 亮度 各 40 点
		var row_a := PackedStringArray()
		var row_l := PackedStringArray()
		var y0 := h / 2
		for i in range(40):
			var x2 := i * (w - 1) / 39
			var c2 := img.get_pixel(x2, y0)
			row_a.append("%3d" % int(c2.a * 255.0))
			row_l.append("%3d" % int((0.2126 * c2.r + 0.7152 * c2.g + 0.0722 * c2.b) * 255.0))
		print("  midα ", " ".join(row_a))
		print("  midL ", " ".join(row_l))
	quit(0)
