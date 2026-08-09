extends SceneTree

## 玻璃卡对账探针:按参考图同规格(1024×1536 画布 / 卡约 750×1230 / 纯黑底)
## 渲染我们的 StageCard 五个档位色 → _shot_glass_<name>.png,
## 供像素剖面器与 assets/reference/ref_glass_*.png 逐指标对比。
##   godot --path . --script res://tools/glass.gd

const COLS := [
	["pink", Color("ff4fa3")],
	["purple", Color("a56bff")],
	["green", Color("35e8e0")],
	["gold", Color("ffb347")],
	["red", Color("ff5f6e")],
]

var _frames := 0
var _idx := 0
var _card: Control = null


class GlassCard:
	extends Control
	var acc := Color.WHITE
	func _draw() -> void:
		# 参考图口径: 卡 750 宽 ≈ 首页大卡 672 的 1.116 倍, 内缩/圆角等比放大
		Widgets.StageCard.draw_card(self, Rect2(0, 0, 750, 1230), acc, 29.0, 27.0)


func _initialize() -> void:
	Shot.canvas(self, 1024, 1536, Color.BLACK)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames % 6 == 2:
		if _idx >= COLS.size():
			quit(0)
			return false
		if _card != null:
			_card.queue_free()
		_card = GlassCard.new()
		_card.acc = COLS[_idx][1]
		_card.position = Vector2(137, 150)
		_card.size = Vector2(750, 1230)
		get_root().add_child(_card)
	elif _frames % 6 == 5 and _card != null:
		Shot.save(self, "glass_%s" % COLS[_idx][0])
		_idx += 1
	return false
