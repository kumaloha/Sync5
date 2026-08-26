extends SceneTree

## Screenshot helper. Run NON-headless (needs rendering):
##   godot --path . --script res://tools/shoot.gd
## Captures the three settle beats: FLY / MERGE / BURST.

var _scene: Node
var _frames := 0
var _fired := false
var _t0 := 0.0
var _shots := [
	{"at": 0.22, "name": "fly"},
	{"at": 0.90, "name": "merge"},
	{"at": 1.90, "name": "burst"},
	{"at": 3.40, "name": "idle"},
]
var _idx := 0

func _initialize() -> void:
	_scene = Shot.stage(self)

func _process(delta: float) -> bool:
	_frames += 1
	if _frames == 4:
		_scene.start_run()     # skip the pick screen
	if not _fired and _frames == 300:
		# stage a wall section so the boss-face banner renders via the real path.
		# Keys/index must track WALL_SECTIONS — a stale hardcoded index renders a
		# blind card reading "06 /4" (Run.next_section() clamps; probes do not).
		_scene.run.run_faces = {}
		var faces := ["norepeat", "norepeat", "static", "rush"]
		for i in range(GameConfig.WALL_SECTIONS.size()):
			_scene.run.run_faces[GameConfig.WALL_SECTIONS[i]] = faces[i % faces.size()]
		_scene.run.section_idx = GameConfig.SECTIONS_PER_RUN - 1
		_scene.run.phrase_in_section = 0
		_scene._start_phrase()
		# a representative loadout: one target + one support per rarity
		var ids := ["mono", "neonsign", "glowstick", "mirror"]   # neonsign -> the bonus beat shows
		for i in range(4):
			var j = Joker.by_id(ids[i])
			_scene.run.joker_slots[i] = j
			_scene.joker_views[i].set_joker(j)
		_scene._settle()
		_fired = true
		_t0 = 0.0
		return false
	if _fired:
		_t0 += delta
		if _idx == 3:
			# force the keys live so the active button texture is visible
			_scene.hand.discard_key.active = true
			_scene.hand.discard_key.fee = 2
			_scene.hand.discard_key.queue_redraw()
		if _idx < _shots.size() and _t0 >= float(_shots[_idx]["at"]):
			Shot.save(self, String(_shots[_idx]["name"]))
			_idx += 1
		if _idx >= _shots.size():
			quit()
	return false
