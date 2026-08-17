class_name PaperCard
extends Button

## Neon GLASS playing card — implements docs/mockups/整副卡牌.dc.html
## (1a 玻璃底 × 2a 传统点阵). Dark translucent body, suit-coloured glowing
## frame, 115° sheen sweep, hairline top highlight, cut-corner inner frame.
## A–10 use the traditional pip layout, J/Q/K a large centred suit,
## 大王/小王 the jester mark. Red suits glow #ff6aa9, black #9fe9ff.

const RATIO := 170.0 / 114.0     # design card is 114×170

## pip layout, ported verbatim from the spec:
## rank -> [[x%, y%, rotated, fontSize?], ...]   (L=29, R=71, C=50)
const L := 29.0
const R := 71.0
const C := 50.0
const LAYOUTS := {
	14: [[C, 50.0, 0, 48.0]],
	2: [[C, 26.0, 0], [C, 74.0, 1]],
	3: [[C, 24.0, 0], [C, 50.0, 0], [C, 76.0, 1]],
	4: [[L, 26.0, 0], [R, 26.0, 0], [L, 74.0, 1], [R, 74.0, 1]],
	5: [[L, 26.0, 0], [R, 26.0, 0], [C, 50.0, 0], [L, 74.0, 1], [R, 74.0, 1]],
	6: [[L, 26.0, 0], [R, 26.0, 0], [L, 50.0, 0], [R, 50.0, 0], [L, 74.0, 1], [R, 74.0, 1]],
	7: [[L, 24.0, 0], [R, 24.0, 0], [C, 37.0, 0], [L, 50.0, 0], [R, 50.0, 0], [L, 76.0, 1], [R, 76.0, 1]],
	8: [[L, 24.0, 0], [R, 24.0, 0], [C, 37.0, 0], [L, 50.0, 0], [R, 50.0, 0], [C, 63.0, 1], [L, 76.0, 1], [R, 76.0, 1]],
	9: [[L, 22.0, 0], [R, 22.0, 0], [L, 41.0, 0], [R, 41.0, 0], [C, 50.0, 0], [L, 59.0, 1], [R, 59.0, 1], [L, 78.0, 1], [R, 78.0, 1]],
	10: [[L, 22.0, 0], [R, 22.0, 0], [C, 31.0, 0], [L, 41.0, 0], [R, 41.0, 0], [L, 59.0, 1], [R, 59.0, 1], [C, 69.0, 1], [L, 78.0, 1], [R, 78.0, 1]],
}

signal drop_received(data: Dictionary)

var card: Card = null
var scoring := false
var selected := false
var show_back := false
var violet := false                 # cache slots use the violet chrome
var drag_payload: Dictionary = {}
var accept_zones: Array = []
var blocked_label := ""             # compact public Blind marker: 弃 / 换 / 丢

static var _sheen: GradientTexture2D = null


## How far the reflection is foreshortened. 1.0 would be a true 1:1 mirror;
## the whole 170px card compresses into ~65px, which is the room the hand
## frame leaves below the cards.
const MIRROR_SQUASH := 0.38

var is_mirror := false          # the flipped copy under the card
var _mirror: PaperCard = null


func _init() -> void:
	clip_text = true
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	if is_mirror:
		return
	# `-webkit-box-reflect: below 5px linear-gradient(transparent 78%, .15)`
	# is a REAL mirror of the element, gradient-masked — a tinted blur under
	# the card (what this used to draw) has no glass in it because none of the
	# card's own content is actually in the image.
	_mirror = PaperCard.new()
	_mirror.is_mirror = true
	_mirror.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mirror.disabled = true
	_mirror.material = _mask_material(size.y, 1.0, 0.16)
	add_child(_mirror)
	_sync_mirror()


## Keep the flipped copy showing exactly what the card shows.
func _sync_mirror() -> void:
	if _mirror == null:
		return
	_mirror.card = card
	_mirror.show_back = show_back
	_mirror.violet = violet
	_mirror.scoring = scoring
	_mirror.selected = selected
	_mirror.blocked_label = blocked_label
	_mirror.size = size
	# Flipped AND foreshortened. A 1:1 mirror masked to the spec's 22% band
	# only ever showed the card's bottom edge — a bare frame. Squashing the
	# whole card into the band instead puts all of its content in the
	# reflection, which is what a card lying on a wet floor actually looks
	# like at a low viewing angle.
	var gap := 5.0 * (size.x / 114.0)
	_mirror.scale = Vector2(1, -MIRROR_SQUASH)
	_mirror.position = Vector2(0, size.y * (1.0 + MIRROR_SQUASH) + gap)
	_mirror._apply_style()
	_mirror.queue_redraw()


