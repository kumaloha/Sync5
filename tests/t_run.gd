extends RefCounted

func run(t) -> void:
	_t_cashout(t)
	_test_run_structure(t)
	_test_run_machine(t)
	_t_fork_complete(t)


# --- Run structure (2026-08-06 节奏定案: run = 4 gigs × 1 blind = 4 sections,
# 6 phrases each, shop every 3 — 商店与盲注解耦) ---

func _test_run_structure(t) -> void:
	t.eq(GameConfig.SECTIONS_PER_GIG, 1, "1 blind per gig")
	t.eq(GameConfig.GIGS_PER_RUN, 4, "4 gigs per run")
	t.eq(GameConfig.SECTIONS_PER_RUN, 4, "4 sections per run")
	t.eq(GameConfig.SECTION_TARGETS.size(), 4, "4 section targets")
	t.eq(GameConfig.PHRASES_PER_SECTION, 6, "6 phrases per section")
	t.eq(GameConfig.PHRASES_PER_SHOP, 3, "shop every 3 phrases")
	t.eq(GameConfig.SHOPS_PER_SECTION, 2, "2 shops per section")
	# ⚠⚠ 这里锁的是**日程**(每段 2 次 × 4 段 = 8 个档期), **不是实际发生的次数**。
	# 实际是 **7 次** —— 末段的段末商店开在 run 结束那一刻, `view/phrase.gd` 在
	# `finale` 那一支直接走结算屏, 根本不开(Tape 实测 37/37 局 = 段中 4 + 段末 3)。
	# 2026-08-09 外部审查指出这条注释误导, 已改。下面那条断言验的是实际次数。
	# 7 shops against 4 joker slots. 槽位是**瓶颈**而不是容量目标 ——
	# 后半程必须「买新替旧」, 那正是构筑弧的发动机(用户 2026-08-06 拍板:
	# 「要上新的就要替代掉以前老的」)。Shops are decoupled from blinds now,
	# so this count is sections × shops-per-section, not sections.
	t.eq(GameConfig.SECTIONS_PER_RUN * GameConfig.SHOPS_PER_SECTION, 8,
		"8 shop slots on the schedule (2 per section × 4)")
	# ⚑ **实际发生的次数** = 日程 − 1(末段的段末商店落在 run 结束那一刻, 不开)。
	# 这条断言是 2026-08-09 补的:此前只锁日程, 于是「一局几次商店」在文档里
	# 被写成 8 写了很久, 而真实是 7 —— 锁了会算的那个数, 没锁真正发生的那个。
	t.eq(GameConfig.SECTIONS_PER_RUN * GameConfig.SHOPS_PER_SECTION - 1, 7,
		"7 shops actually happen (the finale section has no end-of-section shop)")
	t.eq(GameConfig.SECTIONS_PER_RUN * GameConfig.SHOPS_PER_SECTION, 2 * 4,
		"shops outnumber joker slots 2:1")
	# venue arc, shown on the home stage card (docs/mockups/home.html)
	t.eq(GameConfig.GIG_NAMES.size(), GameConfig.GIGS_PER_RUN, "one venue name per gig")
	t.check(GameConfig.gig_name(0) != GameConfig.gig_name(3), "the venue changes between gigs")
	t.eq(GameConfig.gig_name(99), String(GameConfig.GIG_NAMES[-1]), "venue lookup clamps")
	t.eq(GameConfig.section_target(0), int(GameConfig.SECTION_TARGETS[0]), "section_target reads the table")
	t.eq(GameConfig.section_target(99), int(GameConfig.SECTION_TARGETS[-1]), "section_target clamps high")
	t.eq(GameConfig.section_target(-3), int(GameConfig.SECTION_TARGETS[0]), "section_target clamps low")
	# 用户 2026-08-06:「4 个阶段性的任务和规则要做, 也不做跳过, 就是必须做」——
	# 小盲/大盲作废, 每一段都是 BOSS 墙, 递进感由档位色 + 序号承担。
	t.check(GameConfig.WALL_SECTIONS == [0, 1, 2, 3], "every section is a wall")
	for w in GameConfig.WALL_SECTIONS:
		t.check(GameConfig.is_wall(w), "S%d is a wall" % (w + 1))
	t.eq(GameConfig.gig_of(0), 0, "S1 in gig 1")
	t.eq(GameConfig.gig_of(2), 2, "S3 in gig 3")
	t.eq(GameConfig.gig_of(3), 3, "S4 in gig 4")
	t.eq(GameConfig.blind_name(0), "BOSS", "every blind is a BOSS")
	# 2026-08-06 手游节奏: 8 秒乐句 × 6 拍/盲注 × 4 盲注 = 216s 出牌,
	# 加 8 次商店约 4.9 分钟(用户拍板 5 分钟上限)。见 docs/design/levels.md。
	for g in range(GameConfig.GIGS_PER_RUN):
		t.eq(GameConfig.phrase_duration(g), 8.0, "gig %d clock" % (g + 1))
	# Target 回池(2026-08-06 用户拍板:「不应该有任何卡有固定概率, 大家都是一样的。
	# 除了第一轮有 target 之外, 其他都是随机的」)。原来的 from_section 窗口断言随
	# `target_swap` 一起作废 —— 那颗按段号写死的地雷已经拆掉。改锁**回池后的契约**:
	var _tgt_rare := 0
	for e in DB.jokers():
		if String(e["kind"]) == "target":
			# ① 每张 Target 都要有稀有度档 —— 它们现在真的进货架抽取,
			#    空字符串会让 `DRAFT_RARITY_WEIGHTS.get(rarity, 1)` 静默退到权重 1
			#    (比 rare 的 5 还低), 换旗率变成一个没人写下来的数。
			t.check(String(e.get("rarity", "")) != "", "target %s has a rarity tier" % e["id"])
			if String(e.get("rarity", "")) == "rare":
				_tgt_rare += 1
	t.check(_tgt_rare > 0, "targets sit in a real rarity tier")
	# ③ 独狼的换旗保证是**写在卡面上**的效果, 不是暗改概率
	#    (2026-08-06 用户: 「独狼是一定要换旗的」+ 早先拍板「不应该有任何卡有固定概率」
	#     —— 两者只有一种活法: 把保证写到卡上。所以这条既锁机制也锁卡面文字。)
	# 2026-08-07 从「×3 权重」升级成「**必定**出 Target」(用户批 A 案):
	# 独狼重做成经济/节奏卡后, **拖的代价是确定的**而**换的回报只有 52% 会发生** ——
	# 确定的代价配概率的回报, 期望上必然吃亏。做成必定, 两头才对称。
	var _wolf := Joker.by_id("lonewolf")
	t.check(_wolf.shelf_target_guaranteed(), "lone wolf guarantees a Target on the shelf")
	t.check(_wolf.fx_text.contains("Target"), "and its card text says so")
	t.check(Joker.slots_guarantee_target([_wolf, null, null, null]),
		"the slot-wide check picks it up")
	t.check(not Joker.slots_guarantee_target([Joker.by_id("twin"), null, null, null]),
		"other targets do not touch the shelf")
	# ② 首张免费、之后按档收费 —— 免费三选一是 Target 唯一保留的特例。
	var _t0 = Joker.by_id("twin")
	t.eq(Economy.joker_price(_t0, false), 0, "first Target is free")
	t.eq(Economy.joker_price(_t0, true), int(GameConfig.JOKER_PRICES["rare"]),
		"a later Target costs its rarity price, not a bespoke swap price")
	for i in range(1, GameConfig.SECTION_TARGETS.size()):
		var prev: int = GameConfig.SECTION_TARGETS[i - 1]
		var cur: int = GameConfig.SECTION_TARGETS[i]
		if GameConfig.is_wall(i - 1) and not GameConfig.is_wall(i):
			continue  # post-wall breather may step back (faces carry the wall)
		t.check(cur > prev, "targets climb at S%d" % (i + 1))

