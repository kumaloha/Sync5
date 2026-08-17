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
	# ⚑ 2026-08-16 双色调拆两张:一张只管一色 ⇒ 必须**按 colors 实际是红是黑**选规则,
	# 而不是像旧的 twotone 那样一个开关通吃。这条断言的形状变了, 不只是改个名。
	var _red_hand: bool = colors[0].is_red()
	t.eq(Pattern.evaluate_best(colors, {"redtone": true} if _red_hand else {"blacktone": true})["kind"],
		Pattern.Kind.FLUSH, "单色调把同色读成同花")
	t.check(Pattern.evaluate_best(colors, {"blacktone": true} if _red_hand else {"redtone": true})["kind"]
		!= Pattern.Kind.FLUSH, "另一色那张**不**生效 —— 拆分的核心")
	var rd := Deck.new(11)
	Joker.by_id("shortcut").on_acquire(rd)
	Joker.by_id("blacktone").on_acquire(rd)
	t.check(bool(rd.rules.get("shortcut", false)) and bool(rd.rules.get("blacktone", false)), "rule jokers set deck flags")
	var rp := Phrase.new(rd, [], 6)
	rp.start()
	t.check(not rp.current_best().is_empty(), "phrase evaluates under deck rules")
