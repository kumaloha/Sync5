extends SceneTree

const IDS: Array[String] = [
	"dj",
	"magician",
	"boxer",
	"bartender",
	"seer",
	"drummer",
	"rapper",
	"tattooist",
]

const MANIFEST_PATH := "res://assets/characters/manifest.json"
const OUTPUT_PATH := "res://assets/characters/contact-sheet.png"
const SHEET_SIZE := Vector2i(2048, 1152)
const GRID := Vector2i(4, 2)
const CELL_SIZE := Vector2i(512, 576)
const PORTRAIT_PREVIEW_SIZE := Vector2i(150, 196)
const AVATAR_PREVIEW_SIZE := Vector2i(96, 96)
const FRAME_SIZE := Vector2i(128, 128)
const FRAME_PREVIEW_SIZE := Vector2i(52, 52)
const FRAME_COUNT := 8
const FRAME_GAP := 6
const FONT_SIZE := Vector2i(30, 0)
const FONT_PATH := "res://assets/fonts/NotoSansCJKsc-Sync5Roster.otf"
const HEADER_TEXT := "Sync5 profession roster"

var _errors: Array[String] = []
var _records_by_id: Dictionary = {}
var _font_rid: RID
var _text_server: TextServer


func _initialize() -> void:
	_records_by_id = _load_records_by_id()
	_text_server = TextServerManager.get_primary_interface()
	_font_rid = _load_font_rid()
	if not _errors.is_empty():
		_finish()
		return

	var sheet := Image.create(SHEET_SIZE.x, SHEET_SIZE.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("05070d"))
	_draw_text(sheet, HEADER_TEXT, Vector2i(28, 38), Color("d6fbff"))

	for i in range(IDS.size()):
		var id := IDS[i]
		var cell_origin := Vector2i((i % GRID.x) * CELL_SIZE.x, (i / GRID.x) * CELL_SIZE.y)
		_draw_cell(sheet, id, cell_origin)

	if _errors.is_empty():
		_ensure_dir(OUTPUT_PATH.get_base_dir())
	if _errors.is_empty():
		var save_error := sheet.save_png(OUTPUT_PATH)
		if save_error != OK:
			_error("cannot save %s: %s" % [_display_path(OUTPUT_PATH), error_string(save_error)])

	if _errors.is_empty():
		print("saved %s" % _display_path(OUTPUT_PATH))
	_finish()


func _draw_cell(sheet: Image, id: String, cell_origin: Vector2i) -> void:
	var rec: Dictionary = _records_by_id.get(id, {})
	if rec.is_empty():
		_error("missing manifest record for '%s'" % id)
		return

	_fill_rect(sheet, Rect2i(cell_origin + Vector2i(16, 52), CELL_SIZE - Vector2i(32, 72)), Color(0.035, 0.047, 0.075, 0.88))
	_fill_rect(sheet, Rect2i(cell_origin + Vector2i(16, 52), Vector2i(CELL_SIZE.x - 32, 2)), Color("35e8e0"))
	_fill_rect(sheet, Rect2i(cell_origin + Vector2i(16, CELL_SIZE.y - 22), Vector2i(CELL_SIZE.x - 32, 2)), Color("ff4fa3"))

	var label := "%s / %s" % [String(rec.get("cn", "")), String(rec.get("title", ""))]
	_draw_text(sheet, label, cell_origin + Vector2i(24, 98), Color("f6f7ff"))

	_blit_scaled(
		sheet,
		_load_image("res://assets/characters/%s/portrait.png" % id, Vector2i(1536, 2048)),
		cell_origin + Vector2i(28, 122),
		PORTRAIT_PREVIEW_SIZE
	)
	_blit_scaled(
		sheet,
		_load_image("res://assets/characters/%s/avatar.png" % id, Vector2i(512, 512)),
		cell_origin + Vector2i(206, 130),
		AVATAR_PREVIEW_SIZE
	)

	_fill_rect(sheet, Rect2i(cell_origin + Vector2i(320, 134), Vector2i(142, 4)), Color("35e8e0"))
	_fill_rect(sheet, Rect2i(cell_origin + Vector2i(320, 154), Vector2i(112, 4)), Color("ff4fa3"))
	_fill_rect(sheet, Rect2i(cell_origin + Vector2i(320, 174), Vector2i(82, 4)), Color("a56bff"))

	_draw_animation_strip(sheet, id, "walk", cell_origin + Vector2i(27, 354), Color(0.02, 0.42, 0.44, 0.42))
	_draw_animation_strip(sheet, id, "dance", cell_origin + Vector2i(27, 446), Color(0.60, 0.08, 0.36, 0.42))


