extends RefCounted

# --- Mid-section shop (2026-08-06: 商店与盲注解耦) ---
# The break fires INSIDE a blind: score keeps accumulating and no clear/fail
# verdict is rendered, which is what lets the player buy against a KNOWN
# deficit instead of betting on an unseen blind.
func run(t) -> void:
	var r := Run.new()
	r.reset(7)
	r.section_score = 10
	var breaks := 0
	var dones := 0
	for i in range(GameConfig.PHRASES_PER_SECTION):
		var out := r.advance()
		if bool(out["shop_break"]):
			breaks += 1
			t.check(not bool(out["section_done"]), "a break never closes the section")
			t.eq(r.phrase_in_section, GameConfig.PHRASES_PER_SHOP,
				"the break lands on the shop beat")
			t.eq(r.section_score, 10, "a break does NOT reset the score")
		if bool(out["section_done"]):
			dones += 1
			t.check(not bool(out["shop_break"]), "the last beat is a section end, not a break")
	t.eq(breaks, GameConfig.SHOPS_PER_SECTION - 1, "one mid-section break per section")
	t.eq(dones, 1, "exactly one section end")
	# the readouts the mid-section shop board is built on
	r.reset(7)
	t.eq(r.phrases_left(), GameConfig.PHRASES_PER_SECTION, "all phrases left at section start")
	r.advance()
	r.advance()
	r.advance()
	t.eq(r.phrases_left(), GameConfig.PHRASES_PER_SECTION - GameConfig.PHRASES_PER_SHOP,
		"phrases_left counts down to the section end")
	r.section_score = 0
	t.eq(r.deficit(), r.target(), "full deficit at zero score")
	r.section_score = r.target() + 5
	t.eq(r.deficit(), 0, "deficit floors at zero once the target is met")
