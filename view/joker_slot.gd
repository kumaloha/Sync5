class_name JokerSlotView
extends Control

## Joker slot — implements the module in resources/Neon Rain Card Game.dc.html:
## glass panel with a cyan neon frame, header row (CODE + icon box), a dotted
## divider, a gridded DISPLAY WINDOW (animated EQ bars for the target slot, a
## glyph for supports), then a name chip + multiplier chip and a caption line.
## An `assets/jokers/joker_<id>.png` drops straight into the display window.

signal tapped

const BARS := 13

var joker = null
var slot_kind := "support"
var tappable := false
var _art: Texture2D = null
var _t := 0.0
var _phase: Array = []
## 替换模式的提示: "" = 常态 / "replace" = 点我替换 / "cancel" = 点我取消。
## 之前只有屏幕中间一行字, 槽位毫无变化, 玩家根本不知道要点槽(用户 2026-08-05:
## 「替换我还不知道怎么替」)。
var pick_mode := "":
	set(v):
		pick_mode = v
		queue_redraw()
var _pick_t := 0.0

var is_mirror := false          # the flipped copy under the slot
var _mirror: JokerSlotView = null

## 替换手势(2026-08-06): 待装入的新卡挂 `drag_joker` 可以被拖走, 支援槽开
## `accept_joker_drop` 接住它。手势语言和缓存区一致 —— CLAUDE.md 定的是
## 「不存在存入空位, **拖拽 = 两张对调**」, 换小丑牌本来就是一次对调
## (新卡进、旧卡折半回收), 玩家不必再学第二套操作。点击路径保留作降级。
var drag_joker = null
var accept_joker_drop := false


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for i in range(BARS):
		_phase.append(rng.randf_range(0.0, TAU))
	set_process(true)
	if is_mirror:
		return
	# spec: `-webkit-box-reflect: below 8px linear-gradient(transparent 62%, .18)`
	# — a real gradient-masked mirror, not a tinted wash.
	_mirror = JokerSlotView.new()
	_mirror.is_mirror = true
	_mirror.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mirror.slot_kind = slot_kind
	_mirror.size = size
	_mirror.material = PaperCard._mask_material(size.y, 1.0, 0.18)
	# foreshortened like the cards — see PaperCard.MIRROR_SQUASH
	_mirror.scale = Vector2(1, -PaperCard.MIRROR_SQUASH)
	_mirror.position = Vector2(0, size.y * (1.0 + PaperCard.MIRROR_SQUASH) + 8.0)
	add_child(_mirror)
	_mirror.set_joker(joker)


func _process(delta: float) -> void:
	_t += delta
	_pick_t += delta
	if joker != null or pick_mode != "":
		queue_redraw()


func set_joker(j) -> void:
	joker = j
	if _mirror != null:
		_mirror.set_joker(j)
	_art = null
	if j != null:
		var path := "res://assets/jokers/joker_%s.png" % j.id
		if ResourceLoader.exists(path):
			_art = load(path)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if tappable and event is InputEventMouseButton and event.pressed:
		tapped.emit()


func _get_drag_data(_pos: Vector2) -> Variant:
	if drag_joker == null:
		return null
	var prev := JokerSlotView.new()
	prev.is_mirror = true            # skip the reflection child on a drag ghost
	prev.slot_kind = slot_kind
	prev.size = size
	prev.set_joker(drag_joker)
	prev.modulate = Color(1, 1, 1, 0.9)
	prev.pivot_offset = size * 0.5
	prev.rotation_degrees = 4.0
	set_drag_preview(prev)
	return {"zone": "joker", "joker": drag_joker}


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return accept_joker_drop and data is Dictionary and String(data.get("zone", "")) == "joker"


## Same verdict as a tap — the orchestrator owns the money and the slot swap.
func _drop_data(_pos: Vector2, _data: Variant) -> void:
	tapped.emit()