## Fades the mirror out with distance from the seam. Done in a shader because
## the mask has to apply uniformly to every primitive the card draws —
## styleboxes, glyphs, textures — not be threaded through each call.
static func _mask_material(h: float, fade: float, peak: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float card_h = 170.0;
uniform float fade = 0.22;   // visible fraction of the mirror, from the seam
uniform float peak = 0.15;   // alpha at the seam
varying float ly;
void vertex() { ly = VERTEX.y; }
void fragment() {
	float t = (card_h - ly) / max(card_h * fade, 0.001);
	// eased so the far end of the reflection disappears rather than
	// stopping on a visible line
	COLOR.a *= peak * pow(clamp(1.0 - t, 0.0, 1.0), 1.5);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("card_h", h)
	m.set_shader_parameter("fade", fade)
	m.set_shader_parameter("peak", peak)
	return m

func _get_drag_data(_pos: Vector2) -> Variant:
	if drag_payload.is_empty() or card == null:
		return null
	var prev := PaperCard.new()
	prev.size = size
	prev.setup(card)
	prev.modulate = Color(1, 1, 1, 0.88)
	prev.rotation_degrees = 5.0
	prev.pivot_offset = size * 0.5
	set_drag_preview(prev)
	return drag_payload

func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return data is Dictionary and not bool(data.get("swap_blocked", false)) \
		and accept_zones.has(data.get("zone", ""))

func _drop_data(_pos: Vector2, data: Variant) -> void:
	drop_received.emit(data)

func setup(c: Card) -> void:
	card = c
	_apply_style()
	_sync_mirror()
	queue_redraw()

func set_back(b: bool) -> void:
	if show_back == b:
		return
	show_back = b
	_apply_style()
	_sync_mirror()
	queue_redraw()

func set_states(p_scoring: bool, p_selected: bool) -> void:
	if scoring == p_scoring and selected == p_selected:
		return
	scoring = p_scoring
	selected = p_selected
	_apply_style()
	_sync_mirror()
	queue_redraw()


func set_blocked(label: String) -> void:
	if blocked_label == label:
		return
	blocked_label = label
	_sync_mirror()
	queue_redraw()


## 115° sheen sweep across the glass, shared by every card.
static func sheen() -> GradientTexture2D:
	if _sheen == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.28, 0.44, 0.66, 1.0])
		g.colors = PackedColorArray([
			Color(1, 1, 1, 0.18), Color(1, 1, 1, 0.05),
			Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.06)])
		_sheen = GradientTexture2D.new()
		_sheen.gradient = g
		_sheen.width = 128
		_sheen.height = 190
		_sheen.fill_from = Vector2(0.0, 0.30)   # ≈115°
		_sheen.fill_to = Vector2(1.0, 0.72)
	return _sheen


## Ink colour for the rank and the suit — always the suit's own colour.
## There are only two: pink for ♥♦, cyan for ♠♣. Being in the cache must not
## recolour them; that is the frame's job (see _chrome / _frame).
func _accent() -> Color:
	if card == null:
		return StageTheme.SUIT_BLK
	return StageTheme.SUIT_RED if card.is_red() else StageTheme.SUIT_BLK


## Chrome colour for the card's own trim — violet while the card sits in the
## cache, so the row reads as a distinct zone.
func _chrome() -> Color:
	if violet:
		return StageTheme.CACHE_ACCENT
	return _accent()


func _frame() -> Color:
	if selected:
		return StageTheme.MARKED
	if violet:
		return Color(StageTheme.CACHE_ACCENT.r, StageTheme.CACHE_ACCENT.g, StageTheme.CACHE_ACCENT.b, 0.8)
	if card == null:
		return StageTheme.FRAME_BLK
	return StageTheme.frame_color(card)


func _apply_style() -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(12)
	if show_back:
		sb.bg_color = Color(0.10, 0.047, 0.13, 0.92)
		sb.set_border_width_all(2)
		sb.border_color = Color(1.0, 79.0 / 255, 163.0 / 255, 0.45)
		sb.shadow_color = Color(1.0, 79.0 / 255, 163.0 / 255, 0.22)
		sb.shadow_size = 10
	else:
		var f := _frame()
		sb.bg_color = StageTheme.GLASS_BODY
		sb.set_border_width_all(2)
		sb.border_color = f
		# the frame's own bloom — this is what makes the card read as neon glass
		sb.shadow_color = Color(f.r, f.g, f.b, 0.55 if selected else 0.42)
		sb.shadow_size = 18 if selected else 14
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(st, sb)


