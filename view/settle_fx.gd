class_name SettleFx
extends Control

## Three-phase settle sequence, ported from `doSettle` in
## resources/Neon Rain Card Game.dc.html.
##
##   t=0      FLY    基础分 × 乘数 = ?   (boxes pop in, staggered 0/.06/.12)
##   t=450ms  MERGE  the product lands with a bounce; screen shake; wave boost
##   t=1500ms BURST  the panel shatters into 18 shards that fly to the score
##   t=2120ms        the score counts up
##
## Emits `burst(target)` when the shards launch and `finished` at the end.

signal burst_started
signal finished

const SHARDS := 18
# The wave sits at y 426..642, so its centre axis is 534. The panel must stay
# clear below that line: PANEL_Y - 34 (the backdrop's top edge) = 540.
const PANEL_Y := 574.0

var _phase := ""
var _t := 0.0
var _base := 0
var _mult := 1.0
var _bonus := 0
var _final := 0
var _shards: Array = []       # [pos, vel_target, size, delay]
var _target := Vector2(96, 112)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the whole UI is authored at 720×1280; anchors alone leave this at (0,0)
	position = Vector2.ZERO
	size = Vector2(720, 1280)
	visible = false
	set_process(false)


func play(base: int, mult: float, final_score: int, score_pos: Vector2, bonus: int = 0) -> void:
	_base = base
	_mult = mult
	_bonus = bonus
	_final = final_score
	_target = score_pos
	_phase = "fly"
	_t = 0.0
	_shards.clear()
	size = Vector2(720, 1280)
	visible = true
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	match _phase:
		"fly":
			if _t >= 0.45:
				_phase = "merge"
		"merge":
			if _t >= 1.50:
				_phase = "burst"
				_spawn_shards()
				burst_started.emit()
		"burst":
			if _t >= 2.45:
				_phase = ""
				visible = false
				set_process(false)
				finished.emit()
	queue_redraw()


func _spawn_shards() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_t * 1000.0) + _final
	for i in range(SHARDS):
		var p := Vector2(300.0 + rng.randf() * 120.0, PANEL_Y + 30.0 + rng.randf() * 40.0)
		_shards.append({
			"from": p,
			"size": 4.0 + rng.randf() * 6.0,
			"delay": rng.randf() * 0.28,
			"spin": rng.randf_range(-6.0, 6.0),
		})


## eased pop used by every box: overshoot then settle (mirrors dcmergein)
func _pop_scale(local_t: float) -> float:
	if local_t <= 0.0:
		return 0.0
	var u: float = clampf(local_t / 0.30, 0.0, 1.0)
	if u >= 1.0:
		return 1.0
	# 0 → 1.35 → .95 → 1.08 → 1
	return 0.3 + 1.05 * sin(u * PI * 0.5) + 0.18 * sin(u * PI * 2.2) * (1.0 - u)


