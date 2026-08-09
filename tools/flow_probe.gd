extends SceneTree

## Headless flow regression. Run (exits non-zero on a violation):
##   godot --headless --path . --script res://tools/flow_probe.gd
##
## Drives the real battle scene and HAMMERS every end screen with
## a double tap, which is what used to walk the section counter forward behind
## the front screen. Invariants asserted:
##   1. 演出成功 only ever appears at the LAST phrase of a section
##   2. section_idx never skips a step (0→1→2…), never moves while FRONT
##   3. a MID-SECTION shop must not advance the section nor reset the score
##      (2026-08-06 商店与盲注解耦 — the break opens the shop *inside* a blind,
##      so mistakenly routing it through _next_section() would silently eat a
##      whole section, exactly the class of bug invariant 2 was written for)
## States: 0 FRONT, 1 INTRO, 2 DECISION, 3 RESOLVE, 4 DRAFT, 5 END

var _scene: Node
var _frames := 0
var _was_end := false
var _last_idx := 0
var _bugs := 0
var _ends := 0
var _brk_idx := -1        # section_idx captured when a mid-section shop opened
var _brk_score := -1
var _breaks := 0
var _successes := 0       # 演出成功 screens seen (finale only)

func _initialize() -> void:
	get_root().set_content_scale_size(Vector2i(720, 1280))
	_scene = load("res://view/phrase.tscn").instantiate()
	get_root().add_child(_scene)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 4:
		_scene._on_home_start()          # leave the home screen
		return false
	if _frames == 8:
		_scene.choose_character(0)
		return false
	if _frames < 12:
		return false
	var run = _scene.run
	var st: int = _scene.state

	# invariant 2: the section index may only ever step by +1 (or reset to 0)
	var idx: int = run.section_idx
	if idx != _last_idx and idx != _last_idx + 1 and idx != 0:
		print("!!! BUG: section jumped %d -> %d (state=%d)" % [_last_idx, idx, st])
		_bugs += 1
	# invariant 3a: a section may only advance once its phrases are all played.
	# This is the direct catch for a mid-section shop wired to _next_section().
	# Reads Run.last_section_phrases rather than sampling phrase_in_section per
	# frame: the light-banner route advances synchronously, so the boundary
	# value is never visible to a frame-sampling probe (that produced 84 false
	# positives the moment mid-run clears stopped parking on a success screen).
	if idx == _last_idx + 1 and run.last_section_phrases != GameConfig.PHRASES_PER_SECTION:
		print("!!! BUG: S%d advanced early (%d/%d phrases played)"
			% [_last_idx + 1, run.last_section_phrases, GameConfig.PHRASES_PER_SECTION])
		_bugs += 1
	_last_idx = idx

	# invariant 1: 演出成功 belongs to the END OF THE RUN only (2026-08-06 用户:
	# 「只有一整关通关才跳」). Mid-run clears get the light banner instead, so a
	# success screen anywhere but the finale's last phrase is a bug.
	var end_now: bool = _scene.run_end.visible
	if end_now and not _was_end:
		_ends += 1
		var mode: String = _scene.run_end._mode
		if mode == "success":
			_successes += 1
			if run.phrase_in_section != GameConfig.PHRASES_PER_SECTION:
				print("!!! BUG: success mid-section (phrase %d)" % run.phrase_in_section)
				_bugs += 1
			if idx != GameConfig.SECTIONS_PER_RUN - 1:
				print("!!! BUG: success on non-finale S%d" % (idx + 1))
				_bugs += 1
	_was_end = end_now

	match st:
		0:    # FRONT — start another tour
			_scene._on_home_start()
			_scene.choose_character(0)
		1:    # INTRO
			_scene.intro._dismiss()
		2:    # DECISION — guarantee the clear, force the settle
			# invariant 3, checked BEFORE the probe stuffs the score
			if _brk_idx >= 0:
				if run.section_idx != _brk_idx:
					print("!!! BUG: mid-section shop advanced S%d -> S%d"
						% [_brk_idx + 1, run.section_idx + 1])
					_bugs += 1
				if run.section_score != _brk_score:
					print("!!! BUG: mid-section shop reset the score (%d -> %d)"
						% [_brk_score, run.section_score])
					_bugs += 1
				_brk_idx = -1
			_scene.run.section_score = 999999
			_scene.elapsed = 999.0
		3:    # RESOLVE
			_scene.elapsed = 999.0
		4:    # DRAFT
			# a break shop opens mid-blind; a section-end shop opens at phrase 0
			# of the next blind (the counter has already been reset by then)
			if run.phrase_in_section > 0 \
					and run.phrase_in_section < GameConfig.PHRASES_PER_SECTION:
				if _brk_idx < 0:
					_breaks += 1
				_brk_idx = run.section_idx
				_brk_score = run.section_score
			_scene._on_shop_skipped()
			_scene._on_shop_skipped()          # double tap
		5:    # END — hammer it twice, the old re-entry bug
			if _scene.run_end._mode == "success":
				_scene._on_end_next()
				_scene._on_end_next()
			else:
				_scene._on_end_retry()
				_scene._on_end_retry()
	if _frames > 2500:
		print("[flow] %d end-screens (%d success), %d mid-section shops, %d bugs over %d frames"
			% [_ends, _successes, _breaks, _bugs, _frames])
		# a run with zero observed breaks means the probe stopped exercising
		# the decoupled shop at all — that is a silent loss of coverage
		if _breaks == 0:
			print("!!! BUG: no mid-section shop ever observed")
			_bugs += 1
		# likewise: the probe force-clears every section, so it MUST reach the
		# finale and see the one success screen a full run is allowed
		if _successes == 0:
			print("!!! BUG: no finale success screen ever observed")
			_bugs += 1
		quit(1 if _bugs > 0 else 0)
	return false
