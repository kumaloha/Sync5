extends RefCounted

# --- Data config (design/tech.md): loader + validation ---
func run(t) -> void:
	t.eq(DB.load_error(), "", "all data files load clean")
	t.check(FileAccess.file_exists("res://data/boons.json"),
		"finale boons are configured independently from punitive faces")
	# 踩过两次的坑: sim 按 SECTIONS_PER_RUN 迭代, 表比段数长就被**静默截断**成
	# 一个放水盘(random 通关率一度从 0.8% 飙到 42%)。长度必须锁死在一起。
	t.eq(DB.sim()["bot_targets"].size(), GameConfig.SECTIONS_PER_RUN,
		"bot_targets has one entry per section")
	t.eq(int(DB.run()["phrases_per_section"]), 6, "run.json phrases per section")
	t.eq(int(DB.run()["phrases_per_shop"]), 3, "run.json phrases per shop")
	# the shop beat must divide the section evenly or the last "mid" break
	# would land on the section end
	t.check(DB.validate_run({"phrases_per_section": 6, "phrases_per_shop": 4}) != "",
		"non-divisible shop beat rejected")
	t.eq(int(DB.economy()["starting_coins"]), 6, "economy.json starting coins")
	# validation catches planted bad files
	t.check(DB.validate_run({"phrases_per_section": 5}) != "", "missing run key detected")
	t.check(DB.validate_economy({"starting_coins": 6, "typo_key": 1}) != "", "unknown economy key detected")
	t.eq(Character.roster().size(), 8, "8 characters from data")
	t.check(DB.validate_characters({"characters": [{"idx": 1, "cn": "x", "title": "t", "fx": "f"}]}) != "",
		"non-dense idx detected")
	t.eq(Joker.pool().size(), 60, "60 jokers from data (2026-08-13 三个子波毕;wrecker/trio/declutter/doggybag 是仪器债)")
	# 卡面文字随平衡改, 别抄死 —— 只锁「读得回来 + 符合 D2 的 ≤7 词」
	t.check(Joker.by_id("twin").fx_text.length() > 0, "joker text roundtrip")
	for oid in GameConfig.JOKER_PRICE_OVERRIDES:
		t.check(Joker.by_id(String(oid)) != null, "price override id '%s' exists" % oid)
	# ⚠ 夹具必须带 `proof` —— 否则 2026-08-09 加的「proof 必填」会**先**把它拦下,
	# 这条断言照样是绿的, 但它测的就不再是「未知谓词」了。
	# ⚠ 夹具同样必须带 `curve`(2026-08-10 必填)—— 理由同上面 proof 那条:
	# 缺了它断言照绿, 但测的就不再是「未知谓词」了。
	t.check(DB.validate_jokers({"jokers": [{"id": "x", "name": "X", "cn": "x", "kind": "support",
		"rarity": "common", "curve": "burst", "proof": "score", "fx": "f",
		"effects": [{"when": {"typo": 1}, "do": {"bonus": 1}}]}]}) != "",
		"unknown predicate detected")
	# 小丑牌的覆盖自证通路(design/jokers.md 验证方案)—— 漏声明必须直接红,
	# 否则一张新牌可以悄悄绕过 `tools/kit.gd` 那道门。和脸的 `proof` 同一条锁。
	var good_joker := {"id": "x", "name": "X", "cn": "x", "kind": "support",
		"rarity": "common", "curve": "burst", "proof": "score", "fx": "f"}
	t.eq(DB.validate_jokers({"jokers": [good_joker]}), "",
		"a joker with a declared proof channel validates (sanity check on the fixture)")
	var no_proof := good_joker.duplicate()
	no_proof.erase("proof")
	t.check(DB.validate_jokers({"jokers": [no_proof]}) != "",
		"a joker with no proof channel is rejected")
	var bad_proof := good_joker.duplicate()
	bad_proof["proof"] = "vibes"
	t.check(DB.validate_jokers({"jokers": [bad_proof]}) != "",
		"an unknown proof channel is rejected")
	# 每张现役牌都声明了 —— 这条防的是「加了新牌忘了声明」在真实数据上溜过去
	# ⚠ 清单从 DB._JOKER_PROOFS 推导, 不手抄(2026-08-12 加 shop 通路时这里红过一次)
	for e in DB.jokers():
		t.check(DB._JOKER_PROOFS.has(String(e.get("proof", ""))),
			"joker '%s' declares a known proof channel" % e.get("id", "?"))
	t.eq(int(DB.sim()["runs"]), 1000, "sim.json runs")
	t.check(DB.ui().has("stage"), "ui.json has stage")
	# faces.json 是纯数据表(2026-08-09 散文搬去 design/blinds.md)—— 与其余数据文件不同,
	# `_` 前缀键在这里**不**是免检的注释, 防的是散文悄悄长回来。
	var good_face := {"id": "x", "name": "X", "cn": "x", "fx": "f",
		"params": {"target_power": 0.5}, "proof": "score", "tier": 1}
	t.check(DB.validate_faces({"faces": [good_face]}) != "",
		"a lone tier with no fixed_tiers declaration is still rejected (sanity check on the fixture)")
	t.check(DB.validate_faces({"faces": [good_face], "_note": "hello"}) != "",
		"faces.json rejects an underscore-prefixed top-level key (prose must live in design/blinds.md)")
	var face_with_why := good_face.duplicate()
	face_with_why["_why"] = "hello"
	t.check(DB.validate_faces({"faces": [face_with_why]}) != "",
		"faces.json rejects a per-face _why key (prose must live in design/blinds.md §7)")
	var tape_face := good_face.duplicate(true)
	tape_face["proof"] = "tape"
	t.check(DB.validate_faces({"faces": [tape_face], "fixed_tiers": [1]}) != "",
		"'tape' is not a proof channel — proof stays model-side, gate has no tape arm to build")
	var rt_face := good_face.duplicate(true)
	rt_face["proof"] = "solver"
	rt_face["tape_required"] = true
	t.eq(DB.validate_faces({"faces": [rt_face], "fixed_tiers": [1]}), "",
		"real-time faces keep a model proof and declare tape_required separately")