func _accent() -> Color:
	return StageTheme.CYAN


func _draw() -> void:
	var w := size.x
	var h := size.y
	var s := h / 172.0            # design module is 172 tall
	if joker == null:
		_draw_empty(w, h, s)
		return
	var acc := _accent()
	_glass(w, h, s, acc, 0.85)

	var pad := 11.0 * s
	var y := 9.0 * s

	# header: CN name (the one the player actually reads) + kind icon box
	draw_string(StageTheme.zh(), Vector2(pad, y + 13.0 * s), joker.cn_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(16.0 * s), Color("eafffd"))
	var ib := Rect2(w - pad - 13.0 * s, y + 1.0 * s, 13.0 * s, 13.0 * s)
	draw_rect(ib, Color(acc.r, acc.g, acc.b, 0.4), false, 1.0)
	draw_string(StageTheme.zh(), Vector2(ib.position.x, ib.position.y + 10.5 * s),
		_icon_for(joker.kind), HORIZONTAL_ALIGNMENT_CENTER, ib.size.x, int(9.0 * s), acc)

	# divider with three ticks
	y += 22.0 * s
	draw_line(Vector2(pad, y), Vector2(w - pad - 26.0 * s, y), Color(acc.r, acc.g, acc.b, 0.35), 1.0)
	for i in range(3):
		var tx := w - pad - 20.0 * s + float(i) * 6.0 * s
		draw_rect(Rect2(tx, y - 1.5 * s, 4.0 * s, 3.0 * s),
			Color(acc.r, acc.g, acc.b, 0.7 if i != 1 else 0.4), true)

	# --- display window: grid background + EQ bars or glyph ---
	# 50 tall (was 66): the freed rows go to the effect text below — 真人试玩
	# 2026-08-05: the caption was the thing being squinted at, not the art
	y += 5.0 * s
	var win := Rect2(pad * 0.6, y, w - pad * 1.2, 50.0 * s)
	_display_window(win, s, acc)

	# single amount chip, gold — it is the number the player shops by
	y = win.position.y + win.size.y + 6.0 * s
	_chips(w, y, s, acc)

	_pick_overlay(w, h, s)

	# caption — EN card text (≤7 words by design), two lines allowed, bright
	var cap_font := StageTheme.num("Medium")
	var cap_w := w - 10.0 * s
	var cap_sz := int(13.0 * s)
	while cap_sz > int(9.0 * s):
		var sz := cap_font.get_multiline_string_size(joker.fx_text,
			HORIZONTAL_ALIGNMENT_CENTER, cap_w, cap_sz)
		if sz.y <= 36.0 * s:
			break
		cap_sz -= 1
	draw_multiline_string(cap_font, Vector2(5.0 * s, y + 33.0 * s), joker.fx_text,
		HORIZONTAL_ALIGNMENT_CENTER, cap_w, cap_sz, 2, Color("b7f3ec"))



## 替换模式的高亮: 呼吸的金边 + 角标提示。空槽也要画(见 _draw_empty)。
func _pick_overlay(w: float, h: float, s: float) -> void:
	if pick_mode == "":
		return
	var hot := pick_mode == "replace"
	var col: Color = StageTheme.GOLD if hot else Color("8aa0c8")
	var pulse: float = 0.55 + 0.45 * (0.5 - 0.5 * cos(_pick_t * TAU / 0.9))
	for g in [6.0, 3.0, 0.0]:
		ci_stroke(w, h, s, g, Color(col.r, col.g, col.b, (0.14 + 0.5 * pulse) * (1.0 - g / 9.0)))
	var tag := "替 换" if hot else "取 消"
	var tw := StageTheme.zh().get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, int(13.0 * s)).x
	var tr := Rect2((w - tw - 18.0 * s) * 0.5, -11.0 * s, tw + 18.0 * s, 22.0 * s)
	draw_style_box(StageTheme.box(col, Color(0, 0, 0, 0), 0, int(11.0 * s)), tr)
	draw_string(StageTheme.zh(), Vector2(tr.position.x, tr.position.y + 15.5 * s), tag,
		HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, int(13.0 * s), Color("241a02"))


