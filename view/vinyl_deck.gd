class_name VinylDeck
extends Control

## The draw pile as a spinning vinyl record, with a remaining-count badge.

var count := 0
var _angle := 0.0
var _speed := 0.5          # radians/sec idle spin
var _boost := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_count(n: int) -> void:
	if n != count:
		count = n
		queue_redraw()

func spin_boost() -> void:
	_boost = 6.0

func _process(delta: float) -> void:
	_angle += (_speed + _boost) * delta
	_boost = maxf(0.0, _boost - delta * 9.0)
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 4.0

	# glow + plate
	draw_circle(c, r + 4.0, Color(StageTheme.CYAN.r, StageTheme.CYAN.g, StageTheme.CYAN.b, 0.20))
	draw_circle(c, r, Color("0b0e20"))
	draw_arc(c, r, 0, TAU, 64, Color(0.63, 0.71, 1.0, 0.35), 2.0)

	# grooves
	var gr := r * 0.42
	while gr < r - 3.0:
		draw_arc(c, gr, 0, TAU, 48, Color(0.63, 0.71, 1.0, 0.10), 1.0)
		gr += 4.5

	# rotating specular highlight
	draw_arc(c, r * 0.72, _angle, _angle + 0.9, 18, Color(1, 1, 1, 0.14), 5.0)
	draw_arc(c, r * 0.60, _angle + PI, _angle + PI + 0.7, 14, Color(1, 1, 1, 0.09), 4.0)

	# label
	draw_circle(c, r * 0.34, Color("2ab5aa"))
	draw_circle(c, r * 0.30, Color("7cf3e8"))
	draw_circle(c, 2.5, Color("0b0e20"))
	# label notch shows rotation
	var notch := c + Vector2(cos(_angle), sin(_angle)) * r * 0.32
	draw_circle(notch, 2.0, Color("0b0e20"))

	# count badge, pinned to the plate's top-right
	var font := StageTheme.num("Bold")
	var badge := Rect2(c.x + r * 0.62, c.y - r - 4.0, 36, 22)
	var sb := StageTheme.box(StageTheme.GOLD, Color("f0a63f"), 1, 11)
	draw_style_box(sb, badge)
	draw_string(font, Vector2(badge.position.x, badge.position.y + 16), str(count),
		HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, 14, Color("211502"))
