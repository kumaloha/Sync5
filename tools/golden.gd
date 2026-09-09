extends SceneTree

## 金样生成器(docs/design/mirror.md §6)—— Godot 侧算出「期望」, 写成 lua/golden/<族>.lua,
## Lua 镜像用 lua/check.lua 重放比对。**生成物手改无效**;改了 core/ 就重跑本脚本。
##   godot --headless --path . --script res://tools/golden.gd            # 全部六族
##   SYNC5_GOLDEN=rng,pattern godot --headless --path . --script res://tools/golden.gd
## ⚠ 浮点一律写成 H"<f64hex>"(IEEE 位串), 不写十进制 —— 两边 printf 的最后一位不可信。

const OUT_DIR := "res://lua/golden"

func _initialize() -> void:
	var only := OS.get_environment("SYNC5_GOLDEN")
	var fams := {
		"rng": Callable(self, "_fam_rng"),
		"pattern": Callable(self, "_fam_pattern"),
		"settle": Callable(self, "_fam_settle"),
		"fx": Callable(self, "_fam_fx"),
		"run": Callable(self, "_fam_run"),
		"visit": Callable(self, "_fam_visit"),
	}
	var n := 0
	for name in fams:
		if only != "" and not only.split(",").has(name):
			continue
		var body: String = fams[name].call()
		_write("%s/%s.lua" % [OUT_DIR, name], body)
		n += 1
	print("golden: wrote %d families" % n)
	quit(0)


