class_name PickWalker
extends Control

## Run-start protagonist picker. Eight live Walker figures in a 2×4 grid, each
## on a glass tile carrying the character's passive. Emits `picked(idx)` and
## frees itself.
##
## The figures animate here exactly as they do on the hand frame, so what you
## pick is what you see walking.

signal picked(idx: int)

const COLS := 4
const TILE := Vector2(150.0, 196.0)
const GAP := Vector2(16.0, 22.0)

var _roster: Array = []
var _hover := -1
var _tiles: Array = []      # [Rect2, idx]


func _ready() -> void:
	# explicit rect, not an anchor preset — mixing the two makes Godot warn
	# that it will override the size after _ready()
	position = Vector2.ZERO
	size = Vector2(720, 1280)
	# same reason as HomeScreen: the battle scene's Walker draws at z 20
	z_index = 80
	_roster = Character.roster()

	var grid_w := TILE.x * COLS + GAP.x * (COLS - 1)
	var x0 := (720.0 - grid_w) * 0.5
	var y0 := 500.0
	for i in range(_roster.size()):
		var col := i % COLS
		var row := int(i / COLS)
		var r := Rect2(Vector2(x0 + float(col) * (TILE.x + GAP.x),
			y0 + float(row) * (TILE.y + GAP.y)), TILE)
		_tiles.append([r, i])

		var fig := Walker.new()
		fig.set_character(i)
		# the figure stands on the tile's lower third, facing the centre
		fig.position = r.position + Vector2(TILE.x * 0.5, TILE.y - 52.0)
		fig.facing = 1.0 if col < 2 else -1.0
		add_child(fig)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var was := _hover
		_hover = _hit(ev.position)
		if was != _hover:
			queue_redraw()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var hit := _hit(ev.position)
		if hit >= 0:
			picked.emit(hit)   # the phrase screen owns this node and frees it


func _hit(p: Vector2) -> int:
	for t in _tiles:
		var r: Rect2 = t[0]
		if r.has_point(p):
			return int(t[1])
	return -1


func _draw() -> void:
	# the scrim belongs here, not in a child ColorRect: children paint AFTER
	# _draw(), so a child would bury every tile and label under it
	draw_rect(Rect2(0, 0, 720, 1280), Color(0.02, 0.03, 0.07, 0.88), true)

	var zh := StageTheme.zh()
	var num := StageTheme.num("Bold")

	draw_string(zh, Vector2(0, 402), "选 择 主 角", HORIZONTAL_ALIGNMENT_CENTER, 720, 40,
		StageTheme.INK)
	draw_string(zh, Vector2(0, 442), "每位主角带一个贯穿整局的被动", HORIZONTAL_ALIGNMENT_CENTER,
		720, 17, StageTheme.DIM)

	for t in _tiles:
		var r: Rect2 = t[0]
		var i := int(t[1])
		var ch: Character = _roster[i]
		var col := Color(String(Walker.CREW[i]["color"]))
		var on := i == _hover

		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.055, 0.043, 0.10, 0.92)
		sb.set_corner_radius_all(16)
		sb.set_border_width_all(2)
		sb.border_color = Color(col.r, col.g, col.b, 0.9 if on else 0.45)
		sb.shadow_color = Color(col.r, col.g, col.b, 0.40 if on else 0.16)
		sb.shadow_size = 22 if on else 12
		draw_style_box(sb, r)

		# passive plate at the top of the tile
		draw_string(num, r.position + Vector2(0, 26), ch.title.to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15, Color(col.r, col.g, col.b, 0.95))
		draw_line(r.position + Vector2(18, 34), r.position + Vector2(r.size.x - 18, 34),
			Color(col.r, col.g, col.b, 0.28), 1.0)

		# name + effect below the figure
		draw_string(zh, r.position + Vector2(0, r.size.y - 34), ch.cn_name,
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 17, StageTheme.INK)
		draw_string(zh, r.position + Vector2(6, r.size.y - 13), ch.fx_text,
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 12, 11,
			Color(col.r, col.g, col.b, 0.80))