func _draw_animation_strip(sheet: Image, id: String, kind: String, origin: Vector2i, layer_color: Color) -> void:
	var strip_width := FRAME_COUNT * FRAME_PREVIEW_SIZE.x + (FRAME_COUNT - 1) * FRAME_GAP
	_fill_rect(sheet, Rect2i(origin - Vector2i(8, 8), Vector2i(strip_width + 16, FRAME_PREVIEW_SIZE.y + 16)), layer_color)

	var animation_sheet := _load_image("res://assets/characters/%s/%s.png" % [id, kind], Vector2i(1024, 128))
	if animation_sheet.is_empty():
		return
	for i in range(FRAME_COUNT):
		var frame := Image.create(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
		frame.fill(Color(0, 0, 0, 0))
		frame.blit_rect(animation_sheet, Rect2i(Vector2i(i * FRAME_SIZE.x, 0), FRAME_SIZE), Vector2i.ZERO)
		var frame_pos := origin + Vector2i(i * (FRAME_PREVIEW_SIZE.x + FRAME_GAP), 0)
		_blit_scaled(sheet, frame, frame_pos, FRAME_PREVIEW_SIZE)
		_fill_rect(sheet, Rect2i(frame_pos, Vector2i(FRAME_PREVIEW_SIZE.x, 1)), Color(1, 1, 1, 0.28))
		_fill_rect(sheet, Rect2i(frame_pos + Vector2i(0, FRAME_PREVIEW_SIZE.y - 1), Vector2i(FRAME_PREVIEW_SIZE.x, 1)), Color(1, 1, 1, 0.16))


func _blit_scaled(target: Image, source: Image, position: Vector2i, size: Vector2i) -> void:
	if source.is_empty():
		return
	var scaled := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8)
	scaled.fill(Color(0, 0, 0, 0))
	scaled.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i.ZERO)
	scaled.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	target.blend_rect(scaled, Rect2i(Vector2i.ZERO, size), position)


func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	var fill := Image.create(rect.size.x, rect.size.y, false, Image.FORMAT_RGBA8)
	fill.fill(color)
	image.blend_rect(fill, Rect2i(Vector2i.ZERO, rect.size), rect.position)


func _draw_text(image: Image, text: String, baseline: Vector2i, color: Color) -> void:
	var cursor_x := float(baseline.x)
	for i in range(text.length()):
		var codepoint := text.unicode_at(i)
		var glyph := _text_server.font_get_glyph_index(_font_rid, FONT_SIZE.x, codepoint, 0)
		if glyph == 0 and codepoint != 32:
			_error("font cannot render manifest label character U+%04X" % codepoint)
			continue

		if codepoint != 32:
			_text_server.font_render_glyph(_font_rid, FONT_SIZE, glyph)
			var texture_idx := _text_server.font_get_glyph_texture_idx(_font_rid, FONT_SIZE, glyph)
			var uv_rect := _text_server.font_get_glyph_uv_rect(_font_rid, FONT_SIZE, glyph)
			var offset := _text_server.font_get_glyph_offset(_font_rid, FONT_SIZE, glyph)
			var texture := _text_server.font_get_texture_image(_font_rid, FONT_SIZE, texture_idx)
			if texture == null or texture.is_empty():
				_error("font texture for manifest label character U+%04X is empty" % codepoint)
			else:
				texture.convert(Image.FORMAT_RGBA8)
				var glyph_image := Image.create(int(ceil(uv_rect.size.x)), int(ceil(uv_rect.size.y)), false, Image.FORMAT_RGBA8)
				glyph_image.fill(Color(0, 0, 0, 0))
				glyph_image.blit_rect(texture, Rect2i(Vector2i(int(uv_rect.position.x), int(uv_rect.position.y)), Vector2i(int(ceil(uv_rect.size.x)), int(ceil(uv_rect.size.y)))), Vector2i.ZERO)
				_tint_alpha_image(glyph_image, color)
				image.blend_rect(
					glyph_image,
					Rect2i(Vector2i.ZERO, glyph_image.get_size()),
					Vector2i(int(round(cursor_x + offset.x)), int(round(float(baseline.y) + offset.y)))
				)

		var advance := _text_server.font_get_glyph_advance(_font_rid, FONT_SIZE.x, glyph)
		cursor_x += advance.x


func _tint_alpha_image(image: Image, color: Color) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			image.set_pixel(x, y, Color(color.r, color.g, color.b, pixel.a * color.a))