func ci_stroke(w: float, h: float, s: float, g: float, col: Color) -> void:
	draw_style_box(StageTheme.box(Color(0, 0, 0, 0), col, int(2.0 + g * 0.4),
		int(14.0 * s + g)), Rect2(-g, -g, w + g * 2.0, h + g * 2.0))


## Glass body: fill, inner hairline, 115° sheen, top highlight, neon rim.
func _glass(w: float, h: float, s: float, acc: Color, rim: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.10, 0.12, 0.84)
	sb.set_corner_radius_all(int(14.0 * s))
	sb.set_border_width_all(2)
	sb.border_color = Color(acc.r, acc.g, acc.b, rim)
	sb.shadow_color = Color(acc.r, acc.g, acc.b, 0.32)
	sb.shadow_size = int(22.0 * s)
	draw_style_box(sb, Rect2(0, 0, w, h))
	draw_texture_rect(PaperCard.sheen(), Rect2(2, 2, w - 4, h - 4), false)
	draw_line(Vector2(8.0 * s, 2.5), Vector2(w - 8.0 * s, 2.5), Color(1, 1, 1, 0.42), 1.0)
	draw_rect(Rect2(4.0 * s, 4.0 * s, w - 8.0 * s, h - 8.0 * s),
		Color(acc.r, acc.g, acc.b, 0.30), false, 1.0)


func _display_window(win: Rect2, s: float, acc: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.08, 0.10, 0.92)
	sb.set_corner_radius_all(int(6.0 * s))
	sb.set_border_width_all(1)
	sb.border_color = Color(acc.r, acc.g, acc.b, 0.30)
	draw_style_box(sb, win)

	# fine grid
	var g := Color(acc.r, acc.g, acc.b, 0.08)
	var step := 11.0 * s
	var gx := win.position.x + step
	while gx < win.end.x:
		draw_line(Vector2(gx, win.position.y), Vector2(gx, win.end.y), g, 1.0)
		gx += step
	var gy := win.position.y + step
	while gy < win.end.y:
		draw_line(Vector2(win.position.x, gy), Vector2(win.end.x, gy), g, 1.0)
		gy += step

	var mid := win.position.y + win.size.y * 0.5
	if _art != null:
		draw_texture_rect(_art, win.grow(-4.0 * s), false)
	elif joker.kind == "target":
		# live EQ bars — the target slot is the loud one
		var n := BARS
		var bw := (win.size.x - 8.0 * s) / float(n)
		for i in range(n):
			var ph: float = _phase[i]
			var lvl: float = 0.18 + 0.82 * absf(sin(_t * 2.6 + ph)) * (0.45 + 0.55 * absf(sin(_t * 0.9 + ph * 0.5)))
			var bh: float = lvl * (win.size.y - 10.0 * s)
			var bx := win.position.x + 4.0 * s + float(i) * bw
			draw_rect(Rect2(bx + 1.0, mid - bh * 0.5, bw - 2.0, bh),
				Color(acc.r, acc.g, acc.b, 0.45 + 0.5 * lvl), true)
	else:
		draw_string(StageTheme.zh(), Vector2(win.position.x, mid + 12.0 * s),
			_glyph_for(joker.id), HORIZONTAL_ALIGNMENT_CENTER, win.size.x, int(34.0 * s), acc)
	draw_line(Vector2(win.position.x, mid), Vector2(win.end.x, mid), Color(acc.r, acc.g, acc.b, 0.32), 1.0)