# --- Run state machine (docs/design/tech.md: progression lives in core/run.gd) ---
func _test_run_machine(t) -> void:
	var r := Run.new()
	r.reset(7)                                   # seeded face roll, deterministic
	t.eq(r.section_idx, 0, "run starts at S1")
	for w in GameConfig.WALL_SECTIONS:
		t.check(r.run_faces.has(w), "face rolled for wall S%d" % (w + 1))
	r.section_score = 999999
	var out := r.advance()
	for i in range(GameConfig.PHRASES_PER_SECTION - 1):
		t.check(not bool(out["section_done"]), "mid-section keeps going")
		out = r.advance()
	t.check(bool(out["section_done"]), "section closes after 6 phrases")
	t.check(bool(out["cleared"]), "score over target clears")
	t.check(bool(out["is_wall"]), "S1 is a wall")
	r.next_section()
	t.eq(r.section_idx, 1, "advance to S2")
	t.eq(r.section_score, 0, "score resets")

	# --- Beat: 游戏和模型共用的那一份编排 (docs/design/tech.md) ---
	# ⚠ 这里锁的是**顺序契约**, 不是分数: `first_kind` 必须在 Settle 之后才更新
	# (setlist 锁的是本段第一拍打的牌型, 而第一拍自己不受锁约束 —— 先更新就把锁
	# 套在了它自己头上), 而 `prev_kind` 每拍都更新。
	var br := Run.new()
	br.reset(7)
	br.run_faces = {}                            # 不挂脸: 这里测编排, 不测脸
	br.phrase_in_section = 0
	t.eq(br.stage, Run.Stage.DECISION, "a run starts a phrase in DECISION")
	var bp := Phrase.new(br.deck, br.cache, br.coins)
	bp.start()
	var bo := Beat.settle(br, bp, {"late": false, "early": false})
	t.eq(br.stage, Run.Stage.SETTLED, "settle moves the stage forward")
	t.check(bo.has("res"), "settle hands back the raw pattern result too")
	t.eq(br.first_kind, int(bo["res"].get("kind", -99)), "the opening phrase sets first_kind")
	t.eq(br.prev_kind, int(bo["res"].get("kind", -99)), "and prev_kind")
	t.eq(br.section_score, int(bo["score"]), "the section ledger took the score")
	t.eq(br.coins, bp.coins, "the run carries the phrase's coins out")
	Beat.phrase_end(br, bp, {"early": false})
	t.eq(br.stage, Run.Stage.ENDED, "phrase_end closes the phrase")
	# 第二拍: first_kind 不许再动 —— 它是**本段第一拍**的牌型
	br.stage = Run.Stage.DECISION
	br.phrase_in_section = 1
	var locked := br.first_kind
	var bp2 := Phrase.new(br.deck, br.cache, br.coins)
	bp2.start()
	Beat.settle(br, bp2, {})
	t.eq(br.first_kind, locked, "a later phrase must NOT move first_kind")
	Beat.phrase_end(br, bp2, {})

	# --- raisedbar: the one face that is honestly a difficulty knob ---
	var tr := Run.new()
	tr.reset(7)
	tr.section_idx = 0
	var plain: int = GameConfig.SECTION_TARGETS[0]
	tr.run_faces[0] = ""
	t.eq(tr.target(), plain, "no face -> the table's own target")
	tr.run_faces[0] = "raisedbar"
	t.eq(tr.target(), int(round(float(plain) * 1.5)), "raisedbar raises this section's bar")
	tr.run_faces[0] = "norepeat"
	t.eq(tr.target(), plain, "a rule face does NOT move the bar")
	# deficit() must read the raised bar too, or the shop board lies to you
	tr.run_faces[0] = "raisedbar"
	tr.section_score = plain
	t.eq(tr.deficit(), int(round(float(plain) * 1.5)) - plain, "deficit follows the raised bar")

	# --- setlist's lock is per-SECTION state and must reset at the boundary ---
	var lr := Run.new()
	lr.reset(7)
	t.eq(lr.first_kind, -99, "a fresh run has nothing locked")
	lr.first_kind = Pattern.Kind.FLUSH
	lr.next_section()
	t.eq(lr.first_kind, -99, "a new blind opens with the lock cleared")

	# Finale boon is rolled with the run but remains hidden until section four.
	var boon_run := Run.new()
	boon_run.reset(712)
	t.check(BlindBoon.ids().has(boon_run.run_boon), "a run rolls one approved finale boon")
	t.eq(boon_run.boon(), "", "the boon is hidden before round four")
	boon_run.section_idx = GameConfig.SECTIONS_PER_RUN - 1
	t.eq(boon_run.boon(), boon_run.run_boon, "entering round four reveals the rolled boon")
	# ⚑ 2026-08-26 倒计时进 T4 池:随机局第四段可能掷到它(首两拍 8 秒),
	# 断言的本意是「爽点不动钟」—— 把脸钉成赶场, 别让掷点决定测试。
	boon_run.run_faces[GameConfig.SECTIONS_PER_RUN - 1] = "rush"
	for boon_id in BlindBoon.ids():
		boon_run.run_boon = boon_id
		t.eq(boon_run.phrase_duration(), 6.0, "%s never changes Rush timing" % boon_id)

	# Request goals never repeat consecutively; the opening phrase cannot ask
	# for a different hand from a previous phrase that does not exist.
	var request_run := Run.new()
	request_run.reset(713)
	request_run.run_faces[0] = "request"
	request_run.phrase_in_section = 0
	var first_goal: String = request_run.next_request_goal()
	t.check(first_goal != "fresh_kind", "the opening request never references a previous hand")
	var previous_goal: String = first_goal
	for _i in range(12):
		request_run.phrase_in_section = 1
		var goal: String = request_run.next_request_goal()
		t.check(goal != previous_goal, "request goals do not repeat consecutively")
		previous_goal = goal
	# With a live phrase supplied, the roll is filtered to goals the current
	# visible state can actually reach without gambling on a hidden draw.
	var valid_phrase := Phrase.new(Deck.new(1713), [], 50)
	valid_phrase.mod = "request"
	valid_phrase.start()
	valid_phrase.hand = [t._c(2, 0), t._c(3, 0), t._c(4, 0), t._c(5, 0), t._c(6, 0)]
	valid_phrase.cache = [t._c(7, 0), t._c(8, 0), t._c(9, 0)]
	request_run.request_last = ""
	var validated_goal := request_run.next_request_goal(valid_phrase)
	t.check(validated_goal not in ["color_mix", "face_or_ace"],
		"request roll excludes goals invalid for the dealt phrase")
	request_run.phrase_in_section = 0
	request_run.request_last = "initial_cache"
	t.eq(request_run.next_request_goal(valid_phrase), "initial_cache",
		"request keeps the only valid public goal instead of producing an empty beat")

	# Ration is shared across the whole section, not reset each phrase.
	var ration_run := Run.new()
	ration_run.reset(714)
	ration_run.run_faces[0] = "ration"
	var ration_p1 := Beat.begin(ration_run)
	t.eq(ration_p1.discard_budget, 12, "ration starts with twelve cards")
	t.check(ration_p1.discard_selected([0, 1, 2, 3, 4], [0, 1, 2]), "ration can spend eight cards")
	Beat.settle(ration_run, ration_p1)
	t.eq(ration_run.section_discards_used, 8, "the run records spent ration cards")
	Beat.phrase_end(ration_run, ration_p1)
	ration_run.phrase_in_section = 1
	var ration_p2 := Beat.begin(ration_run)
	t.eq(ration_p2.discard_budget, 4, "the next phrase receives only the remaining ration")
	t.check(not ration_p2.discard_selected([0, 1, 2, 3, 4]), "ration rejects five when four remain")

	# Trilogy(裁决 #8, 2026-08-13):种数配额是**税**不是硬门 —— 缺一种目标升一档
	# (悲观实时:段首欠满额, 覆盖一种降一档), 判生死只比分数。罚档从数据推导, 不手抄。
	var trilogy_run := Run.new()
	trilogy_run.reset(715)
	trilogy_run.run_faces[2] = "trilogy"
	trilogy_run.section_idx = 2
	var tri_pen := SectionMod.variety_penalty("trilogy")
	t.check(tri_pen > 0.0, "trilogy declares a variety penalty")
	trilogy_run.section_kinds = {Pattern.Kind.PAIR: true, Pattern.Kind.FLUSH: true,
		Pattern.Kind.STRAIGHT: true}
	var tri_base := trilogy_run.target()
	trilogy_run.section_kinds = {Pattern.Kind.PAIR: true, Pattern.Kind.FLUSH: true}
	t.eq(trilogy_run.target(), int(round(float(tri_base) * (1.0 + tri_pen))),
		"one missing Trilogy type raises the target one step")
	trilogy_run.section_kinds = {}
	t.eq(trilogy_run.target(), int(round(float(tri_base) * (1.0 + tri_pen * 3.0))),
		"an untouched section owes the full variety tax (pessimistic-live)")
	# 判生死:分数够基准、缺一种 → 税后目标没够 = 不过;补上第三种 → 目标回落 = 过
	trilogy_run.section_kinds = {Pattern.Kind.PAIR: true, Pattern.Kind.FLUSH: true}
	trilogy_run.section_score = tri_base + 1
	trilogy_run.phrase_in_section = GameConfig.PHRASES_PER_SECTION - 1
	t.check(not bool(trilogy_run.advance()["cleared"]),
		"base-target score cannot clear while one type is missing")
	trilogy_run.section_kinds[Pattern.Kind.STRAIGHT] = true
	trilogy_run.phrase_in_section = GameConfig.PHRASES_PER_SECTION - 1
	t.check(bool(trilogy_run.advance()["cleared"]),
		"covering the third type drops the bar back and clears")

	# Double Set adds one score-only replay after the normal settlement.
	var double_run := Run.new()
	double_run.reset(716)
	double_run.section_idx = GameConfig.SECTIONS_PER_RUN - 1
	double_run.run_faces[double_run.section_idx] = "rush"
	double_run.run_boon = "doubleset"
	var double_phrase := Beat.begin(double_run)
	var double_out := Beat.settle(double_run, double_phrase)
	t.eq(double_out["score"], int(double_out["raw_score"]) + int(round(
		float(double_out["raw_score"]) * BlindBoon.score_replay_factor("doubleset"))),
		"Double Set adds half the raw score once")
	t.eq(double_run.section_score, double_out["score"], "the section ledger receives the boon total once")

	# Afterglow reads the previous raw score, never a total that already contains
	# an earlier Afterglow addition.
	var glow_run := Run.new()
	glow_run.reset(717)
	glow_run.section_idx = GameConfig.SECTIONS_PER_RUN - 1
	glow_run.run_faces[glow_run.section_idx] = "rush"
	glow_run.run_boon = "afterglow"
	glow_run.previous_raw_score = 1000
	var glow_p1 := Beat.begin(glow_run)
	var glow_o1 := Beat.settle(glow_run, glow_p1)
	t.eq(glow_o1["boon_bonus"], 100, "Afterglow reads the supplied previous raw score")
	var first_raw := int(glow_o1["raw_score"])
	Beat.phrase_end(glow_run, glow_p1)
	glow_run.phrase_in_section = 1
	var glow_p2 := Beat.begin(glow_run)
	var glow_o2 := Beat.settle(glow_run, glow_p2)
	t.eq(glow_o2["boon_bonus"], int(round(float(first_raw) * 0.1)),
		"Afterglow chains from raw score rather than the prior boon total")
	r.section_idx = 1
	r.phrase_in_section = GameConfig.PHRASES_PER_SECTION - 1
	r.section_score = 0
	out = r.advance()
	t.check(bool(out["section_done"]) and not bool(out["cleared"]), "miss = fail")
	t.check(bool(out["is_wall"]), "S2 is a wall")
	t.check(not bool(out["finale"]), "S2 is not the finale")
	r.section_idx = GameConfig.SECTIONS_PER_RUN - 1
	r.phrase_in_section = GameConfig.PHRASES_PER_SECTION - 1
	out = r.advance()
	t.check(bool(out["finale"]), "the last section is the finale")



