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
const SOURCE_DIR := "res://assets/characters/source"
const OUTPUT_DIR_TEMPLATE := "res://assets/characters/%s"
const PORTRAIT_SIZE := Vector2i(1536, 2048)
const AVATAR_SIZE := Vector2i(512, 512)
const FRAME_SIZE := Vector2i(128, 128)
const SHEET_SIZE := Vector2i(1024, 128)
const CELL_GRID := Vector2i(4, 2)
const GUTTER_CROP_FRACTION := 0.03
const CHROMA_KEY := Color(0.0, 1.0, 0.4, 1.0)
const KEY_REMOVE_DISTANCE := 42.0
const KEY_SOFT_DISTANCE := 70.0
const TARGET_FIT := Vector2i(118, 122)
const FOOT_ANCHOR_Y := 124
const FRAME_CENTER_X := 64
const OPAQUE_THRESHOLD := 1.0 / 255.0
const BUILD_STAGES: Array[String] = ["portrait", "walk", "dance"]

var _errors: Array[String] = []
var _manifest: Dictionary = {}
var _records_by_id: Dictionary = {}
var MARKER_ROOT := "res://assets/characters"
var _stage_name := "all"
var _stage_targets: Array[String] = []
var _staging_dir := ""
var _staged_outputs: Dictionary = {}


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--self-test"):
		_run_self_tests()
		return

	if OS.get_cmdline_user_args().has("--check-only"):
		print("character asset builder parse OK")
		quit(0)
		return

	var stages := _parse_stages()
	_stage_targets = _target_paths_for_stages(stages)
	_staging_dir = _new_staging_dir(_stage_name)
	_write_stage_marker("failed", _stage_name, _stage_targets)
	if not _errors.is_empty():
		_finish()
		return

	_collect_missing_sources(stages)
	if not _errors.is_empty():
		_finish()
		return

	if stages.has("portrait"):
		_manifest = _load_manifest()
		_records_by_id = _index_records(_manifest)
		if not _errors.is_empty():
			_finish()
			return

	for id in IDS:
		if stages.has("portrait"):
			_build_portrait_and_avatar(id)
		if stages.has("walk"):
			_build_animation_sheet(id, "walk")
		if stages.has("dance"):
			_build_animation_sheet(id, "dance")

	if _errors.is_empty():
		_publish_staged_outputs()
	if _errors.is_empty():
		_mark_successful_build(_stage_name, _stage_targets)

	_finish()


func _parse_stages() -> Dictionary:
	return _parse_stage_args(OS.get_cmdline_user_args())


func _parse_stage_args(args: PackedStringArray) -> Dictionary:
	var stage := "all"
	var stage_seen := false
	for arg in args:
		var text := String(arg)
		if text == "--check-only" or text == "--self-test":
			continue
		if text.begins_with("--stage="):
			if stage_seen:
				_error("use only one --stage argument")
				continue
			stage_seen = true
			stage = text.substr(8).strip_edges()
		else:
			_error("unknown argument '%s'" % text)

	_stage_name = stage
	if not _errors.is_empty():
		return {}

	match stage:
		"all":
			return {"portrait": true, "walk": true, "dance": true}
		"portrait":
			return {"portrait": true}
		"walk":
			return {"walk": true}
		"dance":
			return {"dance": true}
		_:
			_error("unknown stage '%s'; expected portrait, walk, dance, or all" % stage)
			return {}


func _target_paths_for_stages(stages: Dictionary) -> Array[String]:
	var paths: Array[String] = []
	for id in IDS:
		var output_dir := OUTPUT_DIR_TEMPLATE % id
		if stages.has("portrait"):
			paths.append("%s/portrait.png" % output_dir)
			paths.append("%s/avatar.png" % output_dir)
		if stages.has("walk"):
			paths.append("%s/walk.png" % output_dir)
		if stages.has("dance"):
			paths.append("%s/dance.png" % output_dir)
	return paths


func _collect_missing_sources(stages: Dictionary) -> void:
	for id in IDS:
		if stages.has("portrait"):
			_require_source(id, "portrait")
		if stages.has("walk"):
			_require_source(id, "walk")
		if stages.has("dance"):
			_require_source(id, "dance")


