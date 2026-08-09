extends RefCounted

func run(t) -> void:
	_test_run_structure(t)
	_test_run_machine(t)


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
	# venue arc, shown on the home stage card (resources/home.html)
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
	# 加 8 次商店约 4.9 分钟(用户拍板 5 分钟上限)。见 design/levels.md。
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

# --- Run state machine (design/tech.md: progression lives in core/run.gd) ---
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

	# --- Beat: 游戏和模型共用的那一份编排 (design/tech.md) ---
	# ⚠ 这里锁的是**顺序契约**, 不是分数: `first_kind` 必须在 Settle 之后才更新
	# (setlist 锁的是本段第一拍打的牌型, 而第一拍自己不受锁约束 —— 先更新就把锁
	# 套在了它自己头上), 而 `prev_kind` 每拍都更新。
	var br := Run.new()
	br.reset(7)
	br.run_faces = {}                            # 不挂脸: 这里测编排, 不测脸
	br.character = Character.roster()[0]
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