## One centred amount chip in gold. The old row paired it with a CN name chip
## in dim teal — the name now lives in the header, and the amount was the
## least readable thing on the card (真人试玩 2026-08-05).
func _chips(w: float, y: float, s: float, _acc: Color) -> void:
	var font := StageTheme.num("SemiBold")
	var txt := _mult_for(joker.id)
	var fs := int(15.0 * s)
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var cw := maxf(tw + 18.0 * s, 44.0 * s)
	var r := Rect2((w - cw) * 0.5, y, cw, 20.0 * s)
	draw_rect(r, Color(StageTheme.GOLD.r, StageTheme.GOLD.g, StageTheme.GOLD.b, 0.55), false, 1.0)
	draw_string(font, Vector2(r.position.x, r.position.y + 15.0 * s), txt,
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, StageTheme.GOLD)


func _draw_empty(w: float, h: float, s: float) -> void:
	var col := Color(0.63, 0.71, 1.0, 0.30)
	draw_rect(Rect2(0, 0, w, h), Color(0.63, 0.71, 1.0, 0.04), true)
	var l := 20.0 * s
	for corner in [Vector2(0, 0), Vector2(w, 0), Vector2(0, h), Vector2(w, h)]:
		var dx: float = 1.0 if corner.x == 0.0 else -1.0
		var dy: float = 1.0 if corner.y == 0.0 else -1.0
		draw_line(corner, corner + Vector2(dx * l, 0), col, 2.0)
		draw_line(corner, corner + Vector2(0, dy * l), col, 2.0)
	draw_string(StageTheme.num("Medium"), Vector2(0, 26.0 * s), slot_kind.to_upper(),
		HORIZONTAL_ALIGNMENT_CENTER, w, int(12.0 * s), Color(0.63, 0.71, 1.0, 0.55))
	var c := Vector2(w * 0.5, h * 0.48)
	var r := 18.0 * s
	draw_arc(c, r, 0, TAU, 28, col, 1.5)
	draw_line(c - Vector2(r * 0.45, 0), c + Vector2(r * 0.45, 0), col, 1.5)
	draw_line(c - Vector2(0, r * 0.45), c + Vector2(0, r * 0.45), col, 1.5)
	draw_string(StageTheme.zh(), Vector2(0, h - 14.0 * s), "空 槽",
		HORIZONTAL_ALIGNMENT_CENTER, w, int(13.0 * s), Color(0.63, 0.71, 1.0, 0.5))
	_pick_overlay(w, h, s)



func _icon_for(kind: String) -> String:
	return "◈" if kind == "target" else "♪"

func _glyph_for(id: String) -> String:
	match id:
		"encore": return "≋"
		"finale": return "◤"
		"turnover": return "⟳"
		"tipjar": return "◇"
		"chord": return "♬"
		"neonsign": return "✦"
		"vinyl": return "◉"
		"chorus": return "♫"
		"interest": return "◆"
		"momentum": return "➤"
		"vip": return "♛"
		"glowstick": return "✧"
		"shortcut": return "⤳"
		"fourfingers": return "☰"
		"twotone": return "◑"
		"bassline": return "∿"
		"mirror": return "⧉"
		"wildcard": return "★"
		"twin": return "❋"
		"stair": return "▤"
		_: return "◈"

func _mult_for(id: String) -> String:
	match id:
		"twin": return "×3+"
		"stair": return "×8+"
		"mono": return "×6+"
		"triplet": return "×4+"
		"lonewolf": return "×4"
		"encore": return "+80"
		"finale": return "+70"
		"turnover": return "+20"
		"tipjar": return "+2◆"
		"chord": return "+120"
		"neonsign": return "+80"
		"vinyl": return "+3↗"
		"chorus": return "+75%"
		"interest": return "+◆"
		"momentum": return "10%↗"
		"vip": return "15"
		"glowstick": return "60%↘"
		"shortcut": return "±1"
		"fourfingers": return "4+"
		"twotone": return "2C"
		"bassline": return "×↗"
		"mirror": return "COPY"
		"wildcard": return "WILD"
		_: return "—"
