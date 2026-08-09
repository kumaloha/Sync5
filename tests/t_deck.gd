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
	t.eq(big.rank_label(), "★", "big joker glyph")
	t.eq(Card.new(Card.JOKER_RANK, Card.JOKER_LITTLE).rank_label(), "☆", "little joker glyph")
