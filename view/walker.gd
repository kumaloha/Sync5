class_name Walker
extends Node2D

## The protagonist walking the hand-zone perimeter — ports the `crew` table and
## the walker SVG in resources/Neon Rain Card Game.dc.html.
##
## Eight characters share one stick-figure skeleton (head + spine + legs) and
## differ by a `static` overlay (hat, headphones, arms), an animated `prop`
## (turntable, wand, glove, shaker, crystal ball, drumstick, mic, tattoo gun)
## and a twinkling accent dot.
##
## The spec's figure is authored in a 40×42 SVG whose walk anchor is at local
## (20, 46), i.e. the feet float 8px above the track. FIG_SCALE keeps that
## composition but lets us size the figure against our 114px cards.
##
## Spec has the legs static; we swing them off the bob phase so it reads as
## walking rather than sliding.

const FIG_SCALE := 1.35
const ANCHOR := Vector2(20.0, 46.0)     # walk point inside the 40×52 box
const BOB_PERIOD := 1.1                  # dcbob
const DOT_PERIOD := 1.4                  # dctwinkle

## The eight-strong crew. Geometry is in SVG units; `origin` is the resolved
## transform-origin of the prop group (the spec gives it as a fill-box %).
const CREW := [
	{
		"name": "DJ", "color": "35e8e0",
		"lines": [[[12, 9], [12, 12]], [[24, 9], [24, 12]], [[18, 17], [27, 21]]],
		"quads": [[[12, 9], [18, 1], [24, 9]]],       # headphone band
		"circles": [],
		"prop_lines": [], "prop_circles": [[30, 25, 4.5], [30, 25, 1.2]],
		"anim": "spin", "period": 2.4, "origin": [30, 25], "dot": [34, 14],
	},
	{
		"name": "魔术师", "color": "a56bff",
		"lines": [[[11, 5.5], [25, 5.5]], [[13, 5.5], [13, 0], [23, 0], [23, 5.5]],
			[[18, 17], [27, 13]]],
		"quads": [], "circles": [],
		"prop_lines": [[[27, 13], [34, 9]]], "prop_circles": [],
		"anim": "rock", "period": 1.6, "origin": [27, 13], "dot": [35, 4],
	},
	{
		"name": "拳手", "color": "ff4fa3",
		"lines": [[[18, 17], [10, 20]]], "quads": [], "circles": [[8.5, 20, 2.5]],
		"prop_lines": [[[18, 17], [26, 19]]], "prop_circles": [[28.5, 19, 2.8]],
		"anim": "jab", "period": 0.7, "origin": [18, 17], "dot": [34, 26],
	},
	{
		"name": "调酒师", "color": "ffb347",
		"lines": [[[18, 17], [26, 12]]], "quads": [], "circles": [],
		"prop_lines": [[[26, 11], [24, 4], [30, 4], [28, 11], [26, 11]], [[25, 7], [29, 7]]],
		"prop_circles": [],
		"anim": "rock", "period": 0.5, "origin": [27, 11], "dot": [33, 13],
	},
	{
		"name": "占卜师", "color": "a56bff",
		"lines": [[[18, 17], [26, 22]], [[18, 17], [10, 22]]],
		"quads": [[[10, 11], [18, -2], [26, 11]]],    # hood
		"circles": [],
		"prop_lines": [], "prop_circles": [[29, 25, 4.0]],
		"anim": "twinkle", "period": 1.8, "origin": [29, 25], "dot": [29, 25],
	},
	{
		"name": "鼓手", "color": "35e8e0",
		"lines": [[[26, 30], [34, 30], [33, 36], [27, 36], [26, 30]], [[18, 17], [24, 22]]],
		"quads": [], "circles": [],
		"prop_lines": [[[24, 22], [31, 26]], [[18, 17], [12, 22], [15, 27]]],
		"prop_circles": [],
		"anim": "rock", "period": 0.4, "origin": [12, 17], "dot": [36, 27],
	},
	{
		"name": "RAPPER", "color": "ff4fa3",
		"lines": [[[11, 6], [25, 6], [28, 8]], [[13, 6], [13, 2], [23, 2], [23, 6]],
			[[18, 17], [26, 13]]],
		"quads": [], "circles": [],
		"prop_lines": [[[27, 14.5], [27, 17]]], "prop_circles": [[27, 12.5, 2.0]],
		"anim": "bob", "period": 0.55, "origin": [27, 12.5], "dot": [33, 6],
	},
	{
		"name": "纹身师", "color": "9fe9ff",
		"lines": [[[18, 17], [26, 20]]], "quads": [], "circles": [],
		"prop_lines": [[[26, 18], [31, 18], [31, 24]], [[28, 16], [29, 20]]],
		"prop_circles": [],
		"anim": "buzz", "period": 0.12, "origin": [28.5, 20], "dot": [34, 27],
	},
]

var idx := 0
var facing := 1.0        # +1 right, -1 left
var dancing := false
var show_name := false   # only the crew contact sheet wants the name plate:
                         # in game the label collides with the hand cards

var _t := 0.0
var _ch: Dictionary = CREW[0]
var _col := Color.WHITE


func _ready() -> void:
	set_character(idx)


func set_character(i: int) -> void:
	idx = posmod(i, CREW.size())
	_ch = CREW[idx]
	_col = Color(String(_ch["color"]))
	queue_redraw()


