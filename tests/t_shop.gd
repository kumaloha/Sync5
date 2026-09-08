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
	# ⚑ 联票/赞助/点唱机 2026-08-29 转生为**消耗牌**(都是「只作用于这次商店」的
	# 一次性效果, 占永久槽位是资源错配)。它们的行为断言迁到 `t_consumable`
	# 的 action 口径 —— **不删, 只搬家**:机制还在, 承载它的东西换了。
	t.check(not Joker.slots_rule_guaranteed(plain), "no guarantee without jukebox")
	# 规则牌的机械判据 = 带 acquire 键;点唱机自己**不是**规则牌(shelf-only),
	# 所以它不满足自己的保证 —— 这是故意的(它保证的是搜到别人)。
	# ⚑ 「规则牌」整体搬到消耗牌一侧(2026-08-30 二批转生)——
	# 机械判据从「小丑牌带 acquire」换成「消耗牌带 action.deck_rule」。
	var n_rule := 0
	for e in DB.consumables():
		if Consumable.new(e).is_rule_card():
			n_rule += 1
	t.eq(n_rule, 4, "四张规则牌都在消耗牌里(近道/四指/黑调/红调)")
	for j in Joker.pool():
		t.check(not j.is_rule_card(), "%s 不该是规则牌 —— 转生后小丑牌侧一张都不剩" % j.id)
	# ⚑ 赞助 2026-08-29 转生为消耗牌 —— 折扣改由 `Shop.grant_price_delta` 授予
	# (−2◆, 用户:「−1 好抠」), 断言见 t_consumable。这里只留不依赖它的价格基线。
	t.eq(Economy.shelf_price(Joker.by_id("neonsign"), plain), 3, "no sponsor: base price 3(经济 v2)")
	t.eq(Economy.shelf_price(Joker.by_id("twin"), plain), 0, "first target stays free")

	# ---- 广告 offer(2026-09-08 二审:长在「想要但拿不到」那一刻)----
	var sh := Shop.new()
	t.get_root().add_child(sh)
	# ⚠ runner 在 `_initialize()` 里跑, 那一刻 root 还没 inside_tree ⇒ add_child **不会**触发
	# `_ready`(实测), 而测试不许 await 帧 ⇒ 手动打一次(t_ads 同款)。
	sh._ready()
	var reroll_pos: Vector2 = sh._reroll_btn.position
	var skip_pos: Vector2 = sh._skip_btn.position
	var skip_text: String = sh._skip_btn.text
	t.check(not sh.ad_offer_visible(), "缺省没有 offer(离线 = 今天的商店)")
	# ⚠ 计数用数组不用 int:GDScript 的 lambda **按值捕获**, `got += 1` 只改闭包里的那份。
	var got: Array = []
	sh.ad_requested.connect(func() -> void: got.append(1))
	sh.show_ad_offer(2, 3)
	t.check(sh.ad_offer_visible(), "show 之后可见")
	t.check(sh._ad_btn.text.find("2") != -1 and sh._ad_btn.text.find("3") != -1, "文案带缺口与数额")
	t.eq(sh._reroll_btn.position, reroll_pos, "刷新键位置不动")
	t.eq(sh._skip_btn.position, skip_pos, "继续键位置不动")
	t.eq(sh._skip_btn.text, skip_text, "继续键文案不动")
	sh._layer.visible = true
	sh._on_ad_offer()
	t.eq(got.size(), 1, "点 offer 发 ad_requested")
	sh.hide_ad_offer()
	t.check(not sh.ad_offer_visible(), "hide 之后不可见")
	sh._on_ad_offer()
	t.eq(got.size(), 1, "藏着时点不发")
	sh.show_ad_offer(0, 3)
	t.check(sh._ad_btn.text.find("差") == -1, "缺口 0 用无缺口文案")
	sh.close()
	t.check(not sh.ad_offer_visible(), "close 收掉 offer")
	var before := sh._layer.get_child_count()
	sh._layout(3)
	sh._layout(4)
	t.eq(sh._layer.get_child_count(), before, "反复 _layout 不再建节点(offer 只建一次)")
	# denied 带缺口(need = 差几◆)
	var needs: Array = []
	sh.denied.connect(func(why: String, need: int) -> void: needs.append([why, need]))
	sh._coins = 1
	sh._reroll_count = 0
	sh._layer.visible = true
	sh._on_reroll()
	t.eq(needs.size(), 1, "刷不起发 denied")
	t.eq(needs[0][0], "reroll", "……why = reroll")
	t.eq(needs[0][1], Economy.reroll_cost(0) - 1, "……need = 刷新价 − 金币")
	sh.queue_free()
