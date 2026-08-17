class_name RunEndScreen
extends Control

## Section-end result screens, 1:1 from the user's mocks in docs/mockups/
## success.html + fail.html (the authority for these screens).
##
## SUCCESS 演出成功: three gold stars spin in, confetti + swaying beams +
## a sea of glowsticks, score panel with the clear wage chip, [返回主页][下一关▸].
## FAIL 演出失败: two hollow pink stars + the third star DROPS, dimmed static
## beams, rain streaks (per the mock — the old no-rain rule was about the
## in-game stage), cold skyline, sparse crowd, [返回主页][再来一次↻].
##
## All drawn in _draw() driven by _process time; the only child nodes are the
## two Buttons (children render after _draw, per the project rule).

signal next_pressed      # success: continue to the shop / next section
signal retry_pressed     # fail: restart the run
signal home_pressed      # both: back to the protagonist pick screen

const W := 720.0
const H := 1280.0

var _mode := ""           # "success" | "fail"
var _t := 0.0
var _score := 0
var _target := 1
var _wage := 0
var _finale := false
var _gig := 1             # which gig just cleared (1-based, shown on success)
var _confetti: Array = []
var _sticks: Array = []
var _btn_a: Button
var _btn_b: Button
var _rng := RandomNumberGenerator.new()

# gradient textures must be built ONCE and cached — a freshly created
# GradientTexture2D renders white on its first frames (and per-frame resource
# churn is waste)
static var _bg_cache: Dictionary = {}


func _ready() -> void:
	position = Vector2.ZERO
	size = Vector2(W, H)
	visible = false
	set_process(false)
	_btn_a = _button()
	_btn_a.position = Vector2(360.0 - 215.0 - 8.0, 840.0)
	_btn_a.pressed.connect(func() -> void: home_pressed.emit())
	add_child(_btn_a)
	_btn_b = _button()
	_btn_b.position = Vector2(360.0 + 8.0, 840.0)
	_btn_b.pressed.connect(_on_primary)
	add_child(_btn_b)


func _button() -> Button:
	var b := Button.new()
	b.add_theme_font_override("font", StageTheme.zh())
	b.add_theme_font_size_override("font_size", 21)
	b.custom_minimum_size = Vector2(215, 54)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _style_buttons() -> void:
	_btn_a.text = "返回主页"
	var cold := StageTheme.box(Color(0.047, 0.063, 0.14, 0.6), Color(0.47, 0.59, 0.78, 0.4), 1, 16)
	for st in ["normal", "hover", "pressed"]:
		_btn_a.add_theme_stylebox_override(st, cold)
	_btn_a.add_theme_color_override("font_color", Color("aebfe0"))
	var acc := StageTheme.CYAN if _mode == "success" else Color("ff4f7d")
	var hot := StageTheme.box(
		Color(acc.r * 0.12, acc.g * 0.12, acc.b * 0.12, 0.92), Color(acc.r, acc.g, acc.b, 0.9), 2, 16,
		Color(acc.r, acc.g, acc.b, 0.4), 10)
	for st in ["normal", "hover", "pressed"]:
		_btn_b.add_theme_stylebox_override(st, hot)
	_btn_b.add_theme_color_override("font_color", Color("eafffd") if _mode == "success" else Color("ffe3ec"))
	_btn_b.text = ("谢幕 ▸" if _finale else "下一场演出 ▸") if _mode == "success" else "再来一次 ↻"


func _on_primary() -> void:
	if _mode == "success":
		next_pressed.emit()
	else:
		retry_pressed.emit()


func show_success(score: int, target: int, wage: int, finale: bool, gig_no: int = 1) -> void:
	_mode = "success"
	_score = score
	_target = maxi(1, target)
	_wage = wage
	_finale = finale
	_gig = gig_no
	_rng.randomize()
	_make_confetti()
	_make_sticks()
	_open()


func show_fail(score: int, target: int) -> void:
	_mode = "fail"
	_score = score
	_target = maxi(1, target)
	_finale = false
	_open()


func _open() -> void:
	_t = 0.0
	_style_buttons()
	visible = true
	set_process(true)
	queue_redraw()


func close() -> void:
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


# ============================== GENERATORS ==============================

