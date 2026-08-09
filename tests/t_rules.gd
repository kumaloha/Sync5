extends RefCounted

# --- Rule-change rescues (support batch 2) ---
func run(t) -> void:
	var gap_hand := [t._c(2, 0), t._c(3, 1), t._c(5, 2), t._c(6, 3), t._c(7, 0)]
	t.eq(Pattern.evaluate_best(gap_hand)["kind"], Pattern.Kind.HIGH_CARD, "gap hand is high card by default")
	t.eq(Pattern.evaluate_best(gap_hand, {"shortcut": true})["kind"], Pattern.Kind.STRAIGHT, "shortcut bridges one gap")
	var four_run := [t._c(2, 0), t._c(3, 1), t._c(4, 2), t._c(5, 3), t._c(9, 0)]
	t.eq(Pattern.evaluate_best(four_run, {"fourfingers": true})["kind"], Pattern.Kind.STRAIGHT, "four fingers accepts a 4-run")
	var wheel4 := [t._c(14, 0), t._c(2, 1), t._c(3, 2), t._c(4, 3), t._c(9, 0)]
	t.eq(Pattern.evaluate_best(wheel4, {"fourfingers": true})["kind"], Pattern.Kind.STRAIGHT, "four fingers reads the ace-low run")
	var colors := [t._c(2, 1), t._c(5, 2), t._c(8, 1), t._c(11, 2), t._c(13, 1)]
	t.eq(Pattern.evaluate_best(colors)["kind"], Pattern.Kind.HIGH_CARD, "mixed red suits are no flush by default")
	t.eq(Pattern.evaluate_best(colors, {"twotone": true})["kind"], Pattern.Kind.FLUSH, "two-tone reads color as suit")
	var rd := Deck.new(11)
	Joker.by_id("shortcut").on_acquire(rd)
	Joker.by_id("twotone").on_acquire(rd)
	t.check(bool(rd.rules.get("shortcut", false)) and bool(rd.rules.get("twotone", false)), "rule jokers set deck flags")
	var rp := Phrase.new(rd, [], 6)
	rp.start()
	t.check(not rp.current_best().is_empty(), "phrase evaluates under deck rules")
