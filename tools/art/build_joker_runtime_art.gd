extends SceneTree

const MANIFEST_PATH := "res://assets/jokers/manifest.json"
const SOURCE_TEMPLATE := "res://assets/jokers/source/joker_%s.png"
const OUTPUT_TEMPLATE := "res://assets/jokers/joker_%s.png"
const SOURCE_SIZE := Vector2i(1024, 1024)
const OUTPUT_SIZE := Vector2i(1024, 400)
const ART_BOX_SIZE := Vector2i(900, 360)
const ALPHA_THRESHOLD := 64.0 / 255.0
const BBOX_PADDING := 24

var _errors: Array[String] = []


func _initialize() -> void:
	var manifest := _load_manifest()
	if manifest.is_empty():
		_finish()
		return

	var cards := manifest["cards"] as Array
	var selected := _select_ids(cards)
	if selected.is_empty() and _errors.is_empty():
		_error("no joker IDs selected")
	if not _errors.is_empty():
		_finish()
		return

	for id in selected:
		_build_runtime_art(String(id))

	_finish()


func _load_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		_error("missing %s" % _display_path(MANIFEST_PATH))
		return {}

	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		_error("cannot open %s: %s" % [_display_path(MANIFEST_PATH), error_string(FileAccess.get_open_error())])
		return {}

	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		_error("invalid JSON in %s at line %d: %s" % [
			_display_path(MANIFEST_PATH), parser.get_error_line(), parser.get_error_message(),
		])
		return {}

	if typeof(parser.data) != TYPE_DICTIONARY:
		_error("%s must be a JSON object" % _display_path(MANIFEST_PATH))
		return {}

	var manifest := parser.data as Dictionary
	if not manifest.has("cards") or typeof(manifest["cards"]) != TYPE_ARRAY:
		_error("%s.cards must be a JSON array" % _display_path(MANIFEST_PATH))
		return {}

	var cards := manifest["cards"] as Array
	if cards.size() != 60:
		_error("%s.cards must contain exactly 60 records, found %d" % [_display_path(MANIFEST_PATH), cards.size()])

	var seen := {}
	for i in range(cards.size()):
		var card: Variant = cards[i]
		if typeof(card) != TYPE_DICTIONARY:
			_error("manifest.cards[%d] must be an object" % i)
			continue
		var rec := card as Dictionary
		for key in ["id", "cn", "code", "amount", "trigger_zh"]:
			if not rec.has(key) or typeof(rec[key]) != TYPE_STRING or String(rec[key]).strip_edges().is_empty():
				_error("manifest.cards[%d].%s must be a non-empty string" % [i, key])
		var id := String(rec.get("id", ""))
		if not id.is_empty():
			if seen.has(id):
				_error("duplicate manifest id '%s'" % id)
			seen[id] = true

	return manifest


func _select_ids(cards: Array) -> Array[String]:
	var manifest_ids: Array[String] = []
	var known := {}
	for card in cards:
		if typeof(card) != TYPE_DICTIONARY:
			continue
		var id := String((card as Dictionary).get("id", ""))
		if not id.is_empty():
			manifest_ids.append(id)
			known[id] = true

	var user_args := OS.get_cmdline_user_args()
	var selection_args: Array[String] = []
	for arg in user_args:
		var text := String(arg)
		if text.begins_with("--id=") or text.begins_with("--ids="):
			selection_args.append(text)
		else:
			_error("unknown argument '%s'" % text)

	if selection_args.is_empty():
		return manifest_ids

	if selection_args.size() > 1:
		_error("use only one selection argument: --id=<id> or --ids=<id,id>")
		return []

	var raw_ids: Array[String] = []
	var selection := selection_args[0]
	if selection.begins_with("--id="):
		raw_ids.append(selection.substr(5))
	else:
		raw_ids.assign(selection.substr(6).split(",", true))

	var selected: Array[String] = []
	var seen := {}
	for raw_id in raw_ids:
		var id := raw_id.strip_edges()
		if id.is_empty():
			_error("empty joker ID in selection")
			continue
		if seen.has(id):
			_error("duplicate requested id '%s'" % id)
			continue
		seen[id] = true
		if not known.has(id):
			_error("unknown requested id '%s'" % id)
			continue
		selected.append(id)

	return selected