func _make_confetti() -> void:
	var colors := [Color("35e8e0"), Color("ff4fa3"), Color("a56bff"), Color("ffb347"), Color("9fe9ff"), Color("ff8bbd")]
	_confetti.clear()
	for i in range(26):
		_confetti.append({
			"x": _rng.randf_range(0.02, 0.98) * W,
			"w": _rng.randf_range(5.0, 12.0),
			"h": _rng.randf_range(10.0, 20.0),
			"col": colors[i % colors.size()],
			"rr": _rng.randf_range(TAU, TAU * 3.0),
			"dur": _rng.randf_range(3.4, 6.4),
			"off": _rng.randf_range(0.0, 6.0),
		})


func _make_sticks() -> void:
	var colors := [Color("35e8e0"), Color("ff4fa3"), Color("a56bff"), Color("ffb347"), Color("9fe9ff"), Color("ff8bbd"), Color("cdb2ff")]
	_sticks.clear()
	for i in range(26):
		var x := 14.0 + float(i) * 27.0 + _rng.randf() * 14.0
		var dx := (_rng.randf() - 0.5) * 18.0
		var top_y := 52.0 + _rng.randf() * 10.0
		_sticks.append({
			"ax": x, "ay": 90.0 + _rng.randf() * 6.0,
			"bx": x + dx, "by": top_y + 4.0,
			"gx": x + dx * 1.3, "gy": top_y - 12.0,
			"col": colors[i % colors.size()],
			"dur": _rng.randf_range(0.7, 1.2),
			"delay": _rng.randf_range(0.0, 1.2),
		})


# ============================== DRAW ==============================

func _draw() -> void:
	if _mode == "":
		return
	var ok := _mode == "success"
	_bg(ok)
	_beams(ok)
	if ok:
		_draw_confetti()
	_stars(ok)
	_title(ok)
	_panel(ok)
	_skyline(ok)
	if ok:
		_bottom_glow()
		_glowsticks()
	_crowd(ok)
	if not ok:
		_rain()


static func _bg_tex(ok: bool) -> Texture2D:
	var key := "ok" if ok else "fail"
	if not _bg_cache.has(key):
		var g := Gradient.new()
		if ok:
			g.colors = PackedColorArray([Color("070a1a"), Color("0a0d22"), Color("05060f"), Color("03030a")])
		else:
			g.colors = PackedColorArray([Color("060814"), Color("080a1a"), Color("04050e"), Color("020308")])
		g.offsets = PackedFloat32Array([0.0, 0.45, 0.78, 1.0])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 8
		t.height = 256
		t.fill_from = Vector2(0, 0)
		t.fill_to = Vector2(0, 1)
		_bg_cache[key] = t
	return _bg_cache[key]


func _bg(ok: bool) -> void:
	draw_texture_rect(_bg_tex(ok), Rect2(0, 0, W, H), false)
	# top radial washes
	var glow := PaperCard.glow_tex()
	if ok:
		draw_texture_rect(glow, Rect2(-460, -300, 1040, 600), false, Color(0.21, 0.91, 0.88, 0.22))
		draw_texture_rect(glow, Rect2(120, -260, 1120, 640), false, Color(1.0, 0.31, 0.64, 0.20))
		draw_texture_rect(glow, Rect2(-40, -230, 800, 520), false, Color(0.65, 0.42, 1.0, 0.14))
	else:
		draw_texture_rect(glow, Rect2(-460, -300, 1040, 600), false, Color(1.0, 0.31, 0.49, 0.12))
		draw_texture_rect(glow, Rect2(120, -260, 1120, 640), false, Color(0.65, 0.42, 1.0, 0.08))
		draw_texture_rect(glow, Rect2(-40, -230, 800, 520), false, Color(0.47, 0.55, 0.78, 0.06))


func _beams(ok: bool) -> void:
	# two spotlight cones; success sways ±8°, fail hangs dim and crooked
	var la := (sin(_t * TAU / 5.0) * 8.0) if ok else -6.0
	var ra := (sin((_t - 0.8) * TAU / 6.0) * 8.0) if ok else 7.0
	var lc := Color(0.21, 0.91, 0.88, 0.28 if ok else 0.10)
	var rc := Color(1.0, 0.31, 0.64, 0.24 if ok else 0.10)
	_beam(Vector2(230.0, 26.0), deg_to_rad(la), lc, Color("c9fffa") if ok else Color("5a6a8a"), ok)
	_beam(Vector2(490.0, 26.0), deg_to_rad(ra), rc, Color("ffd6e9") if ok else Color("8a5a6a"), ok)