func _require_source(id: String, kind: String) -> void:
	var source_path := _source_path(id, kind)
	if not FileAccess.file_exists(source_path):
		_error("missing source %s" % _display_path(source_path))


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
	if not manifest.has("characters") or typeof(manifest["characters"]) != TYPE_ARRAY:
		_error("%s.characters must be a JSON array" % _display_path(MANIFEST_PATH))
		return {}

	return manifest


func _index_records(manifest: Dictionary) -> Dictionary:
	var by_id := {}
	var characters: Array = manifest.get("characters", [])
	for i in range(characters.size()):
		var value: Variant = characters[i]
		if typeof(value) != TYPE_DICTIONARY:
			_error("manifest.characters[%d] must be an object" % i)
			continue
		var rec := value as Dictionary
		var id := String(rec.get("id", ""))
		if id.is_empty():
			_error("manifest.characters[%d].id must be a non-empty string" % i)
			continue
		if by_id.has(id):
			_error("duplicate manifest character id '%s'" % id)
			continue
		by_id[id] = rec

	for id in IDS:
		if not by_id.has(id):
			_error("missing manifest record for '%s'" % id)
	return by_id


func _build_portrait_and_avatar(id: String) -> void:
	var source_path := _source_path(id, "portrait")
	var source := _load_image(source_path)
	if source.is_empty():
		return

	var crop_rect := _center_crop_rect(source.get_size(), 3.0 / 4.0)
	var portrait := Image.create(crop_rect.size.x, crop_rect.size.y, false, Image.FORMAT_RGBA8)
	portrait.fill(Color(0, 0, 0, 0))
	portrait.blit_rect(source, crop_rect, Vector2i.ZERO)
	portrait.resize(PORTRAIT_SIZE.x, PORTRAIT_SIZE.y, Image.INTERPOLATE_LANCZOS)

	var output_dir := OUTPUT_DIR_TEMPLATE % id
	var portrait_path := "%s/portrait.png" % output_dir
	_stage_output(portrait, portrait_path)

	_build_avatar(id, portrait)


func _build_avatar(id: String, portrait: Image) -> void:
	var rec: Dictionary = _records_by_id.get(id, {})
	if not rec.has("avatar_crop") or typeof(rec["avatar_crop"]) != TYPE_ARRAY:
		_error("manifest record '%s' missing avatar_crop array" % id)
		return

	var crop_values: Array = rec["avatar_crop"]
	if crop_values.size() != 4:
		_error("manifest record '%s' avatar_crop must have four numbers" % id)
		return

	var normalized := PackedFloat32Array()
	for i in range(4):
		if typeof(crop_values[i]) != TYPE_FLOAT and typeof(crop_values[i]) != TYPE_INT:
			_error("manifest record '%s' avatar_crop[%d] must be numeric" % [id, i])
			return
		normalized.append(float(crop_values[i]))

	var crop := Rect2i(
		int(round(normalized[0] * PORTRAIT_SIZE.x)),
		int(round(normalized[1] * PORTRAIT_SIZE.y)),
		int(round(normalized[2] * PORTRAIT_SIZE.x)),
		int(round(normalized[3] * PORTRAIT_SIZE.y))
	)
	crop = _clamp_rect(crop, PORTRAIT_SIZE)
	if crop.size.x <= 0 or crop.size.y <= 0:
		_error("manifest record '%s' avatar_crop resolves to an empty rectangle" % id)
		return

	var square_crop := _center_crop_rect(crop.size, 1.0)
	square_crop.position += crop.position
	var avatar := Image.create(square_crop.size.x, square_crop.size.y, false, Image.FORMAT_RGBA8)
	avatar.fill(Color(0, 0, 0, 0))
	avatar.blit_rect(portrait, square_crop, Vector2i.ZERO)
	avatar.resize(AVATAR_SIZE.x, AVATAR_SIZE.y, Image.INTERPOLATE_LANCZOS)

	var avatar_path := "%s/avatar.png" % (OUTPUT_DIR_TEMPLATE % id)
	_stage_output(avatar, avatar_path)


