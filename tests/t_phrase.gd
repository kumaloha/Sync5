extends RefCounted

# --- Phrase (discard-refill rules) ---
func run(t) -> void:
	var d := Deck.new(42)
	var cache: Array = []
	var p := Phrase.new(d, cache, GameConfig.STARTING_COINS)
	p.start()
	t.eq(p.hand.size(), 5, "phrase deals 5 cards")
	t.eq(cache.size(), GameConfig.CACHE_CAP, "cache is dealt FULL at start")
	t.eq(p.coins, 6, "starts with 6 coins")

	# discard 2 from hand: pay 2, refill in place immediately
	var kept0: Card = p.hand[0]
	var old1: Card = p.hand[1]
	var old3: Card = p.hand[3]
	t.check(p.discard_selected([1, 3]), "discard two hand cards")
	t.eq(p.coins, 6 - GameConfig.DISCARD_COST * 2, "discarding charges the configured price (now free)")
	t.eq(p.hand.size(), 5, "hand refilled to exactly 5")
	t.check(p.hand[0] == kept0, "untouched card stays in place")
	t.check(p.hand[1] != old1 and p.hand[3] != old3, "discarded slots hold new cards")
	t.eq(p.discards_used, 2, "discards_used tracks count")
	t.check(d.discard_pile.size() >= 2, "old cards reached the discard pile")

	# invalid index leaves state untouched
	var coins_before := p.coins
	t.check(not p.discard_selected([99]), "invalid hand index rejected")
	t.eq(p.coins, coins_before, "no charge on rejected discard")

	# swap hand <-> cache is free (drag = swap; cache is always full)
	var h4: Card = p.hand[4]
	var c0: Card = cache[0]
	t.check(p.swap_with_cache(4, 0), "swap works")
	t.check(p.hand[4] == c0 and cache[0] == h4, "swap exchanged the cards")
	t.eq(p.coins, coins_before, "swap is free")
	t.eq(cache.size(), GameConfig.CACHE_CAP, "cache stays full after swap")

	# discard from cache rerolls that slot
	var old_c1: Card = cache[1]
	t.check(p.discard_selected([], [1]), "discard a cache card")
	t.check(cache[1] != old_c1, "cache slot rerolled")
	t.eq(cache.size(), GameConfig.CACHE_CAP, "cache size unchanged by reroll")

	# sort_hand orders by rank desc
	p.sort_hand()
	var sorted_ok := true
	for i in range(1, p.hand.size()):
		if p.hand[i - 1].rank < p.hand[i].rank:
			sorted_ok = false
	t.check(sorted_ok, "sort_hand orders rank descending")

	# lock settles and blocks all actions
	var res := p.lock_and_settle()
	t.check(not res.is_empty(), "settlement produced a result")
	t.check(p.locked, "phrase is locked")
	t.check(not p.discard_selected([0]), "no discard after lock")
	t.check(not p.swap_with_cache(0, 0), "no swap after lock")

	# cleanup keeps the cache full
	p.cleanup()
	t.eq(p.hand.size(), 0, "cleanup empties hand")
	t.eq(cache.size(), GameConfig.CACHE_CAP, "cache persists across phrases")

	# next phrase with an existing full cache does not overfill it
	var p_next := Phrase.new(d, cache, p.coins)
	p_next.start()
	t.eq(cache.size(), GameConfig.CACHE_CAP, "existing cache is not overfilled")

	# --- 2026-08-07 脸批次:改「输入」的两张(design/research_balatro_bosses) ---
	# lostpage/freshsheet: evict at phrase END, refill at next start. The point
	# is that the cache CONTENT turns over — it is never left short.
	var ed := Deck.new(99)
	ed.shuffle()
	var ecache: Array = []
	var e1 := Phrase.new(ed, ecache, 0)
	e1.mod = "lostpage"
	e1.start()
	t.eq(ecache.size(), GameConfig.CACHE_CAP, "lostpage still deals a full cache")
	var before: Array = ecache.duplicate()
	e1.cleanup()
	t.eq(ecache.size(), GameConfig.CACHE_CAP - 1, "lostpage evicts one at phrase end")
	var kept := 0
	for c in ecache:
		if before.has(c):
			kept += 1
	t.eq(kept, GameConfig.CACHE_CAP - 1, "lostpage evicts exactly one, keeps the rest")
	var e2 := Phrase.new(ed, ecache, 0)
	e2.mod = "lostpage"
	e2.start()
	t.eq(ecache.size(), GameConfig.CACHE_CAP, "the next phrase tops the cache back up")

	var w1 := Phrase.new(ed, ecache, 0)
	w1.mod = "freshsheet"
	w1.start()
	var wbefore: Array = ecache.duplicate()
	w1.cleanup()
	t.eq(ecache.size(), 0, "freshsheet wipes the whole cache")
	var w2 := Phrase.new(ed, ecache, 0)
	w2.mod = "freshsheet"
	w2.start()
	t.eq(ecache.size(), GameConfig.CACHE_CAP, "and the next phrase deals a fresh one")
	var carried := 0
	for c in ecache:
		if wbefore.has(c):
			carried += 1
	t.eq(carried, 0, "freshsheet carries nothing across the phrase boundary")

	# smallstage: shrinks the choice set itself. ⚠ The trim must run BEFORE the
	# top-up, so entering the section holding a full cache still drops to 2 —
	# that is the case a naive `while size < cap` would silently miss.
	var scache: Array = []
	var s0 := Phrase.new(ed, scache, 0)
	s0.start()
	t.eq(scache.size(), GameConfig.CACHE_CAP, "a normal phrase carries a full cache in")
	var s1 := Phrase.new(ed, scache, 0)
	s1.mod = "smallstage"
	s1.start()
	t.eq(scache.size(), GameConfig.CACHE_CAP - 1, "smallstage trims a carried-over cache")
	t.eq(s1.hand.size() + scache.size(), GameConfig.HAND_SIZE + GameConfig.CACHE_CAP - 1,
		"so the solver sees 7 visible cards, not 8")
	# and it releases when the face is gone
	var s2 := Phrase.new(ed, scache, 0)
	s2.start()
	t.eq(scache.size(), GameConfig.CACHE_CAP, "the cache refills once the face is over")

	# --- 信息隐藏族:盖牌拿走视野, 不拿走价值 ---
	var hd := Deck.new(2027)
	hd.shuffle()
	var hcache: Array = []
	var f1 := Phrase.new(hd, hcache, 0)
	f1.mod = "facedown"
	f1.start()
	var want_hidden := 0
	for c in f1.hand:
		if c.rank >= 11 and c.rank <= 13:
			want_hidden += 1
	for c in hcache:
		if c.rank >= 11 and c.rank <= 13:
			want_hidden += 1
	t.eq(f1.hidden.size(), want_hidden, "facedown hides exactly the J/Q/K on the table")
	for c in f1.hidden:
		t.check(c.rank >= 11 and c.rank <= 13, "nothing but a face card is hidden")
	# ⚠ 计分完全不变 —— 盖牌是信息剥夺, 不是数值惩罚
	var open_res := Pattern.evaluate_best(f1.hand, hd.rules)
	t.eq(int(f1.lock_and_settle()["score"]), int(open_res["score"]),
		"a hidden card scores exactly as if it were face up")
	t.eq(f1.hidden.size(), 0, "settling turns everything face up (用户 2026-08-07 拍板)")

	# hidden_indices 必须跟着牌走, 不跟着下标走 —— 理牌会重排, 弃牌会原位换人
	var f2 := Phrase.new(hd, hcache, 0)
	f2.mod = "facedown"
	f2.start()
	if not f2.hidden.is_empty():
		var vis_f: Array = []
		vis_f.append_array(f2.hand)
		vis_f.append_array(hcache)
		var idx_before := f2.hidden_indices(vis_f)
		f2.sort_hand()
		var vis_after: Array = []
		vis_after.append_array(f2.hand)
		vis_after.append_array(hcache)
		var idx_after := f2.hidden_indices(vis_after)
		t.eq(idx_after.size(), idx_before.size(), "sorting does not change HOW MANY are hidden")
		var still_faces := true
		for i in idx_after:
			var cc: Card = vis_after[i]
			if cc.rank < 11 or cc.rank > 13:
				still_faces = false
		t.check(still_faces, "hidden tracks the CARD through a sort, not the index")

	# blindspot: 弃掉的牌离开 hidden, 补进来的牌加入 hidden
	var bcache: Array = []
	var b1 := Phrase.new(hd, bcache, 99)
	b1.mod = "blindspot"
	b1.start()
	t.eq(b1.hidden.size(), 0, "blindspot hides nothing on the deal")
	var old0: Card = b1.hand[0]
	t.check(b1.discard_selected([0]), "discard goes through")
	t.eq(b1.hidden.size(), 1, "the refill comes back face down")
	t.check(b1.hidden.has(b1.hand[0]), "and it is the card that just arrived")
	t.check(not b1.hidden.has(old0), "the discarded card left the hidden set")

	# 身无分文时:弃牌**不再**被挡(2026-08-06 弃牌免费), 交换一直免费。
	# 这条正是这次改动要买到的东西 —— 打崩了也还能重抽, 赌得起。
	var d2 := Deck.new(1)
	var cache2: Array = []
	var p2 := Phrase.new(d2, cache2, 0)
	p2.start()
	t.eq(cache2.size(), GameConfig.CACHE_CAP, "fresh run deals cache full")
	t.check(p2.can_discard(1), "broke players can still discard — the clock is the only gate")
	t.check(p2.swap_with_cache(0, 0), "swap still free at zero coins")
	t.check(not p2.can_discard(0), "an empty selection is still rejected")
