class_name WaveView
extends Control

## Particle sound-wave — ports the canvas routine in
## resources/Neon Rain Card Game.dc.html (`startWave`).
##
## 150 columns × 7 mirrored dot rows. The envelope is a sum of three drifting
## gaussian humps plus a floor; amplitude drives the colour from cyan to pink.
## The wave reads SCORE, not time: settling calls on_score() which raises
## `boost`, and boost eases back down on its own.

const COLS := 150
const ROWS := 7

var boost := 1.0          # current multiplier, eased toward _target
var _target := 1.0
var _t := 0.0
var _spark_phase: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i in range(COLS):
		_spark_phase.append(rng.randf_range(0.0, TAU))


## Feed a settled score. Spec: target = 1.4 + min(2.2, score / 80).
func on_score(norm: float) -> void:
	_target = 1.4 + minf(2.2, norm)


## A small kick when the player acts, so the wave answers input too.
func on_action() -> void:
	_target = maxf(_target, 1.25)


func _process(delta: float) -> void:
	_t += delta
	# spec eases at 0.045 per frame; scale to real time so it is frame-rate free
	var k: float = 1.0 - pow(1.0 - 0.045, delta * 60.0)
	boost += (_target - boost) * k
	if _target > 1.02 and absf(boost - _target) < 0.05:
		_target = 1.0            # decay back once the peak has been reached
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var cy := size.y * 0.5
	# vertical scale: the spec works in a 320px-tall canvas
	var vs := size.y / 320.0

	for i in range(COLS + 1):
		var u := float(i) / float(COLS)
		var x := u * w

		# envelope: three drifting gaussian humps + floor
		var env := 0.0
		env += 60.0 * exp(-pow((u - 0.32 - 0.04 * sin(_t * 0.7)) * 7.0, 2.0))
		env += 95.0 * exp(-pow((u - 0.52 - 0.03 * sin(_t * 0.9 + 2.0)) * 9.0, 2.0))
		env += 55.0 * exp(-pow((u - 0.74 + 0.05 * sin(_t * 0.6 + 4.0)) * 8.0, 2.0))
		env += 14.0
		env *= 0.8 + 0.2 * sin(_t * 2.2 + u * 30.0)
		env *= 1.0 + (boost - 1.0) * 0.85

		var jitter := sin(u * 90.0 + _t * 3.0) * 0.5 + 0.5
		var amp: float = minf(150.0, env * (0.55 + 0.45 * jitter)) * vs

		# cyan at rest, pink at the peaks
		var heat: float = minf(1.0, amp / (90.0 * vs))
		var col := Color(
			(60.0 + heat * 190.0) / 255.0,
			(220.0 - heat * 150.0) / 255.0,
			(230.0 + heat * 25.0) / 255.0)
		var bright: float = minf(1.45, 0.8 + boost * 0.18)
		var dot_scale: float = minf(1.5, 0.9 + boost * 0.14)

		for j in range(ROWS):
			var f := float(j + 1) / float(ROWS)
			var y := amp * f
			var a: float = minf(1.0, 0.55 * (1.0 - f * 0.55) * bright)
			var dr: float = (2.2 if j == ROWS - 1 else 1.4) * dot_scale
			draw_circle(Vector2(x, cy - y), dr, Color(col.r, col.g, col.b, a))
			draw_circle(Vector2(x + 3.0, cy + y * 0.8), dr, Color(col.r, col.g, col.b, a * 0.45))

		# stray sparkles above the crest
		if (i * 7) % 13 == 0:
			var sy := cy - amp - 8.0 - 20.0 * absf(sin(u * 40.0 + _t)) * vs
			draw_circle(Vector2(x + sin(_t + float(i)) * 6.0, sy), 1.1,
				Color(0.63, 0.86, 1.0, 0.25 + 0.2 * sin(_t * 4.0 + float(i))))

	# centre axis glow
	var axis_a: float = minf(0.95, 0.4 + boost * 0.18)
	var pts := PackedVector2Array([Vector2(0, cy), Vector2(w * 0.5, cy), Vector2(w, cy)])
	var cols := PackedColorArray([
		Color(0.21, 0.91, 0.88, 0.0),
		Color(0.55, 0.94, 1.0, axis_a),
		Color(0.21, 0.91, 0.88, 0.0)])
	draw_polyline_colors(pts, cols, 2.0)
