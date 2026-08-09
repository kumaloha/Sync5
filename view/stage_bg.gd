class_name StageBg
extends Control

## The stage scene behind everything: gradient, grid, light beams, giant vinyl
## grooves, drifting bokeh, and a crowd silhouette with blinking phone lights.

var _t := 0.0
var _grad: GradientTexture2D
var _glow_top: GradientTexture2D
var _glow_bottom: GradientTexture2D
var _bokeh: Array = []   # [x, y, r, color, phase]
var _phones: Array = []  # [x, y, color, phase]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grad = StageTheme.vgradient(StageTheme.BG0, StageTheme.BG2)
	_glow_top = StageTheme.radial(Color(StageTheme.CYAN.r, StageTheme.CYAN.g, StageTheme.CYAN.b, 0.16))
	_glow_bottom = StageTheme.radial(Color(StageTheme.VIOLET.r, StageTheme.VIOLET.g, StageTheme.VIOLET.b, 0.20))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(14):
		var col: Color = [StageTheme.CYAN, StageTheme.VIOLET, StageTheme.PINK, Color.WHITE][i % 4]
		_bokeh.append([rng.randf_range(10, 710), rng.randf_range(320, 1240),
			rng.randf_range(1.5, 4.0), Color(col.r, col.g, col.b, rng.randf_range(0.10, 0.28)),
			rng.randf_range(0.0, TAU)])

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_texture_rect(_grad, Rect2(0, 0, w, h), false)
	draw_texture_rect(_glow_top, Rect2(-w * 0.25, -h * 0.28, w * 1.5, h * 0.72), false)
	draw_texture_rect(_glow_bottom, Rect2(-w * 0.25, h * 0.62, w * 1.5, h * 0.75), false)

	# faint studio grid
	var grid := Color(0.55, 0.63, 1.0, 0.045)
	var step := 50.0
	var gx := 0.0
	while gx < w:
		draw_line(Vector2(gx, 0), Vector2(gx, h), grid, 1.0)
		gx += step
	var gy := 0.0
	while gy < h:
		draw_line(Vector2(0, gy), Vector2(w, gy), grid, 1.0)
		gy += step

	# spotlight beams (slow sway)
	_beam(w * 0.10 + sin(_t * 0.35) * 14.0, w * 0.52, StageTheme.CYAN, 0.13, h)
	_beam(w * 0.88 + sin(_t * 0.28 + 2.0) * 14.0, w * 0.46, StageTheme.VIOLET, 0.12, h)
	_beam(w * 0.50 + sin(_t * 0.31 + 4.0) * 10.0, w * 0.62, StageTheme.PINK, 0.07, h * 0.8)

	# hard laser fan cutting the haze (from the cyber-club reference).
	# These are a signature element — they have to actually read, not whisper.
	# apex sits off the top of the frame so the beams read as stage rigging,
	# not as something emitted by the UI. They fade out before the card rows.
	var apex := Vector2(w * 0.5 + sin(_t * 0.33) * 46.0, -70.0)
	for i in range(5):
		var spread: float = (float(i) - 2.0) / 2.0                 # -1 .. 1
		var ang: float = spread * 1.02 + sin(_t * 0.45 + float(i)) * 0.055
		var dir := Vector2(sin(ang), maxf(cos(ang), 0.30))
		var col: Color = [StageTheme.PINK, StageTheme.CYAN, StageTheme.VIOLET][i % 3]
		_laser(apex, apex + dir * 780.0, col, 0.80)
	draw_circle(Vector2(w * 0.10, 4), 20, Color(StageTheme.CYAN.r, StageTheme.CYAN.g, StageTheme.CYAN.b, 0.45))
	draw_circle(Vector2(w * 0.88, 4), 20, Color(StageTheme.VIOLET.r, StageTheme.VIOLET.g, StageTheme.VIOLET.b, 0.45))
	draw_circle(Vector2(w * 0.50, 2), 15, Color(StageTheme.PINK.r, StageTheme.PINK.g, StageTheme.PINK.b, 0.35))

	# giant vinyl grooves off both edges
	var groove := Color(0.63, 0.71, 1.0, 0.06)
	for r in [250.0, 305.0, 360.0, 415.0]:
		draw_arc(Vector2(w + 30, h * 0.55), r, PI * 0.6, PI * 1.4, 40, groove, 1.5)
	for r in [200.0, 250.0, 300.0]:
		draw_arc(Vector2(-40, h * 0.30), r, -PI * 0.45, PI * 0.45, 36, groove, 1.5)

	# drifting bokeh
	for b in _bokeh:
		var off := Vector2(sin(_t * 0.4 + b[4]) * 6.0, cos(_t * 0.3 + b[4]) * 4.0)
		draw_circle(Vector2(b[0], b[1]) + off, b[2], b[3])

	# wet-floor neon smears just above the crowd
	_smear(w * 0.10, h, StageTheme.PINK, 0.20)
	_smear(w * 0.26, h, StageTheme.CYAN, 0.17)
	_smear(w * 0.44, h, StageTheme.VIOLET, 0.18)
	_smear(w * 0.62, h, StageTheme.CYAN, 0.16)
	_smear(w * 0.80, h, StageTheme.PINK, 0.18)
	_smear(w * 0.93, h, StageTheme.VIOLET, 0.14)

	# bobbing heads are a BACK row: they must be drawn first so the front
	# silhouette occludes everything but their crowns. Drawn after, they read
	# as black holes punched into the crowd.
	_crowd_heads(w, h)
	# crowd silhouette along the bottom
	_crowd(w, h)
	_crowd_glowsticks(w, h)
	_crowd_signs(w, h)