func _draw() -> void:
	var w := size.x
	var h := size.y
	if show_back:
		_draw_back(w, h)
		return
	if card == null:
		return
	var acc := _accent()

	# glass depth: darker toward the bottom, then the 115° sheen on top
	draw_rect(Rect2(2, h * 0.42, w - 4, h * 0.56), Color(0.02, 0.01, 0.05, 0.30), true)
	draw_texture_rect(sheen(), Rect2(2, 2, w - 4, h - 4), false)
	# hairline along the top edge
	draw_line(Vector2(6, 2.5), Vector2(w - 6, 2.5), Color(1, 1, 1, 0.42), 1.0)
	# inner frame with two cut corners (clip-path polygon in the spec)
	var chr := _chrome()
	_inner_frame(w, h, Color(chr.r, chr.g, chr.b, 0.30))

	if card.is_wild():
		_draw_wild(w, h, acc)
	else:
		_corner(Vector2(13, 11), acc, false)
		_corner(Vector2(w - 13, h - 11), acc, true)
		_draw_centre_suit(w, h, acc)

	if selected:
		_draw_tag(w)
	if blocked_label != "":
		var mark := Rect2(w - 33.0, 8.0, 25.0, 25.0)
		draw_style_box(StageTheme.box(Color(0.12, 0.01, 0.06, 0.92),
			StageTheme.PINK, 1, 7, Color(StageTheme.PINK.r,
			StageTheme.PINK.g, StageTheme.PINK.b, 0.32), 7), mark)
		draw_string(StageTheme.zh(), Vector2(mark.position.x, mark.position.y + 18.0),
			blocked_label, HORIZONTAL_ALIGNMENT_CENTER, mark.size.x, 13, Color("ffd5e6"))



func _inner_frame(w: float, h: float, col: Color) -> void:
	var i := 6.0
	var cut := 10.0
	var pts := PackedVector2Array([
		Vector2(i + cut, i), Vector2(w - i, i), Vector2(w - i, h - i - cut),
		Vector2(w - i - cut, h - i), Vector2(i, h - i), Vector2(i, i + cut),
		Vector2(i + cut, i)])
	draw_polyline(pts, col, 1.0, true)


## Just the rank, glowing. Bottom-right copy is rotated 180°.
## (The pip grid and the J/Q/K court art were dropped — the final face is
## corner rank + one big centre suit, nothing else.)
func _corner(pos: Vector2, acc: Color, rotated: bool) -> void:
	var s := size.x / 114.0
	draw_set_transform(pos, PI if rotated else 0.0, Vector2.ONE)
	var font := StageTheme.num("Bold")
	var fs := int(32.0 * s)
	# tube glow in the suit colour, near-white filament on top
	_neon_text(font, card.rank_label(), Vector2(0, fs * 0.84), fs, acc, StageTheme.CARD_INK)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## One large suit glyph, dead centre.
func _draw_centre_suit(w: float, h: float, acc: Color) -> void:
	var s := w / 114.0
	_suit(Vector2(w * 0.5, h * 0.5), 27.0 * s, acc, false)


