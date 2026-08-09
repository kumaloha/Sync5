extends SceneTree

## Screenshot probe for the draft shop. Run NON-headless:
##   godot --path . --script res://tools/draft_sheet.gd
## Captures _shot_draft.png (section-end board, one card unaffordable at 5 ◆),
## _shot_draft_mid.png (**mid-section** board: 还差 N 分 · 还剩 N 拍 —— the
## 2026-08-06 decoupled shop) and _shot_draft_replace.png (full slots ->
## the incoming card pinned, drag-or-tap onto a slot).

var _scene: Node
var _frames := 0

func _initialize() -> void:
	_scene = Shot.stage(self)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 4:
		_scene.choose_character(1)
	elif _frames == 8:
		# the blind-intro card holds the clock (and phrase creation) until it
		# dismisses — skip it so the mid-run staging below has a phrase
		_scene.intro._dismiss()
	elif _frames == 30:
		# mid-run state: target + one support owned, 5 ◆ — uncommon/rare dim
		# out. Last section so the pivot window is open (a Target may appear);
		# must stay inside the table — Run.next_section() clamps, probes do not.
		_scene.run.section_idx = GameConfig.SECTIONS_PER_RUN - 1
		_set_slot(0, "mono")
		_set_slot(1, "turnover")
		_scene.phrase.coins = 5
		_scene.run.phrase_in_section = 0        # section-end board: 下一场 preview
		_scene._open_draft()
	elif _frames == 60:
		Shot.save(self, "draft")
	elif _frames == 63:
		# the decoupled mid-section shop: same shelf, but the board now reports
		# THIS blind's deficit and beats left instead of previewing the next
		_scene.shop.close()
		_scene.run.phrase_in_section = GameConfig.PHRASES_PER_SHOP
		_scene.run.section_score = 5200
		_scene._open_draft()
	elif _frames == 64:
		Shot.save(self, "draft_mid")
	elif _frames == 66:
		# full board, 7 ◆ -> tapping a candidate enters replace mode
		_scene.shop.close()
		_set_slot(1, "shortcut")     # batch-2 rule cards get eyeballed here
		_set_slot(2, "twotone")
		_set_slot(3, "fourfingers")
		_scene.phrase.coins = 7
		_scene.run.phrase_in_section = 0
		_scene._open_draft()
	elif _frames == 72:
		_scene.shop._on_pick(0)
	elif _frames == 100:
		Shot.save(self, "draft_replace")
		quit()
	return false

func _set_slot(i: int, id: String) -> void:
	var j = Joker.by_id(id)
	_scene.run.joker_slots[i] = j
	_scene.joker_views[i].set_joker(j)