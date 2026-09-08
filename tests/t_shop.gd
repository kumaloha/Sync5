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

	# ---- 赞助碟 = 货架第三张碟(2026-09-09 赞助商版, 取代 09-08 的「买不起弹 offer」)----
	# ⚑ 同一件事只留一套机制:offer 那个系统按钮整套删掉, 广告在这个世界里变成一个角色(赞助商),
	#   而这个世界里能拿的只有卡和碟 ⇒ 它就是货架上的第三张碟。
	var sh := Shop.new()
	t.get_root().add_child(sh)
	# ⚠ runner 在 `_initialize()` 里跑, 那一刻 root 还没 inside_tree ⇒ add_child **不会**触发
	# `_ready`(实测), 而测试不许 await 帧 ⇒ 手动打一次(t_ads 同款)。
	sh._ready()
	var reroll_pos: Vector2 = sh._reroll_btn.position
	var skip_pos: Vector2 = sh._skip_btn.position
	var skip_text: String = sh._skip_btn.text
	t.eq(sh._cshelf.size(), 3, "碟位建 3 个(第三位给赞助碟, 无货时藏着)")
	# offer 键整套已删 —— 商店层里不许再有广告按钮(离线 = 今天的商店, 一像素不差)
	var ad_btns := 0
	for ch in sh._layer.get_children():
		if ch is Button and (String(ch.text).find("广告") != -1 or String(ch.name).to_lower().find("ad") != -1):
			ad_btns += 1
	t.eq(ad_btns, 0, "商店层里没有广告 offer 按钮了")
	t.check(not sh.has_method("show_ad_offer"), "show_ad_offer 已删")
	t.check(not sh.has_method("ad_offer_visible"), "ad_offer_visible 已删")
	# 两张普通消耗牌 + 赞助碟
	var cs: Array = []
	for e in DB.consumables():
		var cc := Consumable.new(e)
		if not cc.is_sponsor() and cs.size() < 2:
			cs.append(cc)
	var sp := Consumable.new(Consumable.sponsor_entry())
	t.eq(cs.size(), 2, "池子里够两张普通消耗牌")
	# 两碟 = 今天的样子(离线红线):碟位 268 / 482, 第三位藏着
	sh.set_consumables([cs[0], cs[1]], 5, [])
	t.eq(sh._cshelf[0].position.x, 268.0, "两碟时第一碟 x = 268(今天的样子)")
	t.eq(sh._cshelf[1].position.x, 482.0, "两碟时第二碟 x = 482")
	t.check(not sh._cshelf[2].visible, "两碟时第三位藏着")
	t.check(not sh._cshelf[2].sponsor, "……而且不是赞助碟")
	# 三碟 = 201 / 375 / 549(画布 Main.dc.html:列宽 150 · 间距 24 · 起点 192)
	sh.set_consumables([cs[0], cs[1], sp], 5, [])
	t.eq(sh._cshelf[0].position.x, 201.0, "三碟时第一碟 x = 201")
	t.eq(sh._cshelf[1].position.x, 375.0, "三碟时第二碟 x = 375")
	t.eq(sh._cshelf[2].position.x, 549.0, "三碟时第三碟 x = 549")
	t.check(sh._cshelf[2].visible, "三碟时第三位在场")
	t.check(sh._cshelf[2].sponsor, "第三位是赞助碟")
	t.eq(sh._cshelf[2].accent, StageTheme.CYAN, "赞助碟用青(舞台自己的光, 与金环的货架碟分开)")
	t.check(not sh._cshelf[0].sponsor, "普通碟不是赞助碟")
	t.eq(sh._cshelf[0].accent, StageTheme.GOLD, "普通碟仍是金(待售)")
	var ptext: String = sh._cshelf_price[2].text
	t.check(ptext.find(Lingo.t("免费")) != -1, "价签写「免费」")
	t.check(ptext.find("+%d" % Economy.ad_coins()) != -1, "价签写 +N◆(数从卡上来)")
	# 价格 0 与金币无关:身无分文也拿得动
	sh.set_consumables([cs[0], cs[1], sp], 0, [])
	t.check(sh._cshelf[2].armed, "没钱也 armed(它免费)")
	t.check(not sh._cshelf[0].armed, "……而普通碟买不起就压暗")
	# 插播中
	sh.set_sponsor_playing(true)
	t.check(sh._cshelf[2].playing, "set_sponsor_playing(true) ⇒ 第三碟插播中")
	sh.set_sponsor_playing(false)
	t.check(not sh._cshelf[2].playing, "……收得回来")
	# 回到两碟:位置复原, 插播态不许留在下一次(离架即清)
	sh.set_sponsor_playing(true)
	sh.set_consumables([cs[0], cs[1]], 5, [])
	t.eq(sh._cshelf[0].position.x, 268.0, "回到两碟位置复原")
	t.check(not sh._cshelf[2].visible, "……第三位重新藏起来")
	t.check(not sh._cshelf[2].playing, "……插播态跟着离架清掉")
	# 点空的第三位 = 无操作(发奖后碟离架, 同店再点不许再放一次)
	var bought: Array = []
	sh.consumable_bought.connect(func(c, price: int) -> void: bought.append([c, price]))
	sh._layer.visible = true
	sh._on_cshelf_pressed(2)
	t.eq(bought.size(), 0, "第三位空着时点它什么都不发生")
	sh.set_consumables([cs[0], cs[1], sp], 0, [])
	sh._on_cshelf_pressed(2)
	t.eq(bought.size(), 1, "在架时点它发 consumable_bought")
	t.eq(int(bought[0][1]), 0, "……价 0")
	# 反复排布不许再建节点(_layout / set_consumables 都会跑很多次)
	var before := sh._layer.get_child_count()
	sh._layout(3)
	sh._layout(4)
	sh.set_consumables([cs[0], cs[1]], 5, [])
	sh.set_consumables([cs[0], cs[1], sp], 5, [])
	t.eq(sh._layer.get_child_count(), before, "反复排布不再建节点(碟位只建一次)")
	t.eq(sh._reroll_btn.position, reroll_pos, "刷新键位置不动")
	t.eq(sh._skip_btn.position, skip_pos, "继续键位置不动")
	t.eq(sh._skip_btn.text, skip_text, "继续键文案不动")
	# denied 回到单参(缺口参数随 offer 一起退役)
	var whys: Array = []
	sh.denied.connect(func(why: String) -> void: whys.append(why))
	sh._coins = 1
	sh._reroll_count = 0
	sh._layer.visible = true
	sh._on_reroll()
	t.eq(whys.size(), 1, "刷不起发 denied")
	t.eq(whys[0], "reroll", "……why = reroll(单参签名)")
	sh.queue_free()
