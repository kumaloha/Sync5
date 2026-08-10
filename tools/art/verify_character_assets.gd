extends SceneTree

const IDS := ["dj", "magician", "boxer", "bartender", "seer", "drummer", "rapper", "tattooist"]
const FILES := {
	"portrait.png": Vector2i(1536, 2048),
	"avatar.png": Vector2i(512, 512),
	"walk.png": Vector2i(1024, 128),
	"dance.png": Vector2i(1024, 128),
}
const REQUIRED_RECORD_FIELDS := [
	"id", "idx", "cn", "title", "gender_presentation", "selected_panel", "primary",
	"secondary", "silhouette", "profession_prop", "pose", "forbid", "avatar_crop",
]
const IDENTITY_STRING_FIELDS := [
	"id", "cn", "title", "gender_presentation", "selected_panel", "primary",
	"secondary", "silhouette", "profession_prop", "pose",
]
const PROMPT_FIELDS := ["portrait_prompt", "walk_prompt", "dance_prompt"]
const SOURCE_SHA_FIELDS := {
	"portrait": "portrait_source_sha256",
	"walk": "walk_source_sha256",
	"dance": "dance_source_sha256",
}
const MANIFEST_PATH := "res://assets/characters/manifest.json"
const GAMEPLAY_PATH := "res://data/characters.json"
const PLACEHOLDER_WORDS := [
	"todo", "tbd", "fixme", "placeholder", "lorem", "xxx", "replace me", "fill in",
	"待定", "占位",
]
const FRAME_SIZE := Vector2i(128, 128)
const FRAME_COUNT := 8

var _errors: Array[String] = []


func _initialize() -> void:
	_check_manifest()
	_check_assets()

	for err in _errors:
		printerr(err)

	if _errors.is_empty():
		print("character asset manifest OK: %d records" % IDS.size())
		quit(0)
	else:
		printerr("character asset manifest FAILED: %d errors" % _errors.size())
		quit(1)


func _check_manifest() -> void:
	var manifest_value: Variant = _read_json_object(MANIFEST_PATH)
	if manifest_value == null:
		return
	var manifest := manifest_value as Dictionary

	var gameplay_value: Variant = _read_json_object(GAMEPLAY_PATH)
	if gameplay_value == null:
		return
	var gameplay := gameplay_value as Dictionary

	_check_manifest_envelope(manifest)

	if not manifest.has("characters"):
		_error("%s missing required field 'characters'" % _display_path(MANIFEST_PATH))
		return
	if typeof(manifest["characters"]) != TYPE_ARRAY:
		_error("%s.characters must be a JSON array" % _display_path(MANIFEST_PATH))
		return

	if not gameplay.has("characters"):
		_error("%s missing required field 'characters'" % _display_path(GAMEPLAY_PATH))
		return
	if typeof(gameplay["characters"]) != TYPE_ARRAY:
		_error("%s.characters must be a JSON array" % _display_path(GAMEPLAY_PATH))
		return

	var records := manifest["characters"] as Array
	var gameplay_records := gameplay["characters"] as Array
	if records.size() != IDS.size():
		_error("%s.characters must contain exactly %d records, found %d" % [
			_display_path(MANIFEST_PATH), IDS.size(), records.size(),
		])
	if gameplay_records.size() != IDS.size():
		_error("%s.characters must contain exactly %d records, found %d" % [
			_display_path(GAMEPLAY_PATH), IDS.size(), gameplay_records.size(),
		])

	var seen := {}
	for i in range(records.size()):
		var rec: Variant = records[i]
		if typeof(rec) != TYPE_DICTIONARY:
			_error("manifest.characters[%d] must be an object" % i)
			continue

		var gameplay_rec := {}
		if i < gameplay_records.size() and typeof(gameplay_records[i]) == TYPE_DICTIONARY:
			gameplay_rec = gameplay_records[i] as Dictionary

		_check_record(i, rec as Dictionary, gameplay_rec, seen)


func _check_manifest_envelope(manifest: Dictionary) -> void:
	_check_number_field(manifest, "version", 1)
	_check_size_field(manifest, "portrait_size", Vector2i(1536, 2048))
	_check_size_field(manifest, "avatar_size", Vector2i(512, 512))
	_check_size_field(manifest, "frame_size", FRAME_SIZE)
	_check_number_field(manifest, "frame_count", FRAME_COUNT)