func _build_runtime_art(id: String) -> void:
	var source_path := SOURCE_TEMPLATE % id
	if not FileAccess.file_exists(source_path):
		_error("missing source %s" % _display_path(source_path))
		return

	var source := Image.new()
	var load_error := source.load(source_path)
	if load_error != OK:
		_error("cannot load source %s: %s" % [_display_path(source_path), error_string(load_error)])
		return

	var size := Vector2i(source.get_width(), source.get_height())
	if size != SOURCE_SIZE:
		_error("source %s must be %dx%d, found %dx%d" % [
			_display_path(source_path), SOURCE_SIZE.x, SOURCE_SIZE.y, size.x, size.y,
		])
		return

	source.convert(Image.FORMAT_RGBA8)
	var bbox := _meaningful_alpha_bbox(source)
	if bbox.size == Vector2i.ZERO:
		_error("source %s has no meaningful non-transparent pixel" % _display_path(source_path))
		return

	var padded_bbox := _pad_rect(bbox, BBOX_PADDING, size)
	var crop_size := padded_bbox.size
	var scale: float = min(1.0, min(float(ART_BOX_SIZE.x) / float(crop_size.x), float(ART_BOX_SIZE.y) / float(crop_size.y)))
	var scaled_size := Vector2i(max(1, int(round(crop_size.x * scale))), max(1, int(round(crop_size.y * scale))))
	var art := Image.create(crop_size.x, crop_size.y, false, Image.FORMAT_RGBA8)
	art.fill(Color(0, 0, 0, 0))
	art.blit_rect(source, padded_bbox, Vector2i.ZERO)
	if scaled_size != crop_size:
		art.resize(scaled_size.x, scaled_size.y, Image.INTERPOLATE_LANCZOS)

	var output := Image.create(OUTPUT_SIZE.x, OUTPUT_SIZE.y, false, Image.FORMAT_RGBA8)
	output.fill(Color(0, 0, 0, 0))
	var offset := Vector2i((OUTPUT_SIZE.x - scaled_size.x) / 2, (OUTPUT_SIZE.y - scaled_size.y) / 2)
	output.blit_rect(art, Rect2i(Vector2i.ZERO, scaled_size), offset)

	var output_path := OUTPUT_TEMPLATE % id
	var save_error := output.save_png(output_path)
	if save_error != OK:
		_error("cannot save %s: %s" % [_display_path(output_path), error_string(save_error)])
		return

	print("saved %s" % _display_path(output_path))


func _meaningful_alpha_bbox(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= ALPHA_THRESHOLD:
				min_x = min(min_x, x)
				min_y = min(min_y, y)
				max_x = max(max_x, x)
				max_y = max(max_y, y)

	if max_x < min_x or max_y < min_y:
		return Rect2i(Vector2i.ZERO, Vector2i.ZERO)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _pad_rect(rect: Rect2i, padding: int, bounds: Vector2i) -> Rect2i:
	var x: int = max(0, rect.position.x - padding)
	var y: int = max(0, rect.position.y - padding)
	var right: int = min(bounds.x, rect.position.x + rect.size.x + padding)
	var bottom: int = min(bounds.y, rect.position.y + rect.size.y + padding)
	return Rect2i(x, y, right - x, bottom - y)


func _finish() -> void:
	for err in _errors:
		printerr(err)
	if _errors.is_empty():
		quit(0)
	else:
		printerr("joker runtime art build FAILED: %d errors" % _errors.size())
		quit(1)


func _display_path(path: String) -> String:
	if path.begins_with("res://"):
		return path.substr(6)
	return path


func _error(message: String) -> void:
	_errors.append(message)