func _build_animation_sheet(id: String, kind: String) -> void:
	var source_path := _source_path(id, kind)
	var source := _load_image(source_path)
	if source.is_empty():
		return

	var source_size := source.get_size()
	if not _validate_animation_grid(source_size, source_path):
		return

	var cell_size := Vector2i(source_size.x / CELL_GRID.x, source_size.y / CELL_GRID.y)

	var frames: Array[Image] = []
	for row in range(CELL_GRID.y):
		for col in range(CELL_GRID.x):
			var frame_index := row * CELL_GRID.x + col
			var cell := Rect2i(Vector2i(col * cell_size.x, row * cell_size.y), cell_size)
			var frame := _process_animation_cell(source, cell, id, kind, frame_index)
			if frame.is_empty():
				continue
			frames.append(frame)

	if frames.size() != 8:
		return

	var sheet := Image.create(SHEET_SIZE.x, SHEET_SIZE.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	for i in range(frames.size()):
		sheet.blit_rect(frames[i], Rect2i(Vector2i.ZERO, FRAME_SIZE), Vector2i(i * FRAME_SIZE.x, 0))

	var output_dir := OUTPUT_DIR_TEMPLATE % id
	var output_path := "%s/%s.png" % [output_dir, kind]
	_stage_output(sheet, output_path)


func _validate_animation_grid(source_size: Vector2i, source_path: String) -> bool:
	if source_size.x <= 0 or source_size.y <= 0:
		_error("source %s is empty: found %dx%d" % [_display_path(source_path), source_size.x, source_size.y])
		return false
	if source_size.x % CELL_GRID.x != 0 or source_size.y % CELL_GRID.y != 0:
		_error("source %s must divide evenly into 4 columns and 2 rows, found %dx%d" % [
			_display_path(source_path), source_size.x, source_size.y,
		])
		return false
	return true


func _process_animation_cell(source: Image, cell: Rect2i, id: String, kind: String, frame_index: int) -> Image:
	var inset_x := int(round(cell.size.x * GUTTER_CROP_FRACTION))
	var inset_y := int(round(cell.size.y * GUTTER_CROP_FRACTION))
	var crop_rect := Rect2i(
		cell.position + Vector2i(inset_x, inset_y),
		cell.size - Vector2i(inset_x * 2, inset_y * 2)
	)
	if crop_rect.size.x <= 0 or crop_rect.size.y <= 0:
		_error("%s %s frame %d gutter crop is empty" % [id, kind, frame_index])
		return Image.new()

	var cell_image := Image.create(crop_rect.size.x, crop_rect.size.y, false, Image.FORMAT_RGBA8)
	cell_image.fill(Color(0, 0, 0, 0))
	cell_image.blit_rect(source, crop_rect, Vector2i.ZERO)
	_apply_chroma_key(cell_image)

	var bounds := _opaque_bbox(cell_image)
	if bounds.size == Vector2i.ZERO:
		_error("%s %s frame %d is empty after chroma key" % [id, kind, frame_index])
		return Image.new()

	var trimmed := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	trimmed.fill(Color(0, 0, 0, 0))
	trimmed.blit_rect(cell_image, bounds, Vector2i.ZERO)

	var scale: float = min(float(TARGET_FIT.x) / float(bounds.size.x), float(TARGET_FIT.y) / float(bounds.size.y))
	var scaled_size := Vector2i(
		max(1, int(round(bounds.size.x * scale))),
		max(1, int(round(bounds.size.y * scale)))
	)
	trimmed.resize(scaled_size.x, scaled_size.y, Image.INTERPOLATE_LANCZOS)

	var frame := Image.create(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
	frame.fill(Color(0, 0, 0, 0))
	var offset := Vector2i(FRAME_CENTER_X - scaled_size.x / 2, FOOT_ANCHOR_Y - scaled_size.y)
	frame.blit_rect(trimmed, Rect2i(Vector2i.ZERO, scaled_size), offset)

	var frame_bounds := _opaque_bbox(frame)
	if frame_bounds.size == Vector2i.ZERO:
		_error("%s %s frame %d is empty after packing" % [id, kind, frame_index])
		return Image.new()
	if frame_bounds.position.x <= 0:
		_error("%s %s frame %d opaque bounds touch left edge" % [id, kind, frame_index])
		return Image.new()
	if frame_bounds.position.y <= 0:
		_error("%s %s frame %d opaque bounds touch top edge" % [id, kind, frame_index])
		return Image.new()
	if frame_bounds.position.x + frame_bounds.size.x >= FRAME_SIZE.x:
		_error("%s %s frame %d opaque bounds touch right edge" % [id, kind, frame_index])
		return Image.new()

	return frame


func _apply_chroma_key(image: Image) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			var distance := _rgb_distance_255(pixel, CHROMA_KEY)
			if distance <= KEY_REMOVE_DISTANCE:
				pixel = Color(0, 0, 0, 0)
			elif distance < KEY_SOFT_DISTANCE:
				var factor := (distance - KEY_REMOVE_DISTANCE) / (KEY_SOFT_DISTANCE - KEY_REMOVE_DISTANCE)
				pixel.a *= clampf(factor, 0.0, 1.0)
				pixel = _despill_green(pixel)
			image.set_pixel(x, y, pixel)


func _despill_green(pixel: Color) -> Color:
	pixel.g = min(pixel.g, max(pixel.r, pixel.b))
	return pixel


func _rgb_distance_255(a: Color, b: Color) -> float:
	var dr := (a.r - b.r) * 255.0
	var dg := (a.g - b.g) * 255.0
	var db := (a.b - b.b) * 255.0
	return sqrt(dr * dr + dg * dg + db * db)


func _opaque_bbox(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > OPAQUE_THRESHOLD:
				min_x = min(min_x, x)
				min_y = min(min_y, y)
				max_x = max(max_x, x)
				max_y = max(max_y, y)

	if max_x < min_x or max_y < min_y:
		return Rect2i(Vector2i.ZERO, Vector2i.ZERO)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _center_crop_rect(size: Vector2i, aspect: float) -> Rect2i:
	var width := size.x
	var height := size.y
	var current_aspect := float(width) / float(height)
	if current_aspect > aspect:
		width = int(round(height * aspect))
	else:
		height = int(round(width / aspect))
	return Rect2i((size.x - width) / 2, (size.y - height) / 2, width, height)


func _clamp_rect(rect: Rect2i, bounds: Vector2i) -> Rect2i:
	var x := clampi(rect.position.x, 0, bounds.x)
	var y := clampi(rect.position.y, 0, bounds.y)
	var right := clampi(rect.position.x + rect.size.x, x, bounds.x)
	var bottom := clampi(rect.position.y + rect.size.y, y, bounds.y)
	return Rect2i(x, y, right - x, bottom - y)


func _load_image(path: String) -> Image:
	var image := Image.new()
	var load_error := image.load(path)
	if load_error != OK:
		_error("cannot load source %s: %s" % [_display_path(path), error_string(load_error)])
		return Image.new()
	image.convert(Image.FORMAT_RGBA8)
	return image


func _source_path(id: String, kind: String) -> String:
	return "%s/%s_%s.png" % [SOURCE_DIR, id, kind]


func _stage_output(image: Image, final_path: String) -> void:
	_ensure_dir(_staging_dir)
	if not _errors.is_empty():
		return

	var staged_path := "%s/%s" % [_staging_dir, _staging_name(final_path)]
	var save_error := image.save_png(_global_path(staged_path))
	if save_error != OK:
		_error("cannot stage %s: %s" % [_display_path(final_path), error_string(save_error)])
		return
	_staged_outputs[final_path] = staged_path
	print("staged %s" % _display_path(final_path))


func _publish_staged_outputs() -> void:
	for final_path in _stage_targets:
		if not _staged_outputs.has(final_path):
			_error("internal error: missing staged output for %s" % _display_path(final_path))

	if not _errors.is_empty():
		return

	for final_path in _stage_targets:
		var staged_path := String(_staged_outputs[final_path])
		var staged := _load_image(staged_path)
		if staged.is_empty():
			return
		_ensure_dir(final_path.get_base_dir())
		if not _errors.is_empty():
			return
		var save_error := staged.save_png(_global_path(final_path))
		if save_error != OK:
			_error("cannot save %s: %s" % [_display_path(final_path), error_string(save_error)])
			return
		print("saved %s" % _display_path(final_path))


func _staging_name(final_path: String) -> String:
	return _display_path(final_path).replace("/", "__")


func _new_staging_dir(stage: String) -> String:
	return "%s/Sync5-character-build-%s-%d" % [OS.get_temp_dir(), stage, Time.get_ticks_usec()]


func _marker_path_for_stage(stage: String) -> String:
	return "%s/.build-%s-failed.json" % [MARKER_ROOT, stage]


func _write_stage_marker(status: String, stage: String, targets: Array[String]) -> void:
	_write_build_marker(_marker_path_for_stage(stage), status, stage, targets)


func _mark_successful_build(stage: String, targets: Array[String]) -> void:
	if stage == "all":
		_write_stage_marker("ok", "all", _target_paths_for_stages({"portrait": true, "walk": true, "dance": true}))
		for single_stage in BUILD_STAGES:
			_write_stage_marker("ok", single_stage, _target_paths_for_stages({single_stage: true}))
		return

	_write_stage_marker("ok", stage, targets)
	if _all_individual_markers_ok():
		_write_stage_marker("ok", "all", _target_paths_for_stages({"portrait": true, "walk": true, "dance": true}))


func _all_individual_markers_ok() -> bool:
	for stage in BUILD_STAGES:
		if _read_marker_status(_marker_path_for_stage(stage)) != "ok":
			return false
	return true


func _write_build_marker(path: String, status: String, stage: String, targets: Array[String]) -> void:
	_ensure_dir(path.get_base_dir())
	if not _errors.is_empty():
		return

	var target_paths: Array[String] = []
	for target in targets:
		target_paths.append(_display_path(target))

	var payload := {
		"status": status,
		"stage": stage,
		"targets": target_paths,
	}
	var text := JSON.stringify(payload, "\t")
	var file := FileAccess.open(_global_path(path), FileAccess.WRITE)
	if file == null:
		_error("cannot write marker %s: %s" % [_display_path(path), error_string(FileAccess.get_open_error())])
		return
	file.store_string(text + "\n")
	file.close()


func _ensure_dir(path: String) -> void:
	var display := _display_path(path)
	var error := DirAccess.make_dir_recursive_absolute(_global_path(path))
	if error != OK and error != ERR_ALREADY_EXISTS:
		_error("cannot create directory %s: %s" % [display, error_string(error)])


func _finish() -> void:
	for err in _errors:
		printerr(err)
	if _errors.is_empty():
		quit(0)
	else:
		printerr("character asset build FAILED: %d errors" % _errors.size())
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


func _run_self_tests() -> void:
	var failures: Array[String] = []
	_self_test_duplicate_stage(failures)
	_self_test_non_divisible_sheet(failures)
	_self_test_chroma_soft_edge(failures)
	_self_test_failure_marker_preserves_final(failures)
	_self_test_success_marker(failures)
	_self_test_staged_markers_supersede_all_failure(failures)
	_self_test_all_success_writes_all_markers(failures)
	_self_test_staging_uses_os_temp(failures)

	if failures.is_empty():
		print("character asset builder self-test OK")
		quit(0)
	else:
		for failure in failures:
			printerr(failure)
		printerr("character asset builder self-test FAILED: %d errors" % failures.size())
		quit(1)


func _self_test_duplicate_stage(failures: Array[String]) -> void:
	_errors.clear()
	var old_stage := _stage_name
	var stages := _parse_stage_args(PackedStringArray(["--stage=all", "--stage=walk"]))
	_assert(stages.is_empty(), "duplicate stage returns no selected stages", failures)
	_assert(_errors.size() == 1, "duplicate stage reports exactly one error", failures)
	_assert(_errors.size() > 0 and String(_errors[0]).contains("use only one --stage"), "duplicate stage error is explicit", failures)
	_errors.clear()
	_stage_name = old_stage


func _self_test_non_divisible_sheet(failures: Array[String]) -> void:
	_errors.clear()
	var ok := _validate_animation_grid(Vector2i(401, 201), "res://assets/characters/source/dj_walk.png")
	_assert(not ok, "non-divisible animation source is rejected", failures)
	_assert(_errors.size() == 1, "non-divisible source reports exactly one error", failures)
	_assert(
		_errors.size() > 0 and String(_errors[0]).contains("found 401x201"),
		"non-divisible source error includes actual dimensions",
		failures
	)
	_errors.clear()


func _self_test_chroma_soft_edge(failures: Array[String]) -> void:
	var image := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, CHROMA_KEY)
	image.set_pixel(1, 0, Color8(50, 255, 102, 255))
	_apply_chroma_key(image)

	var removed := image.get_pixel(0, 0)
	var soft := image.get_pixel(1, 0)
	_assert(removed.a == 0.0, "fully keyed pixel alpha is zero", failures)
	_assert(removed.r == 0.0 and removed.g == 0.0 and removed.b == 0.0, "fully keyed pixel RGB is cleared", failures)
	_assert(soft.a > 0.0 and soft.a < 1.0, "soft-edge pixel keeps partial alpha", failures)
	_assert(soft.g <= max(soft.r, soft.b) + 0.001, "soft-edge pixel is green-despilled", failures)


func _self_test_failure_marker_preserves_final(failures: Array[String]) -> void:
	var root := "/tmp/sync5-character-builder-self-test-%d" % Time.get_ticks_usec()
	var marker_path := "%s/.build-walk-failed.json" % root
	var final_path := "%s/dj/walk.png" % root
	_ensure_dir(final_path.get_base_dir())
	var stale := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	stale.fill(Color.RED)
	_assert(stale.save_png(final_path) == OK, "atomicity test writes existing final fixture", failures)
	var before_hash := FileAccess.get_sha256(final_path)
	_write_build_marker(marker_path, "failed", "walk", [final_path])
	var ok := _validate_animation_grid(Vector2i(401, 201), "%s/source_bad_walk.png" % root)
	_assert(not ok, "atomicity test fault input is rejected", failures)
	var after_hash := FileAccess.get_sha256(final_path)
	_assert(before_hash == after_hash, "failed marker does not touch existing final bytes", failures)
	_assert(_read_marker_status(marker_path) == "failed", "failed marker records failed status", failures)
	_errors.clear()


func _self_test_success_marker(failures: Array[String]) -> void:
	var root := "/tmp/sync5-character-builder-self-test-%d" % Time.get_ticks_usec()
	var marker_path := "%s/.build-walk-failed.json" % root
	var final_path := "%s/dj/walk.png" % root
	_write_build_marker(marker_path, "ok", "walk", [final_path])
	_assert(_read_marker_status(marker_path) == "ok", "success marker records ok status", failures)
	_errors.clear()


func _self_test_staged_markers_supersede_all_failure(failures: Array[String]) -> void:
	var old_root := MARKER_ROOT
	MARKER_ROOT = "/tmp/sync5-character-builder-marker-test-%d" % Time.get_ticks_usec()
	_write_stage_marker("failed", "all", ["target-all"])
	_mark_successful_build("portrait", ["target-portrait"])
	_assert(_read_marker_status(_marker_path_for_stage("all")) == "failed", "portrait alone leaves all marker failed", failures)
	_mark_successful_build("walk", ["target-walk"])
	_assert(_read_marker_status(_marker_path_for_stage("all")) == "failed", "portrait plus walk leaves all marker failed", failures)
	_mark_successful_build("dance", ["target-dance"])
	_assert(_read_marker_status(_marker_path_for_stage("all")) == "ok", "three successful individual stages mark all ok", failures)
	_assert(_read_marker_status(_marker_path_for_stage("portrait")) == "ok", "portrait marker ok after staged success", failures)
	_assert(_read_marker_status(_marker_path_for_stage("walk")) == "ok", "walk marker ok after staged success", failures)
	_assert(_read_marker_status(_marker_path_for_stage("dance")) == "ok", "dance marker ok after staged success", failures)
	MARKER_ROOT = old_root
	_errors.clear()


func _self_test_all_success_writes_all_markers(failures: Array[String]) -> void:
	var old_root := MARKER_ROOT
	MARKER_ROOT = "/tmp/sync5-character-builder-marker-test-%d" % Time.get_ticks_usec()
	_mark_successful_build("all", ["target-all"])
	for stage in ["all", "portrait", "walk", "dance"]:
		_assert(_read_marker_status(_marker_path_for_stage(stage)) == "ok", "all success writes %s marker ok" % stage, failures)
	MARKER_ROOT = old_root
	_errors.clear()


func _self_test_staging_uses_os_temp(failures: Array[String]) -> void:
	var staging := _new_staging_dir("walk")
	_assert(not staging.begins_with("res://"), "staging path is outside res://", failures)
	_assert(staging.begins_with(OS.get_temp_dir()), "staging path uses OS temp dir", failures)


func _read_marker_status(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return ""
	if typeof(parser.data) != TYPE_DICTIONARY:
		return ""
	return String((parser.data as Dictionary).get("status", ""))


func _assert(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