func _check_record(index: int, rec: Dictionary, gameplay_rec: Dictionary, seen: Dictionary) -> void:
	for key in REQUIRED_RECORD_FIELDS:
		if not rec.has(key):
			_error("manifest.characters[%d] missing required field '%s'" % [index, key])

	for key in IDENTITY_STRING_FIELDS:
		if rec.has(key):
			if typeof(rec[key]) != TYPE_STRING:
				_error("manifest.characters[%d].%s must be a string" % [index, key])
			elif String(rec[key]).strip_edges().is_empty():
				_error("manifest.characters[%d].%s must not be empty" % [index, key])

	if index < IDS.size():
		var expected_id := String(IDS[index])
		var actual_id := String(rec.get("id", ""))
		if actual_id != expected_id:
			_error("manifest.characters[%d].id must be '%s', found '%s'" % [index, expected_id, actual_id])
		elif seen.has(actual_id):
			_error("manifest.characters[%d].id duplicates '%s'" % [index, actual_id])
		else:
			seen[actual_id] = true

	if not rec.has("idx"):
		pass
	elif typeof(rec["idx"]) != TYPE_FLOAT and typeof(rec["idx"]) != TYPE_INT:
		_error("manifest.characters[%d].idx must be %d" % [index, index])
	elif int(rec["idx"]) != index or float(rec["idx"]) != float(index):
		_error("manifest.characters[%d].idx must be %d, found %s" % [index, index, str(rec["idx"])])

	if not gameplay_rec.is_empty():
		var gameplay_idx: Variant = gameplay_rec.get("idx")
		if typeof(gameplay_idx) != TYPE_FLOAT and typeof(gameplay_idx) != TYPE_INT:
			_error("%s.characters[%d].idx must be %d" % [_display_path(GAMEPLAY_PATH), index, index])
		elif int(gameplay_idx) != index or float(gameplay_idx) != float(index):
			_error("%s.characters[%d].idx must be %d, found %s" % [
				_display_path(GAMEPLAY_PATH), index, index, str(gameplay_idx),
			])

		for key in ["cn", "title"]:
			var expected := String(gameplay_rec.get(key, ""))
			var actual := String(rec.get(key, ""))
			if actual != expected:
				_error("manifest.characters[%d].%s must equal %s.characters[%d].%s '%s', found '%s'" % [
					index, key, _display_path(GAMEPLAY_PATH), index, key, expected, actual,
				])

	_check_forbid(index, rec)
	_check_avatar_crop(index, rec)
	_check_placeholder_copy("manifest.characters[%d]" % index, rec)


func _check_forbid(index: int, rec: Dictionary) -> void:
	if not rec.has("forbid"):
		return
	if typeof(rec["forbid"]) != TYPE_ARRAY:
		_error("manifest.characters[%d].forbid must be a non-empty array of strings" % index)
		return

	var forbid := rec["forbid"] as Array
	if forbid.is_empty():
		_error("manifest.characters[%d].forbid must be a non-empty array of strings" % index)
	for i in range(forbid.size()):
		if typeof(forbid[i]) != TYPE_STRING or String(forbid[i]).strip_edges().is_empty():
			_error("manifest.characters[%d].forbid[%d] must be a non-empty string" % [index, i])


func _check_avatar_crop(index: int, rec: Dictionary) -> void:
	if not rec.has("avatar_crop"):
		return
	if typeof(rec["avatar_crop"]) != TYPE_ARRAY:
		_error("manifest.characters[%d].avatar_crop must be [x, y, width, height]" % index)
		return

	var crop := rec["avatar_crop"] as Array
	if crop.size() != 4:
		_error("manifest.characters[%d].avatar_crop must have exactly 4 entries, found %d" % [index, crop.size()])
		return
	for i in range(4):
		if typeof(crop[i]) != TYPE_FLOAT and typeof(crop[i]) != TYPE_INT:
			_error("manifest.characters[%d].avatar_crop[%d] must be a number" % [index, i])
			return


func _check_assets() -> void:
	for id_value in IDS:
		var id := String(id_value)
		for filename in FILES.keys():
			var path := "res://assets/characters/%s/%s" % [id, String(filename)]
			_check_image(id, String(filename), path, FILES[filename])
		_check_prompt(id)


func _check_image(id: String, filename: String, path: String, expected: Vector2i) -> void:
	if not FileAccess.file_exists(path):
		_error("missing character asset %s" % _display_path(path))
		return

	var image := Image.new()
	var load_error := image.load(path)
	if load_error != OK:
		_error("cannot load character asset %s: %s" % [_display_path(path), error_string(load_error)])
		return

	var actual := Vector2i(image.get_width(), image.get_height())
	if actual != expected:
		_error("character asset %s must be %dx%d, found %dx%d" % [
			_display_path(path), expected.x, expected.y, actual.x, actual.y,
		])
		return

	if filename == "walk.png" or filename == "dance.png":
		_check_sheet_alpha(id, filename, image)


func _check_sheet_alpha(id: String, filename: String, image: Image) -> void:
	for frame in range(FRAME_COUNT):
		var has_transparent := false
		var has_opaque := false
		var start_x := frame * FRAME_SIZE.x
		for y in range(FRAME_SIZE.y):
			for x in range(FRAME_SIZE.x):
				var alpha := image.get_pixel(start_x + x, y).a
				if alpha <= 0.0:
					has_transparent = true
				if alpha > 0.0:
					has_opaque = true
				if has_transparent and has_opaque:
					break
			if has_transparent and has_opaque:
				break

		if not has_transparent:
			_error("%s %s frame %d must contain at least one transparent pixel" % [id, filename, frame])
		if not has_opaque:
			_error("%s %s frame %d must contain at least one non-transparent pixel" % [id, filename, frame])


