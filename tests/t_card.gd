extends RefCounted

# --- Card ---
func run(t) -> void:
	t.eq(t._c(14, 3).label(), "AS", "ace of spades label")
	t.eq(t._c(10, 0).rank_label(), "10", "ten rank label")
	t.check(t._c(2, 2).is_red(), "hearts is red")
	t.check(not t._c(2, 3).is_red(), "spades not red")
