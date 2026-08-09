class_name EqStrip
extends Control

## The vertical bar curtain that sits between the wave and the hand zone.
## Ports the strip in resources/Neon Rain Card Game.dc.html:
##
##   repeating-linear-gradient(90deg, rgba(120,140,220,.35) 0 12px,
##                                    transparent 12px 22px)
##   mask-image: linear-gradient(180deg, transparent, #000 60%)
##   opacity: .55;  animation: dcpulse 2s ease-in-out infinite
##
## Each bar is one textured rect carrying the vertical mask, so the whole
## curtain costs ~33 draw calls rather than a few hundred slices.

const BAR_W := 12.0
const PITCH := 22.0
const OPACITY := 0.55

var urgency := 0.0         # 0..1, final-seconds escalation: faster, pinker, louder

var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	# dcpulse: .85 → 1 → .85 over 2s; the warning window quadruples the tempo
	var period: float = lerpf(2.0, 0.5, urgency)
	var pulse: float = 0.85 + 0.15 * (0.5 - 0.5 * cos(_t * TAU / period))
	var a := 0.35 * OPACITY * pulse * (1.0 + 0.6 * urgency)
	var base := Color(120.0 / 255.0, 140.0 / 255.0, 220.0 / 255.0)
	var col_rgb := base.lerp(StageTheme.PINK, urgency * 0.65)
	var col := Color(col_rgb.r, col_rgb.g, col_rgb.b, a)
	var x := 0.0
	while x < size.x:
		draw_texture_rect(mask_tex(), Rect2(x, 0.0, BAR_W, size.y), false, col)
		x += PITCH


static var _mask: GradientTexture2D

## Vertical fade: transparent at the top, solid from 60% down.
static func mask_tex() -> GradientTexture2D:
	if _mask != null:
		return _mask
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 1.0)])
	_mask = GradientTexture2D.new()
	_mask.gradient = g
	_mask.width = 4
	_mask.height = 64
	_mask.fill_from = Vector2(0, 0)
	_mask.fill_to = Vector2(0, 1)
	return _mask