## A sharp laser: wide bloom, bright body, hot white core — and a falloff so the
## beam dies out before it reaches the play area instead of striping the cards.
func _laser(a: Vector2, b: Vector2, col: Color, alpha: float) -> void:
	var n := 14
	var pts := PackedVector2Array()
	for i in range(n):
		pts.append(a.lerp(b, float(i) / float(n - 1)))
	for pass_i in range(4):
		var wdt: float = [22.0, 9.0, 3.0, 1.2][pass_i]
		var mul: float = [0.15, 0.30, 0.80, 0.50][pass_i]
		var base: Color = col if pass_i < 3 else Color(1, 1, 1)
		var cols := PackedColorArray()
		for i in range(n):
			var f := float(i) / float(n - 1)
			var fade: float = clampf(1.0 - pow(f, 1.5) * 1.35, 0.0, 1.0)
			cols.append(Color(base.r, base.g, base.b, alpha * mul * fade))
		draw_polyline_colors(pts, cols, wdt)


## Vertical neon reflection smear on the wet floor above the crowd line.
func _smear(x: float, h: float, col: Color, alpha: float) -> void:
	# One soft texture, not ten stacked rectangles — the old version read as a
	# row of flat colour columns with visible steps and hard vertical edges,
	# and it faded the wrong way (brightest at the top instead of at the floor).
	var sw := 96.0
	var sh := 260.0
	var wob: float = sin(_t * 0.8 + x * 0.013) * 7.0
	draw_texture_rect(smear_tex(),
		Rect2(x - sw * 0.5 + wob, h - 40.0 - sh, sw, sh), false,
		Color(col.r, col.g, col.b, alpha))


static var _smear_tex: ImageTexture

## Vertical neon smear: a horizontal bell times a bottom-weighted ramp, so it
## is soft on every edge and brightest where it meets the floor.
static func smear_tex() -> ImageTexture:
	if _smear_tex != null:
		return _smear_tex
	var tw := 48
	var th := 160
	var img := Image.create(tw, th, false, Image.FORMAT_RGBA8)
	for y in range(th):
		var v := float(y) / float(th - 1)
		var vert: float = pow(v, 1.7)
		for x in range(tw):
			var u := (float(x) / float(tw - 1) - 0.5) * 2.0
			var horiz: float = exp(-u * u * 3.0)
			img.set_pixel(x, y, Color(1, 1, 1, vert * horiz))
	_smear_tex = ImageTexture.create_from_image(img)
	return _smear_tex


