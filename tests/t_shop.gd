extends RefCounted

# --- Mid-section shop (2026-08-06: 商店与盲注解耦) ---
# The break fires INSIDE a blind: score keeps accumulating and no clear/fail
# verdict is rendered, which is what lets the player buy against a KNOWN
# deficit instead of betting on an unseen blind.
func run(t) -> void:
	var r := Run.new()
	r.reset(7)
	r.section_score = 10
	var breaks := 0
	var dones := 0
	for i in range(GameConfig.PHRASES_PER_SECTION):
		var out := r.advance()
		if bool(out["shop_break"]):
			breaks += 1
			t.check(not bool(out["section_done"]), "a break never closes the section")
			t.eq(r.phrase_in_section, GameConfig.PHRASES_PER_SHOP,
				"the break lands on the shop beat")
			t.eq(r.section_score, 10, "a break does NOT reset the score")
		if bool(out["section_done"]):
			dones += 1
			t.check(not bool(out["shop_break"]), "the last beat is a section end, not a break")
	t.eq(breaks, GameConfig.SHOPS_PER_SECTION - 1, "one mid-section break per section")
	t.eq(dones, 1, "exactly one section end")
	# the readouts the mid-section shop board is built on
	r.reset(7)
	t.eq(r.phrases_left(), GameConfig.PHRASES_PER_SECTION, "all phrases left at section start")
	r.advance()
	r.advance()
	r.advance()
	t.eq(r.phrases_left(), GameConfig.PHRASES_PER_SECTION - GameConfig.PHRASES_PER_SHOP,
		"phrases_left counts down to the section end")
	r.section_score = 0
	t.eq(r.deficit(), r.target(), "full deficit at zero score")
	r.section_score = r.target() + 5
	t.eq(r.deficit(), 0, "deficit floors at zero once the target is met")

	# ---- shelf 三件套(2026-08-12 流派批二波):货架结构卡的 API 契约 ----
	# 游戏侧(view/shop.gd)与 bot 侧(tools/bot.gd)都消费这几个口, 契约锁在这里。
	var plain: Array = [null, Joker.by_id("neonsign"), null, null]
	var with_db: Array = [null, Joker.by_id("doublebill"), null, null]
	var with_sp: Array = [null, Joker.by_id("sponsor"), null, null]
	var with_jb: Array = [null, Joker.by_id("jukebox"), null, null]
	t.eq(Joker.slots_shelf_size(plain), 3, "default shelf holds 3")
	t.eq(Joker.slots_shelf_size(with_db), 4, "doublebill widens the shelf to 4")
	t.eq(Joker.slots_buy_limit(plain), 1, "default one buy per shop")
	t.eq(Joker.slots_buy_limit(with_db), 2, "doublebill allows two buys")
	t.eq(Joker.slots_price_delta(with_sp), -1, "sponsor discounts by one")
	t.check(Joker.slots_rule_guaranteed(with_jb), "jukebox guarantees a rule card")
	t.check(not Joker.slots_rule_guaranteed(plain), "no guarantee without jukebox")
	# 规则牌的机械判据 = 带 acquire 键;点唱机自己**不是**规则牌(shelf-only),
	# 所以它不满足自己的保证 —— 这是故意的(它保证的是搜到别人)。
	t.check(Joker.by_id("shortcut").is_rule_card(), "shortcut is a rule card")
	t.check(Joker.by_id("trim").is_rule_card(), "trim is a rule card")
	t.check(not Joker.by_id("neonsign").is_rule_card(), "neonsign is not")
	t.check(not Joker.by_id("jukebox").is_rule_card(), "jukebox itself is not a rule card")
	# 赞助折扣走 Economy.shelf_price:普通 4→3;免费(首张 Target)不受折扣;地板 1◆。
	var tgt_first: Array = [null, Joker.by_id("sponsor"), null, null]
	t.eq(Economy.shelf_price(Joker.by_id("neonsign"), with_sp), 2, "sponsor: common 3 -> 2(经济 v2 平价)")
	t.eq(Economy.shelf_price(Joker.by_id("neonsign"), plain), 3, "no sponsor: base price 3(经济 v2)")
	t.eq(Economy.shelf_price(Joker.by_id("twin"), tgt_first), 0, "first target stays free under sponsor")
	var tgt_owned: Array = [Joker.by_id("twin"), Joker.by_id("sponsor"), null, null]
	t.eq(Economy.shelf_price(Joker.by_id("stair"), tgt_owned), 2, "target swap 3 -> 2 with sponsor(经济 v2 平价)")
	t.eq(Economy.sell_value(Joker.by_id("neonsign")), 1, "sell-back ignores the discount (3/2=1, 经济 v2)")