func _draw() -> void:
	if _phase == "":
		return
	if _phase == "burst":
		_draw_shards()
		return

	var cx := size.x * 0.5
	var boxes := [
		{"cap": "基础分", "val": str(_base), "col": Color("ff9ecb"),
			"frame": Color(1.0, 79.0 / 255, 163.0 / 255, 0.85), "bg": Color(26.0 / 255, 8.0 / 255, 20.0 / 255, 0.94),
			"w": 108.0, "fs": 32, "delay": 0.0},
		{"cap": "乘数", "val": "×%s" % _fmt_mult(), "col": Color("8ff5ee"),
			"frame": Color(53.0 / 255, 232.0 / 255, 224.0 / 255, 0.85), "bg": Color(6.0 / 255, 20.0 / 255, 24.0 / 255, 0.94),
			"w": 108.0, "fs": 32, "delay": 0.06},
	]
	if _bonus > 0:
		# flat rewards land after the multiplier — they get their own beat
		boxes.append({"cap": "奖励分", "val": "+%d" % _bonus, "col": Color("cfa9ff"),
			"frame": Color(165.0 / 255, 107.0 / 255, 1.0, 0.85), "bg": Color(18.0 / 255, 10.0 / 255, 30.0 / 255, 0.94),
			"w": 92.0, "fs": 28, "delay": 0.12})
	boxes.append({"cap": "最终分数", "val": (str(_final) if _phase == "merge" else "?"), "col": Color("ffe9c9"),
		"frame": Color(1.0, 179.0 / 255, 71.0 / 255, 0.9), "bg": Color(30.0 / 255, 18.0 / 255, 4.0 / 255, 0.94),
		"w": 140.0, "fs": 36, "delay": 0.18 if _bonus > 0 else 0.12})

	# lay the row out: [box] × [box] (+ [box]) = [box]
	var syms: Array = ["×", "+", "="] if _bonus > 0 else ["×", "="]
	var gap := 14.0 if _bonus <= 0 else 10.0
	var sep_w := 26.0 if _bonus <= 0 else 22.0
	var total := 0.0
	for b in boxes:
		total += float(b["w"])
	total += gap * 4.0 + sep_w * 2.0
	var x := cx - total * 0.5

	# backdrop: the row has to read over the wave and the vinyl disc
	var lead: float = clampf(_t / 0.18, 0.0, 1.0)
	# 540..652 — below the wave axis (534), above the 手牌区 tab (659)
	var band := Rect2(cx - total * 0.5 - 34.0, PANEL_Y - 34.0, total + 68.0, 112.0)
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.043, 0.024, 0.078, 0.72 * lead)
	bsb.set_corner_radius_all(20)
	bsb.set_border_width_all(1)
	bsb.border_color = Color(0.55, 0.42, 0.85, 0.30 * lead)
	bsb.shadow_color = Color(0.0, 0.0, 0.0, 0.45 * lead)
	bsb.shadow_size = 26
	draw_style_box(bsb, band)

	var font := StageTheme.num("Bold")
	var zh := StageTheme.zh()
	for i in range(boxes.size()):
		var b: Dictionary = boxes[i]
		var sc := _pop_scale(_t - float(b["delay"]))
		if sc <= 0.0:
			x += float(b["w"]) + gap
			if i < boxes.size() - 1:
				x += sep_w + gap
			continue
		var bw: float = float(b["w"])
		var bh := 56.0
		var cxx := x + bw * 0.5
		var cyy := PANEL_Y + bh * 0.5

		# caption above the box
		draw_string(zh, Vector2(x, PANEL_Y - 10.0), String(b["cap"]),
			HORIZONTAL_ALIGNMENT_CENTER, bw, 13, Color(b["col"]))

		draw_set_transform(Vector2(cxx, cyy), 0.0, Vector2(sc, sc))
		var r := Rect2(-bw * 0.5, -bh * 0.5, bw, bh)
		var sb := StyleBoxFlat.new()
		sb.bg_color = b["bg"]
		sb.set_corner_radius_all(12)
		sb.set_border_width_all(2)
		sb.border_color = b["frame"]
		sb.shadow_color = Color(float(b["frame"].r), float(b["frame"].g), float(b["frame"].b), 0.45)
		sb.shadow_size = 18
		draw_style_box(sb, r)
		var fs: int = int(b["fs"])
		draw_string(font, Vector2(r.position.x, fs * 0.36), String(b["val"]),
			HORIZONTAL_ALIGNMENT_CENTER, bw, fs, Color(b["col"]))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		x += bw + gap
		if i < boxes.size() - 1:
			draw_string(font, Vector2(x, PANEL_Y + bh * 0.5 + 11.0), String(syms[i]),
				HORIZONTAL_ALIGNMENT_CENTER, sep_w, 30, Color("8a9cc4"))
			x += sep_w + gap


func _draw_shards() -> void:
	var local := _t - 1.50
	for sh in _shards:
		var u: float = clampf((local - float(sh["delay"])) / 0.80, 0.0, 1.0)
		if u <= 0.0:
			continue
		# cubic-bezier(.35,.5,.3,1)-ish ease
		var e: float = 1.0 - pow(1.0 - u, 2.4)
		var p: Vector2 = Vector2(sh["from"]).lerp(_target, e)
		var scl: float = 1.0 - 0.75 * e
		var a: float = 1.0 if u < 0.75 else (1.0 - (u - 0.75) / 0.25)
		var sz: float = float(sh["size"]) * scl
		draw_set_transform(p, float(sh["spin"]) * e, Vector2.ONE)
		draw_rect(Rect2(-sz * 0.5, -sz * 0.5, sz, sz), Color(1.0, 0.85, 0.63, a), true)
		draw_rect(Rect2(-sz * 0.9, -sz * 0.9, sz * 1.8, sz * 1.8), Color(1.0, 0.70, 0.28, a * 0.35), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _fmt_mult() -> String:
	if absf(_mult - round(_mult)) < 0.01:
		return str(int(round(_mult)))
	return "%.1f" % _mult
