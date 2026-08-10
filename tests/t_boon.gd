extends RefCounted


func run(t) -> void:
	t.check(FileAccess.file_exists("res://data/boons.json"),
		"finale boons live in their own data table")
	var boon_script = load("res://core/blind_boon.gd")
	t.check(boon_script != null, "BlindBoon has a focused data facade")
	if boon_script == null:
		return
	var roster: Array = boon_script.roster()
	t.eq(roster.size(), 4, "four finale boons are configured")
	var ids: Array = boon_script.ids()
	t.check(ids == ["doubleset", "spotlight", "afterglow", "encore"],
		"the approved four-boon roster is exact and ordered")
	for id in ids:
		t.check(boon_script.by_id(id) != null, "%s is addressable by id" % id)
	t.eq(boon_script.score_replay_factor("doubleset"), 0.5,
		"Double Set replays half the raw score")
	t.eq(boon_script.spotlight_cards("spotlight"), 1,
		"Spotlight adds one non-interactive card")
	t.eq(boon_script.previous_raw_factor("afterglow"), 0.1,
		"Afterglow adds ten percent of previous raw score")
	t.check(boon_script.ghost_first_discard("encore"),
		"Encore keeps the first discarded hand card as a ghost")