func _beam(x_top: float, spread: float, col: Color, alpha: float, depth: float) -> void:
	var pts := PackedVector2Array([
		Vector2(x_top - 20, 0), Vector2(x_top + 20, 0),
		Vector2(x_top + spread * 0.5, depth), Vector2(x_top - spread * 0.5, depth)])
	var cols := PackedColorArray([
		Color(col.r, col.g, col.b, alpha), Color(col.r, col.g, col.b, alpha),
		Color(col.r, col.g, col.b, 0.0), Color(col.r, col.g, col.b, 0.0)])
	draw_polygon(pts, cols)

func _crowd(w: float, h: float) -> void:
	var base := h - 8.0
	var dark := Color("0a0d20")
	dark.a = 0.92
	var pts := PackedVector2Array()
	pts.append(Vector2(0, h))
	pts.append(Vector2(0, base - 34))
	var x := 0.0
	var i := 0
	while x < w:
		var head_r := 16.0 + fmod(float(i * 37 % 23), 9.0)
		var cx := x + head_r
		# raised arm every third head
		if i % 3 == 1:
			pts.append(Vector2(cx - head_r * 0.6, base - 30))
			pts.append(Vector2(cx - head_r * 0.35, base - 66))
			pts.append(Vector2(cx - head_r * 0.05, base - 34))
		# head bump
		for k in range(5):
			var a := PI - PI * float(k) / 4.0
			pts.append(Vector2(cx + cos(a) * head_r, base - 26 - sin(a) * head_r * 1.15))
		x += head_r * 2.1
		i += 1
	pts.append(Vector2(w, base - 34))
	pts.append(Vector2(w, h))
	draw_colored_polygon(pts, dark)
	# phone lights
	if _phones.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		for k in range(7):
			var col: Color = [StageTheme.CYAN, StageTheme.PINK, StageTheme.GOLD][k % 3]
			_phones.append([rng.randf_range(30, 690), base - rng.randf_range(58, 84), col, rng.randf_range(0.0, TAU)])
	for p in _phones:
		var blink := 0.35 + 0.65 * maxf(0.0, sin(_t * 1.2 + p[3]))
		var c: Color = p[2]
		draw_rect(Rect2(p[0], p[1], 5, 8), Color(c.r, c.g, c.b, 0.75 * blink), true)

## Smooth 0..1..0 easing over one period, peaking at the keyframe midpoint —
## matches the `0%,100% -> X; 50% -> Y` shape used by dchead/dcsway/dc-lamp specs.
func _anim_bounce(period: float, delay: float) -> float:
	var t: float = fmod(_t - delay, period)
	if t < 0.0:
		t += period
	var phase: float = t / period
	return (1.0 - cos(TAU * phase)) * 0.5

func _rotate_pt(p: Vector2, pivot: Vector2, angle_rad: float) -> Vector2:
	var v := p - pivot
	var s := sin(angle_rad)
	var c := cos(angle_rad)
	return pivot + Vector2(v.x * c - v.y * s, v.x * s + v.y * c)

