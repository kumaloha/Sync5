extends SceneTree

const IDS := [
	"twin", "stair", "mono", "triplet", "lonewolf", "kaleido", "shredder", "wrecker",
	"encore", "finale", "turnover", "tipjar", "chord", "neonsign", "vinyl", "chorus",
	"interest", "momentum", "vip", "glowstick", "shortcut", "fourfingers", "blacktone",
	"bassline", "mirror", "wildcard", "variation", "reprise", "fullcast", "superfan",
	"opener", "popup", "rainbow", "nopair", "backup", "rehearsal", "trio", "bassclef",
	"warmtone", "cooltone", "undertone", "curtain", "stopwatch", "freeze", "earlyout",
	"crescendo", "segue", "stilllife", "declutter", "stageexit", "doggybag", "royalty",
	"digger", "collector", "doublebill", "sponsor", "skint", "rebrand", "trim", "xray",
	# 2026-08-12 流派批 +7(docs/design/archetypes.md §5;快闪/伴唱撤出 json 但素材保留,
	# wrecker 先例)。⚠ 这 7 张的 source/prompt/成卡素材尚未出图 —— 本工具在出图前对
	# 它们报缺是**正确读数**(待办信号),不是门坏了。
	"duo", "duet", "triad", "triplebill", "backer", "bench", "boxseats", "jukebox",
	# 2026-08-17 twotone 拆分收尾:黑调占 twotone 的旧位(S-15), 红调**追加在队尾**而不是
	# 排在黑调旁边 —— code 是按下标推导的(`_expected_code`), 插在中间会让 bassline 起
	# 40+ 张全体改号, 而 code 已经冻结在既有素材与 prompt 里。
	"redtone",
]
const REQUIRED := ["id", "cn", "code", "kind", "rarity", "trigger_zh", "amount", "art_subject"]
const VALID_KIND := ["target", "support"]
const VALID_RARITY := ["common", "uncommon", "rare"]

const MANIFEST_PATH := "res://assets/jokers/manifest.json"
const CARD_SIZE := Vector2i(1240, 1376)
const PREVIEW_SIZE := Vector2i(155, 172)
const RUNTIME_ART_SIZE := Vector2i(1024, 400)
const PLACEHOLDER_WORDS := [
	"todo", "tbd", "fixme", "placeholder", "lorem", "xxx", "replace me", "fill in",
	"待定", "占位",
]
var _errors: Array[String] = []


func _initialize() -> void:
	_check_manifest()
	_check_assets()

	for err in _errors:
		printerr(err)

	if _errors.is_empty():
		print("joker asset manifest OK: %d records" % IDS.size())
		quit(0)
	else:
		printerr("joker asset manifest FAILED: %d errors" % _errors.size())
		quit(1)


func _check_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST_PATH):
		_error("missing %s" % _display_path(MANIFEST_PATH))
		return

	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		_error("cannot open %s: %s" % [_display_path(MANIFEST_PATH), error_string(FileAccess.get_open_error())])
		return

	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		_error("invalid JSON in %s at line %d: %s" % [
			_display_path(MANIFEST_PATH), parser.get_error_line(), parser.get_error_message(),
		])
		return

	var manifest: Variant = parser.data
	if typeof(manifest) != TYPE_DICTIONARY:
		_error("%s must be a JSON object" % _display_path(MANIFEST_PATH))
		return

	var manifest_dict := manifest as Dictionary
	_check_manifest_envelope(manifest_dict)

	if not manifest_dict.has("cards"):
		_error("%s missing required field 'cards'" % _display_path(MANIFEST_PATH))
		return

	var records: Variant = manifest_dict["cards"]
	if typeof(records) != TYPE_ARRAY:
		_error("%s.cards must be a JSON array" % _display_path(MANIFEST_PATH))
		return

	if records.size() != IDS.size():
		_error("%s.cards must contain exactly %d records, found %d" % [
			_display_path(MANIFEST_PATH), IDS.size(), records.size(),
		])

	for i in range(records.size()):
		var rec: Variant = records[i]
		if typeof(rec) != TYPE_DICTIONARY:
			_error("manifest.cards[%d] must be an object" % i)
			continue
		_check_record(i, rec)


func _check_manifest_envelope(manifest: Dictionary) -> void:
	if not manifest.has("version"):
		_error("%s missing required field 'version'" % _display_path(MANIFEST_PATH))
	elif typeof(manifest["version"]) != TYPE_FLOAT and typeof(manifest["version"]) != TYPE_INT:
		_error("%s.version must be 1" % _display_path(MANIFEST_PATH))
	elif float(manifest["version"]) != 1.0:
		_error("%s.version must be 1, found %s" % [_display_path(MANIFEST_PATH), str(manifest["version"])])

	_check_size_field(manifest, "card_size", CARD_SIZE)
	_check_size_field(manifest, "preview_size", PREVIEW_SIZE)
	_check_size_field(manifest, "runtime_art_size", RUNTIME_ART_SIZE)


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


