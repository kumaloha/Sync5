extends RefCounted

# --- Phrase (discard-refill rules) ---
func run(t) -> void:
	var d := Deck.new(42)
	var cache: Array = []
	var p := Phrase.new(d, cache, GameConfig.STARTING_COINS)
	p.start()
	t.eq(p.hand.size(), 5, "phrase deals 5 cards")
	t.eq(cache.size(), GameConfig.CACHE_CAP, "cache is dealt FULL at start")
	t.eq(p.coins, 8, "starts with 8 coins(2026-08-30 收入重构:用户「钱宽松的本质是现在获取太容易」——判据换成「一局能买几张卡」(原作 2~3 张, 我们改前 25 张))")

	# discard 2 from hand: pay 2, refill in place immediately
	var kept0: Card = p.hand[0]
	var old1: Card = p.hand[1]
	var old3: Card = p.hand[3]
	t.check(p.discard_selected([1, 3]), "discard two hand cards")
	t.eq(p.coins, 8 - GameConfig.DISCARD_COST * 2, "discarding charges 1◆/张(经济 v2 推翻弃牌免费)")
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

	# --- 2026-08-07 脸批次:改「输入」的两张(docs/design/research_balatro_bosses) ---
	# lostpage/freshsheet: evict at phrase END, refill at next start. The point
	# is that the cache CONTENT turns over — it is never left short.
	var ed := Deck.new(99)
	ed.shuffle()
	var ecache: Array = []
	var e1 := Phrase.new(ed, ecache, 50)
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
	var e2 := Phrase.new(ed, ecache, 50)
	e2.mod = "lostpage"
	e2.start()
	t.eq(ecache.size(), GameConfig.CACHE_CAP, "the next phrase tops the cache back up")

	var w1 := Phrase.new(ed, ecache, 50)
	w1.mod = "freshsheet"
	w1.start()
	var wbefore: Array = ecache.duplicate()
	w1.cleanup()
	t.eq(ecache.size(), 0, "freshsheet wipes the whole cache")
	var w2 := Phrase.new(ed, ecache, 50)
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
	var s0 := Phrase.new(ed, scache, 50)
	s0.start()
	t.eq(scache.size(), GameConfig.CACHE_CAP, "a normal phrase carries a full cache in")
	var s1 := Phrase.new(ed, scache, 50)
	s1.mod = "smallstage"
	s1.start()
	t.eq(scache.size(), GameConfig.CACHE_CAP - 1, "smallstage trims a carried-over cache")
	t.eq(s1.hand.size() + scache.size(), GameConfig.HAND_SIZE + GameConfig.CACHE_CAP - 1,
		"so the solver sees 7 visible cards, not 8")
	# and it releases when the face is gone
	var s2 := Phrase.new(ed, scache, 50)
	s2.start()
	t.eq(scache.size(), GameConfig.CACHE_CAP, "the cache refills once the face is over")

	# --- 信息隐藏族:盖牌拿走视野, 不拿走价值 ---
	var hd := Deck.new(2027)
	hd.shuffle()
	var hcache: Array = []
	var f1 := Phrase.new(hd, hcache, 50)
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
	var f2 := Phrase.new(hd, hcache, 50)
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

	# 经济 v2(2026-08-26 推翻 08-06 弃牌免费):身无分文时弃牌**重新被挡**,
	# 交换仍然免费 —— 出牌永远免费所以无硬死锁, 软破产由收支曲线管(levels.md 经济 v2)。
	var d2 := Deck.new(1)
	var cache2: Array = []
	var p2 := Phrase.new(d2, cache2, 0)
	p2.start()
	t.eq(cache2.size(), GameConfig.CACHE_CAP, "fresh run deals cache full")
	t.check(not p2.can_discard(1), "broke players cannot discard(1◆/张, 经济 v2)")
	t.check(p2.swap_with_cache(0, 0), "swap still free at zero coins")
	t.check(not p2.can_discard(0), "an empty selection is still rejected")

	# --- 第一轮:一口气按张数限(2026-08-25 重铸:「弃牌不在次数, 在张数」) ---
	var one_take := Phrase.new(Deck.new(301), [], 50)
	one_take.mod = "onetake"
	one_take.start()
	t.check(one_take.discard_selected([0, 1]), "onetake permits two cards in one batch")
	t.check(not one_take.discard_selected([2]), "onetake rejects the third card")

	var one_swap := Phrase.new(Deck.new(302), [], 50)
	one_swap.mod = "oneswap"
	one_swap.start()
	t.check(one_swap.swap_with_cache(0, 0), "oneswap permits the first swap")
	t.check(not one_swap.swap_with_cache(1, 1), "oneswap rejects the second swap")

	# --- 第二/三轮:限流按弃换合计张数限(2026-08-25 重铸), 换一次记一张 ---
	var throttle := Phrase.new(Deck.new(303), [], 50)
	throttle.mod = "throttle"
	throttle.start()
	t.check(throttle.swap_with_cache(0, 0), "throttle card one (swap)")
	t.check(throttle.discard_selected([1, 2]), "throttle cards two and three (batch discard)")
	t.check(throttle.swap_with_cache(3, 1), "throttle card four (swap)")
	t.check(not throttle.discard_selected([4]), "throttle rejects the fifth card via discard")
	t.check(not throttle.swap_with_cache(0, 2), "throttle rejects the fifth card via swap")

	var discard_track := Phrase.new(Deck.new(304), [], 50)
	discard_track.mod = "switchtrack"
	discard_track.start()
	t.check(discard_track.discard_selected([0]), "switchtrack can choose discard first")
	t.check(not discard_track.swap_with_cache(1, 0), "discard first closes the swap track")
	var swap_track := Phrase.new(Deck.new(305), [], 50)
	swap_track.mod = "switchtrack"
	swap_track.start()
	t.check(swap_track.swap_with_cache(0, 0), "switchtrack can choose swap first")
	t.check(not swap_track.discard_selected([1]), "swap first closes the discard track")

	# redlight blocks only a red card entering cache.
	var red_cache: Array = [t._c(3, 0), t._c(4, 0), t._c(5, 0)]
	var redlight := Phrase.new(Deck.new(306), red_cache, 50)
	redlight.mod = "redlight"
	redlight.start()
	redlight.hand = [t._c(8, 1), t._c(8, 0), t._c(9, 0), t._c(10, 0), t._c(11, 0)]
	t.check(not redlight.swap_with_cache(0, 0), "a red hand card cannot enter cache")
	t.check(redlight.swap_with_cache(1, 0), "a black hand card can still enter cache")

	# wetink locks the newly cached object for the rest of this phrase, then releases.
	var ink_cache: Array = []
	var wet := Phrase.new(Deck.new(307), ink_cache, 50)
	wet.mod = "wetink"
	wet.start()
	t.check(wet.swap_with_cache(0, 0), "wetink accepts the initial swap")
	var inked: Card = ink_cache[0]
	t.check(not wet.swap_with_cache(1, 0), "the newly cached card cannot move again this phrase")
	var wet_next := Phrase.new(wet.deck, ink_cache, 50)
	wet_next.mod = "wetink"
	wet_next.start()
	t.check(wet_next.swap_with_cache(0, ink_cache.find(inked)), "wetink releases on the next phrase")

	# handseal and doubleseal pin object identities chosen at phrase start.
	var sealed := Phrase.new(Deck.new(308), [], 50)
	sealed.mod = "handseal"
	sealed.start()
	var sealed_i := sealed.hand.find(sealed.sealed_hand_card)
	t.check(sealed_i >= 0, "handseal marks one opening hand card")
	t.check(not sealed.can_discard_selected([sealed_i], []),
		"selection-aware validation rejects the sealed card before feedback")
	t.check(not sealed.discard_selected([sealed_i]), "the marked hand card cannot be discarded")
	var free_i := 0 if sealed_i != 0 else 1
	t.check(sealed.discard_selected([free_i]), "another hand card remains discardable")
	var moved_seal := Phrase.new(Deck.new(1308), [], 50)
	moved_seal.mod = "handseal"
	moved_seal.start()
	var moved_card: Card = moved_seal.sealed_hand_card
	var moved_i := moved_seal.hand.find(moved_card)
	t.check(moved_seal.swap_with_cache(moved_i, 0),
		"the sealed card may still be routed through cache")
	t.check(not moved_seal.can_discard_selected([], [0]),
		"the same sealed object stays non-discardable after moving to cache")
	t.check(moved_seal.discard_blocked_cache().has(moved_card),
		"the cache view can keep marking a moved hand seal")

	var shared_meta := {"ages": {}, "next": 0}
	var double_seal := Phrase.new(Deck.new(309), [], 50)
	double_seal.cache_meta = shared_meta
	double_seal.mod = "doubleseal"
	double_seal.start()
	var oldest_i := double_seal.cache.find(double_seal.sealed_cache_card)
	t.check(oldest_i >= 0, "doubleseal marks the oldest cache object")
	t.check(not double_seal.swap_with_cache(0, oldest_i), "the oldest cache object cannot swap")
	t.check(double_seal.swap_blocked_cache().has(double_seal.sealed_cache_card),
		"the view model can mark the sealed cache object before a drag")

	# lowend searches the available deck for a 2..9 refill without consuming high cards.
	var low_deck := Deck.new(310)
	var lowend := Phrase.new(low_deck, [], 50)
	lowend.mod = "lowend"
	lowend.start()
	low_deck.draw_pile = [t._c(5, 0), t._c(13, 0)]
	t.check(lowend.discard_selected([0]), "lowend discard succeeds")
	t.eq(lowend.hand[0].rank, 5, "lowend refill is within 2..9")
	t.eq(low_deck.draw_pile[-1].rank, 13, "an ineligible high card stays in the deck")
	# If only high cards remain in the draw pile, eligible discarded lows must be
	# recycled instead of returning null into the live hand.
	var recycle_deck := Deck.new(1310)
	var recycle_low: Card = t._c(6, 1)
	recycle_deck.draw_pile = [t._c(12, 0), t._c(14, 1)]
	recycle_deck.discard_pile = [recycle_low]
	t.eq(recycle_deck.draw_rank_range(2, 9), recycle_low,
		"lowend recycles eligible discards when the live draw pile has only highs")
	t.check(recycle_deck.draw_pile.all(func(c): return c != null),
		"rank-filtered draw never injects a null card")

	# lostpage chooses the victim before the decision window and removes exactly
	# that object at cleanup; moving/discarding it consumes the mark, not a second card.
	var page_cache: Array = []
	var lost_page := Phrase.new(Deck.new(1311), page_cache, 50)
	lost_page.mod = "lostpage"
	lost_page.start()
	var marked_page: Card = lost_page.marked_cache_card
	t.check(marked_page != null and page_cache.has(marked_page),
		"lostpage exposes one marked cache victim at phrase start")
	lost_page.cleanup()
	t.check(not page_cache.has(marked_page), "lostpage removes the preannounced cache object")

	# ration is a card budget, not an action budget.
	var ration := Phrase.new(Deck.new(311), [], 50)
	ration.mod = "ration"
	ration.discard_budget = 2
	ration.start()
	t.check(ration.discard_selected([0, 1]), "ration can spend the remaining two cards at once")
	t.check(not ration.discard_selected([2]), "ration rejects cards beyond the shared remainder")

	# request goals are evaluated against the final hand and the phrase-start cache snapshot.
	var request := Phrase.new(Deck.new(312), [], 50)
	request.mod = "request"
	request.start()
	request.request_goal = "color_mix"
	request.hand = [t._c(2, 1), t._c(3, 0), t._c(5, 0), t._c(7, 0), t._c(9, 0)]
	request.lock_and_settle()
	t.check(request.request_met, "request accepts a final hand containing red and black")
	var invalid_request := Phrase.new(Deck.new(1312), [], 50)
	invalid_request.mod = "request"
	invalid_request.start()
	invalid_request.hand = [t._c(2, 0), t._c(3, 0), t._c(4, 0), t._c(5, 0), t._c(6, 0)]
	invalid_request.cache = [t._c(7, 0), t._c(8, 0), t._c(9, 0)]
	t.check(not invalid_request.request_goal_valid("color_mix"),
		"request validity rejects a color goal with no visible red route")
	t.check(not invalid_request.request_goal_valid("face_or_ace"),
		"request validity rejects a face goal with no visible J/Q/K/A route")
	var miss_request := Phrase.new(Deck.new(313), [], 50)
	miss_request.mod = "request"
	miss_request.start()
	miss_request.request_goal = "face_or_ace"
	miss_request.hand = [t._c(2, 0), t._c(3, 0), t._c(5, 0), t._c(7, 0), t._c(9, 0)]
	miss_request.lock_and_settle()
	t.check(not miss_request.request_met, "request records a missed public goal")
	var cache_request := Phrase.new(Deck.new(314), [], 50)
	cache_request.mod = "request"
	cache_request.start()
	cache_request.request_goal = "initial_cache"
	cache_request.hand[0] = cache_request.initial_cache[0]
	cache_request.lock_and_settle()
	t.check(cache_request.request_met, "request tracks initial cache cards by object identity")

	# Spotlight adds a scoring-only sixth card; the interactive hand remains five.
	var spot := Phrase.new(Deck.new(315), [], 50)
	spot.boon = "spotlight"
	spot.start()
	t.eq(spot.hand.size(), GameConfig.HAND_SIZE, "Spotlight does not add an action slot")
	t.check(spot.spotlight_card != null, "Spotlight deals one separate card")
	var six_cards: Array = spot.hand.duplicate()
	six_cards.append(spot.spotlight_card)
	t.eq(spot.current_best()["score"], Pattern.evaluate_best(six_cards, spot.deck.rules)["score"],
		"Spotlight scores the best five of six")

	# Encore clones the first discarded hand object into scoring without keeping
	# a second live reference to a card that already returned to the deck.
	var encore_phrase := Phrase.new(Deck.new(316), [], 50)
	encore_phrase.boon = "encore"
	encore_phrase.start()
	encore_phrase.hand = [t._c(10, 0), t._c(2, 0), t._c(4, 1), t._c(6, 2), t._c(8, 3)]
	encore_phrase.deck.draw_pile = [t._c(3, 1)]
	var discarded_ten: Card = encore_phrase.hand[0]
	var discarded_two: Card = encore_phrase.hand[1]
	t.check(encore_phrase.discard_selected([0, 1]), "Encore batch discard still follows the normal action")
	t.eq(encore_phrase.ghost_cards.size(), 2, "Encore returns the whole first discarded hand batch")
	t.check(encore_phrase.ghost_cards[0] != discarded_ten, "Encore uses detached ghost objects")
	t.eq(encore_phrase.ghost_cards[0].label(), discarded_ten.label(), "the first ghost preserves rank and suit")
	t.eq(encore_phrase.ghost_cards[1].label(), discarded_two.label(), "the second ghost preserves rank and suit")
	var without_ghost := Pattern.evaluate_best(encore_phrase.hand, encore_phrase.deck.rules)
	var with_ghost := encore_phrase.lock_and_settle()
	t.check(int(with_ghost["score"]) > int(without_ghost["score"]),
		"the ghost participates in best-five scoring")

	# ---- 动作内容记账(2026-08-13 引擎波次·子波1:断舍离/让位/串场的信号源)----
	# 这三个量在 core/phrase.gd 里数, 由 core/beat.gd 拼进 ctx —— 拼装只此一处。
	var act := Phrase.new(Deck.new(4242), [], 99)
	act.start()
	t.eq(act.discard_batch_max, 0, "a fresh phrase has no discard batch")
	t.eq(act.faces_discarded, 0, "and no discarded faces")
	# 手牌塞成已知内容:两张人头 + 三张小牌, 一次弃三张
	act.hand[0] = t._c(13, 0)
	act.hand[1] = t._c(12, 1)
	act.hand[2] = t._c(3, 2)
	act.deck.draw_pile = [t._c(5, 0), t._c(6, 1), t._c(7, 2), t._c(8, 3)]
	t.check(act.discard_selected([0, 1, 2]), "batch discard lands")
	t.eq(act.discard_batch_max, 3, "batch peak records the biggest single batch")
	t.eq(act.faces_discarded, 2, "two face cards left the hand")
	t.check(act.discard_selected([0]), "a later single discard still works")
	t.eq(act.discard_batch_max, 3, "batch peak is a MAX, not the latest batch")
	# 串场:换入的牌参与成牌才算 —— 而 bot 的「试探换回」不许留下痕迹
	var sw := Phrase.new(Deck.new(4243), [], 99)
	sw.cache = [t._c(9, 0), t._c(9, 1), t._c(9, 2)]
	sw.start()
	var original: Card = sw.hand[0]
	t.check(sw.swap_with_cache(0, 0), "swap in a cache card")
	var brought_in: Card = sw.hand[0]
	t.eq(sw.swapped_scoring_count([brought_in]), 1, "a swapped-in scoring card counts")
	t.eq(sw.swapped_scoring_count([original]), 0, "the card it replaced does not")
	t.check(sw.swap_with_cache(0, 0), "swap it straight back (bot probes do this)")
	t.eq(sw.swapped_scoring_count([original]), 0,
		"a swap-and-revert leaves no phantom credit —— 试探不算换入")


	# ⚠ 洗牌那一节已随机制退役删除(2026-09-01 用户拍板:「万能牌只需要在弃牌的时候
	# 有几率洗出来就行, 不用专门一个洗牌按钮」)。⚑ **牌堆自己的「抽干了洗回弃牌堆」没退役**
	# —— 那正是万能牌循环出来所依赖的机制, 它的契约在 tests/t_deck.gd。
	# 这里补一条替代契约:注入的万能牌必须真的能被抽到。
	var rd := Deck.new(88)
	rd.add_wilds("superwild", 4)
	var seen_wild := false
	for _i in range(60):
		var c3 := rd.draw()
		if c3 != null and c3.is_wild():
			seen_wild = true
			break
	t.check(seen_wild, "注入的万能牌能在正常抽牌里出现(弃牌补牌就是这条路径)")
