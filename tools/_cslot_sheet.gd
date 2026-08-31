extends SceneTree

## 一次性:消耗品栏位四态 + 真实语境(纯黑 + 手牌上沿), 1:1 与 2×。
##   godot --path . --script res://tools/_cslot_sheet.gd
var _n := 0

func _initialize() -> void:
	# ⚠ 底色**必须是纯黑** —— 局内 BG0 = #000000。用别的底看不出「空格看不看得见」。
	Shot.canvas(self, 760, 460, Color(0, 0, 0))
	var CS = Widgets.ConsumableSlot
	var accent := Widgets.StageCard.accent_for(0)     # S1 蓝 #23cdff
	var specs := [["", false, true], ["超级百搭", true, true], ["修剪", true, false]]

	# 1:1 一行(左)+ 2× 一行(下), 都在纯黑上
	for scale_i in range(2):
		for i in range(specs.size()):
			var holder := Node2D.new()
			var sc := 1.0 if scale_i == 0 else 2.0
			holder.position = Vector2(30 + i * (100 * sc + 20), 30 + scale_i * 130)
			holder.scale = Vector2(sc, sc)
			get_root().add_child(holder)
			var s = CS.new()
			s.size = Vector2(88, 88)
			s.accent = accent
			s.label = String(specs[i][0])
			s.filled = bool(specs[i][1])
			s.armed = bool(specs[i][2])
			holder.add_child(s)

	# 真实语境:两格空 + 五张手牌的上沿(对比用)
	var band := Node2D.new()
	band.position = Vector2(30, 300)
	get_root().add_child(band)
	for i in range(2):
		var s2 = CS.new()
		s2.size = Vector2(88, 88)
		s2.accent = accent
		s2.filled = false
		s2.position = Vector2(408 + i * 94, 0)
		band.add_child(s2)
	# 手牌上沿的参照:用与卡框同族的发光矩形(HandCard 要真牌数据, 这里只要"旁边有多亮")
	for i in range(5):
		var cr := ColorRect.new()
		cr.color = Color(6.0/255, 8.0/255, 16.0/255, 0.92)
		cr.size = Vector2(114, 74)
		cr.position = Vector2(i * 130, 92)
		band.add_child(cr)
		var edge := ColorRect.new()
		edge.color = Color(159.0/255, 233.0/255, 255.0/255, 0.55) if i % 2 == 0 \
			else Color(1.0, 106.0/255, 169.0/255, 0.55)
		edge.size = Vector2(114, 2)
		edge.position = Vector2(i * 130, 92)
		band.add_child(edge)


func _process(_d: float) -> bool:
	_n += 1
	if _n == 4:
		Shot.save(self, "cslot")
		quit()
	return false