func _beam(apex: Vector2, ang: float, col: Color, bulb: Color, ok: bool) -> void:
	var dirv := Vector2(sin(ang), cos(ang))
	var nrm := Vector2(dirv.y, -dirv.x)
	var len := 880.0
	var top_w := 16.0
	var bot_w := 300.0
	var pts := PackedVector2Array([
		apex - nrm * top_w * 0.5, apex + nrm * top_w * 0.5,
		apex + dirv * len + nrm * bot_w * 0.5, apex + dirv * len - nrm * bot_w * 0.5,
	])
	var fade := Color(col.r, col.g, col.b, 0.0)
	draw_polygon(pts, PackedColorArray([col, col, fade, fade]))
	var glow := PaperCard.glow_tex()
	var ga := 0.75 if ok else 0.4
	draw_texture_rect(glow, Rect2(apex - Vector2(26, 26), Vector2(52, 52)), false,
		Color(bulb.r, bulb.g, bulb.b, ga))
	draw_circle(apex, 6.0, bulb)


func _draw_confetti() -> void:
	for cf in _confetti:
		var p := fposmod((_t + float(cf["off"])) / float(cf["dur"]), 1.0)
		var y := -60.0 + p * (H + 120.0)
		var a := 1.0 if p < 0.9 else (1.0 - (p - 0.9) / 0.1)
		var rot: float = p * float(cf["rr"])
		var col: Color = cf["col"]
		draw_set_transform(Vector2(float(cf["x"]), y), rot, Vector2.ONE)
		var w: float = cf["w"]
		var h: float = cf["h"]
		draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h), Color(col.r, col.g, col.b, a * 0.9), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## dcstarin: scale 3.2→1 with overshoot, rotate -18°→0. Returns [scale, rot, alpha].
func _star_anim(delay: float) -> Array:
	var u := clampf((_t - delay) / 0.55, 0.0, 1.0)
	if u <= 0.0:
		return [0.0, 0.0, 0.0]
	var s: float
	if u < 0.55:
		s = lerpf(3.2, 0.92, u / 0.55)
	elif u < 0.75:
		s = lerpf(0.92, 1.12, (u - 0.55) / 0.2)
	else:
		s = lerpf(1.12, 1.0, (u - 0.75) / 0.25)
	var rot := deg_to_rad(lerpf(-18.0, 0.0, minf(u / 0.55, 1.0)))
	return [s, rot, minf(u / 0.55, 1.0)]