## 大王 / 小王 — vertical JOKER rails plus the jester mark, all in the same
## neon-tube language as the number cards: a soft wide halo under a sharp
## core, on every line, dot and letter. Warm (SUIT_RED) for 大王, cool
## (SUIT_BLK) for 小王 — `acc` already carries that via `_accent()`.
func _draw_wild(w: float, h: float, acc: Color) -> void:
	var s := w / 114.0
	var font := StageTheme.num("SemiBold")
	var joker_fs := int(11.0 * s)
	for side in [9.0 * s, w - 9.0 * s]:
		draw_set_transform(Vector2(side, h * 0.5 - 34.0 * s), PI * 0.5, Vector2.ONE)
		_neon_text(font, "J O K E R", Vector2.ZERO, joker_fs, acc, StageTheme.CARD_INK)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var c := Vector2(w * 0.5, h * 0.46)
	var u := 1.0 * s
	var face_centre := c + Vector2(0, 9 * u)
	# a lit-lamp bloom behind the jester's face before the crisp linework
	var d := 30.0 * u
	draw_texture_rect(glow_tex(), Rect2(face_centre - Vector2(d, d) * 0.5, Vector2(d, d)),
		false, Color(acc.r, acc.g, acc.b, 0.35))
	# jester hat
	_neon_line(PackedVector2Array([
		c + Vector2(0, -6 * u), c + Vector2(-17 * u, -26 * u), c + Vector2(-9 * u, -8 * u),
		c + Vector2(0, -30 * u), c + Vector2(9 * u, -8 * u), c + Vector2(17 * u, -26 * u),
		c + Vector2(0, -6 * u)]), acc, 2.0 * s)
	for bell in [Vector2(-17, -26), Vector2(0, -30), Vector2(17, -26)]:
		_neon_dot(c + bell * u, 2.5 * u, acc)
	# face
	_neon_arc(face_centre, 13 * u, 0, TAU, 32, acc, 2.0 * s)
	_neon_dot(c + Vector2(-5 * u, 6 * u), 1.6 * u, acc)
	_neon_dot(c + Vector2(5 * u, 6 * u), 1.6 * u, acc)
	_neon_arc(c + Vector2(0, 10 * u), 6 * u, 0.25 * PI, 0.75 * PI, 12, acc, 1.8 * s)
	# collar
	_neon_line(PackedVector2Array([
		c + Vector2(-16 * u, 34 * u), c + Vector2(-8 * u, 26 * u), c + Vector2(0, 34 * u),
		c + Vector2(8 * u, 26 * u), c + Vector2(16 * u, 34 * u)]), acc, 2.0 * s)
	var lbl := "大王" if card.is_big_joker() else "小王"
	var zh_font := StageTheme.zh()
	var lbl_fs := int(12.0 * s)
	var lbl_w := zh_font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, lbl_fs).x
	_neon_text(zh_font, lbl, Vector2((w - lbl_w) * 0.5, h - 12.0 * s), lbl_fs, acc, StageTheme.CARD_INK)


## Two-pass neon stroke for the joker's line art: a wide (2.6×), faint
## (alpha 0.18) glow pass under a sharp core pass — the vector-line analogue
## of what `_neon_text`'s ring sampling does for glyphs.
func _neon_line(pts: PackedVector2Array, col: Color, width: float) -> void:
	draw_polyline(pts, Color(col.r, col.g, col.b, col.a * 0.18), width * 2.6, true)
	draw_polyline(pts, col, width, true)


func _neon_arc(center: Vector2, radius: float, angle_from: float, angle_to: float,
		point_count: int, col: Color, width: float) -> void:
	draw_arc(center, radius, angle_from, angle_to, point_count,
		Color(col.r, col.g, col.b, col.a * 0.18), width * 2.6, true)
	draw_arc(center, radius, angle_from, angle_to, point_count, col, width, true)


func _neon_dot(center: Vector2, radius: float, col: Color) -> void:
	draw_circle(center, radius * 2.6, Color(col.r, col.g, col.b, col.a * 0.18))
	draw_circle(center, radius, col)


func _draw_tag(w: float) -> void:
	var s := w / 114.0
	var tw := 58.0 * s
	var tag := Rect2(w * 0.5 - tw * 0.5, -14.0 * s, tw, 24.0 * s)
	var sb := StyleBoxFlat.new()
	sb.bg_color = StageTheme.MARKED
	sb.set_corner_radius_all(int(10.0 * s))
	sb.shadow_color = Color(StageTheme.MARKED.r, StageTheme.MARKED.g, StageTheme.MARKED.b, 0.7)
	sb.shadow_size = 10
	draw_style_box(sb, tag)
	draw_string(StageTheme.zh(), Vector2(tag.position.x, tag.position.y + 17.0 * s), "待弃",
		HORIZONTAL_ALIGNMENT_CENTER, tw, int(14.0 * s), Color("3a2200"))


## Card back: diagonal lattice + ♪ medallion (user PNG wins if present).
func _draw_back(w: float, h: float) -> void:
	var pink := Color(1.0, 79.0 / 255, 163.0 / 255, 1.0)
	draw_rect(Rect2(4, 4, w - 8, h - 8), Color(pink.r, pink.g, pink.b, 0.25), false, 1.0)
	# diagonal lattice both ways, clipped to the inner rect
	var lat := Color(pink.r, pink.g, pink.b, 0.16)
	var m := 6.0
	var step := 12.0
	var span := h - m * 2.0
	for dir_v in [1.0, -1.0]:
		var dir: float = dir_v
		var d: float = m - span
		while d < w - m + span:
			var ax: float = d
			var bx: float = d + dir * span
			var ay: float = m
			var by: float = h - m
			# clip the segment to [m, w-m] on x, moving y proportionally
			if ax < m:
				if bx <= m:
					d += step
					continue
				ay = lerpf(ay, by, (m - ax) / (bx - ax))
				ax = m
			if ax > w - m:
				if bx >= w - m:
					d += step
					continue
				ay = lerpf(ay, by, (ax - (w - m)) / (ax - bx))
				ax = w - m
			if bx < m:
				by = lerpf(by, ay, (m - bx) / (ax - bx))
				bx = m
			if bx > w - m:
				by = lerpf(by, ay, (bx - (w - m)) / (bx - ax))
				bx = w - m
			draw_line(Vector2(ax, ay), Vector2(bx, by), lat, 1.0)
			d += step

	var c := Vector2(w * 0.5, h * 0.5)
	draw_arc(c, 21.0 * (w / 114.0), 0, TAU, 36, Color(pink.r, pink.g, pink.b, 0.5), 1.0)
	draw_string(StageTheme.zh(), Vector2(0, c.y + 8.0), "♪",
		HORIZONTAL_ALIGNMENT_CENTER, w, int(20.0 * (w / 114.0)), Color("ff7ebd"))


