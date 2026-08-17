class_name BlindBanner
extends Control

## Light strip for non-boss blind clears (docs/design/levels.md 关卡重构): the full
## 演出成功 celebration is reserved for gig walls — small/big blinds get a
## sub-second banner (target ✓ + wage) that never blocks input; the shop
## opens beneath it while it slides away.

const W := 470.0
const H := 58.0
const SHOW_Y := 196.0

var _score := 0
var _target := 0
var _wage := 0
var _tw: Tween


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(W, H)
	position = Vector2((720.0 - W) * 0.5, SHOW_Y)


func pop(score: int, target: int, wage: int) -> void:
	_score = score
	_target = target
	_wage = wage
	move_to_front()
	visible = true
	modulate.a = 0.0
	position.y = SHOW_Y - 26.0
	queue_redraw()
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	_tw.set_parallel(true)
	_tw.tween_property(self, "position:y", SHOW_Y, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(self, "modulate:a", 1.0, 0.14)
	_tw.set_parallel(false)
	_tw.tween_interval(0.55)
	_tw.tween_property(self, "modulate:a", 0.0, 0.20)
	_tw.parallel().tween_property(self, "position:y", SHOW_Y - 18.0, 0.20)
	_tw.tween_callback(func() -> void: visible = false)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(StageTheme.box(
		Color(0.043, 0.055, 0.13, 0.88),
		Color(StageTheme.CYAN.r, StageTheme.CYAN.g, StageTheme.CYAN.b, 0.55), 2, 14,
		Color(StageTheme.CYAN.r, StageTheme.CYAN.g, StageTheme.CYAN.b, 0.30), 14), r)
	var zh := StageTheme.zh()
	var num := StageTheme.num("Bold")
	var seg_a := "目标达成 ✓  "
	var seg_n := "%d / %d" % [_score, _target]
	var seg_b := "   工资 +%d ◆" % _wage
	var wa: float = zh.get_string_size(seg_a, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var wn: float = num.get_string_size(seg_n, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	var wb: float = zh.get_string_size(seg_b, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var x := (W - (wa + wn + wb)) * 0.5
	var base_y := H * 0.5 + 8.0
	draw_string(zh, Vector2(x, base_y), seg_a, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("dffcf9"))
	draw_string(num, Vector2(x + wa, base_y + 1.0), seg_n, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, StageTheme.GOLD)
	draw_string(zh, Vector2(x + wa + wn, base_y), seg_b, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("ffd9a0"))
