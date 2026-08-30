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
	# ⚑ 四指的同花半边(2026-08-18, 与近道的差异所在):任一花色 ≥4 张即同花
	var f4 := [t._c(2, 0), t._c(7, 0), t._c(9, 0), t._c(12, 0), t._c(5, 1)]
	t.check(Pattern.evaluate_best(f4)["kind"] != Pattern.Kind.FLUSH, "默认 4 张同花不算同花")
	t.eq(Pattern.evaluate_best(f4, {"fourfingers": true})["kind"], Pattern.Kind.FLUSH,
		"四指:四张同花即同花(原作的另一半, 也是它与近道的区别)")
	var f22 := [t._c(2, 0), t._c(7, 0), t._c(9, 3), t._c(12, 3), t._c(5, 1)]
	t.check(Pattern.evaluate_best(f22, {"fourfingers": true})["kind"] != Pattern.Kind.FLUSH,
		"两两花色凑不出四指同花 —— 数的是**单一花色** ≥4")
	t.eq(Pattern.evaluate_best(f22, {"fourfingers": true, "blacktone": true})["kind"],
		Pattern.Kind.FLUSH, "四指×黑调:黑色两花色按颜色类合并后 ≥4 ⇒ 同花(组合零特例)")
	var sf4 := [t._c(5, 0), t._c(6, 0), t._c(7, 0), t._c(8, 0), t._c(13, 1)]
	t.eq(Pattern.evaluate_best(sf4, {"fourfingers": true})["kind"], Pattern.Kind.STRAIGHT_FLUSH,
		"四张同花连号 = 同花顺(顺半边与花半边叠加)")
	var rd := Deck.new(11)
	# ⚑ 规则牌 2026-08-30 转生为**消耗牌**:标志位由 `action.deck_rule` 写进牌堆,
	# 执行口在 `view/phrase.gd`(两条通路)与 `tools/bot.gd::_apply_bot_action`。
	# 这里锁的是**数据契约**:这四张确实带 deck_rule, 且值指向真的规则名。
	var rule_ids := {"shortcut": true, "fourfingers": true, "blacktone": true, "redtone": true}
	var seen := {}
	for e in DB.consumables():
		var c := Consumable.new(e)
		if not c.is_rule_card():
			continue
		seen[String(e["id"])] = true
		t.eq(String(c.action["deck_rule"]), String(e["id"]),
			"%s 的 deck_rule 指向它自己(规则名 = 卡 id, Pattern 按这个键查)" % e["id"])
		rd.rules[String(c.action["deck_rule"])] = true
	t.eq(seen, rule_ids, "四张规则牌全在消耗牌里(转生后 Joker 侧一张都没有)")
	t.check(bool(rd.rules.get("shortcut", false)) and bool(rd.rules.get("blacktone", false)),
		"规则牌把标志位写进牌堆")
	# ⚠⚠ **写进去就撤不掉** —— 全仓没有任何撤销路径, 这正是判它们「一次性」的依据。
	t.check(not Joker.by_id("shortcut") is Joker, "近道已不在小丑牌池(by_id 返回 null)")
	var rp := Phrase.new(rd, [], 6)
	rp.start()
	t.check(not rp.current_best().is_empty(), "phrase evaluates under deck rules")