func color() -> Color:
	return _col


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var bob_u: float = fmod(_t, BOB_PERIOD) / BOB_PERIOD
	var bob: float = -3.0 * sin(bob_u * PI)
	var s := FIG_SCALE
	var tilt := 0.0
	var extra := Vector2.ZERO
	if dancing:
		# settle celebration: hop and sway instead of the walking bob
		bob = -6.0 - 8.0 * absf(sin(_t * 9.0))
		tilt = sin(_t * 9.0) * 0.16
		extra = Vector2(sin(_t * 4.5) * 10.0, 0.0)

	var pivot: Vector2 = extra + Vector2(-ANCHOR.x * s * facing, (-ANCHOR.y + bob) * s)
	draw_set_transform(pivot, tilt, Vector2(s * facing, s))

	# ── skeleton ───────────────────────────────────────────────────────────
	_circle(Vector2(18, 10), 5.0, 1.6)
	_line([Vector2(18, 15), Vector2(18, 27)], 1.6)

	# legs swing off the bob phase (spec draws them static)
	var swing := sin(bob_u * TAU) * 3.5
	var lift: float = maxf(0.0, sin(bob_u * TAU)) * 1.5
	if dancing:
		swing = sin(_t * 9.0) * 5.0
		lift = 0.0
	_line([Vector2(18, 27), Vector2(13 - swing, 38 - lift)], 1.6)
	_line([Vector2(18, 27), Vector2(23 + swing, 38)], 1.6)

	# ── character overlay ──────────────────────────────────────────────────
	for q in _ch["quads"]:
		_quad(_v(q[0]), _v(q[1]), _v(q[2]), 1.5)
	for ln in _ch["lines"]:
		_line(_pts(ln), 1.5)
	for c in _ch["circles"]:
		_circle(Vector2(c[0], c[1]), float(c[2]), 1.5)

	# ── animated prop ──────────────────────────────────────────────────────
	var org := _v(_ch["origin"])
	var rot := 0.0
	var off := Vector2.ZERO
	var alpha := 1.0
	var u: float = fmod(_t, float(_ch["period"])) / float(_ch["period"])
	match String(_ch["anim"]):
		"spin":
			rot = u * TAU
		"rock":
			rot = deg_to_rad(14.0) * sin(u * TAU)          # ±14°
		"jab":
			# 0/40/100% rest, 20% forward 5px
			off = Vector2(5.0 * sin(minf(u, 0.4) / 0.4 * PI), 0.0)
		"bob":
			off = Vector2(0.0, -3.0 * sin(u * PI))
		"buzz":
			off = Vector2(1.0, 0.8) * sin(u * PI)
		"twinkle":
			alpha = 0.15 + 0.85 * (0.5 - 0.5 * cos(u * TAU))

	draw_set_transform(pivot, tilt, Vector2(s * facing, s))
	var prop_col := Color(_col.r, _col.g, _col.b, alpha)
	for ln in _ch["prop_lines"]:
		_line(_prop_xform(_pts(ln), org, rot, off), 1.5, prop_col)
	for c in _ch["prop_circles"]:
		var cc: Vector2 = _prop_xform([Vector2(c[0], c[1])], org, rot, off)[0]
		_circle(cc, float(c[2]), 1.5, prop_col)

	# accent dot
	var dot_u: float = fmod(_t, DOT_PERIOD) / DOT_PERIOD
	var da: float = 0.15 + 0.85 * (0.5 - 0.5 * cos(dot_u * TAU))
	var d := _v(_ch["dot"])
	draw_circle(d, 1.3, Color(_col.r, _col.g, _col.b, da))
	draw_circle(d, 3.2, Color(_col.r, _col.g, _col.b, da * 0.25))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if not show_name:
		return
	# name plate above the head — below the feet it would sit on the walk track.
	# Drawn unscaled so the glyphs stay crisp.
	var f := StageTheme.zh()
	var label := String(_ch["name"])
	var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var ly := (-ANCHOR.y - 9.0) * s   # clears the magician's top hat too
	draw_string(f, Vector2(-w * 0.5, ly), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(_col.r, _col.g, _col.b, 0.9))


# ── helpers ────────────────────────────────────────────────────────────────

func _v(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func _pts(raw: Array) -> Array:
	var out: Array = []
	for p in raw:
		out.append(_v(p))
	return out


func _prop_xform(pts: Array, org: Vector2, rot: float, off: Vector2) -> Array:
	var out: Array = []
	for p_v in pts:
		var p: Vector2 = p_v
		out.append(org + (p - org).rotated(rot) + off)
	return out


## Two passes: a soft wide halo then the core stroke — stands in for the
## spec's `filter: drop-shadow(0 0 5px color)`.
func _line(pts: Array, w: float, col: Color = Color.TRANSPARENT) -> void:
	var c: Color = _col if col.a == 0.0 else col
	var arr := PackedVector2Array()
	for p in pts:
		arr.append(p)
	if arr.size() < 2:
		return
	draw_polyline(arr, Color(c.r, c.g, c.b, c.a * 0.18), w * 2.0, true)
	draw_polyline(arr, c, w, true)


func _circle(center: Vector2, radius: float, w: float, col: Color = Color.TRANSPARENT) -> void:
	var c: Color = _col if col.a == 0.0 else col
	draw_arc(center, radius, 0.0, TAU, 24, Color(c.r, c.g, c.b, c.a * 0.18), w * 2.0, true)
	draw_arc(center, radius, 0.0, TAU, 24, c, w, true)


func _quad(p0: Vector2, ctrl: Vector2, p1: Vector2, w: float) -> void:
	var pts: Array = []
	for i in range(11):
		var t := float(i) / 10.0
		var a := p0.lerp(ctrl, t)
		var b := ctrl.lerp(p1, t)
		pts.append(a.lerp(b, t))
	_line(pts, w)
