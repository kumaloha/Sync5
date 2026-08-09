class_name OrbitZone
extends Control

## The hand-area frame that the character walks around. One lap = one phrase.
## Start/settle point (beat diamond) is bottom-center; the walker goes
## clockwise (leftward along the bottom first). The walked part of the loop
## glows gold behind them; the remainder is a faint dashed track.

const INSET := 2.0
const CORNER := 26.0

var progress := 0.0        # 0..1 around the loop
var warning := false
var seconds_left := 99.0   # to lock; drives the 3-2-1 countdown in the warning window
var mode := "walk"         # "walk" | "dance" (dance = settle celebration at the beat point)
var _walker: Walker
var _pulse_t := 0.0
var _dance_t := 0.0
var _last_digit := -1
var _digit_pop := 0.0      # scale-pop timer, restarted on each new countdown digit

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_walker = Walker.new()
	_walker.z_index = 20
	add_child(_walker)

## Pick one of the eight crew members (Walker.CREW).
func set_character(i: int) -> void:
	_walker.set_character(i)
	queue_redraw()

func character_color() -> Color:
	return _walker.color()

func set_progress(p: float, warn: bool, secs: float = 99.0) -> void:
	progress = clampf(p, 0.0, 1.0)
	warning = warn
	seconds_left = secs
	if warn:
		var d := maxi(1, int(ceil(secs)))
		if d != _last_digit:
			_last_digit = d
			_digit_pop = 0.30
	else:
		_last_digit = -1

func set_mode(m: String) -> void:
	if mode != m:
		mode = m
		_dance_t = 0.0
		_walker.dancing = (m == "dance")

func _process(delta: float) -> void:
	_pulse_t += delta
	_digit_pop = maxf(0.0, _digit_pop - delta)
	if mode == "dance":
		# celebration on the beat point (the figure animates itself)
		_dance_t += delta
		_walker.position = Vector2(size.x * 0.5, size.y - INSET)
		_walker.facing = 1.0 if sin(_dance_t * 4.5) >= 0.0 else -1.0
	else:
		var st := _path_state(progress)
		_walker.position = st[0]
		if absf(st[1].x) > 0.1:
			_walker.facing = 1.0 if st[1].x > 0.0 else -1.0
	queue_redraw()

## Piecewise rounded-rect path starting at bottom-center, going LEFT
## (clockwise when viewed on screen). Returns [point, tangent].
func _path_state(p: float) -> Array:
	var pts := _loop_points()
	var total := 0.0
	var lens: Array = []
	for i in range(pts.size() - 1):
		var l: float = pts[i].distance_to(pts[i + 1])
		lens.append(l)
		total += l
	var target := p * total
	var acc := 0.0
	for i in range(lens.size()):
		if acc + lens[i] >= target:
			var f := (target - acc) / maxf(lens[i], 0.001)
			var dir: Vector2 = (pts[i + 1] - pts[i]).normalized()
			return [pts[i].lerp(pts[i + 1], f), dir]
		acc += lens[i]
	return [pts[pts.size() - 1], Vector2.RIGHT]

## Polyline approximating the loop (corners as arcs sampled).
func _loop_points() -> PackedVector2Array:
	var w := size.x
	var h := size.y
	var l := INSET
	var r := w - INSET
	var t := INSET
	var b := h - INSET
	var c := CORNER
	var pts := PackedVector2Array()
	pts.append(Vector2(w * 0.5, b))
	pts.append(Vector2(l + c, b))
	_arc(pts, Vector2(l + c, b - c), c, PI * 0.5, PI)
	pts.append(Vector2(l, t + c))
	_arc(pts, Vector2(l + c, t + c), c, PI, PI * 1.5)
	pts.append(Vector2(r - c, t))
	_arc(pts, Vector2(r - c, t + c), c, PI * 1.5, TAU)
	pts.append(Vector2(r, b - c))
	_arc(pts, Vector2(r - c, b - c), c, 0, PI * 0.5)
	pts.append(Vector2(w * 0.5, b))
	return pts

func _arc(pts: PackedVector2Array, center: Vector2, radius: float, from: float, to: float) -> void:
	for i in range(1, 7):
		var a := from + (to - from) * float(i) / 6.0
		pts.append(center + Vector2(cos(a), sin(a)) * radius)

func _draw() -> void:
	var pts := _loop_points()

	# faint dashed full loop
	var faint := Color(0.63, 0.71, 1.0, 0.20)
	for i in range(pts.size() - 1):
		if i % 2 == 0:
			draw_line(pts[i], pts[i + 1], faint, 1.5)

	# walked golden trail (bottom-center going clockwise to walker)
	var total := 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	var target := progress * total
	var acc := 0.0
	var trail := PackedVector2Array()
	trail.append(pts[0])
	for i in range(pts.size() - 1):
		var l: float = pts[i].distance_to(pts[i + 1])
		if acc + l >= target:
			trail.append(pts[i].lerp(pts[i + 1], (target - acc) / maxf(l, 0.001)))
			break
		trail.append(pts[i + 1])
		acc += l
	if trail.size() >= 2:
		# spec: one soft 7px pass at .28 alpha, one 2.5px core at .9
		var col := StageTheme.PINK if warning else _walker.color()
		draw_polyline(trail, Color(col.r, col.g, col.b, 0.28), 8.0, true)
		draw_polyline(trail, Color(col.r, col.g, col.b, 0.9), 2.8, true)

	# beat diamond at bottom-center
	var beat := Vector2(size.x * 0.5, size.y - INSET)
	var pulse := 0.5 + 0.5 * sin(_pulse_t * (12.0 if warning else 5.0))
	var br := 8.0 + pulse * 2.5
	draw_circle(beat, br + 8.0, Color(StageTheme.GOLD.r, StageTheme.GOLD.g, StageTheme.GOLD.b, 0.16 + 0.12 * pulse))
	draw_colored_polygon(PackedVector2Array([
		beat + Vector2(0, -br), beat + Vector2(br, 0),
		beat + Vector2(0, br), beat + Vector2(-br, 0)]), StageTheme.GOLD)

	# final-seconds escalation: the whole track flashes pink and a 3-2-1
	# countdown pops beside the beat point — the lap alone reads as scenery,
	# not as a clock (2026-08-05 真人试玩: no urgency)
	if warning and mode == "walk":
		var wa := 0.10 + 0.16 * pulse
		draw_polyline(pts, Color(StageTheme.PINK.r, StageTheme.PINK.g, StageTheme.PINK.b, wa), 3.0, true)
		var digit := str(maxi(1, int(ceil(seconds_left))))
		var font := StageTheme.num("Bold")
		var k := _digit_pop / 0.30
		var fs := int(round(40.0 * (1.0 + 0.45 * k * k)))
		var tw := font.get_string_size(digit, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := Vector2(beat.x - tw * 0.5, beat.y - 24.0)
		var centre := at + Vector2(tw * 0.5, -fs * 0.36)
		var d := fs * 2.0
		draw_texture_rect(PaperCard.glow_tex(), Rect2(centre - Vector2(d, d) * 0.5, Vector2(d, d)),
			false, Color(StageTheme.PINK.r, StageTheme.PINK.g, StageTheme.PINK.b, 0.30 + 0.25 * k))
		draw_string(font, at, digit, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.86, 0.92))
