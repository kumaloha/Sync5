extends RefCounted

# --- META 资产层(core/asset.gd)—— 「买资产 → 变现 → 买更多」循环的纯函数直测 ---
#
# ⚠ 与 t_ticket 同一个格局:不测 SaveState 的壳(探针闸挡着, 测到的只会是闸),
# 测接字典的簿记层。SaveState 侧只验「探针恒空」——那条闸本身就是契约。

func run(t) -> void:
	# ---- 数据面 ----
	var ids := Asset.ids()
	t.check(ids.size() >= 6, "asset ladder has at least six rungs (got %d)" % ids.size())
	var last := 0
	for id in ids:
		t.check(Asset.price(String(id)) >= last, "ladder ordered by price (db locks it too)")
		last = Asset.price(String(id))
		var has_outlet: bool = Asset.yield_gems(String(id)) > 0 \
			or Asset.ticket_of(String(id)) != "" \
			or Asset.track_of(String(id)) != "" \
			or Asset.flair_of(String(id)) != ""
		t.check(has_outlet, "every asset has an outlet (%s)" % id)
	t.check(Asset.gems_per_section() >= 0 and Asset.full_clear_bonus() >= 0,
		"base gem income is non-negative")
	t.eq(Asset.price("nosuch"), 0, "unknown asset prices at 0")

	# ---- 买入:每种一件, 钱不够不卖, 扣款入账一次完成 ----
	var a0 := String(ids[0])
	var d := {"gems": Asset.price(a0) - 1}
	t.check(not Asset.can_buy(d, a0), "one gem short: no sale")
	t.check(not Asset.buy(d, a0), "buy refuses when can_buy is false")
	d["gems"] = Asset.price(a0) + 5
	t.check(Asset.buy(d, a0), "affordable: sold")
	t.eq(int(d["gems"]), 5, "price deducted exactly")
	t.check(Asset.has_asset(d, a0), "ownership recorded")
	t.check(not Asset.can_buy(d, a0), "one of each: no double-buy")
	t.check(not Asset.buy({"gems": 9999}, "nosuch"), "unknown id never sells")

	# ---- 出口面(v2, 2026-08-19 晚拍板「买了就想玩」):内容三类 + 零分红 ----
	var track_assets: Array = []
	var flair_assets: Array = []
	var ticket_assets: Array = []
	for id in ids:
		if Asset.track_of(String(id)) != "":
			track_assets.append(String(id))
		if Asset.flair_of(String(id)) != "":
			flair_assets.append(String(id))
		if Asset.ticket_of(String(id)) != "":
			ticket_assets.append(String(id))
	t.check(track_assets.size() >= 4, "vinyl rack exists (got %d)" % track_assets.size())
	t.check(flair_assets.size() >= 2 and ticket_assets.size() >= 2,
		"flair and deal assets exist")
	t.eq(Asset.flair_of("turntable"), "homejuke", "turntable unlocks home ambience")

	# ---- 赛季脚手架(meta.md §4 批 B):下架 ≠ 没收 ----
	t.eq(Asset.season_now(), "", "no active season at ship")
	for id in ids:
		t.check(Asset.on_shelf(String(id)), "evergreen assets are always on shelf (%s)" % id)

	# ---- 探索型货架:boost 空表逐字节退回(sim/bot/探针的随机流一位不能漂)----
	var cands: Array = []
	for e in DB.jokers().slice(0, 6):
		cands.append(Joker.new(e))
	var r1 := RandomNumberGenerator.new()
	var r2 := RandomNumberGenerator.new()
	r1.seed = 4242
	r2.seed = 4242
	var pick_a := Economy.weighted_pick(cands, 3, 1.0, r1, {})
	var pick_b := Economy.weighted_pick(cands, 3, 1.0, r2, {}, {})
	t.eq(pick_a.size(), pick_b.size(), "empty boost: same shelf size")
	for i in range(pick_a.size()):
		t.eq(String(pick_a[i].id), String(pick_b[i].id), "empty boost is byte-identical")
	t.eq(r1.state, r2.state, "empty boost consumes identical RNG")
	# ⚠ 上面三条比的是「缺省实参 vs 显式同值」—— 2026-08-21 评审指出这是恒真。真正的契约是
	# **非空 boost 必须改变分布**:给 b 乘 1000, 200 个种子里 b 必须几乎总在第一位。
	var two: Array = [cands[0], cands[1]]
	var b_first := 0
	for sd in range(200):
		var rr := RandomNumberGenerator.new()
		rr.seed = 1000 + sd
		var pk := Economy.weighted_pick(two, 1, 1.0, rr, {}, {String(two[1].id): 1000.0})
		if String(pk[0].id) == String(two[1].id):
			b_first += 1
	t.check(b_first >= 190, "non-empty boost actually moves the draw (b first %d/200)" % b_first)
	var a_first := 0
	for sd in range(200):
		var rr := RandomNumberGenerator.new()
		rr.seed = 1000 + sd
		var pk := Economy.weighted_pick(two, 1, 1.0, rr, {}, {})
		if String(pk[0].id) == String(two[0].id):
			a_first += 1
	t.check(a_first > 10 and a_first < 190, "without boost neither card dominates (a first %d/200)" % a_first)
	# 「没有回本周期」= 出厂 roster 零分红(yield_gems 机制留在代码里, 表里不用)
	var all_owned := {"gems": 0, "assets": ids.duplicate()}
	t.eq(Asset.run_yield(all_owned), 0,
		"v2 roster pays no dividends (user: no payback-period math)")
	var d2 := {"gems": 0, "assets": [track_assets[0], ticket_assets[0], flair_assets[0]]}
	var daily := Asset.daily_ticket_ids(d2)
	t.eq(daily.size(), 1, "one ticket deal grants one daily ticket")
	t.eq(String(daily[0]), Asset.ticket_of(ticket_assets[0]), "…of the deal's ticket type")
	t.eq(Asset.owned_tracks(d2), [Asset.track_of(track_assets[0])],
		"owned vinyls map to their tracks")
	t.check(Asset.has_flair(d2, Asset.flair_of(flair_assets[0])), "owned flair detected")
	t.check(not Asset.has_flair({}, "confetti"), "no assets, no flair")

	# ---- 歌单池(Music.track_pool, 纯静态):免费首曲恒在, 唱片只进自己的场馆 ----
	var mus = load("res://view/music.gd")
	for sec in range(4):
		var base_pool: Array = mus.track_pool(sec, [])
		t.eq(base_pool.size(), 1, "venue %d starts with exactly its free track" % sec)
	var venue1_extra := String(mus.VENUES[1][1])
	var with_own: Array = mus.track_pool(1, [venue1_extra])
	t.eq(with_own.size(), 2, "owned vinyl joins its venue's pool")
	t.check(with_own.has(String(mus.VENUES[1][0])), "free track never leaves the pool")
	t.eq(mus.track_pool(0, [venue1_extra]).size(), 1,
		"a club vinyl does not leak into the small bar")
	# roster 的每个 track 都真的属于某个场馆池(接错场馆 = 买了永远轮不到的唱片)
	for aid in track_assets:
		var tr := Asset.track_of(String(aid))
		var found := false
		for v in mus.VENUES:
			if (v as Array).has(tr):
				found = true
		t.check(found, "track '%s' belongs to a venue pool" % tr)

	# ---- 校验面(静默错的形状)----
	var base := {"gems": {"per_section": 1, "full_clear_bonus": 2}, "season_now": "",
		"profile": {"xp_source": "sections", "levels": [{"xp": 0, "cn": "甲", "name": "A"}, {"xp": 3, "cn": "乙", "name": "B"}]}}
	var mk := func(assets: Array) -> Dictionary:
		var out := base.duplicate(true)
		out["assets"] = assets
		return out
	var good := {"id": "x", "cn": "甲", "name": "X", "cn_fx": "每局分红 +1 宝石",
		"price": 5, "yield_gems": 1}
	t.eq(DB.validate_assets(mk.call([good])), "", "well-formed roster validates clean")
	# ---- 玩家档案等级(meta.md §8, 2026-08-22 拍板:参与度等级, 零数值)----
	var shipped: Array = DB.assets().get("profile", {}).get("levels", [])
	t.check(shipped.size() >= 5, "shipped profile has a ladder (≥5 levels)")
	t.eq(int(shipped[0]["xp"]), 0, "first level starts at 0 xp (a new player is LV.1, not LV.0)")
	var l0 := Asset.level_for(0)
	t.eq(int(l0["level"]), 1, "0 sections ⇒ LV.1")
	t.eq(int(l0["xp"]), 0, "0 sections ⇒ 0 xp into the level")
	t.eq(int(l0["xp_max"]), int(shipped[1]["xp"]), "LV.1 span = next threshold")
	var thr2 := int(shipped[1]["xp"])
	t.eq(int(Asset.level_for(thr2)["level"]), 2, "reaching the 2nd threshold ⇒ LV.2")
	t.eq(int(Asset.level_for(thr2 - 1)["level"]), 1, "one short of the threshold stays LV.1")
	t.eq(int(Asset.level_for(thr2 + 1)["xp"]), 1, "xp is counted from the level's own floor")
	var top := Asset.level_for(int(shipped[shipped.size() - 1]["xp"]) + 999)
	t.eq(int(top["level"]), shipped.size(), "past the last threshold ⇒ top level")
	t.eq(int(top["xp_max"]), 0, "top level has no span (bar renders full)")
	t.check(String(top["title"].get("cn", "")) != "" and String(top["title"].get("name", "")) != "",
		"every level carries a bilingual title")
	t.check(not SaveState.profile().has("coins"), "profile has no cross-run coin (chip deleted 08-22)")
	t.eq(int(SaveState.profile()["level"]), 1, "probe/new player profile is LV.1")
	# 表形状校验:乱序 / 首档非 0 / 带数值键 / 缺双语 都红
	var pbad: Dictionary = mk.call([good])
	pbad["profile"] = {"xp_source": "sections", "levels": [{"xp": 0, "cn": "甲", "name": "A"}, {"xp": 0, "cn": "乙", "name": "B"}]}
	t.check(DB.validate_assets(pbad) != "", "non-ascending level xp rejected")
	pbad["profile"] = {"xp_source": "sections", "levels": [{"xp": 2, "cn": "甲", "name": "A"}]}
	t.check(DB.validate_assets(pbad) != "", "first level must start at 0")
	pbad["profile"] = {"xp_source": "sections", "levels": [{"xp": 0, "cn": "甲", "name": "A", "mult": 1.1}]}
	t.check(DB.validate_assets(pbad) != "", "a level carrying a numeric perk is rejected (零数值红线)")
	pbad["profile"] = {"xp_source": "score", "levels": [{"xp": 0, "cn": "甲", "name": "A"}]}
	t.check(DB.validate_assets(pbad) != "", "xp must come from participation, not score")
	pbad["profile"] = {"xp_source": "sections", "levels": [{"xp": 0, "cn": "甲"}]}
	t.check(DB.validate_assets(pbad) != "", "level without an English title rejected")
	var dup := [good, good]
	t.check(DB.validate_assets(mk.call(dup)) != "", "duplicate id rejected")
	var badtk := good.duplicate()
	badtk["id"] = "y"
	badtk["ticket"] = "nosuchticket"
	t.check(DB.validate_assets(mk.call([badtk])) != "",
		"unknown ticket ref rejected (would silently never grant)")
	var deco := {"id": "z", "cn": "乙", "name": "Z", "cn_fx": "空", "price": 5}
	t.check(DB.validate_assets(mk.call([deco])) != "",
		"asset with no outlet rejected (pure decoration)")
	var badtrack := {"id": "v", "cn": "丙", "name": "V", "cn_fx": "空", "price": 5,
		"track": "99_nosuch_track"}
	t.check(DB.validate_assets(mk.call([badtrack])) != "",
		"vinyl pointing at a missing wav rejected (silent dead vinyl)")
	var goodtrack := badtrack.duplicate()
	goodtrack["track"] = "02_small_bar_nu_disco_lounge"
	t.eq(DB.validate_assets(mk.call([goodtrack])), "", "real track file validates")
	var badflair := {"id": "u", "cn": "丁", "name": "U", "cn_fx": "空", "price": 5,
		"flair": "fireworks"}
	t.check(DB.validate_assets(mk.call([badflair])) != "",
		"flair without a consumer rejected (whitelist)")
	var disorder := [good.duplicate(), good.duplicate()]
	disorder[1]["id"] = "w"
	disorder[1]["price"] = 3
	t.check(DB.validate_assets(mk.call(disorder)) != "", "price disorder rejected (the table IS the ladder)")

	# ---- SaveState 壳:探针恒空、绝不落盘 ----
	t.eq(SaveState.gems(), 0, "probe wallet is always empty")
	t.eq(SaveState.assets_owned().size(), 0, "probe owns nothing")
	t.check(not SaveState.buy_asset(a0), "probe cannot buy")
	t.eq(SaveState.settle_run_meta(true, 4, ["norepeat"]).size(), 0,
		"probe meta settlement is a no-op (and must not write the save)")
	t.eq(SaveState.streak(), 0, "probe streak is neutral")
	t.eq(SaveState.faces_seen().size(), 0, "probe has seen nothing")
