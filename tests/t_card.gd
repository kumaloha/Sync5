extends RefCounted

# --- Card ---
func run(t) -> void:
	t.eq(t._c(14, 3).label(), "AS", "ace of spades label")
	t.eq(t._c(10, 0).rank_label(), "10", "ten rank label")
	# 万能牌标签往返闭合(2026-09-06):超级百搭注入 suit 2/3, Tape 重放靠 label 比对手牌集合
	for su in range(4):
		var w := Card.new(Card.JOKER_RANK, su)
		t.eq(Card.from_label(w.label()).label(), w.label(), "wild label roundtrip suit %d" % su)
	t.check(t._c(2, 2).is_red(), "hearts is red")
	t.check(not t._c(2, 3).is_red(), "spades not red")