## One suit glyph. Drawn from the font — the hand-rolled vector spade/club
## fell apart once the face went to a single large centre suit, and the spec
## renders the suits as text anyway. r ≈ half the glyph height.
const SUIT_GLYPH := {0: "\u2663", 1: "\u2666", 2: "\u2665", 3: "\u2660"}

func _suit(pos: Vector2, r: float, col: Color, rotated: bool) -> void:
	var g: String = "\u2666" if card.is_wild() else String(SUIT_GLYPH[card.suit])
	var f := StageTheme.zh()
	var fs := int(round(r * 2.4))
	draw_set_transform(pos, PI if rotated else 0.0, Vector2.ONE)
	var cw := f.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	# halo 0.55: the big glyph carries a lot of lit area already \u2014 full-strength
	# bloom read as a flashlight and drowned the rank corners
	_neon_text(f, g, Vector2(-cw * 0.5, fs * 0.36), fs, col,
		col.lerp(Color(1, 1, 1, col.a), 0.16), 0.55)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Neon text: the bloom is built from ring-offset copies of the SAME glyph at
## the SAME size. Scaling the glyph up for the halo instead (what this used to
## do) never nests concentrically — the font rasterises each size differently
## and the baseline drifts — so it read as a doubled, downward smear rather
## than light. Core is drawn last and stays crisp.
func _neon_text(font: Font, txt: String, at: Vector2, fs: int,
		glow: Color, core: Color, halo := 1.0) -> void:
	neon_text(self, font, txt, at, fs, glow, core, halo, size.x / 114.0)


## 同一支霓虹管, 任何 CanvasItem 都能在自己的 `_draw()` 里借用 —— 盲注卡要和
## 手牌是**同一套**语言, 各画各的就会飘。`s` = 相对 114px 手牌宽的缩放。
static func neon_text(ci: CanvasItem, font: Font, txt: String, at: Vector2, fs: int,
		glow: Color, core: Color, halo := 1.0, s := 1.0) -> void:
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var centre := at + Vector2(tw * 0.5, -fs * 0.36)

	# 1. wide halo — a radial gradient, which is smooth by construction. Ring
	#    sampling cannot reach this far: at r=12 eight copies sit 9px apart and
	#    you simply see eight glyphs. `halo` scales the whole bloom down — the
	#    huge centre suit at full strength drowned the card (真人试玩 2026-08-05).
	var d := fs * 2.2
	ci.draw_texture_rect(glow_tex(), Rect2(centre - Vector2(d, d) * 0.5, Vector2(d, d)),
		false, Color(glow.r, glow.g, glow.b, glow.a * 0.42 * halo))

	# 2. tight shape-following glow — small radii only, so the copies overlap
	for ring in [[4.6, 10, 0.075], [2.8, 8, 0.085], [1.4, 6, 0.095]]:
		var rad: float = float(ring[0]) * s
		var n: int = int(ring[1])
		var a: float = float(ring[2]) * glow.a * halo
		for i in range(n):
			var ang := TAU * float(i) / float(n) + (PI / float(n))
			ci.draw_string(font, at + Vector2(cos(ang), sin(ang)) * rad, txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(glow.r, glow.g, glow.b, a))

	# 3. filament
	ci.draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, core)


static var _glow: GradientTexture2D

## White radial falloff, modulated per call. Cached like sheen().
static func glow_tex() -> GradientTexture2D:
	if _glow != null:
		return _glow
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.18, 0.42, 0.70, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.72), Color(1, 1, 1, 0.32),
		Color(1, 1, 1, 0.09), Color(1, 1, 1, 0.0)])
	_glow = GradientTexture2D.new()
	_glow.gradient = g
	_glow.width = 128
	_glow.height = 128
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	return _glow
