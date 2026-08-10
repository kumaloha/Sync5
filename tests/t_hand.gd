extends RefCounted

# --- Hand input: tap vs drag are DIFFERENT gestures (2026-08-06 用户) ---
# 「点到手牌区的卡和缓存区的卡就直接交换了, 但我有时候只是想同时对他们弃牌」。
# Contract: tap = select only (across both zones, for a batch discard);
# drag = swap. A tap must never swap, or cross-zone multi-select is unreachable.
func run(t) -> void:
	var h := Hand.new()
	t.get_root().add_child(h)
	h._decide = true
	var swaps: Array = []
	h.swap_requested.connect(func(a, b): swaps.append([a, b]))

	h._on_hand_tap(2)
	h._on_cache_card_tap(1)
	t.check(h.sel_hand == [2], "tapping a hand card selects it")
	t.check(h.sel_cache == [1], "tapping a cache card selects it too")
	t.eq(h.selection_total(), 2, "selection spans both zones")
	t.eq(swaps.size(), 0, "taps NEVER swap — that shortcut ate the second tap")

	h._on_hand_tap(2)
	t.check(h.sel_hand.is_empty(), "tapping again deselects")

	# drag is the swap gesture (CLAUDE.md:「拖拽 = 两张对调」)
	h.clear_selection()
	h._on_cache_drop({"zone": "hand", "index": 3}, 0)
	t.eq(swaps.size(), 1, "dropping a hand card on a cache slot swaps")
	t.check(swaps[0] == [3, 0], "swap carries (hand_i, cache_i)")
	h._on_hand_drop({"zone": "cache", "index": 2}, 4)
	t.eq(swaps.size(), 2, "dropping a cache card on a hand card swaps")
	t.check(swaps[1] == [4, 2], "reverse drop keeps the same argument order")
	h._on_hand_drop({"zone": "bogus", "index": 0}, 1)
	t.eq(swaps.size(), 2, "a drop from an unknown zone is ignored")
	h._can_swap = false
	h._on_cache_drop({"zone": "hand", "index": 1}, 0)
	t.eq(swaps.size(), 2, "a closed Blind swap gate blocks drag intent in the view")
	h._can_swap = true
	var drop_key := Widgets.DJKey.new()
	drop_key.accept_drop = true
	t.check(not drop_key._can_drop_data(Vector2.ZERO,
		{"zone": "hand", "discard_blocked": true}),
		"a sealed card cannot bypass its marker by being dragged onto discard")

	# selection must survive a swap-free tap sequence but clear on a real swap
	h.clear_selection()
	h._on_hand_tap(0)
	h._on_cache_drop({"zone": "hand", "index": 0}, 2)
	t.check(h.sel_hand.is_empty() and h.sel_cache.is_empty(), "a swap clears the selection")
	h.queue_free()

	# 档位色 = 四档递进(2026-08-06 用户拍板, CLAUDE.md 美术方向已锁定):
	# 蓝 → 橙 → 红 → 粉, 逐档升温。曾被改成全轮统一品红并配了断言, 2026-08-10 还原。
	var tier_ramp := [StageTheme.BLUE, StageTheme.AMBER, StageTheme.RED, StageTheme.PINK]
	for section in range(GameConfig.SECTIONS_PER_RUN):
		t.eq(Widgets.StageCard.accent_for(section), tier_ramp[section],
			"Blind section %d keeps the locked tier color ramp" % (section + 1))
	t.eq(Widgets.StageCard.boon_accent(), StageTheme.GOLD,
		"the positive finale surprise keeps a separate gold identity")

	var blind_card := Widgets.BlindCard.new()
	var rush := SectionMod.by_id("rush")
	var boon := BlindBoon.by_id("doubleset")
	blind_card.setup(3, rush, null, boon)
	t.eq(blind_card.boon, boon, "the current round-four card receives the revealed boon")
	blind_card.set_status("点歌 · 红黑同台")
	t.eq(blind_card.status_text, "点歌 · 红黑同台",
		"the in-run Blind card receives the active public request")