func _load_font_rid() -> RID:
	if not FileAccess.file_exists(FONT_PATH):
		_error("missing contact sheet font %s" % _display_path(FONT_PATH))
		return RID()

	var bytes := FileAccess.get_file_as_bytes(FONT_PATH)
	if bytes.is_empty():
		_error("contact sheet font %s is empty" % _display_path(FONT_PATH))
		return RID()

	var rid := _text_server.create_font()
	_text_server.font_set_data(rid, bytes)
	_text_server.font_set_antialiasing(rid, TextServer.FONT_ANTIALIASING_GRAY)
	_text_server.font_set_generate_mipmaps(rid, false)
	_text_server.font_set_allow_system_fallback(rid, false)
	if _font_supports_labels(rid):
		return rid

	_text_server.free_rid(rid)
	_error("contact sheet font %s cannot render all required manifest/header text" % _display_path(FONT_PATH))
	return RID()


func _font_supports_labels(rid: RID) -> bool:
	if not _font_supports_text(rid, HEADER_TEXT):
		return false
	for id in IDS:
		var rec: Dictionary = _records_by_id.get(id, {})
		var label := "%s / %s" % [String(rec.get("cn", "")), String(rec.get("title", ""))]
		if not _font_supports_text(rid, label):
			return false
	return true


func _font_supports_text(rid: RID, text: String) -> bool:
	for i in range(text.length()):
		var codepoint := text.unicode_at(i)
		if codepoint == 32:
			continue
		if _text_server.font_get_glyph_index(rid, FONT_SIZE.x, codepoint, 0) == 0:
			return false
	return true


func _load_records_by_id() -> Dictionary:
	var manifest_value: Variant = _read_json_object(MANIFEST_PATH)
	if manifest_value == null:
		return {}
	var manifest := manifest_value as Dictionary
	if typeof(manifest.get("characters")) != TYPE_ARRAY:
		_error("%s.characters must be a JSON array" % _display_path(MANIFEST_PATH))
		return {}

	var by_id := {}
	var characters: Array = manifest.get("characters", [])
	for i in range(characters.size()):
		if typeof(characters[i]) != TYPE_DICTIONARY:
			_error("manifest.characters[%d] must be an object" % i)
			continue
		var rec := characters[i] as Dictionary
		var id := String(rec.get("id", ""))
		var cn := String(rec.get("cn", ""))
		var title := String(rec.get("title", ""))
		if id.is_empty() or cn.is_empty() or title.is_empty():
			_error("manifest.characters[%d] must include non-empty id, cn, and title" % i)
			continue
		by_id[id] = rec

	for id in IDS:
		if not by_id.has(id):
			_error("missing manifest record for '%s'" % id)
	return by_id


func _read_json_object(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		_error("missing %s" % _display_path(path))
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_error("cannot open %s: %s" % [_display_path(path), error_string(FileAccess.get_open_error())])
		return null

	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		_error("invalid JSON in %s at line %d: %s" % [
			_display_path(path), parser.get_error_line(), parser.get_error_message(),
		])
		return null

	if typeof(parser.data) != TYPE_DICTIONARY:
		_error("%s must be a JSON object" % _display_path(path))
		return null
	return parser.data


func _load_image(path: String, expected_size: Vector2i) -> Image:
	if not FileAccess.file_exists(path):
		_error("missing %s" % _display_path(path))
		return Image.new()

	var image := Image.new()
	var load_error := image.load(path)
	if load_error != OK:
		_error("cannot load %s: %s" % [_display_path(path), error_string(load_error)])
		return Image.new()
	var actual_size := image.get_size()
	if actual_size != expected_size:
		_error("%s must be %dx%d, found %dx%d" % [
			_display_path(path), expected_size.x, expected_size.y, actual_size.x, actual_size.y,
		])
		return Image.new()
	image.convert(Image.FORMAT_RGBA8)
	return image


func _ensure_dir(path: String) -> void:
	var display := _display_path(path)
	var error := DirAccess.make_dir_recursive_absolute(_global_path(path))
	if error != OK and error != ERR_ALREADY_EXISTS:
		_error("cannot create directory %s: %s" % [display, error_string(error)])


func _finish() -> void:
	if _text_server != null and _font_rid.is_valid():
		_text_server.free_rid(_font_rid)
	for err in _errors:
		printerr(err)
	if _errors.is_empty():
		quit(0)
	else:
		printerr("character contact sheet FAILED: %d errors" % _errors.size())
		quit(1)


func _display_path(path: String) -> String:
	if path.begins_with("res://"):
		return path.substr(6)
	return path


func _global_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


func _error(message: String) -> void:
	_errors.append(message)