## 2026-08-21 外部审查:RunLoop.fork 漏拷七个字段 ⇒ 买牌推演的世界与本尊分叉。
## 这里把「本尊上能设的字段」全设上, fork 之后逐一对比 —— 新加字段要么进 fork 要么在这里红。
func _t_fork_complete(t) -> void:
	var RL = load("res://tools/runloop.gd")
	# 探针世界的 boon:缺省 AUTO = 掷一张(与游戏同池, 独立流, 按 deck_seed 确定);"" = 明确无
	t.eq(RL.Opts.new().boon, RL.BOON_AUTO, "RunLoop.Opts rolls a boon by default (probe world has boons)")
	t.check(BlindBoon.ids().has(RL.roll_boon(5)), "roll_boon draws from the approved boon pool")
	t.eq(RL.roll_boon(5), RL.roll_boon(5), "roll_boon is deterministic per deck_seed")
	var spread := {}
	for sd in range(40):
		spread[RL.roll_boon(sd)] = true
	t.check(spread.size() >= 2, "roll_boon varies across deck seeds (not one boon forever)")
	var r := Run.new()
	r.deck = Deck.new(7)
	r.run_faces = {0: "norepeat", 1: "request", 2: "ration", 3: "rush"}
	r.run_boon = "doubleset"
	r.section_idx = 2
	r.phrase_in_section = 3
	r.section_score = 123
	r.phrase_index = 15
	r.prev_kind = 4
	r.first_kind = 2
	r.section_discards_used = 5
	r.section_kinds = {2: true, 4: true}
	r.cache_meta = {"ages": {"x": 3}, "next": 9}
	r.previous_raw_score = 777
	r.request_last = "color_mix"
	r.coins = 11
	r.tutorial = false
	var f: Run = RL.fork(r, 42)
	for k in ["run_boon", "section_idx", "phrase_in_section", "section_score", "phrase_index",
			"prev_kind", "first_kind", "section_discards_used", "previous_raw_score",
			"request_last", "coins", "tutorial"]:
		t.eq(f.get(k), r.get(k), "fork copies %s" % k)
	t.eq(f.section_kinds, r.section_kinds, "fork copies section_kinds")
	t.eq(f.cache_meta, r.cache_meta, "fork copies cache_meta")
	t.eq(f.run_faces, r.run_faces, "fork copies run_faces")
	f.section_kinds[9] = true
	t.check(not r.section_kinds.has(9), "fork's section_kinds is a copy, not an alias")
	f.cache_meta["ages"]["y"] = 1
	t.check(not r.cache_meta["ages"].has("y"), "fork's cache_meta is a deep copy")


	# --- 断点续玩:snapshot → JSON 圆环 → restore(2026-08-24)---
	# 快照就是这么存进 user:// 的(JSON.stringify), 所以圆环必须过 JSON:
	# int 键变字符串、类型收窄, 全在这一环里现形。
	var sr := Run.new()
	sr.reset(4242)
	sr.section_idx = 2
	sr.phrase_index = 13
	sr.phrase_in_section = 1
	sr.section_score = 777
	sr.prev_kind = 3
	sr.first_kind = 5
	sr.previous_raw_score = 456
	sr.request_last = "color_mix"
	sr.run_faces = {0: "norepeat", 2: "rush"}
	sr.run_boon = "spotlight"
	sr.coins = 23
	sr.section_discards_used = 4
	sr.section_kinds = {2: true, 4: true}
	sr.cache = [t._c(9, 1), t._c(12, 2), t._c(7, 0)]
	sr.cache_meta = {"ages": {sr.cache[0]: 4, sr.cache[2]: 6}, "next": 7}
	sr.joker_slots[0] = Joker.by_id("twin")
	sr.joker_slots[2] = Joker.by_id("vinyl")
	sr.joker_slots[2].state = {"n": 7}
	for _i in range(5):
		sr.deck.discard(sr.deck.draw())   # 两堆都攒点内容, 顺序才有的可验
	var snap: Dictionary = sr.snapshot(9)
	snap = JSON.parse_string(JSON.stringify(snap))
	var rr := Run.new()
	rr.reset(1)
	t.check(rr.restore(snap), "restore 认得 JSON 圆环后的快照")
	for k2 in ["section_idx", "phrase_index", "phrase_in_section", "section_score",
			"prev_kind", "first_kind", "previous_raw_score", "request_last",
			"run_boon", "coins", "section_discards_used"]:
		t.eq(rr.get(k2), sr.get(k2), "restore 还原 %s" % k2)
	t.eq(rr.run_faces, sr.run_faces, "restore 还原 run_faces(int 键从 JSON 字符串键转回)")
	t.eq(rr.section_kinds, sr.section_kinds, "restore 还原 section_kinds(集合语义原样)")
	t.eq(rr.cache.size(), 3, "缓存三张都在")
	t.eq(rr.cache[1].label(), sr.cache[1].label(), "缓存的牌面一致")
	t.eq(int(rr.cache_meta["ages"][rr.cache[0]]), 4, "缓存年龄按下标重挂到新实例上")
	t.check(not rr.cache_meta["ages"].has(rr.cache[1]), "没记年龄的格子不凭空长出年龄")
	t.eq(int(rr.cache_meta["next"]), 7, "年龄计数器还原")
	t.eq(String(rr.joker_slots[0].id), "twin", "槽 0 的卡还原")
	t.check(rr.joker_slots[1] == null, "空槽还是空槽")
	t.eq(int(rr.joker_slots[2].state.get("n", 0)), 7, "成长计数器还原")
	t.check(not rr.tutorial, "恢复的局恒是正式局")
	t.eq(rr.stage, Run.Stage.DECISION, "恢复落在拍边界 = DECISION")
	t.eq(int(snap.get("run_index", -1)), 9, "快照带着局数(恢复不重新 note_run_started)")
	# 牌堆:同一副堆序 —— 连抽五张逐张同面
	for _j in range(5):
		t.eq(rr.deck.draw().label(), sr.deck.draw().label(), "恢复后的堆序逐张一致")
	t.eq(rr.deck.discard_pile.size(), sr.deck.discard_pile.size() - 0, "弃牌堆同长")
	# 坏快照:不认就拒, 不许半恢复
	t.check(not Run.new().restore({}), "空快照被拒")
	t.check(not Run.new().restore({"v": 99, "deck": {}, "faces": {}}), "未知版本被拒")