func _write(path: String, body: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("golden: cannot write " + path)
		quit(1)
		return
	f.store_string("-- 由 tools/golden.gd 生成 —— 仪器输出, 手改无效(docs/design/mirror.md §6)\n")
	f.store_string(body)
	f.close()
	print("  wrote ", path, " (", body.length(), " chars)")


# ---------------------------------------------------------------- Lua 序列化

static func f64hex(x: float) -> String:
	var b := PackedFloat64Array([x]).to_byte_array()
	var s := ""
	for i in range(7, -1, -1):
		s += "%02x" % b[i]
	return s


static func state_hex(st: int) -> String:
	return "%08x%08x" % [(st >> 32) & 0xFFFFFFFF, st & 0xFFFFFFFF]


static func lstr(s: String) -> String:
	var out := "\""
	for ch in s:
		match ch:
			"\\": out += "\\\\"
			"\"": out += "\\\""
			"\n": out += "\\n"
			"\r": out += "\\r"
			"\t": out += "\\t"
			_: out += ch
	return out + "\""


## 任意 Variant → Lua 字面量。int → 十进制, float → H"hex", null → nil, Object → 走它的 to_golden()(若有)。
static func lua(v) -> String:
	match typeof(v):
		TYPE_NIL: return "nil"
		TYPE_BOOL: return "true" if v else "false"
		TYPE_INT: return "%d" % v
		TYPE_FLOAT: return "H\"%s\"" % f64hex(v)
		TYPE_STRING, TYPE_STRING_NAME: return lstr(String(v))
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			var parts: Array = []
			for e in v:
				parts.append(lua(e))
			return "{" + ",".join(parts) + "}"
		TYPE_DICTIONARY:
			var parts: Array = []
			for k in v:
				var ks: String
				if typeof(k) == TYPE_INT:
					ks = "[%d]" % k
				else:
					ks = "[%s]" % lstr(String(k))
				parts.append(ks + "=" + lua(v[k]))
			return "{" + ",".join(parts) + "}"
		TYPE_OBJECT:
			if v.has_method("to_golden"):
				return lua(v.to_golden())
			return lstr(str(v))
		_:
			return lstr(str(v))


# ---------------------------------------------------------------- rng 族

## 若干种子 × 混合调用序列;每一步的返回值都是期望。第 54 步记状态、第 104 步写回, 验 setter。
func _fam_rng() -> String:
	var seeds := [0, 1, -1, 2147483648, 4294967301, 700000, 9007199254740991, -123456789012, 90000, 41000,
		12345, 2026, 777, 31337, 65536, 4294967295, 8675309, 999999937, 3, 42]
	var cases: Array = []
	for s in seeds:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var ops: Array = []
		var saved := 0
		for k in range(200):
			match k % 5:
				0: ops.append(["i", rng.randi()])
				1: ops.append(["r", 0, k + 1, rng.randi_range(0, k + 1)])
				2: ops.append(["r", -7, 7, rng.randi_range(-7, 7)])
				3: ops.append(["f", rng.randf()])
				4:
					ops.append(["s", state_hex(rng.state)])
					if k == 54:
						saved = rng.state
					if k == 104:
						rng.state = saved
						ops.append(["S", state_hex(saved)])
		cases.append({"seed": s, "ops": ops})
	return "return " + lua(cases) + "\n"


# ---------------------------------------------------------------- pattern 族

static func cards_out(arr: Array) -> Array:
	var out: Array = []
	for c in arr:
		out.append([c.rank, c.suit])
	return out


static func labels(arr: Array) -> Array:
	var out: Array = []
	for c in arr:
		out.append(c.label())
	return out


## 1500 手:8 张(种子牌堆抽)+ 强制 0~5 张万能 + 16 种规则位组合(每三手带 false 键)。
## 期望 = evaluate_best 的全部字段 + best_score_of + 前五张的 score_five。
func _fam_pattern() -> String:
	var cases: Array = []
	var keys := ["shortcut", "fourfingers", "redtone", "blacktone"]
	for i in range(1500):
		var deck := Deck.new(41000 + i)
		var cards: Array = []
		for _j in range(8):
			cards.append(deck.draw())
		var w: int = 0 if i % 5 < 3 else (i % 3) + 1   # 四成带万能(全带时 Lua 5.5 重放要 30 s)
		if i % 97 == 0:
			w = 4
		if i % 193 == 0:
			w = 5
		for j in range(w):
			cards[j] = Card.new(Card.JOKER_RANK, 2 + (j % 2))
		var bits: int = i % 16
		var rules := {}
		for b in range(4):
			var on: bool = (bits >> b) & 1 == 1
			if on or i % 3 == 0:
				rules[keys[b]] = on
		var res: Dictionary = Pattern.evaluate_best(cards, rules)
		var five: Array = cards.slice(0, 5)
		cases.append({
			"cards": cards_out(cards), "rules": rules,
			"kind": int(res["kind"]), "name": String(res["name"]), "chips": int(res["chips"]),
			"pmult": int(res["pmult"]), "rank_sum": int(res["rank_sum"]), "score": int(res["score"]),
			"coins": int(res["coins"]), "resolved": labels(res["resolved"]),
			"best": Pattern.best_score_of(cards, rules),
			"five": Pattern.score_five(five, rules),
			"five_kind": int(Pattern.evaluate_best(five, rules)["kind"]),
		})
	return "return " + lua(cases) + "\n"


# ---------------------------------------------------------------- 共用:随机上下文

static func slots_out(slots: Array) -> Array:
	var out: Array = []
	for j in slots:
		if j == null:
			out.append(false)
		else:
			out.append({"id": j.id, "state": j.state.duplicate(true)})
	return out


static func popups_out(popups: Array) -> Array:
	var out: Array = []
	for p in popups:
		out.append([int(p["slot"]), String(p["text"])])
	return out


static func outcome_out(o: Dictionary) -> Dictionary:
	return {
		"score": int(o["score"]), "coins": int(o["coins"]), "base": int(o["base"]),
		"mult": float(o["mult"]), "bonus": int(o.get("bonus", 0)),
		"pattern_mult": float(o.get("pattern_mult", 1.0)), "joker_mult": float(o.get("joker_mult", 1.0)),
		"bonus_pct": float(o.get("bonus_pct", 0.0)), "target_hit": bool(o.get("target_hit", false)),
		"face_bit": bool(o.get("face_bit", false)), "popups": popups_out(o["popups"]),
	}


## 随机的一组槽:n 张, 0 号只放 target, 1..3 只放 support;计数器随机初值。
static func rand_slots(rng: RandomNumberGenerator, n: int, force_id: String = "") -> Array:
	var targets: Array = []
	var supports: Array = []
	for e in DB.jokers():
		if String(e["kind"]) == "target":
			targets.append(String(e["id"]))
		else:
			supports.append(String(e["id"]))
	var slots: Array = [null, null, null, null]
	var forced: Joker = null
	if force_id != "":
		forced = Joker.by_id(force_id)
	if forced != null and forced.kind == "target":
		slots[0] = forced
	elif n > 0 and rng.randi_range(0, 3) > 0:
		slots[0] = Joker.by_id(targets[rng.randi_range(0, targets.size() - 1)])
	var k := 1
	if forced != null and forced.kind != "target":
		slots[1] = forced
		k = 2
	while k <= 3 and k <= n:
		var sid: String = supports[rng.randi_range(0, supports.size() - 1)]
		var dup := false
		for j in slots:
			if j != null and j.id == sid:
				dup = true
		if not dup:
			slots[k] = Joker.by_id(sid)
		k += 1
	for j in slots:
		if j != null:
			# 按 counters 表(不是 state):没 init 的计数器(贝斯线的 n)在 state 里本来没有键。键名排序 = 两侧同序。
			var names: Array = j._counters.keys()
			names.sort()
			for cname in names:
				j.state[String(cname)] = float(rng.randi_range(0, 12))
	return slots


static func rand_cache(rng: RandomNumberGenerator, deck: Deck, i: int) -> Array:
	var cache: Array = []
	match i % 6:
		1:   # 三条
			var r := rng.randi_range(2, 14)
			for s in range(3):
				cache.append(Card.new(r, s))
		2:   # 顺
			var lo := rng.randi_range(2, 12)
			for s in range(3):
				cache.append(Card.new(lo + s, rng.randi_range(0, 3)))
		3:   # 全人头 / 同色
			for s in range(3):
				cache.append(Card.new(rng.randi_range(11, 13), 1 + (s % 2)))
		4:   # 同花
			var su := rng.randi_range(0, 3)
			for s in range(3):
				cache.append(Card.new(rng.randi_range(2, 14), su))
		_:
			for s in range(3):
				cache.append(deck.draw())
	if i % 11 == 0:
		cache[0] = Card.new(Card.JOKER_RANK, 2)
	return cache


static func rand_extra(rng: RandomNumberGenerator, deck: Deck, res: Dictionary, slots: Array, i: int) -> Dictionary:
	var faces: Array = SectionMod.pooled_ids()
	var mod := ""
	if i % 4 != 0:
		mod = String(faces[rng.randi_range(0, faces.size() - 1)])
	var section := rng.randi_range(0, 3)
	var kind: int = int(res.get("kind", -1))
	var prev_choices := [-99, kind, rng.randi_range(0, 9)]
	var lucks: Array = []
	for _k in range(rng.randi_range(0, 3)):
		lucks.append(float(rng.randi_range(0, 9999)) / 10000.0)
	var boosts: Array = []
	if i % 3 == 0:
		var bpool: Array = []
		for e in DB.consumables():
			if e.has("boost"):
				bpool.append(e["boost"])
		for _b in range(rng.randi_range(1, 2)):
			boosts.append((bpool[rng.randi_range(0, bpool.size() - 1)] as Dictionary).duplicate(true))
	var cache := rand_cache(rng, deck, i)
	var crs := 0
	for c in cache:
		crs += c.rank
	return {
		"prev_kind": prev_choices[rng.randi_range(0, 2)],
		"prev_target_hit": rng.randi_range(0, 1) == 1,
		"phrase_boosts": boosts,
		"rolled_suit": rng.randi_range(-1, 3),
		"callout_unsolved": rng.randi_range(0, 2) == 0,
		"luck_rolls": lucks,
		"odds_mult": Joker.slots_odds_mult(slots),
		"cache_rank_sum": crs if rng.randi_range(0, 1) == 1 else 0,
		"acted_late": rng.randi_range(0, 1) == 1,
		"discards": rng.randi_range(0, 3),
		"coins": rng.randi_range(0, 24),
		"phrase_idx": rng.randi_range(0, 5),
		"cache_cards": cache,
		"early_finish": rng.randi_range(0, 1) == 1,
		"acted_final": rng.randi_range(0, 2) == 0,
		"seconds_left": float(rng.randi_range(0, 80)) / 10.0,
		"early_discards": rng.randi_range(0, 1) == 1,
		"section_idx": section,
		"swaps": rng.randi_range(0, 3),
		"discard_batch_max": rng.randi_range(0, 8),
		"faces_discarded": rng.randi_range(0, 3),
		"swapped_scoring": rng.randi_range(0, 3),
		"section_score": rng.randi_range(0, 4000),
		"section_target": int(GameConfig.SECTION_TARGETS[section]) if rng.randi_range(0, 5) > 0 else 0,
		"mod": mod,
		"first_kind": prev_choices[rng.randi_range(0, 2)],
		"request_met": rng.randi_range(0, 2) > 0,
		"patch_restored": rng.randi_range(0, 3) == 0,
	}


static func extra_out(x: Dictionary) -> Dictionary:
	var o := x.duplicate(true)
	o["cache_cards"] = cards_out(x["cache_cards"])
	return o


static func rand_result(rng: RandomNumberGenerator, deck: Deck, i: int) -> Array:
	var cards: Array = []
	var n: int = 8 if i % 9 == 0 else 5
	for _j in range(n):
		cards.append(deck.draw())
	if i % 7 == 0:
		cards[0] = Card.new(Card.JOKER_RANK, 2)
	if i % 13 == 0:   # 凑对/三条, 让牌型谓词多触发
		cards[1] = Card.new(cards[0].rank if not cards[0].is_wild() else 9, (cards[0].suit + 1) % 4)
	var res: Dictionary = Pattern.evaluate_best(cards, {})
	var hidden := rng.randi_range(0, 2) if i % 5 == 0 else 0
	res["hidden_scoring"] = hidden
	return [cards, res, hidden]


# ---------------------------------------------------------------- settle 族

func _fam_settle() -> String:
	var cases: Array = []
	for i in range(1200):   # 2000 → 1200(2026-09-06 晚:金样进仓库, 每次重生成都是一份新 blob, 按重放成本与仓库体积定)
		var rng := RandomNumberGenerator.new()
		rng.seed = 52000 + i
		var deck := Deck.new(52000 + i)
		var rr := rand_result(rng, deck, i)
		var cards: Array = rr[0]
		var res: Dictionary = rr[1]
		var slots := rand_slots(rng, i % 5)
		var extra := rand_extra(rng, deck, res, slots, i)
		var extra_in := extra_out(extra)      # 结算会消耗 luck_rolls, 先存输入
		var outcome := Settle.run(res, slots, extra)
		cases.append({
			"cards": cards_out(cards), "hidden": int(rr[2]), "slots": slots_out(slots),
			"extra": extra_in, "out": outcome_out(outcome),
		})
	return "return " + lua(cases) + "\n"


# ---------------------------------------------------------------- fx 族(每张卡的电池 + 钩子 + 统计 + 经济 + 脸 + 消耗牌 + 增益 + 配置)

static func state_out(st: Dictionary) -> Dictionary:
	return st.duplicate(true)


func _fam_fx() -> String:
	var g := {}
	# ① 每张小丑牌 × 24 个上下文(它在自己的槽位上;support 时 0 号放随机 target)
	var per_joker: Array = []
	var jid := 0
	for e in DB.jokers():
		var id := String(e["id"])
		for k in range(16):   # 24 → 16(同上)
			var i := jid * 16 + k
			var rng := RandomNumberGenerator.new()
			rng.seed = 61000 + i
			var deck := Deck.new(61000 + i)
			var rr := rand_result(rng, deck, i)
			var slots := rand_slots(rng, 1 + (k % 3), id)
			var extra := rand_extra(rng, deck, rr[1], slots, i)
			var extra_in := extra_out(extra)
			var outcome := Settle.run(rr[1], slots, extra)
			per_joker.append({"cards": cards_out(rr[0]), "hidden": int(rr[2]), "slots": slots_out(slots),
				"extra": extra_in, "out": outcome_out(outcome)})
		jid += 1
	g["battery"] = per_joker
	# ② 钩子序列 + 元数据
	var hooks: Array = []
	for e in DB.jokers():
		var j := Joker.by_id(String(e["id"]))
		var trail: Array = [state_out(j.state)]
		j.on_discard(2); trail.append(state_out(j.state))
		j.on_shop_event("reroll"); trail.append(state_out(j.state))
		j.on_shop_event("buy"); trail.append(state_out(j.state))
		j.on_shop_event("target_swap"); trail.append(state_out(j.state))
		j.on_phrase_end({"early_finish": true}); trail.append(state_out(j.state))
		j.on_phrase_end({"early_finish": false}); trail.append(state_out(j.state))
		j.on_discard(0); trail.append(state_out(j.state))
		var life1 := j.tick_section_life(); trail.append(state_out(j.state))
		var life2 := j.tick_section_life(); trail.append(state_out(j.state))
		var d2 := Deck.new(77)
		j.on_acquire(d2)
		hooks.append({"id": j.id, "trail": trail, "life": [life1, life2],
			"trial_free": j.trial_free(), "rolls": j.chance_rolls_needed(), "swap_bonus": j.swap_bonus_pct(),
			"rule": j.is_rule_card(), "has_fx": j.has_effects(), "shelf_mult": j.shelf_target_mult(),
			"shelf_guar": j.shelf_target_guaranteed(), "cn": j.cn_name, "kind": j.kind, "rarity": j.rarity,
			"deck_total": d2.total(), "deck_rules": d2.rules.duplicate(true), "deck_trim": d2.trim_low,
			"deck_wildx": d2.wild_extra.duplicate(true), "clone_state": state_out(j.clone().state)})
	g["hooks"] = hooks
	# ③ 槽统计 + 经济
	var statics: Array = []
	for s in range(40):
		var rng := RandomNumberGenerator.new()
		rng.seed = 70000 + s
		var slots := rand_slots(rng, s % 5)
		var pool := Joker.pool()
		var rm := {} if s % 2 == 0 else {"common": 1.5, "uncommon": 0.7, "rare": 2.0}
		var boost := {} if s % 3 != 0 else {"twin": 3.0, "stair": 0.5}
		var tm: float = 1.0 if s % 4 != 0 else 3.0
		var picked: Array = Economy.weighted_pick(pool, 3, tm, rng, rm, boost)
		var pids: Array = []
		for pj in picked:
			pids.append(pj.id)
		var prices: Array = []
		var weights: Array = []
		for pj in pool:
			prices.append([pj.id, Economy.joker_price(pj, false), Economy.joker_price(pj, true),
				Economy.sell_value(pj), Economy.shelf_price(pj, slots)])
			weights.append(Economy.shelf_weight(pj, tm, rm))
		statics.append({"slots": slots_out(slots), "shelf_size": Joker.slots_shelf_size(slots, s % 3),
			"buy_limit": Joker.slots_buy_limit(slots), "price_delta": Joker.slots_price_delta(slots),
			"coin_cap": Joker.slots_coin_cap(slots), "odds": Joker.slots_odds_mult(slots),
			"cache_scoring": Joker.slots_cache_scoring(slots), "target_mult": Joker.slots_target_mult(slots),
			"copy_cons": Joker.slots_copy_consumable(slots), "free_support": Joker.first_free_support(slots),
			"room_t": Joker.has_room_for(slots, "target"), "room_s": Joker.has_room_for(slots, "support"),
			"guar": Joker.slots_guarantee_target(slots), "loan": Joker.slots_loan(slots),
			"rule_guar": Joker.slots_rule_guaranteed(slots),
			"picked": pids, "tm": tm, "rm": rm, "boost": boost, "prices": prices, "weights": weights,
			"grant": [Economy.grant(3, 4, slots), Economy.grant(20, 4, slots), Economy.grant(20, -2, slots)],
			"cap_held": Economy.cap_held(30, slots), "reroll": [Economy.reroll_cost(0), Economy.reroll_cost(3), Economy.reroll_cost(1, -2), Economy.reroll_cost(0, -9)],
			"discard_cost": [Economy.discard_cost(0), Economy.discard_cost(3)]})
	g["statics"] = statics
	# ④ 脸:参数电池 + 掷脸
	var faces: Array = []
	for m in SectionMod.roster():
		var id: String = m.id
		var pf: Array = []
		var tp: Array = []
		for idx in range(6):
			pf.append(SectionMod.phase_factor(id, idx))
			tp.append(SectionMod.time_penalty_at(id, idx))
		faces.append({"id": id, "cn": m.cn_name, "params": m.params.duplicate(true),
			"axes": SectionMod.attack_axes(id), "settle": SectionMod.affects_settle(id),
			"tiers": SectionMod.tiers_of(id), "tier": SectionMod.tier_of(id), "base": SectionMod.base_of(id),
			"combo": SectionMod.combo_of(id), "proof": SectionMod.proof(id), "tape": SectionMod.tape_required(id),
			"unlocked": [SectionMod.unlocked_at(id, -1), SectionMod.unlocked_at(id, 1), SectionMod.unlocked_at(id, 9)],
			"v": [SectionMod.time_penalty(id), SectionMod.phrase_toll(id), SectionMod.target_power(id),
				SectionMod.repeat_factor(id), SectionMod.zero_discard_factor(id), SectionMod.cache_evict(id),
				SectionMod.cache_cap(id), SectionMod.lock_first(id), SectionMod.target_mult(id),
				SectionMod.hide_refill(id), SectionMod.hide_faces(id), SectionMod.discard_lock_last(id),
				SectionMod.swap_lock_last(id), SectionMod.discard_action_limit(id), SectionMod.swap_action_limit(id),
				SectionMod.action_limit(id), SectionMod.discard_cards_max(id), SectionMod.action_cards_max(id),
				SectionMod.cache_blocks_red(id), SectionMod.refill_rank_min(id), SectionMod.refill_rank_max(id),
				SectionMod.cache_lock_phrases(id), SectionMod.seals_lowest_start(id), SectionMod.seals_oldest_cache(id),
				SectionMod.seals_random_start(id), SectionMod.seals_random_cache(id), SectionMod.hide_random(id),
				SectionMod.hide_suits(id), SectionMod.hide_ranks(id), SectionMod.roll_chance(id),
				SectionMod.roll_cache_extra(id), SectionMod.rolls_suit(id), SectionMod.suit_half(id),
				SectionMod.callout_factor(id), SectionMod.rolls_kind(id), SectionMod.required_kinds(id),
				SectionMod.variety_penalty(id), SectionMod.restores_with_initial_cache(id),
				SectionMod.section_discard_budget(id), SectionMod.exclusive_action_tracks(id),
				SectionMod.request_factor(id), SectionMod.joker_power(id), SectionMod.bonus_disabled(id),
				SectionMod.discard_open(id, 2.0), SectionMod.swap_open(id, 2.0), SectionMod.discard_open(id, 1.5)],
			"pf": pf, "tp": tp})
	var pools: Array = []
	for sidx in range(GameConfig.SECTIONS_PER_RUN):
		pools.append(SectionMod.pool_for(sidx))
	var rolls: Array = []
	for s in range(120):
		var rng := RandomNumberGenerator.new()
		rng.seed = 80000 + s
		var ri: int = [-1, 1, 3, 5, 9][s % 5]
		var out := SectionMod.roll_run(rng, ri)
		var arr: Array = []
		for w in GameConfig.WALL_SECTIONS:
			arr.append(String(out.get(int(w), "")))
		rolls.append({"seed": 80000 + s, "run_index": ri, "faces": arr, "after": rng.randi(),
			"single": SectionMod.roll(s % 4, rng, [String(arr[0])], ri)})
	g["faces"] = {"list": faces, "pools": pools, "pooled": SectionMod.pooled_ids(), "axes": SectionMod.axis_ids(),
		"fixed": [SectionMod.tier_is_fixed(1), SectionMod.tier_is_fixed(4)], "rolls": rolls}
	# ⑤ 消耗牌
	var cons: Array = []
	for e in DB.consumables():
		var c := Consumable.new(e)
		var due: Array = []
		for beat in range(1, 7):
			for q in range(0, 3):
				due.append(c.due_on(beat, q))
		cons.append({"id": c.id, "instant": c.is_instant(), "rule": c.is_rule_card(), "label": c.fire_label(),
			"price": c.price, "due": due, "name": c.display_name(), "clone_q": c.clone().queued_beats})
	var shelves: Array = []
	for s in range(60):
		var rng := RandomNumberGenerator.new()
		rng.seed = 90000 + s
		var held := {}
		if s % 3 == 1:
			held["superwild"] = true
		if s % 3 == 2:
			held["doublebill"] = true
			held["opener"] = true
		var rows: Array = Consumable.roll_shelf(held, s % 2 == 0, 2 + (s % 2),
			func(n): return rng.randi_range(0, n - 1))
		var ids: Array = []
		for r in rows:
			ids.append("" if r == null else String(r["id"]))
		shelves.append({"seed": 90000 + s, "held": held, "rule_first": s % 2 == 0, "n": 2 + (s % 2), "ids": ids})
	g["consumables"] = {"list": cons, "shelves": shelves}
	# ⑥ 增益 + 配置
	var boons: Array = []
	for s in range(30):
		var rng := RandomNumberGenerator.new()
		rng.seed = 95000 + s
		boons.append(BlindBoon.roll(rng))
	var bparams: Array = []
	for bid in BlindBoon.ids():
		bparams.append([bid, BlindBoon.score_replay_factor(bid), BlindBoon.spotlight_cards(bid),
			BlindBoon.previous_raw_factor(bid), BlindBoon.ghost_first_discard(bid), BlindBoon.by_id(bid).cn_name])
	g["boons"] = {"ids": BlindBoon.ids(), "rolls": boons, "params": bparams}
	var cfg := {
		"pps": GameConfig.PHRASES_PER_SECTION, "shop": GameConfig.PHRASES_PER_SHOP, "sps": GameConfig.SHOPS_PER_SECTION,
		"spg": GameConfig.SECTIONS_PER_GIG, "gpr": GameConfig.GIGS_PER_RUN, "spr": GameConfig.SECTIONS_PER_RUN,
		"walls": GameConfig.WALL_SECTIONS, "targets": GameConfig.SECTION_TARGETS, "avg": GameConfig.avg_beat_target(),
		"hand": GameConfig.HAND_SIZE, "cache": GameConfig.CACHE_CAP, "bd": GameConfig.BEAT_DISCARDS,
		"bb": GameConfig.BEAT_DISCARD_BATCH, "bs": GameConfig.BEAT_SWAPS, "blind": GameConfig.BLIND_SAMPLES,
		"coins": GameConfig.STARTING_COINS, "dc": GameConfig.DISCARD_COST, "wage": GameConfig.SECTION_CLEAR_REWARD,
		"rb": GameConfig.DRAFT_REROLL_BASE, "rs": GameConfig.DRAFT_REROLL_STEP,
		"s1": [GameConfig.S1_FACE_MIN_RUN, GameConfig.S1_EASY_CHANCE], "windows": [GameConfig.LATE_ACT_WINDOW,
			GameConfig.FINAL_ACT_WINDOW, GameConfig.EARLY_DISCARD_WINDOW, GameConfig.EARLY_FINISH_LEFT, GameConfig.RESOLVE_FEEDBACK],
		"per_section": [], "budget": [],
	}
	for sidx in range(GameConfig.SECTIONS_PER_RUN):
		var d := GameConfig.phrase_duration(sidx)
		cfg["per_section"].append([d, GameConfig.warning_time(d), GameConfig.lock_time(d), GameConfig.is_wall(sidx),
			GameConfig.gig_of(sidx), GameConfig.blind_name(sidx), GameConfig.gig_name(sidx), GameConfig.section_target(sidx)])
		for dur in [8.0, 6.0, 4.0]:
			cfg["budget"].append([sidx, dur, GameConfig.beat_discards(dur, sidx), GameConfig.discard_batch(dur, sidx)])
	g["config"] = cfg
	return "return " + lua(g) + "\n"


# ---------------------------------------------------------------- run 族(整局重放)

## 与 lua/tools/fams.lua::canon 逐字相同的规范化串(摘要用)。
static func canon(v) -> String:
	match typeof(v):
		TYPE_NIL: return "nil"
		TYPE_BOOL: return "T" if v else "F"
		TYPE_INT: return "%d" % v
		TYPE_FLOAT:
			if v == floor(v) and absf(v) < 9007199254740992.0:
				return "%d" % int(v)
			return "f:" + f64hex(v)
		TYPE_STRING, TYPE_STRING_NAME: return "'" + String(v) + "'"
		TYPE_ARRAY:
			var parts: Array = []
			for e in v:
				parts.append(canon(e))
			return "[" + ",".join(parts) + "]"
		TYPE_DICTIONARY:
			var keys: Array = []
			for k in v:
				keys.append(String(k))
			keys.sort()
			var parts: Array = []
			for k in keys:
				var val = v[k] if v.has(k) else v[int(k)]
				parts.append(k + "=" + canon(val))
			return "{" + ",".join(parts) + "}"
		_: return "'" + str(v) + "'"


static func joker_digest(j) -> String:
	if j == null:
		return "-"
	var keys: Array = j.state.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append(String(k) + "=" + canon(j.state[k]))
	return String(j.id) + "{" + ",".join(parts) + "}"


static func lbl(arr: Array) -> String:
	var out: Array = []
	for c in arr:
		out.append(c.label() if c != null else "?")
	return " ".join(out)


## 一局在某一刻的状态摘要 —— lua/tools/runloop.lua::digest 同一定义。
static func digest(run: Run) -> String:
	var slots_s: Array = []
	for j in run.joker_slots:
		slots_s.append(joker_digest(j))
	var cons: Array = []
	for c in run.consumables:
		cons.append("%s:%d" % [String(c.id), int(c.queued_beats)])
	var kinds: Array = []
	for k in run.section_kinds:
		kinds.append(int(k))
	kinds.sort()
	var ks: Array = []
	for k in kinds:
		ks.append("%d" % k)
	var rules: Array = []
	for k in run.deck.rules:
		if run.deck.rules[k]:
			rules.append(String(k))
	rules.sort()
	return "|".join([
		"sec=%d" % run.section_idx, "pis=%d" % run.phrase_in_section, "pi=%d" % run.phrase_index,
		"score=%d" % run.section_score, "coins=%d" % run.coins, "debt=%d" % run.debt, "stage=%d" % run.stage,
		"rng=" + state_hex(run.deck._rng.state),
		"draw=" + lbl(run.deck.draw_pile), "disc=" + lbl(run.deck.discard_pile), "cache=" + lbl(run.cache),
		"slots=" + ";".join(slots_s), "cons=" + ",".join(cons), "boost=%d" % run.phrase_boosts.size(),
		"face=" + run.face(), "boon=" + run.run_boon, "mr=" + canon(run.mod_roll),
		"pk=%d" % run.prev_kind, "pth=" + ("T" if run.prev_target_hit else "F"), "fk=%d" % run.first_kind,
		"kinds=" + ",".join(ks), "sdu=%d" % run.section_discards_used, "sb=%d" % run.shelf_bonus,
		"rl=" + run.request_last, "prs=%d" % run.previous_raw_score,
		"brng=" + state_hex(run._blind_rng.state), "rs=%d" % run._roll_seed,
		"trim=" + ("T" if run.deck.trim_low else "F"), "rules=" + ",".join(rules),
		"wildx=" + canon(run.deck.wild_extra),
		"tut=%s/%d" % [("T" if run.tutorial else "F"), run.tutorial_step],
	])


## 商店的非渲染逻辑 —— lua/app/shop.lua 的同构体(view/shop.gd 授予记账 + view/phrase.gd 成交编排)。
## ⚑ 记账已收成一份 `Shelf.Visit`(三方共用) ⇒ 整局金样证的「ShopSim = Lua」也覆盖到了 view 用的那份账;
## ⚠ 但**编排**仍是三处一份(view / 这里 / Lua):改商店的流程仍要三处同改(mirror.md §12)。
class ShopSim extends RefCounted:
	var run: Run
	var rng: RandomNumberGenerator
	var candidates: Array = []
	## ⚑ 记账只有一份:联票名额 / 免费刷新 / 折扣 / 挑高 / 5 选 1 计数 / 帕奇欧一次 / 离店清零
	## 全在 `Shelf.Visit` 里 —— view/shop.gd 与 lua/app/shop.lua 消费的是**同一个类**。
	## 这里只留不属于记账的店内状态:货架、消耗牌货架、开过没、跨店的规则牌保底。
	var visit := Shelf.Visit.new()
	var coffer: Array = []
	var opened := false
	var rule_next := false

	## 只读转发:`closed` 住在 Visit 里,调用方语法不变。
	var closed: bool:
		get:
			return visit.closed

	func _init(r: Run, g: RandomNumberGenerator) -> void:
		run = r
		rng = g

	func open() -> void:
		Joker.notify_shop(run.joker_slots, "enter")
		visit.open(run.shelf_bonus)
		run.shelf_bonus = 0
		deal()
		var rf := rule_next
		rule_next = false
		coffer = roll_consumables(rf)
		opened = true

	func deal() -> void:
		candidates = Shelf.deal(run.joker_slots, visit.shelf_bonus, visit.grant_shelf, visit.grant_min_rarity, rng, {}, {})

	func roll_consumables(rule_first: bool) -> Array:
		var held := {}
		for c in run.consumables:
			held[c.id] = true
		var out: Array = []
		for e in Consumable.roll_shelf(held, rule_first, 2, func(n: int) -> int: return run.deck.pick_index(n)):
			out.append(null if e == null else Consumable.new(e))
		return out

	func price(j) -> int:
		return visit.price(j, run.joker_slots)

	func has_room(j) -> bool:
		return Joker.has_room_for(run.joker_slots, String(j.kind))

	func affordable(j) -> bool:
		return visit.affordable(j, run.joker_slots, run.coins)

	func buy_limit() -> int:
		return visit.buy_limit(run.joker_slots)

	func consumable_effective(c) -> bool:
		if c.action.has("copy_one_destroy_rest"):
			var n := 0
			for i in range(1, run.joker_slots.size()):
				if run.joker_slots[i] != null:
					n += 1
			return n >= 2
		return true

	func _after_sale(sold_joker) -> bool:
		# ⚠ 去留判在**离店副作用之前**取:帕奇欧会应用消耗牌(可能再发名额),
		# 拿它之后的名额判去留 = 让复制出来的联票把已经该关的店重新开开。
		if visit.shop_buys >= visit.buy_limit(run.joker_slots):
			_exit()
			return false
		if sold_joker != null:
			sold(sold_joker)
		return visit.stay(run.joker_slots)

	func _exit() -> void:
		# ⚠ 帕奇欧在 `close()` **之前** —— 它应用的消耗牌会写授予/重掷货架,
		# 顺序反了那些授予会活过这一店。
		perkeo_on_exit()
		visit.close()

	func sold(j) -> void:
		var at: int = candidates.find(j)
		candidates.erase(j)
		var refill = Shelf.refill(run.joker_slots, candidates, visit.grant_min_rarity, rng, {}, {})
		if refill != null:
			if at >= 0 and at <= candidates.size():
				candidates.insert(at, refill)
			else:
				candidates.append(refill)

	## 返回 {ok, replace, stay}
	func buy(i: int) -> Dictionary:
		if closed or i >= candidates.size():
			return {"ok": false}
		var j = candidates[i]
		if not affordable(j):
			return {"ok": false}
		if not has_room(j):
			return {"ok": false, "replace": true}
		return _install_bought(j, price(j))

	func _install_bought(j, p: int) -> Dictionary:
		if p < 0 or run.coins < p:
			return {"ok": false}
		run.coins -= p
		run.tutorial_note("buy")
		Joker.notify_shop(run.joker_slots, "buy")
		var swapped_target := false
		if j.kind == "target":
			var swapping: bool = run.joker_slots[0] != null
			swapped_target = swapping
			if swapping:
				Joker.notify_shop(run.joker_slots, "target_swap")
				var trefund := Economy.sell_value(run.joker_slots[0])
				if trefund > 0:
					run.coins = Economy.grant(run.coins, trefund, run.joker_slots)
			run.joker_slots[0] = j
			j.on_acquire(run.deck)
		else:
			for k in range(1, run.joker_slots.size()):
				if run.joker_slots[k] == null:
					run.joker_slots[k] = j
					j.on_acquire(run.deck)
					break
		run.coins = Economy.cap_held(run.coins, run.joker_slots)
		if run.tutorial and j.kind == "target":
			run.tutorial_shop_seen()
			_exit()
			return {"ok": true, "stay": false}
		if not (j.kind == "target" and swapped_target):
			visit.note_buy()
		return {"ok": true, "stay": _after_sale(j)}

	func replace(i: int, k: int) -> Dictionary:
		if closed or i >= candidates.size():
			return {"ok": false}
		var new_j = candidates[i]
		if k == 0:
			return {"ok": false, "stay": true}
		var old = run.joker_slots[k]
		var p := price(new_j)
		var refund: int = Economy.sell_value(old) if old != null else 0
		if run.coins + refund < p:
			return {"ok": false, "stay": true}
		run.coins = Economy.grant(run.coins, refund, run.joker_slots) - p
		Joker.notify_shop(run.joker_slots, "buy")
		run.joker_slots[k] = new_j
		new_j.on_acquire(run.deck)
		run.coins = Economy.cap_held(run.coins, run.joker_slots)
		visit.note_buy()
		return {"ok": true, "stay": _after_sale(new_j)}

	func reroll() -> Dictionary:
		if closed:
			return {"ok": false}
		if visit.take_free_reroll():
			Joker.notify_shop(run.joker_slots, "reroll")
			deal()
			return {"ok": true, "cost": 0}
		var cost := visit.reroll_cost_now()
		if run.coins < cost:
			return {"ok": false}
		visit.note_reroll()
		run.coins -= cost
		Joker.notify_shop(run.joker_slots, "reroll")
		deal()
		return {"ok": true, "cost": cost}

	func buy_consumable(i: int) -> Dictionary:
		if closed or i >= coffer.size() or coffer[i] == null or visit.coffer_used:
			return {"ok": false}
		var c = coffer[i]
		if run.coins < c.price:
			return {"ok": false}
		if not consumable_effective(c):
			return {"ok": false}
		run.coins -= c.price
		var used: Dictionary = run.take_consumable(c)
		if not used.is_empty():
			apply_consumable(used)
		visit.note_buy()
		visit.coffer_used = true
		if visit.shop_buys < visit.buy_limit(run.joker_slots):
			# 名额没满 ⇒ 消耗牌货架继续开着(只摘掉刚买的那张)
			visit.coffer_used = false
			for k in range(coffer.size()):
				if coffer[k] != null and String(coffer[k].id) == String(c.id):
					coffer[k] = null
		return {"ok": true, "stay": _after_sale(null)}

	func leave() -> Dictionary:
		if closed:
			return {"ok": false}
		run.tutorial_shop_seen()
		_exit()
		return {"ok": true, "stay": false}

	func apply_consumable(used: Dictionary) -> void:
		var cid := String(used["id"])
		var act: Dictionary = used.get("action", {})
		if act.has("wilds"):
			run.deck.add_wilds(cid, int(act["wilds"]))
		if act.has("trim_low"):
			run.deck.trim_low_ranks()
		if act.has("deck_rule"):
			run.deck.rules[String(act["deck_rule"])] = true
		apply_shop_action(cid, act)

	func apply_shop_action(id: String, act: Dictionary) -> void:
		# 属于记账的五个键收在 Visit 里;这里只做碰 deck / coins / 跨店的另一半。
		if bool(visit.apply_action(act)["redeal"]) and opened and not closed:
			deal()
		if act.has("rule_guaranteed"):
			rule_next = true
		if act.has("deck_rule"):
			run.deck.rules[String(act["deck_rule"])] = true
		if act.has("loan"):
			var ln: Dictionary = act["loan"]
			run.coins = Economy.grant(run.coins, int(ln.get("borrow", 0)), run.joker_slots)
			run.debt += int(ln.get("repay", 0))
		if act.has("copy_one_destroy_rest"):
			anvil()
		if act.has("wilds"):
			run.deck.add_wilds(id, int(act["wilds"]))
		if act.has("trim_low"):
			run.deck.trim_low_ranks()

	func anvil() -> void:
		var owned: Array = []
		for i in range(1, run.joker_slots.size()):
			if run.joker_slots[i] != null:
				owned.append(i)
		if owned.size() < 2:
			return
		var keep: int = owned[run.deck.pick_index(owned.size())]
		var kept = run.joker_slots[keep]
		for i in range(run.joker_slots.size()):
			if i != keep:
				run.joker_slots[i] = null
		if kept.kind == "support":
			for i in range(1, run.joker_slots.size()):
				if run.joker_slots[i] == null:
					var dup = Joker.by_id(kept.id)
					dup.state = kept.state.duplicate(true)
					run.joker_slots[i] = dup
					break

	func perkeo_on_exit() -> void:
		if visit.perkeo_fired:
			return
		visit.perkeo_fired = true
		if not Joker.slots_copy_consumable(run.joker_slots):
			return
		var src: Array = run.consumables.duplicate()
		if src.is_empty():
			return
		var pick = src[run.deck.pick_index(src.size())]
		for e in DB.consumables():
			if String(e["id"]) == pick.id:
				var copy := Consumable.new(e)
				var used: Dictionary = run.take_consumable(copy)
				if not used.is_empty():
					apply_consumable(used)
				break


## 一局的随机策略回放脚本(动作 + 摘要)。不死局:段末工资照发、还不上就清账继续(RunLoop 口径)。
func _play_run(seed: int, tutorial: bool) -> Dictionary:
	var prng := RandomNumberGenerator.new()
	prng.seed = seed * 3 + 1
	var srng := RandomNumberGenerator.new()
	srng.seed = seed * 5 + 2
	var run := Run.new()
	run.deck = Deck.new(seed)
	run.cache = []
	run.joker_slots = [null, null, null, null]
	run.coins = GameConfig.STARTING_COINS
	run.tutorial = tutorial
	run._blind_rng.seed = seed * 31 + 7
	run._roll_seed = seed * 97 + 13
	if tutorial:
		run.run_faces = {}
		run.run_boon = ""
	else:
		var frng := RandomNumberGenerator.new()
		frng.seed = seed * 13 + 3
		run.run_faces = SectionMod.roll_run(frng)
		run.run_boon = RunLoop.roll_boon(seed)
	var shop := ShopSim.new(run, srng)
	var ops: Array = []
	var died := -1
	for section in range(GameConfig.SECTIONS_PER_RUN):
		run.section_idx = section
		run.reset_section_state()
		var section_over := false
		while not section_over:
			var p := Beat.begin(run)
			run.age_consumables()
			for used in run.due_consumables(run.phrase_in_section + 1):
				shop.apply_consumable(used)
			ops.append(["beat"])
			var n_act := prng.randi_range(0, 2)
			for _a in range(n_act):
				var t := prng.randi_range(0, 6)
				if t <= 3:
					var k := prng.randi_range(1, 3)
					var h: Array = []
					var c: Array = []
					for _t in range(k):
						if prng.randi_range(0, 3) == 0 and not run.cache.is_empty():
							var ci := prng.randi_range(0, run.cache.size() - 1)
							if not c.has(ci):
								c.append(ci)
						else:
							var hi := prng.randi_range(0, p.hand.size() - 1)
							if not h.has(hi):
								h.append(hi)
					ops.append(["discard", h, c])
					p.discard_selected(h, c)
				elif t <= 5:
					if not run.cache.is_empty():
						var hi := prng.randi_range(0, p.hand.size() - 1)
						var ci := prng.randi_range(0, run.cache.size() - 1)
						ops.append(["swap", hi, ci])
						p.swap_with_cache(hi, ci)
				else:
					ops.append(["sort"])
					p.sort_hand()
			var flags := {"late": prng.randi_range(0, 3) == 0, "early": prng.randi_range(0, 3) == 0,
				"final": prng.randi_range(0, 7) == 0, "secs_left": float(prng.randi_range(0, 80)) / 10.0,
				"early_discards": prng.randi_range(0, 3) == 0}
			ops.append(["settle", flags])
			Beat.settle(run, p, flags)
			Beat.phrase_end(run, p, flags)
			run.tutorial_note("play")
			run.tutorial_try_advance()
			var out := run.advance()
			ops.append(["D", digest(run)])
			if run.tutorial and not bool(out["section_done"]):
				if run.tutorial_step == Tutorial.shop_step() and run.joker_slots[0] == null:
					_shop_visit(shop, prng, ops)
					continue
				if bool(out["shop_break"]):
					continue
			if bool(out["section_done"]):
				if run.tutorial and run.tutorial_done():
					run.tutorial = false
					run.roll_faces(seed * 11 + 5, -1)
					ops.append(["tutorial_done"])
				ops.append(["sec_end", bool(out["cleared"])])
				if not bool(out["cleared"]) and died < 0:
					died = section
				run.coins = Economy.grant(run.coins, GameConfig.SECTION_CLEAR_REWARD, run.joker_slots)
				if run.debt > 0:
					var rp: Dictionary = run.repay_debt(run.coins)
					if bool(rp["ok"]):
						run.coins = int(rp["coins"])
					else:
						run.coins = 0
						run.debt = 0
				ops.append(["D", digest(run)])
				section_over = true
				if not bool(out["finale"]):
					run.next_section()
					_shop_visit(shop, prng, ops)
			elif bool(out["shop_break"]):
				_shop_visit(shop, prng, ops)
	ops.append(["end"])
	return {"seed": seed, "tutorial": tutorial, "ops": ops, "died": died}


func _shop_visit(shop: ShopSim, prng: RandomNumberGenerator, ops: Array) -> void:
	shop.open()
	ops.append(["shop"])
	for _step in range(4):
		if shop.closed:
			break
		var r := prng.randi_range(0, 9)
		if r <= 4:
			var n := shop.candidates.size()
			if n == 0:
				ops.append(["leave"])
				shop.leave()
				break
			var i := prng.randi_range(0, n - 1)
			if not shop.affordable(shop.candidates[i]):
				i = -1
				for k in range(n):
					if shop.affordable(shop.candidates[k]):
						i = k
						break
			if i < 0:
				ops.append(["leave"])
				shop.leave()
				break
			var res := shop.buy(i)
			if bool(res.get("replace", false)):
				var k := prng.randi_range(1, 3)
				ops.append(["replace", i, k])
				shop.replace(i, k)
			else:
				ops.append(["buy", i])
		elif r <= 6:
			var ci := prng.randi_range(0, 1)
			ops.append(["cbuy", ci])
			shop.buy_consumable(ci)
		elif r == 7:
			ops.append(["reroll"])
			shop.reroll()
		else:
			ops.append(["leave"])
			shop.leave()
	if not shop.closed:
		ops.append(["leave"])
		shop.leave()
	ops.append(["shop_end"])
	ops.append(["D", digest(shop.run)])


func _fam_run() -> String:
	var runs: Array = []
	for i in range(30):
		runs.append(_play_run(100000 + i * 7, i % 10 == 0))
	return "return " + lua(runs) + "\n"


# ---------------------------------------------------------------- visit 族(一次进店的记账)

## `Shelf.Visit` 的字段快照 —— lua/tools/fams.lua::visit_digest 同一定义。
## ⚠ `tools/mirror.py` 只查顶层 func ⇒ 查不到内部类;这一族**就是** Visit 孪生的唯一机械证据。
static func visit_digest(v) -> String:
	return "|".join([
		"rc=%d" % v.reroll_count, "bl=%d" % v.buys_left, "sb=%d" % v.shelf_bonus,
		"gs=%d" % v.grant_shelf, "geb=%d" % v.grant_extra_buys, "gp=%d" % v.grant_price,
		"gfr=%d" % v.grant_free_reroll, "gmr=" + v.grant_min_rarity,
		"buys=%d" % v.shop_buys, "cu=" + ("T" if v.coffer_used else "F"),
		"pf=" + ("T" if v.perkeo_fired else "F"), "cl=" + ("T" if v.closed else "F"),
	])


## 槽位规格(4 个 id 字符串, "" = 空)→ 真槽。Lua 侧空位是 false, 这里是 null。
static func visit_slots(spec: Array) -> Array:
	var out: Array = []
	for id in spec:
		out.append(null if String(id) == "" else Joker.by_id(String(id)))
	return out


## 一条脚本化序列:每一步之后记下**全部字段**与这一步的返回值。
func _visit_case(slots_spec: Array, ops: Array) -> Dictionary:
	var v := Shelf.Visit.new()
	var slots := visit_slots(slots_spec)
	var trail: Array = []
	for op in ops:
		var k := String(op[0])
		var ret = null
		match k:
			"open": v.open(int(op[1]))
			"act": ret = v.apply_action(op[1])
			"price": ret = v.price(Joker.by_id(String(op[1])), slots)
			"afford": ret = v.affordable(Joker.by_id(String(op[1])), slots, int(op[2]))
			"rcost": ret = v.reroll_cost_now()
			"free": ret = v.take_free_reroll()
			"nroll": v.note_reroll()
			"limit": ret = v.buy_limit(slots)
			"nbuy": v.note_buy()
			"stay": ret = v.stay(slots)
			"close": v.close()
			"slots": slots = visit_slots(op[1])
			"cused": v.coffer_used = bool(op[1])
			"pfired": v.perkeo_fired = bool(op[1])
			_:
				push_error("golden visit: 未知 op " + k)
				quit(1)
		trail.append(visit_digest(v) + "|ret=" + canon(ret))
	return {"slots": slots_spec, "ops": ops, "trail": trail}


func _fam_visit() -> String:
	var cases: Array = []
	# ① 授予的累加口径 + 离店/进店各清什么
	cases.append(_visit_case(["", "encore", "", ""], [
		["open", 0],
		["act", {"shelf_slots": 4, "extra_buys": 2}],   # 联票:货架取大 · 名额加法
		["limit"],
		["act", {"shelf_slots": 3}],                    # 取大 ⇒ 仍是 4(不叠成 7)
		["act", {"extra_buys": 1}],                     # 加法 ⇒ 3
		["limit"],
		["act", {"price_delta": -2}],
		["rcost"],
		["act", {"price_delta": -9}],                   # 折扣可以叠到负很多, 地板在 Economy
		["rcost"],
		["act", {"free_reroll": 3}],
		["act", {}],                                    # 空 action ⇒ 不重掷、什么都不动
		["act", {"min_rarity": "uncommon"}],
		["act", {"min_rarity": "rare"}],                # 覆盖, 不是取大也不是先到先得
		["close"],                                      # 四个「本店」授予清零, 挑高留着
		["limit"],
		["open", 2],                                    # 进店:挑高清零 + 灌入点名奖励
		["limit"],
	]))
	# ② 5 选 1 的计数与去留
	cases.append(_visit_case(["", "encore", "finale", "turnover"], [
		["open", 1],
		["limit"],
		["nbuy"],
		["stay"],                                       # 基础名额 1 ⇒ 买一张就走
		["open", 0],
		["act", {"extra_buys": 2}],
		["limit"],
		["nbuy"], ["stay"],                             # 还能再选 2 张
		["nbuy"], ["stay"],                             # 还能再选 1 张
		["nbuy"], ["stay"],                             # 满额 ⇒ 关店 + 授予清零
		["limit"],
		["cused", true], ["pfired", true],
		["close"],                                      # close **不**清这两个
		["open", 0],                                    # open 清
	]))
	# ③ 价格:免费首张 Target · 折扣 · 地板 1
	cases.append(_visit_case(["", "", "", ""], [
		["open", 0],
		["price", "twin"], ["afford", "twin", 0],       # 首张 Target 免费, 身无分文也拿得动
		["price", "encore"],
		["afford", "encore", 2], ["afford", "encore", 3],
		["act", {"price_delta": -2}],
		["price", "encore"], ["price", "twin"],         # 折扣不许把免费打成 −2
		["act", {"price_delta": -9}],
		["price", "encore"], ["price", "perkeo"],       # 地板 1◆
		["afford", "encore", 1], ["afford", "encore", 0],
		["act", {"price_delta": 4}],                    # 正的增量也走同一条
		["price", "encore"], ["price", "perkeo"],
	]))
	# ④ 满槽的回收预算(Support 只在 1..3;换旗没有退款 ⇒ Target 只看现钱)
	cases.append(_visit_case(["twin", "encore", "finale", "turnover"], [
		["open", 0],
		["price", "perkeo"],
		["afford", "perkeo", 0],                        # 预算 = 现钱 + 最好的一张 Support 回收
		["afford", "perkeo", 1], ["afford", "perkeo", 5],
		["price", "lonewolf"], ["afford", "lonewolf", 0], ["afford", "lonewolf", 9],
		["slots", ["", "encore", "finale", "turnover"]],  # 没有 Target + 三个 Support 满
		["afford", "perkeo", 0], ["afford", "lonewolf", 0],
		["slots", ["twin", "encore", "", ""]],          # 有空位 ⇒ 不算回收
		["afford", "perkeo", 0], ["afford", "perkeo", 9],
	]))
	# ⑤ 刷新:阶梯 · 折扣 · 免费刷新不推阶梯
	cases.append(_visit_case(["", "encore", "", ""], [
		["open", 0],
		["rcost"], ["free"],                            # 没授予 ⇒ 免费刷新拿不到
		["nroll"], ["rcost"],
		["nroll"], ["rcost"],
		["nroll"], ["rcost"],
		["act", {"price_delta": -2}], ["rcost"],
		["act", {"free_reroll": 2}],
		["free"], ["rcost"],                            # 免费一次:阶梯不动
		["free"], ["rcost"],
		["free"],                                       # 用完
		["nroll"], ["rcost"],
		["close"], ["rcost"],                           # 离店清折扣 ⇒ 阶梯回到原价
	]))
	return "return " + lua(cases) + "\n"
