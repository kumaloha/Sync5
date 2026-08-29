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

	# 万能牌唯一来源 = superwild 注入(2026-08-26 取代百搭;enable_wilds 已退役)
	var nw := Deck.new(3)
	t.eq(nw.total(), 52, "no wilds in the default deck")
	nw.add_wilds("superwild", 4)
	t.eq(nw.total(), 56, "superwild injects four JOKERs")
	var wilds := 0
	while nw.remaining() > 0:
		var c := nw.draw()
		if c.is_wild():
			wilds += 1
	t.eq(wilds, 4, "exactly four wild cards")
	var big := Card.new(Card.JOKER_RANK, Card.JOKER_BIG)
	t.check(big.is_wild() and big.is_big_joker(), "big joker flags(Card 层表示保留)")

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
	# ⚑ 修剪 2026-08-29 转生为消耗牌(移除 2/3 后卡本身没用了 = 一次性)。
	# 链路仍从**卡数据**取参数, 不硬编码 —— 断言测的是「卡声明的动作真的发生了」。
	var td := Deck.new(13)
	for _e in DB.consumables():
		if String(_e["id"]) == "trim":
			if Consumable.new(_e).action.get("trim_low", false):
				td.trim_low_ranks()
	t.eq(td.total(), 44, "修剪(消耗牌)的 action 真的做了手术")
	t.eq(big.rank_label(), "★", "big joker glyph")
	t.eq(Card.new(Card.JOKER_RANK, Card.JOKER_LITTLE).rank_label(), "☆", "little joker glyph")

	# add_wilds(2026-08-26 超级百搭):按来源注入 JOKER, 同来源幂等, snapshot 往返。
	var aw := Deck.new(21)
	aw.add_wilds("superwild", 4)
	t.eq(aw.total(), 56, "add_wilds injects 4 JOKERs")
	aw.add_wilds("superwild", 4)
	t.eq(aw.total(), 56, "same source twice = once(买新替旧再买回不许翻倍)")
	var aws := Deck.from_snapshot(aw.snapshot())
	t.eq(aws.total(), 56, "snapshot round-trip keeps injected wilds")
	t.check(aws.wild_extra.has("superwild"), "snapshot round-trip keeps the source ledger")
	var awf := aw.fork(7)
	t.check(awf.wild_extra.has("superwild"), "fork carries the ledger(求解器推演同世界)")
	# ⚑ 超级百搭转生为消耗牌后, 「按来源记账、注入不翻倍」这条契约仍由 Deck 守着 ——
	# 它本来就在 deck 侧, 与谁调用无关。用两次 add_wilds 直接测那条契约。
	var ad := Deck.new(22)
	ad.add_wilds("superwild", 4)
	t.eq(ad.total(), 56, "超级百搭注入四张万能")
	ad.add_wilds("superwild", 4)
	t.eq(ad.total(), 56, "注入两次 = 一次(deck 侧来源记账挡)")
