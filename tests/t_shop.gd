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
	# 「免费」这个词只有一家 —— 与刷新键同一个 `free_text`(ui.json 的叶子已经过语言层)
	t.check(ptext.find(String(DB.ui()["shop"]["free_text"])) != -1,
		"价签写「免费」(与刷新键共用 free_text)")
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
	# ⚑ 货架数组**不别名**(2026-09-09 审查):编排器交出去之后还会就地改它(买走一张置 null、
	# 赞助碟上下架 resize)—— 存引用等于视图的「当次货架」在背后跟着变形。
	var mine: Array = [cs[0], cs[1], sp]
	sh.set_consumables(mine, 5, [])
	var kept: int = sh._coffer.size()
	mine.clear()
	t.eq(sh._coffer.size(), kept, "改回自己的数组不动商店那一份(set_consumables 拷了一份)")
	# ⚑ 摆几个位按**碟数**算, 不按数组长度算:买走一张后编排器把那格置 null, 长度仍是 3。
	sh.set_consumables([cs[0], cs[1], null], 5, [])
	t.eq(sh._cshelf[0].position.x, 268.0, "末位空的三格货架按**两碟**排(第一碟仍是 268)")
	t.eq(sh._cshelf[1].position.x, 482.0, "……第二碟 482")
	t.check(not sh._cshelf[2].visible, "……空着的第三位藏起来")
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
	sh.visit.reroll_count = 0
	sh._layer.visible = true
	sh._on_reroll()
	t.eq(whys.size(), 1, "刷不起发 denied")
	t.eq(whys[0], "reroll", "……why = reroll(单参签名)")
	# ---- 视图是 `Shelf.Visit` 的**消费者**(2026-09-09 商店记账收口 2/4)----
	# ⚑ 视图不再自己存记账字段;`Shop.new()` 自带一份默认 Visit(测试/探针直接 new 得能用),
	#   编排器每次进店 `set_visit()` 换一份新的。
	t.check(sh.visit != null, "Shop.new() 自带一份默认 Visit(直接 new 也能用)")
	var v2 := Shelf.Visit.new()
	v2.open(0)
	sh.set_visit(v2)
	t.check(sh.visit == v2, "set_visit 换掉那一份")
	t.eq(sh._reroll_cost_now(), Economy.reroll_cost(0), "换进来的是新的一次进店 ⇒ 刷新价回到阶梯第 0 级")
	v2.note_reroll()
	t.eq(sh._reroll_cost_now(), Economy.reroll_cost(1),
		"视图读的就是那一份 —— 记账走 Visit, 视图没有第二本账")
	t.eq(sh.reroll_count(), v2.reroll_count, "reroll_count() 是委托, 不是副本")
	v2.apply_action({"price_delta": -2})
	t.eq(sh._reroll_cost_now(), Economy.reroll_cost(1, -2), "本店折扣也从那一份来")
	sh.queue_free()

	# ---- Shelf.Visit(2026-09-09 商店记账收口:一次进店 = 一份记账)----
	# ⚑ 联票名额 / 免费刷新 / 折扣 / 挑高 / 5 选 1 计数 / 离店清零此前住在**三处**
	#   (view · tools/golden.gd::ShopSim · lua/app/shop.lua),现在是 `core/shelf.gd` 的一份。
	#   逐字段对拍在金样第六族 `visit`;这里锁的是**契约**(每个方法一条)。
	# ⚠ 数一律从 `Joker.slots_buy_limit` / `Economy.reroll_cost` / `Economy.shelf_price` 推导 ——
	#   写死等于把平衡表抄了第二份(runner 顶上那条纪律)。
	var vslots: Array = [null, Joker.by_id("encore"), null, null]
	var v := Shelf.Visit.new()
	# open:进店归零 + 灌入点名的解除奖励;「本店」授予**不**清(上一店 close 清过)
	v.grant_shelf = 4
	v.grant_extra_buys = 2
	v.grant_min_rarity = "uncommon"
	v.shop_buys = 3
	v.reroll_count = 5
	v.buys_left = 2
	v.coffer_used = true
	v.perkeo_fired = true
	v.closed = true
	v.open(1)
	t.eq([v.shop_buys, v.reroll_count, v.buys_left], [0, 0, 0], "open 归零成交/刷新/续买三个计数")
	t.eq(v.grant_min_rarity, "", "open 清挑高 —— 它是「下次货架」类, 进店这一刻消费掉")
	t.eq(v.shelf_bonus, 1, "open 灌入点名的解除奖励")
	t.check(not v.coffer_used and not v.perkeo_fired and not v.closed, "open 复位三个布尔")
	t.eq(v.grant_shelf, 4, "open **不**清「本店」授予(那是 close 的活)")

	# apply_action:只认五个记账键, 返回值说要不要当场重掷
	v = Shelf.Visit.new()
	v.open(0)
	t.check(bool(v.apply_action({"shelf_slots": 4})["redeal"]), "联票改了货架构成 ⇒ 当场重掷")
	v.apply_action({"shelf_slots": 3})
	t.eq(v.grant_shelf, 4, "shelf_slots 取大(一店两张联票不叠成 7)")
	t.check(not bool(v.apply_action({"extra_buys": 2})["redeal"]), "给名额不顺手送一次免费刷新")
	v.apply_action({"extra_buys": 1})
	t.eq(v.grant_extra_buys, 3, "extra_buys 是加法 —— 取大时联票买掉的正是它要给的那次成交")
	v.apply_action({"price_delta": -2})
	v.apply_action({"price_delta": -1})
	t.eq(v.grant_price, -3, "price_delta 累加(含负数)")
	v.apply_action({"free_reroll": 2})
	v.apply_action({"free_reroll": 1})
	t.eq(v.grant_free_reroll, 3, "free_reroll 累加")
	t.check(bool(v.apply_action({"min_rarity": "uncommon"})["redeal"]), "挑高当场重发一次")
	t.eq(v.grant_min_rarity, "uncommon", "min_rarity 是覆盖, 不是累加")
	var untouched: Array = [v.grant_shelf, v.grant_extra_buys, v.grant_price, v.grant_free_reroll]
	t.check(not bool(v.apply_action({"loan": {"borrow": 5, "repay": 7}, "wilds": 4,
		"deck_rule": "shortcut", "rule_guaranteed": true, "copy_one_destroy_rest": true,
		"ad_coins": 3})["redeal"]), "碰钱/碰牌堆/跨店的键不归 Visit —— 留在调用方")
	t.eq([v.grant_shelf, v.grant_extra_buys, v.grant_price, v.grant_free_reroll], untouched,
		"……而且一个记账字段都不动")

	# price:展示价与成交价共用一份;折扣的地板是 1◆, 免费保 0
	v = Shelf.Visit.new()
	v.open(0)
	var enc := Joker.by_id("encore")
	var twin := Joker.by_id("twin")
	t.eq(v.price(enc, vslots), Economy.shelf_price(enc, vslots), "无折扣时 = Economy.shelf_price")
	t.eq(v.price(twin, vslots), 0, "首张 Target 免费")
	v.apply_action({"price_delta": -1})
	t.eq(v.price(enc, vslots), maxi(1, Economy.shelf_price(enc, vslots) - 1), "赞助的本店折扣")
	v.apply_action({"price_delta": -99})
	t.eq(v.price(enc, vslots), 1, "折扣的地板是 1◆(0 会混进「免费」的打点与文案分支)")
	t.eq(v.price(twin, vslots), 0, "……免费那一档仍是 0, 不吃地板")

	# affordable:满槽时最好的一张 Support 回收算进预算;换旗没有退款
	v = Shelf.Visit.new()
	v.open(0)
	var p_enc := Economy.shelf_price(enc, vslots)
	t.check(v.affordable(enc, vslots, p_enc), "钱刚好 = 买得起")
	t.check(not v.affordable(enc, vslots, p_enc - 1), "差一枚就买不起")
	t.check(v.affordable(twin, vslots, 0), "免费的首张 Target 身无分文也拿得动")
	var full: Array = [Joker.by_id("twin"), Joker.by_id("encore"),
		Joker.by_id("finale"), Joker.by_id("turnover")]
	var best := 0
	for k in range(1, full.size()):
		best = maxi(best, Economy.sell_value(full[k]))
	t.check(best > 0, "前提:满槽里的 Support 回收值不为 0")
	var pk := Joker.by_id("perkeo")
	var p_pk := Economy.shelf_price(pk, full)
	t.check(v.affordable(pk, full, p_pk - best), "满槽 Support:旧卡的回收算进预算")
	t.check(not v.affordable(pk, full, p_pk - best - 1), "……只算最好的那一张")
	var lw := Joker.by_id("lonewolf")
	t.check(not v.affordable(lw, full, Economy.shelf_price(lw, full) - 1),
		"换旗不退款 ⇒ Target 只看现钱")

	# reroll:阶梯 · 本店折扣 · 免费刷新不推阶梯
	v = Shelf.Visit.new()
	v.open(0)
	t.eq(v.reroll_cost_now(), Economy.reroll_cost(0), "首刷 = 阶梯第 0 级")
	v.note_reroll()
	t.eq(v.reroll_cost_now(), Economy.reroll_cost(1), "刷一次推一级")
	v.apply_action({"price_delta": -2})
	t.eq(v.reroll_cost_now(), Economy.reroll_cost(1, -2), "刷新价也吃本店折扣")
	t.check(not v.take_free_reroll(), "没授予就没有免费刷新")
	v.apply_action({"free_reroll": 2})
	t.check(v.take_free_reroll(), "加急:第一次免费")
	t.eq(v.reroll_count, 1, "免费刷新**不推阶梯** —— 用完后首刷跳价就是卡面说谎")
	t.check(v.take_free_reroll(), "第二次也免费")
	t.check(not v.take_free_reroll(), "两次用完就没了")

	# buy_limit / note_buy / stay:5 选 1 的计数与去留
	v = Shelf.Visit.new()
	v.open(0)
	var base_limit := Joker.slots_buy_limit(vslots)
	t.eq(v.buy_limit(vslots), base_limit, "基础名额 = Joker.slots_buy_limit")
	v.apply_action({"extra_buys": 2})
	t.eq(v.buy_limit(vslots), base_limit + 2, "授予的名额加在基础之上")
	for i in range(base_limit + 1):
		v.note_buy()
		t.check(v.stay(vslots), "名额没用完就留在店里(第 %d 张)" % (i + 1))
		t.eq(v.buys_left, base_limit + 2 - v.shop_buys, "……副标题的「还能再选 N 张」")
	v.note_buy()
	t.check(not v.stay(vslots), "满额 ⇒ 离店")
	t.check(v.closed, "……stay 判满额时顺手 close")
	t.eq(v.buy_limit(vslots), base_limit, "……授予清零后名额回到基础")

	# close:清「这次商店」类的四个, 不清挑高与两个布尔
	v = Shelf.Visit.new()
	v.open(0)
	v.apply_action({"shelf_slots": 4, "extra_buys": 1, "price_delta": -2,
		"free_reroll": 1, "min_rarity": "uncommon"})
	v.coffer_used = true
	v.perkeo_fired = true
	v.close()
	t.eq([v.grant_shelf, v.grant_extra_buys, v.grant_price, v.grant_free_reroll], [0, 0, 0, 0],
		"close 清四个「本店」授予 —— 一次性就是一次性")
	t.eq(v.grant_min_rarity, "uncommon", "……但不清挑高(「下次货架」类, 清零点在 open)")
	t.check(v.coffer_used and v.perkeo_fired, "……也不清这两个布尔(它们跟着 open 复位)")
	t.check(v.closed, "close 之后 closed")
	v.open(0)
	t.eq(v.grant_min_rarity, "", "下一次 open 才清挑高")
