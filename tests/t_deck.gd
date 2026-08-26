extends RefCounted

# --- Deck ---
func run(t) -> void:
	var d := Deck.new(123)
	t.eq(d.total(), 52, "deck has 52 cards")
	# 52 unique cards
	var seen := {}
	while d.remaining() > 0:
		var c := d.draw()
		seen[c.label()] = true
	t.eq(seen.size(), 52, "all 52 cards unique")

	# seeded shuffle is deterministic
	var a := Deck.new(777)
	var b := Deck.new(777)
	t.eq(a.draw().label(), b.draw().label(), "same seed -> same first draw")

	# discard reshuffle: draw all, discard all, next draw works
	var e := Deck.new(5)
	var pulled: Array = []
	while e.remaining() > 0:
		pulled.append(e.draw())
	for c in pulled:
		e.discard(c)
	t.check(e.draw() != null, "reshuffle from discard yields a card")

	# 大小王 are OFF by default and only appear once a joker enables them
	var nw := Deck.new(3)
	t.eq(nw.total(), 52, "no wilds in the default deck")
	nw.enable_wilds()
	t.eq(nw.total(), 54, "enable_wilds adds 大王 + 小王")
	var wilds := 0
	while nw.remaining() > 0:
		var c := nw.draw()
		if c.is_wild():
			wilds += 1
	t.eq(wilds, 2, "exactly two wild cards")
	var big := Card.new(Card.JOKER_RANK, Card.JOKER_BIG)
	t.check(big.is_wild() and big.is_big_joker(), "big joker flags")

	# trim(修剪, 2026-08-12 流派批):2/3 永久离开牌库 —— 减牌手术, enable_wilds 的镜像。
	# 手/缓存里已握的 2/3 不当场没收, 弃掉时经 discard() 过滤离场(玩家看得见的牌不凭空消失)。
	var tr := Deck.new(9)
	tr.trim_low_ranks()
	t.eq(tr.total(), 44, "trim removes the eight 2s and 3s")
	var lows := 0
	while tr.remaining() > 0:
		if tr.draw().rank <= Deck.TRIM_RANK_MAX:
			lows += 1
	t.eq(lows, 0, "no 2/3 left to draw after trim")
	tr.discard(Card.new(2, 0))
	t.eq(tr.total(), 0, "a held 2 discarded after trim leaves play for good")
	tr.discard(Card.new(7, 0))
	t.eq(tr.total(), 1, "other ranks still recycle through the discard pile")
	var trf := Deck.new(11)
	trf.trim_low_ranks()
	t.check(trf.fork(1).trim_low, "fork carries the trim flag (solver sees the surgery)")
	var td := Deck.new(13)
	Joker.by_id("trim").on_acquire(td)
	t.eq(td.total(), 44, "trim joker on_acquire performs the surgery")
	t.eq(big.rank_label(), "★", "big joker glyph")
	t.eq(Card.new(Card.JOKER_RANK, Card.JOKER_LITTLE).rank_label(), "☆", "little joker glyph")

	# add_wilds(2026-08-26 超级百搭):按来源注入 JOKER, 同来源幂等, snapshot 往返。
	var aw := Deck.new(21)
	aw.add_wilds("superwild", 4)
	t.eq(aw.total(), 56, "add_wilds injects 4 JOKERs")
	aw.add_wilds("superwild", 4)
	t.eq(aw.total(), 56, "same source twice = once(买新替旧再买回不许翻倍)")
	aw.enable_wilds()
	t.eq(aw.total(), 58, "大小王与注入独立叠加(共存拍板前的缺省)")
	var aws := Deck.from_snapshot(aw.snapshot())
	t.eq(aws.total(), 58, "snapshot round-trip keeps injected wilds")
	t.check(aws.wild_extra.has("superwild"), "snapshot round-trip keeps the source ledger")
	var awf := aw.fork(7)
	t.check(awf.wild_extra.has("superwild"), "fork carries the ledger(求解器推演同世界)")
	var sj := Joker.by_id("superwild")
	var ad := Deck.new(22)
	sj.on_acquire(ad)
	t.eq(ad.total(), 56, "superwild on_acquire injects via acquire.wilds=4")
	sj.on_acquire(ad)
	t.eq(ad.total(), 56, "on_acquire twice = once(deck 侧来源记账挡)")