func _check_prompt(id: String) -> void:
	var path := "res://assets/characters/%s/prompt.json" % id
	if not FileAccess.file_exists(path):
		_error("missing character prompt %s" % _display_path(path))
		return

	var prompt_value: Variant = _read_json_object(path)
	if prompt_value == null:
		return
	var prompt := prompt_value as Dictionary

	if String(prompt.get("id", "")) != id:
		_error("prompt %s id must be '%s', found '%s'" % [
			_display_path(path), id, String(prompt.get("id", "")),
		])

	for key in PROMPT_FIELDS:
		if typeof(prompt.get(key)) != TYPE_STRING or String(prompt.get(key, "")).strip_edges().is_empty():
			_error("prompt %s %s must be a non-empty string" % [_display_path(path), key])

	var revision: Variant = prompt.get("revision")
	if typeof(revision) != TYPE_FLOAT and typeof(revision) != TYPE_INT:
		_error("prompt %s revision must be a number >= 1" % _display_path(path))
	elif int(revision) < 1:
		_error("prompt %s revision must be >= 1" % _display_path(path))

	for source_kind in SOURCE_SHA_FIELDS.keys():
		var sha_key := String(SOURCE_SHA_FIELDS[source_kind])
		var recorded_sha := String(prompt.get(sha_key, ""))
		if not _is_sha256(recorded_sha):
			_error("prompt %s %s must be 64 lowercase SHA-256 hex characters" % [_display_path(path), sha_key])
			continue

		var source_path := "res://assets/characters/source/%s_%s.png" % [id, String(source_kind)]
		if not FileAccess.file_exists(source_path):
			_error("missing character source asset %s" % _display_path(source_path))
			continue

		var actual_sha := FileAccess.get_sha256(source_path)
		if recorded_sha != actual_sha:
			_error("prompt %s %s does not match %s" % [
				_display_path(path), sha_key, _display_path(source_path),
			])


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

	return parser.data as Dictionary


func _check_number_field(manifest: Dictionary, key: String, expected: int) -> void:
	var path := "%s.%s" % [_display_path(MANIFEST_PATH), key]
	if not manifest.has(key):
		_error("%s missing required field '%s'" % [_display_path(MANIFEST_PATH), key])
		return

	var value: Variant = manifest[key]
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		_error("%s must be %d" % [path, expected])
		return
	if int(value) != expected or float(value) != float(expected):
		_error("%s must be %d, found %s" % [path, expected, str(value)])


func _check_size_field(manifest: Dictionary, key: String, expected: Vector2i) -> void:
	var path := "%s.%s" % [_display_path(MANIFEST_PATH), key]
	if not manifest.has(key):
		_error("%s missing required field '%s'" % [_display_path(MANIFEST_PATH), key])
		return

	var value: Variant = manifest[key]
	if typeof(value) != TYPE_ARRAY:
		_error("%s must be [%d, %d]" % [path, expected.x, expected.y])
		return

	var size_array := value as Array
	if size_array.size() != 2:
		_error("%s must have exactly 2 entries, found %d" % [path, size_array.size()])
		return

	for i in range(2):
		if typeof(size_array[i]) != TYPE_FLOAT and typeof(size_array[i]) != TYPE_INT:
			_error("%s[%d] must be a number" % [path, i])
			return

	var actual := Vector2i(int(size_array[0]), int(size_array[1]))
	if actual != expected or float(size_array[0]) != float(expected.x) or float(size_array[1]) != float(expected.y):
		_error("%s must be [%d, %d], found [%s, %s]" % [
			path, expected.x, expected.y, str(size_array[0]), str(size_array[1]),
		])


func _check_placeholder_copy(path: String, value: Variant) -> void:
	match typeof(value):
		TYPE_DICTIONARY:
			for key in value.keys():
				_check_placeholder_copy("%s.%s" % [path, String(key)], value[key])
		TYPE_ARRAY:
			for i in range(value.size()):
				_check_placeholder_copy("%s[%d]" % [path, i], value[i])
		TYPE_STRING:
			var text := String(value).strip_edges().to_lower()
			for word in PLACEHOLDER_WORDS:
				if text == word or text.contains(word):
					_error("%s contains placeholder copy '%s'" % [path, word])


func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for i in range(value.length()):
		var ch := value.unicode_at(i)
		var is_digit := ch >= 48 and ch <= 57
		var is_lower_hex := ch >= 97 and ch <= 102
		if not is_digit and not is_lower_hex:
			return false
	return true


func _display_path(path: String) -> String:
	if path.begins_with("res://"):
		return path.substr(6)
	return path


func _error(message: String) -> void:
	_errors.append(message)