func _check_record(index: int, rec: Dictionary) -> void:
	for key in REQUIRED:
		if not rec.has(key):
			_error("manifest.cards[%d] missing required field '%s'" % [index, key])
			continue
		if typeof(rec[key]) != TYPE_STRING:
			_error("manifest.cards[%d].%s must be a string" % [index, key])
			continue
		if String(rec[key]).strip_edges().is_empty():
			_error("manifest.cards[%d].%s must not be empty" % [index, key])

	if index < IDS.size():
		var expected_id := String(IDS[index])
		var actual_id := String(rec.get("id", ""))
		if actual_id != expected_id:
			_error("manifest.cards[%d].id must be '%s', found '%s'" % [index, expected_id, actual_id])
	else:
		_error("manifest.cards[%d] is outside the immutable %d-card ID list" % [index, IDS.size()])

	if index < IDS.size() and rec.has("code") and typeof(rec["code"]) == TYPE_STRING:
		var expected_code := _expected_code(index)
		var actual_code := String(rec["code"])
		if actual_code != expected_code:
			_error("manifest.cards[%d].code must be '%s', found '%s'" % [index, expected_code, actual_code])

	if rec.has("kind") and typeof(rec["kind"]) == TYPE_STRING and not VALID_KIND.has(String(rec["kind"])):
		_error("manifest.cards[%d].kind must be one of %s" % [index, VALID_KIND])

	if rec.has("rarity") and typeof(rec["rarity"]) == TYPE_STRING and not VALID_RARITY.has(String(rec["rarity"])):
		_error("manifest.cards[%d].rarity must be one of %s" % [index, VALID_RARITY])

	if rec.has("amount") and typeof(rec["amount"]) == TYPE_STRING:
		var amount := String(rec["amount"])
		if amount.contains("\n") or amount.contains("\r"):
			_error("manifest.cards[%d].amount must not contain a line break" % index)

	_check_placeholder_copy("manifest.cards[%d]" % index, rec)


func _expected_code(index: int) -> String:
	if index < 8:
		return "T-%02d" % (index + 1)
	return "S-%02d" % (index - 7)


func _check_assets() -> void:
	for id in IDS:
		var joker_id := String(id)
		_check_image("source", "res://assets/jokers/source/joker_%s.png" % joker_id, Vector2i(1024, 1024))
		_check_image("runtime", "res://assets/jokers/joker_%s.png" % joker_id, RUNTIME_ART_SIZE)
		_check_image("card", "res://assets/jokers/cards/joker_%s.png" % joker_id, CARD_SIZE)
		_check_image("preview", "res://assets/jokers/previews/joker_%s.png" % joker_id, PREVIEW_SIZE)
		_check_prompt(joker_id)


func _check_image(label: String, path: String, expected: Vector2i) -> void:
	if not FileAccess.file_exists(path):
		_error("missing %s asset %s" % [label, _display_path(path)])
		return

	var image := Image.new()
	var load_error := image.load(path)
	if load_error != OK:
		_error("cannot load %s asset %s: %s" % [label, _display_path(path), error_string(load_error)])
		return

	var actual := Vector2i(image.get_width(), image.get_height())
	if actual != expected:
		_error("%s asset %s must be %dx%d, found %dx%d" % [
			label, _display_path(path), expected.x, expected.y, actual.x, actual.y,
		])


func _check_prompt(id: String) -> void:
	var path := "res://assets/jokers/prompts/joker_%s.json" % id
	if not FileAccess.file_exists(path):
		_error("missing prompt %s" % _display_path(path))
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_error("cannot open prompt %s: %s" % [_display_path(path), error_string(FileAccess.get_open_error())])
		return

	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		_error("invalid JSON in prompt %s at line %d: %s" % [
			_display_path(path), parser.get_error_line(), parser.get_error_message(),
		])
		return

	if typeof(parser.data) != TYPE_DICTIONARY:
		_error("prompt %s must be an object" % _display_path(path))
		return

	var prompt := parser.data as Dictionary
	if String(prompt.get("id", "")) != id:
		_error("prompt %s id must be '%s', found '%s'" % [
			_display_path(path), id, String(prompt.get("id", "")),
		])

	if typeof(prompt.get("prompt")) != TYPE_STRING or String(prompt.get("prompt", "")).strip_edges().is_empty():
		_error("prompt %s prompt must be a non-empty string" % _display_path(path))

	var revision: Variant = prompt.get("revision")
	if typeof(revision) != TYPE_FLOAT and typeof(revision) != TYPE_INT:
		_error("prompt %s revision must be a number >= 1" % _display_path(path))
	elif int(revision) < 1:
		_error("prompt %s revision must be >= 1" % _display_path(path))

	var source_sha := String(prompt.get("source_sha256", ""))
	if not _is_sha256(source_sha):
		_error("prompt %s source_sha256 must be 64 lowercase SHA-256 hex characters" % _display_path(path))
	else:
		var source_path := "res://assets/jokers/source/joker_%s.png" % id
		if FileAccess.file_exists(source_path):
			var actual_source_sha := FileAccess.get_sha256(source_path)
			if source_sha != actual_source_sha:
				_error("prompt %s source_sha256 does not match %s" % [
					_display_path(path), _display_path(source_path),
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