## 达标即收工(2026-08-27 用户拍板 A 案):段分独立不变, 补 cash out 出口。
func _t_cashout(t) -> void:
	var r := Run.new()
	r.reset(1)
	r.section_idx = 0
	r.phrase_in_section = 2
	r.section_score = 0
	t.check(not r.can_cash_out(), "没达标不能收工")
	r.section_score = r.target()
	t.check(r.can_cash_out(), "达标即可收工")
	t.eq(r.phrases_left(), GameConfig.PHRASES_PER_SECTION - 2, "剩余拍数按已打拍算")
	var out: Dictionary = r.advance(true)
	t.check(bool(out["section_done"]), "收工 = 直接推到段边界")
	t.check(bool(out["cleared"]), "收工时段分已达标 ⇒ 判过关")
	t.eq(r.phrases_left(), 0, "收工后没有剩余拍")
	# 打满的老路径逐位不变(收工是新增出口, 不许改既有行为)
	var r2 := Run.new()
	r2.reset(1)
	r2.phrase_in_section = GameConfig.PHRASES_PER_SECTION - 1
	r2.section_score = r2.target()
	var out2: Dictionary = r2.advance()
	t.check(bool(out2["section_done"]) and bool(out2["cleared"]), "打满达标照旧过关")
	t.check(not r2.can_cash_out(), "最后一拍打完没有剩余拍, 收工键不该出现")
	# 落袋算术:每剩一拍固定单价, 0 拍不给钱
	t.eq(Economy.cashout(3), 3 * GameConfig.CASHOUT_PER_PHRASE, "落袋 = 剩余拍 × 单价")
	t.eq(Economy.cashout(0), 0, "没剩拍不落袋")
	t.check(GameConfig.CASHOUT_PER_PHRASE > 0, "单价必须为正 —— 否则收工是纯亏, 键等于骗人")