## A round-capped stroke: a line plus small circles at both ends.
func _round_line(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	draw_line(a, b, col, width, true)
	draw_circle(a, width * 0.5, col)
	draw_circle(b, width * 0.5, col)

## Three groups of nodding heads bobbing over the crowd silhouette
## (spec: dchead, 720x56 local coords anchored to the screen bottom).
func _crowd_heads(w: float, h: float) -> void:
	# lifted well above the spec's 56px strip: this row sits BEHIND the front
	# silhouette (crest ≈ h-52..h-63), so only ~18px of each crown shows.
	var base_y := h - 90.0
	var groups := [
		{"period": 1.6, "delay": 0.0, "color": Color("04050e"),
			"heads": [[60.0, 34.0, 13.0], [248.0, 32.0, 14.0], [500.0, 33.0, 13.0], [700.0, 34.0, 14.0]]},
		{"period": 1.9, "delay": 0.5, "color": Color("050610"),
			"heads": [[118.0, 36.0, 15.0], [330.0, 35.0, 13.0], [560.0, 36.0, 15.0]]},
		{"period": 1.4, "delay": 0.9, "color": Color("04050e"),
			"heads": [[182.0, 34.0, 13.0], [415.0, 33.0, 14.0], [648.0, 33.0, 12.0]]},
	]
	for g in groups:
		var period: float = g["period"]
		var delay: float = g["delay"]
		var col: Color = g["color"]
		var dy: float = -2.5 * _anim_bounce(period, delay)
		for head in g["heads"]:
			var hx: float = head[0]
			var hy: float = head[1]
			var hr: float = head[2]
			draw_circle(Vector2(hx, base_y + hy + dy), hr, col)

## Four glowsticks swaying left/right around their handle's lower end
## (spec: dcsway, +-10deg about the grip's bottom point).
func _crowd_glowsticks(w: float, h: float) -> void:
	var base_y := h - 56.0
	var sticks := [
		{"grip_a": Vector2(96, 34), "grip_b": Vector2(104, 10), "tube_a": Vector2(104, 12), "tube_b": Vector2(106, 4),
			"color": Color("35e8e0"), "period": 1.6, "delay": 0.0},
		{"grip_a": Vector2(298, 36), "grip_b": Vector2(290, 12), "tube_a": Vector2(290, 14), "tube_b": Vector2(288, 6),
			"color": Color("ff4fa3"), "period": 1.9, "delay": 0.4},
		{"grip_a": Vector2(452, 34), "grip_b": Vector2(460, 8), "tube_a": Vector2(460, 10), "tube_b": Vector2(462, 2),
			"color": Color("a56bff"), "period": 1.4, "delay": 0.8},
		{"grip_a": Vector2(618, 36), "grip_b": Vector2(610, 12), "tube_a": Vector2(610, 14), "tube_b": Vector2(608, 6),
			"color": Color("ffb347"), "period": 1.7, "delay": 0.2},
	]
	for s in sticks:
		var grip_a: Vector2 = s["grip_a"]
		var grip_b: Vector2 = s["grip_b"]
		var tube_a: Vector2 = s["tube_a"]
		var tube_b: Vector2 = s["tube_b"]
		var col: Color = s["color"]
		var period: float = s["period"]
		var delay: float = s["delay"]
		var angle_deg: float = -10.0 + 20.0 * _anim_bounce(period, delay)
		var angle_rad: float = deg_to_rad(angle_deg)
		var pivot := grip_a  # lower endpoint (larger y = visually lower)
		var offset := Vector2(0, base_y)
		var rga := _rotate_pt(grip_a, pivot, angle_rad) + offset
		var rgb := _rotate_pt(grip_b, pivot, angle_rad) + offset
		var rta := _rotate_pt(tube_a, pivot, angle_rad) + offset
		var rtb := _rotate_pt(tube_b, pivot, angle_rad) + offset
		# dark handle
		_round_line(rga, rgb, Color("0a0c1a"), 5.0)
		# glowing tube: soft wide bloom pass, then a bright core
		_round_line(rta, rtb, Color(col.r, col.g, col.b, 0.35), 7.0)
		_round_line(rta, rtb, Color(col.r, col.g, col.b, 0.9), 3.0)

## Two small light-sign rectangles breathing in opacity.
func _crowd_signs(w: float, h: float) -> void:
	var base_y := h - 56.0
	var signs := [
		{"pos": Vector2(326, 38), "size": Vector2(9, 6), "color": Color("9fe9ff"), "op_hi": 0.55, "op_lo": 0.2, "period": 2.8},
		{"pos": Vector2(556, 40), "size": Vector2(9, 6), "color": Color("cdb2ff"), "op_hi": 0.5, "op_lo": 0.15, "period": 3.4},
	]
	for sgn in signs:
		var pos: Vector2 = sgn["pos"]
		var sz: Vector2 = sgn["size"]
		var col: Color = sgn["color"]
		var op_hi: float = sgn["op_hi"]
		var op_lo: float = sgn["op_lo"]
		var period: float = sgn["period"]
		var op: float = op_hi + (op_lo - op_hi) * _anim_bounce(period, 0.0)
		var r := Rect2(pos.x, base_y + pos.y, sz.x, sz.y)
		# bloom first, or a flat rect on a near-black silhouette just reads grey
		draw_rect(r.grow(4.0), Color(col.r, col.g, col.b, op * 0.16), true)
		draw_rect(r.grow(2.0), Color(col.r, col.g, col.b, op * 0.30), true)
		draw_rect(r, Color(col.r, col.g, col.b, minf(1.0, op * 1.6)), true)