static func _star_pts(c: Vector2, R: float, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(10):
		var r := R if i % 2 == 0 else R * 0.45
		var a := -PI / 2.0 + rot + TAU * float(i) / 10.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


func _stars(ok: bool) -> void:
	var xs := [360.0 - 122.0, 360.0, 360.0 + 122.0]
	var ys := [212.0, 196.0, 212.0]
	var rr := [48.0, 60.0, 48.0]
	var glow := PaperCard.glow_tex()
	for i in range(3):
		var c := Vector2(xs[i], ys[i])
		if ok:
			var an := _star_anim(0.1 + 0.22 * float(i))
			if float(an[0]) <= 0.0:
				continue
			var gold := Color("ffb347")
			var gd: float = rr[i] * 3.4 * float(an[0])
			draw_texture_rect(glow, Rect2(c - Vector2(gd, gd) * 0.5, Vector2(gd, gd)), false,
				Color(gold.r, gold.g, gold.b, 0.55 * float(an[2])))
			draw_colored_polygon(_star_pts(c, rr[i] * float(an[0]), float(an[1])),
				Color(gold.r, gold.g, gold.b, float(an[2])))
		elif i < 2:
			var an2 := _star_anim(0.1 + 0.22 * float(i))
			if float(an2[0]) <= 0.0:
				continue
			var pink := Color(1.0, 0.49, 0.62, 0.75 * float(an2[2]))
			var ring := _star_pts(c, rr[i] * float(an2[0]), float(an2[1]))
			ring.append(ring[0])
			draw_polyline(ring, pink, 2.5, true)
		else:
			# the third star drops off: fade in while sliding down and keeling over
			var u := clampf((_t - 0.6) / 1.3, 0.0, 1.0)
			if u <= 0.0:
				continue
			var dy := 44.0 * minf(u / 0.6, 1.0)
			var rot := deg_to_rad(22.0 * minf(u / 0.6, 1.0))
			var grey := Color(0.47, 0.55, 0.71, 0.5 * minf(u * 5.0, 1.0))
			var ring2 := _star_pts(c + Vector2(0, dy), rr[i], rot)
			ring2.append(ring2[0])
			draw_polyline(ring2, grey, 2.5, true)


## Neon headline per the project recipe: wide halo = radial texture, tight
## halo = same-size ring sampling (radius ≤5px), then the sharp core.
func _neon_spaced(text: String, cy: float, fs: int, spacing: float, core: Color, halo: Color, halo_a: float) -> void:
	var font := StageTheme.zh()
	var widths: Array = []
	var total := 0.0
	for ch in text:
		var wd: float = font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		widths.append(wd)
		total += wd + spacing
	total -= spacing
	var glow := PaperCard.glow_tex()
	draw_texture_rect(glow, Rect2(360.0 - total * 0.75, cy - fs * 1.15, total * 1.5, fs * 2.2), false,
		Color(halo.r, halo.g, halo.b, halo_a * 0.55))
	var x := 360.0 - total * 0.5
	for i in range(text.length()):
		var ch := text[i]
		for k in range(8):
			var a := TAU * float(k) / 8.0
			draw_string(font, Vector2(x, cy) + Vector2(cos(a), sin(a)) * 3.0, ch,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(halo.r, halo.g, halo.b, halo_a * 0.22))
		draw_string(font, Vector2(x, cy), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, core)
		x += float(widths[i]) + spacing


func _title(ok: bool) -> void:
	if ok:
		var pulse := 0.75 + 0.25 * (0.5 + 0.5 * sin(_t * TAU / 2.4))
		_neon_spaced("演出成功", 410.0, 72, 18.0, Color("eafffd"), StageTheme.CYAN, pulse)
		_sub("第 %d 场演出 · 全场沸腾" % _gig, 448.0, Color("5fd8d0"))
	else:
		_neon_spaced("演出失败", 410.0, 72, 18.0, Color("ffe3ec"), Color("ff4fa3"), 0.9)
		_sub("STAGE FAILED · 观众散场了", 448.0, Color("c96a85"))


func _sub(text: String, y: float, col: Color) -> void:
	var font := StageTheme.zh()
	var spacing := 12.0
	var total := 0.0
	for ch in text:
		total += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + spacing
	total -= spacing
	var x := 360.0 - total * 0.5
	for ch in text:
		draw_string(font, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, col)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + spacing


## dcmergein for the panel: scale .3→1.15→.97→1.
func _merge_scale(delay: float) -> float:
	var u := clampf((_t - delay) / 0.5, 0.0, 1.0)
	if u <= 0.0:
		return 0.0
	if u < 0.4:
		return lerpf(0.3, 1.15, u / 0.4)
	if u < 0.7:
		return lerpf(1.15, 0.97, (u - 0.4) / 0.3)
	return lerpf(0.97, 1.0, (u - 0.7) / 0.3)


func _shown_score() -> int:
	var dur := 1.1 if _mode == "fail" else 1.3
	var p := clampf((_t - 0.5) / dur, 0.0, 1.0)
	return int(round(float(_score) * (1.0 - pow(1.0 - p, 3.0))))


func _panel(ok: bool) -> void:
	var sc := _merge_scale(0.5 if ok else 0.4)
	if sc <= 0.0:
		return
	var acc := StageTheme.CYAN if ok else Color("ff4f7d")
	var pw := 460.0
	var ph := 150.0 if ok else 138.0
	var c := Vector2(360.0, 490.0 + ph * 0.5)
	draw_set_transform(c, 0.0, Vector2(sc, sc))
	var r := Rect2(-pw * 0.5, -ph * 0.5, pw, ph)
	draw_style_box(StageTheme.box(
		Color(0.04, 0.10, 0.125, 0.8) if ok else Color(0.1, 0.035, 0.07, 0.8),
		Color(acc.r, acc.g, acc.b, 0.4), 1, 22,
		Color(acc.r, acc.g, acc.b, 0.15), 16), r)
	var num := StageTheme.num("Bold")
	var zh := StageTheme.zh()
	var shown := _shown_score()
	var score_col := Color("ffd9a0") if ok else Color("ff9ecb")
	var dim := Color("66799f") if ok else Color("8a6070")
	# 最终得分  {shown}  / {target}
	var num_w: float = num.get_string_size(str(shown), HORIZONTAL_ALIGNMENT_LEFT, -1, 76).x
	var lx := -num_w * 0.5 - 96.0
	draw_string(zh, Vector2(lx, r.position.y + 62.0), "最终得分", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, dim)
	draw_string(num, Vector2(-num_w * 0.5, r.position.y + 74.0), str(shown), HORIZONTAL_ALIGNMENT_LEFT, -1, 76, score_col)
	draw_string(num, Vector2(num_w * 0.5 + 12.0, r.position.y + 62.0), "/ %d" % _target, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, dim)
	# progress bar
	var bar := Rect2(r.position.x + 36.0, r.position.y + 88.0, pw - 72.0, 10.0)
	draw_style_box(StageTheme.box(Color(0.08, 0.1, 0.21, 0.9) if ok else Color(0.12, 0.06, 0.1, 0.9),
		Color(acc.r, acc.g, acc.b, 0.18), 1, 6), bar)
	var frac := clampf(float(shown) / float(_target), 0.0, 1.0)
	if frac > 0.02:
		var fill_col := Color("ffb347") if ok else Color("ff6f96")
		draw_style_box(StageTheme.box(fill_col, Color(0, 0, 0, 0), 0, 6),
			Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)))
	# footer line
	if ok:
		var chip := Rect2(-150.0, r.position.y + 108.0, 128.0, 34.0)
		draw_style_box(StageTheme.box(Color(0.12, 0.07, 0.02, 0.6), Color(1.0, 0.7, 0.28, 0.5), 1, 16), chip)
		draw_circle(chip.position + Vector2(24.0, 17.0), 9.0, Color("ffb347"))
		draw_string(num, Vector2(chip.position.x + 40.0, chip.position.y + 24.0), "+%d" % _wage,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("ffd9a0"))
		var chip2 := Rect2(-6.0, r.position.y + 108.0, 172.0, 34.0)
		draw_style_box(StageTheme.box(Color(0.08, 0.04, 0.14, 0.6), Color(0.65, 0.42, 1.0, 0.5), 1, 16), chip2)
		draw_string(zh, Vector2(chip2.position.x + 12.0, chip2.position.y + 24.0), "♪ 小丑牌 · 待挑选",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("cdb2ff"))
	else:
		var lack := maxi(0, _target - _score)
		var msg_a := "还差 "
		var msg_n := str(lack)
		var msg_b := " 分就能点燃全场"
		var wa: float = zh.get_string_size(msg_a, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		var wn: float = num.get_string_size(msg_n, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		var wb: float = zh.get_string_size(msg_b, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		var x0 := -(wa + wn + wb) * 0.5
		draw_string(zh, Vector2(x0, r.position.y + 128.0), msg_a, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("c96a85"))
		draw_string(num, Vector2(x0 + wa, r.position.y + 128.0), msg_n, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("ffd9a0"))
		draw_string(zh, Vector2(x0 + wa + wn, r.position.y + 128.0), msg_b, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("c96a85"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


const SKYLINE := [34, 34, 20, 20, 40, 40, 12, 12, 32, 32, 44, 44, 18, 18, 38, 38, 26, 26, 46, 46, 8, 8, 30, 30, 42, 42, 22, 22, 36, 36, 16, 16, 40, 40]
const SKYLINE_X := [0, 38, 38, 74, 74, 118, 118, 152, 152, 200, 200, 248, 248, 286, 286, 338, 338, 382, 382, 430, 430, 462, 462, 512, 512, 556, 556, 596, 596, 648, 648, 682, 682, 720]

func _skyline(ok: bool) -> void:
	var base_y := (H - 96.0 - 72.0) if ok else (H - 78.0 - 72.0)
	var alpha := 0.8 if ok else 0.55
	var pts := PackedVector2Array([Vector2(0, base_y + 72.0)])
	for i in range(SKYLINE_X.size()):
		pts.append(Vector2(float(SKYLINE_X[i]), base_y + float(SKYLINE[i])))
	pts.append(Vector2(W, base_y + 72.0))
	draw_colored_polygon(pts, Color(0.027, 0.035, 0.078, alpha))
	# blinking windows + antennas
	var blink := 0.5 + 0.5 * sin(_t * TAU / 4.1)
	draw_rect(Rect2(256, base_y + 24, 4, 5), Color(1.0, 0.31, 0.64, (0.6 if ok else 0.35) * blink), true)
	draw_line(Vector2(434, base_y + 8), Vector2(434, base_y + 46), Color(1.0, 0.31, 0.64, 0.7 if ok else 0.3), 1.5)
	if ok:
		var blink2 := 0.5 + 0.5 * sin(_t * TAU / 3.2 + 1.0)
		draw_rect(Rect2(128, base_y + 18, 4, 5), Color(0.21, 0.91, 0.88, 0.7 * blink2), true)
		draw_rect(Rect2(438, base_y + 14, 4, 5), Color(0.65, 0.42, 1.0, 0.7 * blink), true)
		draw_line(Vector2(156, base_y + 12), Vector2(156, base_y + 32), Color(0.21, 0.91, 0.88, 0.6), 1.5)


func _bottom_glow() -> void:
	var glow := PaperCard.glow_tex()
	draw_texture_rect(glow, Rect2(360.0 - 360.0, H - 110.0, 720.0, 140.0), false, Color(0.65, 0.42, 1.0, 0.14))
	draw_texture_rect(glow, Rect2(-120.0, H - 80.0, 440.0, 100.0), false, Color(0.21, 0.91, 0.88, 0.10))
	draw_texture_rect(glow, Rect2(400.0, H - 80.0, 440.0, 100.0), false, Color(1.0, 0.31, 0.64, 0.10))


func _glowsticks() -> void:
	var oy := H - 110.0
	for gs in _sticks:
		var sway := deg_to_rad(12.0) * sin((_t + float(gs["delay"])) * TAU / float(gs["dur"]))
		var pivot := Vector2(float(gs["ax"]), oy + float(gs["ay"]))
		draw_set_transform(pivot, sway, Vector2.ONE)
		var arm := Vector2(float(gs["bx"]) - float(gs["ax"]), float(gs["by"]) - float(gs["ay"]))
		var tip := Vector2(float(gs["gx"]) - float(gs["ax"]), float(gs["gy"]) - float(gs["ay"]))
		draw_line(Vector2.ZERO, arm, Color("141a34"), 4.5, true)
		var col: Color = gs["col"]
		draw_line(arm, tip, Color(col.r, col.g, col.b, 0.35), 7.0, true)
		draw_line(arm, tip, Color(col.r, col.g, col.b, 0.9), 3.4, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _crowd(ok: bool) -> void:
	var oy := H - 110.0
	var amp := 4.0 if ok else 1.5
	var rows: Array
	if ok:
		rows = [
			{"y": 86.0, "r": 10.5, "n": 13, "step": 54.0, "x0": 22.0, "dur": 1.0, "ph": 0.0, "col": Color("0c1022")},
			{"y": 93.0, "r": 12.5, "n": 12, "step": 58.0, "x0": 48.0, "dur": 0.8, "ph": 0.3, "col": Color("101530")},
			{"y": 102.0, "r": 13.5, "n": 12, "step": 60.0, "x0": 20.0, "dur": 1.2, "ph": 0.6, "col": Color("131836")},
		]
	else:
		rows = [
			{"y": 88.0, "r": 10.5, "n": 4, "step": 203.0, "x0": 60.0, "dur": 2.6, "ph": 0.0, "col": Color("0c1022")},
			{"y": 96.0, "r": 12.0, "n": 3, "step": 215.0, "x0": 130.0, "dur": 3.0, "ph": 0.5, "col": Color("101528")},
			{"y": 104.0, "r": 13.0, "n": 4, "step": 220.0, "x0": 30.0, "dur": 0.0, "ph": 0.0, "col": Color("12162c")},
		]
	for row in rows:
		var bob := 0.0
		if float(row["dur"]) > 0.0:
			bob = -amp * (0.5 + 0.5 * sin((_t - float(row["ph"])) * TAU / float(row["dur"])))
		for i in range(int(row["n"])):
			draw_circle(Vector2(float(row["x0"]) + float(i) * float(row["step"]), oy + float(row["y"]) + bob),
				float(row["r"]), row["col"])


func _rain() -> void:
	# the mock's dcrain layer: sparse near-vertical streaks scrolling fast
	var col := Color(0.71, 0.86, 1.0, 0.064)
	var drop := fposmod(_t * 820.0, 300.0)
	var dirv := Vector2(sin(deg_to_rad(12.0)), cos(deg_to_rad(12.0)))
	for i in range(10):
		var x0 := -80.0 + float(i) * 80.0 - drop * dirv.x
		var y0 := fposmod(drop + float(i * 137), 300.0)
		var y := y0 - 300.0
		while y < H:
			var a := Vector2(x0 + (y + 300.0) * dirv.x * 0.21, y)
			draw_line(a, a + dirv * 34.0, col, 2.0, true)
			y += 300.0
