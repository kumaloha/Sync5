class_name DB
extends RefCounted

## Data-config loader (docs/design/tech.md). Loads data/*.json once and validates.
##
## ⚑⚑ **校验是「测试期门禁」,不是运行时拒绝 —— 这是有意的,2026-08-09 拍板。**
##
## 违规时 `_fail()` 记进 `load_error()` 并 `push_error`,**然后照常返回解析结果**,
## 游戏继续跑。`tests/t_db.gd` 第一条就断言 `DB.load_error() == ""`,
## 所以任何 schema 违规**在测试里直接红**。
##
## 为什么运行时不 fail-closed(外部审查提过这一点):数据文件**随游戏一起发布**
## 且发布前已经过测试门,而 `_load` 若在违规时返回 `{}`,调用方会在四处
## 炸出一串莫名其妙的错 —— 那不是一次干净的失败,而玩家看到的是黑屏。
## **代价不对称:漏网的坏数据只影响一次构建,开不了机影响每一个玩家。**
##
## ⚠ 曾经这里写的是「validates hard, fails loudly」,读起来像运行时会拒绝 ——
## **那是一句承诺了不存在的保障的话**,和 `core/beat.gd` 那句「漏步 = 崩」同一个毛病
## (`push_error` 根本不中断执行)。**注释不许描述一个没有实现的机制。**
##
## ⚠ 要改成运行时严格的话,改的不是这里,而是要先给出一个**单点的**失败出口
## (例如启动时统一检查 `load_error()` 并显示一屏可读的错误),否则只是把静默
## 换成了雪崩。
## `_comment` keys (any key starting with "_") are ignored everywhere —
## **except faces.json**, which is data-only (2026-08-09): its design prose
## lives in docs/design/blinds.md, and `_`-prefixed keys are rejected there on
## purpose so the notes cannot silently grow back into the data file.

static var _cache: Dictionary = {}
static var _err := ""

const _RUN_KEYS := ["phrases_per_section", "phrases_per_shop", "sections_per_gig",
	"gigs_per_run", "blind_names", "gig_names", "section_targets", "gig_clocks",
	"warning_offset", "lock_offset", "late_act_window", "final_act_window",
	"early_finish_left", "early_discard_window",
	"hand_size", "cache_cap", "beat_budget", "death_spec",
	"s1_face_min_run", "s1_easy_chance"]
const _ECO_KEYS := ["starting_coins", "discard_cost", "section_clear_reward",
	"draft_rarity_weights", "joker_prices", "joker_price_overrides",
	"reroll", "kind_coins"]
const _TAPE_KEYS := ["enabled", "to_file", "dir", "max_events", "mute"]   # upload 是可选节, 另查


## Forces every data file through its validator; "" = all clean.
static func load_error() -> String:
	run()
	economy()
	faces()
	boons()
	jokers()
	sim()
	ui()
	tape()
	tutorial()
	director()
	ranking()
	lingo()
	profile()
	return _err


## run.json 里上屏的只有 gig_names(blind_names 本来就是拉丁)—— localize 只动表里有的串,
## 数字与结构原样;en 模式下返回的是副本, 消费方(GameConfig)只读不写, 无副作用。
static func run() -> Dictionary:
	return Lingo.localize(_load("run", func(d): return validate_run(d)), "run")


static func economy() -> Dictionary:
	return _load("economy", func(d): return validate_economy(d))


static func faces() -> Dictionary:
	return _load("faces", func(d): return validate_faces(d))


static func boons() -> Dictionary:
	return _load("boons", func(d): return validate_boons(d))


static func jokers() -> Array:
	return _load("jokers", func(d): return validate_jokers(d)).get("jokers", [])


## 消耗牌(2026-08-29 开轴)。与 jokers() 同一条线:_load + 校验器,
## 未知键/坏引用在测试期直接红(t_db 断言 load_error() == "")。
static func consumables() -> Array:
	return _load("consumables", func(d): return validate_consumables(d)).get("consumables", [])


static func sim() -> Dictionary:
	return _load("sim", func(d): return validate_sim(d))


## ⚑ 展示串出口过 Lingo(1.1 英文化):en 模式返回按 lingo.json 整树替换的缓存副本,
## cn 模式原样 —— 23 个消费点因此零改动。tutorial()/run() 同一条线。
static func ui() -> Dictionary:
	return Lingo.localize(_load("ui", func(d): return validate_ui(d)), "ui")


## 打点开关(core/tape.gd)。名字不叫 log —— `log` 是 GDScript 内置数学函数,
## 在类里同名会把它遮掉。
static func tape() -> Dictionary:
	return _load("tape", func(d): return validate_tape(d))


static func tutorial() -> Dictionary:
	return Lingo.localize(_load("tutorial", func(d): return validate_tutorial(d)), "tutorial")


## 首页顶栏的两个数(2026-08-24;`core/save.gd` 是它唯一的消费者)。
static func profile() -> Dictionary:
	return _load("profile", func(d): return validate_profile(d))


static func validate_profile(d: Dictionary) -> String:
	var e := _keys_ok(d, ["energy_max", "xp_per_level"])
	if e != "":
		return e
	# 0 或负数不是「关掉」而是静默除零/恒零 —— 要关体力显示去改 view, 别改成 0
	if int(d["energy_max"]) < 1 or int(d["xp_per_level"]) < 1:
		return "energy_max / xp_per_level 必须 >= 1"
	return ""


## 中→英对照表(1.1 英文化, core/lingo.gd 是它唯一的消费者)。
static func lingo() -> Dictionary:
	return _load("lingo", func(d): return validate_lingo(d))


## ⚠ 两条硬校验都是「静默错」的形状:英文值里混中文 = 漏翻上屏不报错;
## `%` 占位符两边数量不齐 = 运行时格式化直接炸(而且只炸 en 模式, cn 测试全绿)。
static func validate_lingo(d: Dictionary) -> String:
	var e := _keys_ok(d, ["table"])
	if e != "":
		return e
	var tb = d.get("table", {})
	if typeof(tb) != TYPE_DICTIONARY:
		return "table 必须是 {中文: English} 字典"
	# ⚠ 不用 \p{Han}:PCRE2 新版按 script-extensions 匹配, 「·」(U+00B7) 的扩展集里
	# 有 Hani ⇒ 带间隔号的纯英文值会被误判成「混中文」(2026-08-19 实测踩到)。
	var re := RegEx.create_from_string("[\\x{4e00}-\\x{9fff}\\x{3400}-\\x{4dbf}\\x{f900}-\\x{faff}]")
	for k in tb:
		var src := String(k)
		var dst := String(tb[k])
		if src == "" or dst == "":
			return "空键或空值: '%s' → '%s'" % [src, dst]
		if re.search(dst) != null:
			return "英文值里混着中文(漏翻): '%s'" % dst
		if src.count("%") != dst.count("%"):
			return "占位符数量不齐: '%s'(%d 个 %%)→ '%s'(%d 个 %%)" \
				% [src, src.count("%"), dst, dst.count("%")]
	return ""


## 脸难度排序(Director 的输入, 2026-08-18 接线)。⚑ **这是仪器输出不是设计常量**:
## 由 `tools/price.gd` 出数、脚本重刷, **手改无效**(probbook 同款纪律)。
## 校验是硬的:四段齐全、每段非空、id 都是活脸 —— 脸的池子一变这里就红,
## 「排序表过期」因此是测试期红灯而不是静默的旧导演。
static func ranking() -> Dictionary:
	return _load("ranking", func(d): return validate_ranking(d))


## 给 Run.face_ranking 的形状:{段号(int): [由易到难的 face_id]}。
static func ranking_tiers() -> Dictionary:
	var out := {}
	for k in ranking():
		if String(k).begins_with("_"):
			continue
		out[int(String(k))] = ranking()[k]
	return out


static func validate_ranking(d: Dictionary) -> String:
	var ids := {}
	for f in faces().get("faces", []):
		ids[String(f["id"])] = true
	# 段数从 run.json 推(2026-08-21 评审 D):按段索引的表不许写死 4(CLAUDE.md 那条清单)
	var n_sec := int(run().get("sections_per_gig", 1)) * int(run().get("gigs_per_run", 4))
	var sec_keys: Array = []
	for i in range(n_sec):
		sec_keys.append(str(i))
	for sec in sec_keys:
		if not d.has(sec):
			return "ranking 缺第 %s 段(Director 1.0 必须喂满, 用户拍板)" % sec
		var lst = d[sec]
		if typeof(lst) != TYPE_ARRAY or lst.is_empty():
			return "ranking 第 %s 段必须是非空数组" % sec
		for fid in lst:
			if not ids.has(String(fid)):
				return "ranking 第 %s 段有未知脸 '%s'(脸池变了 ⇒ 重跑 tools/price.gd 重刷)" % [sec, fid]
		# ⚠⚠ 反向完备性(2026-08-20 补, trilogy 事故):池里的脸必须都在排序表里 ——
		# Director.ranked_pool 是**取交**, 漏一张 = 那张脸永不登场且不报错(静默丢内容)。
		for pid in SectionMod.pool_for(int(sec)):
			if not lst.has(String(pid)):
				return "ranking 第 %s 段漏了池脸 '%s'(Director 取交后它永不登场)⇒ 重跑 tools/rankgen.py" % [sec, pid]
	for k in d:
		if not String(k).begins_with("_") and not sec_keys.has(String(k)):
			return "ranking 未知键 '%s'" % k
	return ""


## B 轴 · 跨局序列表(docs/design/difficulty.md §3)。`core/director.gd` 是它唯一的消费者。
static func director() -> Dictionary:
	return _load("director", func(d): return validate_director(d))


static func _load(fname: String, validator: Callable) -> Dictionary:
	if _cache.has(fname):
		return _cache[fname]
	var f := FileAccess.open("res://data/%s.json" % fname, FileAccess.READ)
	if f == null:
		_fail("%s.json: cannot open" % fname)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		_fail("%s.json: not a JSON object" % fname)
		return {}
	var v: String = validator.call(parsed)
	if v != "":
		_fail("%s.json: %s" % [fname, v])
	# ⚠ **违规也照常缓存并返回** —— 见文件头:这是「测试期门禁」的有意选择,
	# 不是漏写的 early-return。错误已经进了 `_err`, 而 `_err` 是**粘的**
	# (`load_error()` 累加, 不会被后续成功的加载冲掉), 所以测试一定红。
	# ⚠ 缓存之后不再重新校验 —— 文件在一次运行内不会变, 重验没有意义;
	# 但这意味着**错误只 push_error 一次**, 别指望在日志里反复看到它。
	_cache[fname] = parsed
	return parsed


## ⚠ `_err` 只增不减 —— 一旦有过违规, `load_error()` 在本次运行内**永远非空**。
## 这是故意的:测试断言的是「全程零违规」, 不是「最后一次加载是干净的」。
static func _fail(msg: String) -> void:
	_err += msg + "; "
	push_error("[DB] " + msg)


static func _keys_ok(d: Dictionary, allowed: Array) -> String:
	for k in d:
		if String(k).begins_with("_"):
			continue
		if not allowed.has(k):
			return "unknown key '%s'" % k
	for k in allowed:
		if not d.has(k):
			return "missing key '%s'" % k
	return ""


static func validate_run(d: Dictionary) -> String:
	var e := _keys_ok(d, _RUN_KEYS)
	if e != "":
		return e
	var n: int = int(d["sections_per_gig"]) * int(d["gigs_per_run"])
	if d["section_targets"].size() != n:
		return "section_targets wants %d entries" % n
	if d["gig_clocks"].size() != int(d["gigs_per_run"]):
		return "gig_clocks wants %d entries" % int(d["gigs_per_run"])
	if d["blind_names"].size() != int(d["sections_per_gig"]):
		return "blind_names wants %d entries" % int(d["sections_per_gig"])
	# 商店与盲注解耦(2026-08-06 用户拍板): 一段 6 拍、每 3 拍一次商店。
	# 必须整除, 否则中途商店会落在半拍上 —— 段尾那次就不是段末商店了。
	var pps: int = int(d["phrases_per_section"])
	var ppshop: int = int(d["phrases_per_shop"])
	if ppshop <= 0 or pps % ppshop != 0:
		return "phrases_per_section (%d) must be a multiple of phrases_per_shop (%d)" % [pps, ppshop]
	# 手速预算 (docs/design/solver_roadmap.md): 求解器与模拟器共用的上限, 必须为正。
	# swaps 至少要够把任意「8 选 5」搬进手牌 —— 那需要 cache_cap 次交换,
	# 少于它, 求解器就够不到部分持法, 上界会被工具而不是被游戏限制。
	var bb = d["beat_budget"]
	if typeof(bb) != TYPE_DICTIONARY or not bb.has("discards") or not bb.has("swaps") \
			or not bb.has("discard_batch"):
		return "beat_budget wants {discards, swaps, discard_batch}"
	if int(bb["discards"]) < 0 or int(bb["swaps"]) < 0:
		return "beat_budget must be non-negative"
	# 动作粒度(2026-08-27):discards = 动作次数, discard_batch = 单批张数上限。
	# 批上限 < 手牌数会让「整手换血」这个真人做得到的手势在模型里做不到 —— 静默削 bot。
	if int(bb["discard_batch"]) < int(d["hand_size"]):
		return "beat_budget.discard_batch (%d) < hand_size (%d): 单批连整手都圈不满" \
			% [int(bb["discard_batch"]), int(d["hand_size"])]
	if int(bb["swaps"]) < int(d["cache_cap"]):
		return "beat_budget.swaps (%d) < cache_cap (%d): solver could not reach every 5-of-8 hold" \
			% [int(bb["swaps"]), int(d["cache_cap"])]
	# 设计死亡谱 (2026-08-07 从 tools/curve.gd 挪进 data/)。生成器按它反解目标分,
	# 所以表长错了会**静默**用错分位 —— 和 sim.json bot_targets 被静默截断成放水盘
	# 同一个形状的坑, 那次坏了整整一天没人发现。
	# ⚠ **故意不校验单调性**:目标函数换成留存之后,「一关比一关难」是待检验的假设
	# 而不是原则, 而起承転結的「転」本来就不单调。这条曲线由搜索来挑。
	var ds = d["death_spec"]
	if typeof(ds) != TYPE_ARRAY or ds.size() != n:
		return "death_spec wants %d entries (one per section)" % n
	for v in ds:
		if float(v) < 0.0 or float(v) >= 1.0:
			return "death_spec entries are 到达者死亡率, must be in [0, 1) — got %s" % v
	# 首墙两层放水(2026-08-24)。min_run < 1 会让「第 0 局」这种不存在的局号当真;
	# chance 越界 = 静默变成「永远简单/永远不简单」, 两头都要喊。
	if int(d["s1_face_min_run"]) < 1:
		return "s1_face_min_run must be >= 1 (1 = 第 1 局起就掷脸)"
	if float(d["s1_easy_chance"]) < 0.0 or float(d["s1_easy_chance"]) >= 1.0:
		return "s1_easy_chance must be in [0, 1) — 1.0 就不是「偶尔」了, 那是删掉首墙"
	return ""


static func validate_economy(d: Dictionary) -> String:
	var e := _keys_ok(d, _ECO_KEYS)
	if e != "":
		return e
	# 稀有度的价格表与权重表键集必须相等 —— 拼错的稀有度两边各吞一个默认值
	var prices: Dictionary = d.get("joker_prices", {})
	var weights: Dictionary = d.get("draft_rarity_weights", {})
	for r in prices:
		if not weights.has(r):
			return "joker_prices 的稀有度 '%s' 不在 draft_rarity_weights 里" % r
	for r in weights:
		if not prices.has(r):
			return "draft_rarity_weights 的稀有度 '%s' 不在 joker_prices 里" % r
	# 经济 v2(2026-08-26):牌型金币表十键必须齐 —— 缺键 = 那个牌型结算给 0◆ 且不报错。
	var kc: Dictionary = d.get("kind_coins", {})
	for kn in ["HIGH_CARD", "PAIR", "TWO_PAIR", "THREE_KIND", "STRAIGHT",
			"FLUSH", "FULL_HOUSE", "FOUR_KIND", "STRAIGHT_FLUSH", "ROYAL_FLUSH"]:
		if not kc.has(kn):
			return "kind_coins 缺牌型 '%s'(那个牌型会静默给 0◆)" % kn
	return ""


static func validate_tape(d: Dictionary) -> String:
	# `upload` 是可选节(2026-08-21 外部审查:此前进了 _TAPE_KEYS 就成了必填, t_tape 的合法夹具当场红)
	var d_req := d.duplicate()
	d_req.erase("upload")
	var e := _keys_ok(d_req, _TAPE_KEYS)
	if e != "":
		return e
	if not d["mute"] is Array:
		return "mute wants an array of event names"
	# 缓冲一满就落盘(或退化成环形), 0 会让每条事件都触发一次写文件
	if int(d["max_events"]) < 1:
		return "max_events must be >= 1"
	# 回传节(1.1)。⚠ enabled 而 url 为空 = 配置想开却开不了, 这属于「静默不生效」
	# 一族(Beacon 会因 Uplink.enabled() 为 false 直接睡掉), 测试期就要红。
	if d.has("upload"):
		var up = d["upload"]
		if not up is Dictionary:
			return "upload wants an object"
		var ue := _keys_ok(up, ["enabled", "url", "batch_max", "retry_seconds"])
		if ue != "":
			return "upload: " + ue
		var uurl := String(up.get("url", ""))
		if bool(up.get("enabled", false)) and uurl == "":
			return "upload.enabled 开着但 url 为空 —— 要么填端点要么关掉"
		if uurl != "" and not (uurl.begins_with("https://") or uurl.begins_with("http://")):
			return "upload.url 必须是 http(s):// 端点"
		if int(up.get("batch_max", 3)) < 1:
			return "upload.batch_max must be >= 1"
		if float(up.get("retry_seconds", 30.0)) <= 0.0:
			return "upload.retry_seconds must be > 0"
	return ""


## Every param key a face may carry. ⚠ This whitelist is the whole point of
## the check: `SectionMod._param` falls back to a default on a missing key, so
## a typo'd param does not crash — it makes the face SILENTLY do nothing, and
## the section's target is then computed for a difficulty that never happened.
## That exact failure has already cost this project two faces (rush before the
## budget hook existed, cover with κ=0); it does not get a third.
## Split in two ON PURPOSE. `Solver._settle_identity()` skips the whole Settle
## chain when nothing can change the score — that single fast path is worth 4×
## on solver probes (8.4 → 36 ms/beat when it is lost). It used to give up the
## moment ANY face was present, which is far too blunt: most faces never touch
## Settle at all.
## ⚠ Putting a new param in the wrong list is a **silent scoring bug**, not a
## slowdown: a Settle-reading param filed under OTHER would be skipped by the
## fast path and the face would quietly stop working. Both lists are asserted
## against SectionMod in tests/runner.gd.
const _FACE_PARAMS_SETTLE := ["target_power", "bonus_disabled", "repeat_factor",
	"zero_discard_factor", "lock_first", "request_factor", "joker_power",
	"phase_factors", "suit_half", "callout_factor"]
const _FACE_PARAMS_OTHER := ["time_penalty", "phrase_toll", "cache_evict",
	"cache_cap_delta", "target_mult", "hide_refill", "hide_faces",
	"discard_lock_last", "swap_lock_last", "discard_actions", "swap_actions",
	"action_limit", "cache_block_red", "refill_rank_min", "refill_rank_max",
	"cache_lock_phrases", "seal_lowest_start", "required_kinds", "variety_penalty",
	"seal_oldest_cache", "restore_with_initial_cache", "section_discard_budget",
	"exclusive_action_tracks", "discard_cards_max", "action_cards_max",
	"seal_random_start", "seal_random_cache", "time_curve", "hide_random",
	"roll_chance", "roll_cache_extra", "roll_suit", "roll_kind",
	"hide_suits", "hide_ranks"]
const _FACE_PARAMS := _FACE_PARAMS_SETTLE + _FACE_PARAMS_OTHER
const _BOON_PARAMS := ["score_replay_factor", "spotlight_cards",
	"previous_raw_factor", "ghost_first_discard"]


## faces.json is data-only (2026-08-09: design prose moved to docs/design/blinds.md).
## ⚠ Unlike every other data file, `_`-prefixed keys are NOT treated as comments
## here — that exemption is exactly how the prose grew to 77.6% of the file
## before. Both the root object and each face entry are locked to a whitelist,
## so a stray `_why`/`_note` etc. added later fails loudly instead of quietly
## re-accumulating.
const _FACE_ROOT_KEYS := ["faces", "families", "fixed_tiers", "weak_upper_bound"]


static func validate_faces(d: Dictionary) -> String:
	for k in d:
		if not _FACE_ROOT_KEYS.has(k):
			return "faces.json unknown top-level key '%s' — it is data-only now, design notes belong in docs/design/blinds.md" % k
	if not d.has("faces"):
		return "wants 'faces'"
	var cerr := _validate_face_combos(d)
	if cerr != "":
		return cerr
	var ids := {}
	for e in d["faces"]:
		for k in e:
			if not ["id", "name", "cn", "fx", "params", "proof", "tape_required", "tier", "tiers",
					"min_run", "base", "combo"].has(k):
				return "face '%s' unknown key '%s' — faces.json is data-only now, design notes belong in docs/design/blinds.md §7" % [e.get("id", "?"), k]
		if e.has("tape_required") and not e["tape_required"] is bool:
			return "face '%s' tape_required wants bool" % e.get("id", "?")
		if ids.has(e["id"]):
			return "duplicate face id '%s'" % e["id"]
		# 档位脸(2026-08-26):base 必须指向存在的脸 —— 拼错 = 图标回落静默失效。
		if e.has("base"):
			var base_found := false
			for e2 in d["faces"]:
				if String(e2["id"]) == String(e["base"]):
					base_found = true
			if not base_found:
				return "face '%s' base '%s' 不存在" % [e["id"], e["base"]]
		var params: Dictionary = e.get("params", {})
		# 复合脸(2026-08-27)自己不带 params, 它的参数由成分合出来 —— 空不等于「什么都不做」。
		# 「恰两成分 / 异轴 / 成分先登过场 / 同键冲突」四条在 `_validate_face_combos` 里守。
		if params.is_empty() and not e.has("combo"):
			return "face '%s' has no params — it would do nothing" % e["id"]
		for pk in params:
			if not _FACE_PARAMS.has(String(pk)):
				return "face '%s' unknown param '%s'" % [e["id"], pk]
		ids[e["id"]] = true
	# 池子由 tier 推导(2026-08-07 用户拍板): 一张脸的归属只写一遍, 而且**不填 tier
	# 就进不了池子** —— 手写池子时「这张新脸塞哪轮」是可以被忘掉的, 现在忘不掉。
	# ⚠ 这里刻意不引用 `GameConfig` —— 它是 data/ 之上的门面、反过来读 DB, 会成环。
	# 「tier 覆盖了全部段」那条断言放在 tests/runner.gd(那边两边都看得见)。
	# ⚑ 2026-08-14:轮次从**一个数**放成**一个集合**(`tiers`), `tier` 留作**主场轮次** ——
	# 定价(tools/price.gd)与门禁(tools/gate.gd)的基准位置。缺 `tiers` 时退回 `[tier]`,
	# 所以既有 30 张脸一行不用改、行为逐字节不变。理由与证据见 core/modifier.gd 文件头。
	# ⚠ 这里刻意不调 `SectionMod.tiers_of_entry` —— 它反过来读 DB, 会成环(同 GameConfig 那条)。
	var by_tier := {}          # tier -> [face id]
	var tier_of := {}          # face id -> 主场 tier
	# ⚑ 教学弧那条断言(soft 必须早于 hard)问的是「**最早**出现在第几轮」, 不是主场 ——
	# 轮次放成集合之后这两个不再是同一个数, 而**旧代码用主场问了一个关于顺序的问题**。
	# 这正是「改段数要顺手核对所有按段索引的表」那条踩过的形状:schema 放宽会**静默**打破
	# 按单值索引的不变量。单轮时 min(tiers) == tier, 所以既有行为不变。
	var first_tier_of := {}    # face id -> min(tiers)
	for e in d["faces"]:
		if not e.has("tier"):
			if e.has("tiers"):
				return "face '%s' 只写了 tiers 没写 tier —— tier 是主场轮次(定价/门禁的基准位置), 不能省" % e["id"]
			continue           # 没有 tier = 没入池(退役, 或还没决定塞哪轮)
		var t: int = int(e["tier"])
		if t < 1:
			return "face '%s' tier must be >= 1 (玩家口径的第几轮), got %d" % [e["id"], t]
		var ts: Array = [t]
		if e.has("tiers"):
			if not (e["tiers"] is Array):
				return "face '%s' tiers wants an array of 轮次" % e["id"]
			ts = []
			for v in e["tiers"]:
				var vt: int = int(v)
				if vt < 1:
					return "face '%s' tiers 里有 %d —— 轮次从 1 起" % [e["id"], vt]
				if ts.has(vt):
					return "face '%s' tiers 里 %d 写了两遍" % [e["id"], vt]
				ts.append(vt)
			if ts.is_empty():
				return "face '%s' tiers 是空的 —— 想退池就把 tier 一起删掉" % e["id"]
			# 主场必须在合法集里, 否则定价基准指向一个这张脸不会出现的位置。
			if not ts.has(t):
				return "face '%s' 主场 tier=%d 不在 tiers=%s 里 —— 定价基准会指向它不出现的轮次" % [e["id"], t, str(ts)]
		var earliest: int = t
		for tv in ts:
			if not by_tier.has(tv):
				by_tier[tv] = []
			by_tier[tv].append(String(e["id"]))
			earliest = mini(earliest, int(tv))
		tier_of[String(e["id"])] = t
		first_tier_of[String(e["id"])] = earliest
	# 「每轮 >=2 张」曾经是硬规则, 理由写的是「否则脸的价格不可辨识」—— **那个理由是错的**:
	# tools/price.gd 对**无脸基准**测价, 不在池内互比。固定的真实代价是**新鲜感为零**,
	# 所以规则改成:固定允许, 但必须显式声明。**固定必须是有意的, 不能是排漏了。**
	# ⚠⚠ **JSON 的数字全是 float, 而 `Array.has()` 是严格比较** —— `[4.0].has(4)` 是
	# **false**, 不报错, 只是「声明了等于没声明」。这个项目最典型的静默失配形状,
	# 2026-08-07 当场踩到:fixed_tiers 写了 [4] 却一直判定成没写。**读进来先转 int。**
	var fixed: Array = []
	for v in d.get("fixed_tiers", []):
		fixed.append(int(v))
	for t in by_tier:
		var cnt: int = by_tier[t].size()
		if cnt < 2 and not fixed.has(t):
			return "tier %d 只有 %d 张脸, 这一轮每局都一样 —— 想固定就写进 fixed_tiers(设计判据见 docs/design/blinds.md §3)" % [t, cnt]
		if cnt > 1 and fixed.has(t):
			return "tier %d 声明成 fixed 却有 %d 张脸 —— 声明和内容对不上" % [t, cnt]
	# 覆盖自证的**量级豁免**(2026-08-08 用户拍板 A 案)。判据两条 —— |z|>=3(信不信得过)
	# **且** 量级>=5%(要不要管);量级不够时允许豁免, 但**必须显式声明**,
	# 和 `fixed_tiers` 同一条原则:**豁免必须是有意的, 不能是漏掉的**。
	# ⚠ 声明的是"对**完美玩家**的上界效应小", **不是**"这张脸没用" —— 见 docs/design/blinds.md §5。
	# ⚠ 拼错 id 会让豁免**静默失效**(门照样红, 所以不至于放行, 但作者会一头雾水), 这里挡掉。
	# ⚠ 退役的脸留在列表里也挡掉:它是一块过期的遮羞布。
	for w in d.get("weak_upper_bound", []):
		var wid := String(w)
		if not ids.has(wid):
			return "weak_upper_bound 里的 '%s' 不是任何一张脸的 id —— 拼错了, 或者那张脸已经退役" % wid
		if not tier_of.has(wid):
			return "weak_upper_bound 里的 '%s' 没有 tier(不在任何池子里), 豁免一张不出场的脸没有意义" % wid
	var ferr := _validate_face_families(d, ids, first_tier_of)
	if ferr != "":
		return ferr
	return _validate_face_proof(d, tier_of)


## 教学关脚本(docs/design/difficulty.md §4)。`core/tutorial.gd` 是它唯一的消费者。
## ⚠ 这里守的是**结构**, 不是内容:拍长多少、教哪几步是设计, 由用户直接改 JSON。
static func validate_tutorial(d: Dictionary) -> String:
	for k in d:
		if String(k).begins_with("_"):
			continue
		if not ["components", "steps", "cutins"].has(k):
			return "tutorial.json unknown top-level key '%s'" % k
	if not d.has("components") or not (d["components"] is Array) or d["components"].is_empty():
		return "tutorial.json wants a non-empty 'components' whitelist"
	if not d.has("steps") or not (d["steps"] is Array) or d["steps"].is_empty():
		return "tutorial.json wants a non-empty 'steps' array"
	var known: Array = []
	for c in d["components"]:
		known.append(String(c))
	# 区域白名单来自 `ui.json` 的 `tutor_focus`(坐标归 ui.json 那条铁律)。
	# ⚠ 这里嵌套调 `ui()` 是安全的:`_load` 有缓存, 且 ui 的校验不反过来读 tutorial(无环)。
	var known_regions: Array = []
	for rk in ui().get("tutor_focus", {}):
		if not String(rk).begins_with("_"):
			known_regions.append(String(rk))
	# 亮过的部件 —— 同一个部件解锁两次是脚本写错了(第二次是死行, 而且读起来像它会再亮一遍)。
	var seen: Array = []
	# 分镜(v6):同 shot 的步必须 focus 相同(构图共享是分镜的定义, 岔开 = 镜头会跳),
	# 且必须连续(A B A 那样被打断的分镜是脚本写错了)。
	var shot_focus := {}
	var last_shot := ""
	for i in range(d["steps"].size()):
		var st = d["steps"][i]
		if not (st is Dictionary):
			return "tutorial step %d wants an object" % i
		for k in st:
			if not ["seconds", "unlock", "require", "command", "signal", "focus",
					"shot", "spot", "args"].has(String(k)):
				return "tutorial step %d unknown key '%s'" % [i, k]
		# ⚠⚠ **写错一个动作名, 那一步永远推进不了, 而且不报错** —— 玩家会**卡死在教学关里**,
		# 而这是个只有真人玩才发现得了的死法(探针不走 view, 不产生这些动作)。
		# 所以这条必须是硬校验, 和「focus 指向未知区域」同一类静默失败。
		var req := String(st.get("require", ""))
		if req != "" and not Tutorial.ACTIONS.has(req):
			return "tutorial step %d require 未知动作 '%s'(白名单: %s)" \
				% [i, req, ", ".join(Tutorial.ACTIONS)]
		# 指向一块不存在的区域 = **画不出来而且不报错**, 正是这个项目最贵的那类静默失败。
		for r in st.get("focus", []):
			if not known_regions.has(String(r)):
				return "tutorial step %d focus 指向未知区域 '%s'(白名单在 data/ui.json 的 tutor_focus: %s)" \
					% [i, r, ", ".join(known_regions)]
		var sh := String(st.get("shot", ""))
		if sh != "":
			if shot_focus.has(sh):
				if last_shot != sh:
					return "tutorial step %d 的分镜 '%s' 不连续 —— 同一分镜的步必须挨着" % [i, sh]
				if shot_focus[sh] != st.get("focus", []):
					return "tutorial step %d 与同分镜 '%s' 的 focus 不一致 —— 分镜 = 构图共享, 同 shot 必同 focus" % [i, sh]
			shot_focus[sh] = st.get("focus", [])
		last_shot = sh
		var sp := String(st.get("spot", ""))
		if sp != "" and not known_regions.has(sp):
			return "tutorial step %d spot 指向未知区域 '%s'" % [i, sp]
		var terr := _tutorial_text_error(String(st.get("command", "")),
			st.get("args", []), "tutorial step %d" % i)
		if terr != "":
			return terr
		if float(st.get("seconds", 0.0)) <= 0.0:
			return "tutorial step %d wants seconds > 0" % i
		for c in st.get("unlock", []):
			var id := String(c)
			if not known.has(id):
				return "tutorial step %d unlocks unknown component '%s' (whitelist: %s)" \
					% [i, id, ", ".join(known)]
			if seen.has(id):
				return "tutorial step %d unlocks '%s' again — unlock 是累积的, 写两遍是死行" % [i, id]
			seen.append(id)
		# 卡面那条规矩:英文 ≤7 词(1.5 秒读懂)。提示行沿用同一条。
		var sig := String(st.get("signal", ""))
		if sig == "" or String(st.get("command", "")) == "":
			return "tutorial step %d wants both command(中文) and signal(英文短标)" % i
		if sig.split(" ", false).size() > 7:
			return "tutorial step %d signal '%s' 超过 7 词(卡面那条 1.5 秒规矩)" % [i, sig]
	# 走完教学关必须全部解锁, 否则某个部件会一直是灰的 —— 那是个静默死锁。
	for id in known:
		if not seen.has(id):
			return "component '%s' 从来没被任何一步解锁 —— 教学关走完它仍是灰的" % id
	# ---- 特写(v6 cutins):α/β = RESOLVE 冻钟插播, γ = 转正式的公示卡 ----
	# 名字是白名单:消费面按名字分流(编排器只认这三个), 写错名字 = 永不播且不报错。
	if d.has("cutins"):
		if not (d["cutins"] is Dictionary):
			return "tutorial.json cutins wants an object"
		for ck in d["cutins"]:
			var cname := String(ck)
			if cname.begins_with("_"):
				continue
			if not ["alpha", "beta", "gamma"].has(cname):
				return "cutins 未知特写 '%s'(白名单: alpha, beta, gamma —— 消费面按名字分流)" % cname
			var cu = d["cutins"][ck]
			if not (cu is Dictionary):
				return "cutin '%s' wants an object" % cname
			for k2 in cu:
				if not ["after_step", "seconds", "focus", "command", "args"].has(String(k2)):
					return "cutin '%s' unknown key '%s'" % [cname, k2]
			var af := int(cu.get("after_step", -1))
			if af < 0 or af > d["steps"].size():
				return "cutin '%s' after_step %d 越界(0..%d)" % [cname, af, d["steps"].size()]
			if float(cu.get("seconds", 0.0)) <= 0.0:
				return "cutin '%s' wants seconds > 0" % cname
			for r2 in cu.get("focus", []):
				if not known_regions.has(String(r2)):
					return "cutin '%s' focus 指向未知区域 '%s'" % [cname, r2]
			if String(cu.get("command", "")) == "":
				return "cutin '%s' wants a command" % cname
			var cerr := _tutorial_text_error(String(cu.get("command", "")),
				cu.get("args", []), "cutin '%s'" % cname)
			if cerr != "":
				return cerr
	return ""


## v6 文案的两条硬校验(steps 与 cutins 共用):
## ① %d 价签个数 = args 个数、键在 `Tutorial.ARG_KEYS` —— 不一致 = 运行时格式化直接炸;
## ② {} 高亮段配对且**至多一个**(设计规格;TutorHint 按它画双色, 画不出来不报错)。
static func _tutorial_text_error(cmd: String, args, where: String) -> String:
	if not (args is Array):
		return "%s args wants an array" % where
	for a in args:
		if not Tutorial.ARG_KEYS.has(String(a)):
			return "%s args 未知键 '%s'(白名单: %s)" % [where, a, ", ".join(Tutorial.ARG_KEYS)]
	if cmd.count("%d") != args.size():
		return "%s 的 %%d 价签有 %d 个而 args 给了 %d 个 —— 个数必须一致" \
			% [where, cmd.count("%d"), args.size()]
	var open_n := cmd.count("{")
	if open_n != cmd.count("}") or open_n > 1:
		return "%s 的 {} 高亮段必须配对且至多一个(每句一个重点)" % where
	if open_n == 1 and cmd.find("{") > cmd.find("}"):
		return "%s 的 {} 顺序反了" % where
	return ""


## ---- B 轴 · Director(docs/design/difficulty.md §3) ----
##
## ⚑⚑ **Director 是一张按局数索引、对所有人相同的设计常量表**(2026-08-14 用户拍板:
## 「这里不是千人千面的不用读 context」)。所以这里守的是**结构**, 不是内容 ——
## 第几局哪个状态、货架偏多少是设计, 用户直接改 JSON;而**它能碰哪些字段**是铁律,
## 由下面这三张表锁死。
const _DIRECTOR_KEYS := ["band_fraction", "loop_from", "sequence", "states"]
const _DIRECTOR_STATE_KEYS := ["face_bias", "shelf"]
const _DIRECTOR_SHELF_KEYS := ["rarity_weight_mult"]
const _DIRECTOR_BIASES := ["mild", "median", "harsh"]

## **明确禁用**的键 —— 白名单本来就挡得住它们, 这张表是为了**说清楚为什么**。
## ⚠ 「unknown key」那种错误信息会让作者以为「拼错了, 换个名字就行」, 而这里每一条
## 都是**拍过板的边界**, 换个名字照样越界。四类:
##   ① 目标分/难度形状 —— 铁律「Director 不许调目标分」(玩家看得见的数不许按局数漂);
##   ② 价格 —— 定价先过 docs/design/numbers.md 的宪法, 不许从这里绕;
##   ③ 「必定出某张牌」—— 2026-08-06 用户拍板「不应该有任何卡有固定概率」,
##      活法是**把保证写在卡面上**(独狼/点唱机), 不是藏进 Director 的掷点;
##   ④ 读 context —— 2026-08-14 拍板作废的那三节(Inputs / 行为模型 / 掌握度)。
const _DIRECTOR_FORBIDDEN := {
	"target_mult": "铁律「Director 不许调目标分」(docs/design/difficulty.md §3)—— 玩家看得见的数不许按局数漂",
	"section_targets": "目标分表在 data/run.json, 它对所有人、对每一局都是同一张",
	"death_spec": "难度形状是 A 轴的设计常量(data/run.json), 不是 B 轴的手段",
	"gig_clocks": "拍长玩家感觉得到(时间是唯一压力货币)—— 教学关可以放宽, 正式局不许按局数漂",
	"joker_prices": "定价先过 docs/design/numbers.md 的三轴框架与六步 SOP, 不许从 Director 绕",
	"price_delta": "同上;货架价格增减是卡面效果(赞助), 不是 Director 的口",
	"reroll": "同上",
	"discard_cost": "同上",
	"starting_coins": "同上",
	"section_clear_reward": "同上",
	"target_guaranteed": "「不应该有任何卡有固定概率」(2026-08-06 用户拍板)—— 保证要写在**卡面**上(独狼), 不许藏进掷点",
	"rule_guaranteed": "同上(点唱机)",
	"target_weight_mult": "同上:货架上 Target 的权重是卡面效果, 不是按局数的暗改",
	"inputs": "context 走 roll_run 的 ctx **入参**(2026-08-19 推翻「不读 context」后仍然如此)—— 数据侧只有 `context` 节的两个布尔开关, 玩家模型的形状不许从数据进",
	"player_model": "同上(levels.md 的 Recent behavior model 已作废;新的 m 向量在 SaveState, 由编排器传参)",
	"tendency": "同上",
	"mastery": "同上(Joker learning states 已作废)",
	"rolling_window": "同上",
}


## 跨局序列表(docs/design/difficulty.md §3)。`core/director.gd` 是它唯一的消费者。
## ⚠ 这里读 `economy()` 拿稀有度名单 —— 不引用 `GameConfig`(它反过来读 DB, 会成环,
## 同 `validate_faces` 那条);`validate_economy` 不碰 director, 所以不成环。
static func validate_director(d: Dictionary) -> String:
	# ⚠ **禁用键要先于白名单查** —— 否则作者只会看到一句「unknown key」, 拿不到越界的理由。
	for k in d:
		var re := _director_key_ok(String(k), "")
		if re != "":
			return re
	for sname in d.get("states", {}):
		var st = d["states"][sname]
		if st is Dictionary:
			var se := _director_no_forbidden(st, "states.%s." % sname)
			if se != "":
				return se
	# `context` / `cycle` 是可选键, 摘掉再对白名单(_keys_ok 把 allowed 同时当必备键用)。
	var d_req := d.duplicate()
	d_req.erase("context")
	d_req.erase("context_tuning")
	d_req.erase("cycle")
	var e := _keys_ok(d_req, _DIRECTOR_KEYS)
	if e != "":
		return e
	# context 节(2026-08-19「基于 context」推翻 08-14 拍板后的**唯一**数据面):
	# **可选键**(不在 _DIRECTOR_KEYS 里 —— 那张表同时当必备键用), 有则恰好两个布尔开关,
	# 多一个键都是在往数据里塞玩家模型, 那仍然被上面的禁用表挡着。
	if d.has("context"):
		var cx = d["context"]
		if not cx is Dictionary:
			return "context 要是对象"
		for ck in cx:
			if String(ck).begins_with("_"):
				continue
			if not ["novelty", "streak_shift", "returning", "explore_shelf"].has(String(ck)):
				return "context 未知键 '%s'(开关白名单: novelty/streak_shift/returning/explore_shelf)" % ck
			if typeof(cx[ck]) != TYPE_BOOL:
				return "context.%s 要是布尔开关" % ck
	# context_tuning(可选):四个阈值, 只许这四个键, 各自有下界
	if d.has("context_tuning"):
		var tn = d["context_tuning"]
		if not tn is Dictionary:
			return "context_tuning 要是对象"
		var bounds := {"lose_streak": 1, "win_streak": 1, "return_gap_days": 1, "explore_mult": 1.0}
		for tk in tn:
			if String(tk).begins_with("_"):
				continue
			if not bounds.has(String(tk)):
				return "context_tuning 未知键 '%s'(白名单: %s)" % [tk, ", ".join(bounds.keys())]
			if not (tn[tk] is float or tn[tk] is int) or float(tn[tk]) < float(bounds[tk]):
				return "context_tuning.%s 要 ≥ %s, got %s" % [tk, str(bounds[tk]), str(tn[tk])]
	# cycle 节(可选):10-run 周期机制课程(difficulty.md §2.5, 2026-08-26 用户拍板)。
	# 结构铁律与 states 同一条线:**它只偏置「哪张脸上场」**, 能写的只有轴名 +
	# 考试题型 + 一个权重乘数 —— 多一个键就是多一条按局数漂的通道。
	if d.has("cycle"):
		var cy = d["cycle"]
		if not cy is Dictionary:
			return "cycle 要是对象"
		for ck in cy:
			if String(ck).begins_with("_"):
				continue
			if not ["groups", "bias_mult"].has(String(ck)):
				return "cycle 未知键 '%s'(只有 groups / bias_mult)" % ck
		if cy.has("bias_mult"):
			var bm = cy["bias_mult"]
			if not (bm is float or bm is int) or float(bm) < 1.0:
				return "cycle.bias_mult 要 ≥ 1(1 = 没有课程;<1 会把课程静默反转成回避), got %s" % str(bm)
		var gs = cy.get("groups", [])
		if not (gs is Array) or gs.is_empty():
			return "cycle.groups 是空的 —— 周期表至少要有一组"
		var axes: Array = SectionMod.axis_ids()
		for gi in range(gs.size()):
			var row = gs[gi]
			if not (row is Array) or row.size() != 10:
				return "cycle.groups[%d] 要恰好 10 位(10-run 周期是用户拍的数), got %s" \
					% [gi, str(row.size() if row is Array else row)]
			for p in range(row.size()):
				var slot := String(row[p])
				if p == 4 or p == 9:
					# 考试位(第 5/10 局)。⚠ 轴名写在这里会**静默变成学习位**才要拦。
					if not ["wall", "combo"].has(slot):
						return "cycle.groups[%d] 第 %d 位是考试位, 只能是 wall/combo, got '%s'" \
							% [gi, p + 1, slot]
				elif not axes.has(slot):
					# ⚠ 拼错的轴名会让那两局**静默没有课程**(attack_axes 匹配不到任何脸),
					# 正是这个项目栽过六次的形状。轴名单只有一份 —— SectionMod._AXIS_PARAMS。
					return "cycle.groups[%d] 第 %d 位 '%s' 不是攻击轴(有 %s;考试题型只许在第 5/10 位)" \
						% [gi, p + 1, slot, ", ".join(axes)]
	# 档宽:0 会让每一档都空(pick_face 无解), >1 等于「整池」也就是没有倾向。
	var bf := float(d["band_fraction"])
	if bf <= 0.0 or bf > 1.0:
		return "band_fraction 要在 (0, 1] —— 0 会让每一档都空, >1 等于没有倾向, got %s" % str(bf)
	if not (d["sequence"] is Array) or d["sequence"].is_empty():
		return "sequence 是空的 —— Director 至少要给第 1 局一个状态"
	if not (d["states"] is Dictionary) or d["states"].is_empty():
		return "states 是空的"
	var n: int = d["sequence"].size()
	var lf := int(d["loop_from"])
	if lf < 0 or lf >= n:
		return "loop_from=%d 越界(sequence 有 %d 项, 合法下标 0..%d)—— 走完序列之后就没有下一局了" \
			% [lf, n, n - 1]
	var used := {}
	for i in range(n):
		var sname := String(d["sequence"][i])
		if not d["states"].has(sname):
			return "sequence 第 %d 项 '%s' 不是任何一个 state —— 拼错了" % [i + 1, sname]
		used[sname] = true
	# 定义了却没排进序列的状态 = 一行死设计(同 tutorial 那条「解锁两次是死行」)。
	# ⚠ 它不会报错也不会生效, 只会让读表的人以为这一局会发生别的事。
	for sname in d["states"]:
		if not used.has(String(sname)):
			return "state '%s' 从来没进过 sequence —— 那是一行死设计, 排进去或者删掉" % sname
	var rar: Dictionary = economy().get("draft_rarity_weights", {})
	for sname in d["states"]:
		var st = d["states"][sname]
		if not (st is Dictionary):
			return "state '%s' wants an object" % sname
		var ke := _keys_ok(st, _DIRECTOR_STATE_KEYS)
		if ke != "":
			return "state '%s': %s —— Director 一局只调两样(脸的排布 + 货架), 见 docs/design/difficulty.md §3" \
				% [sname, ke]
		if not _DIRECTOR_BIASES.has(String(st["face_bias"])):
			return "state '%s' 的 face_bias '%s' 不认识, 只能是 %s" \
				% [sname, st["face_bias"], str(_DIRECTOR_BIASES)]
		var sh = st["shelf"]
		if not (sh is Dictionary):
			return "state '%s' 的 shelf wants an object —— 中性写 {}(中性必须是有意的, 不能是漏掉的)" % sname
		for k in sh:
			if String(k).begins_with("_"):
				continue
			if not _DIRECTOR_SHELF_KEYS.has(String(k)):
				return "state '%s' 的 shelf 不认识 '%s'(只有 %s)" \
					% [sname, k, ", ".join(_DIRECTOR_SHELF_KEYS)]
		var rw = sh.get("rarity_weight_mult", {})
		if not (rw is Dictionary):
			return "state '%s' 的 rarity_weight_mult wants an object" % sname
		for k in rw:
			var rk := String(k)
			# ⚠ 拼错的稀有度会**静默不生效**(乘数找不到就退回 1.0), 正是这个项目栽过
			# 六次的形状。稀有度名单只有一份 —— data/economy.json。
			if not rar.has(rk):
				return "state '%s' 的 rarity_weight_mult 里 '%s' 不是 data/economy.json 的稀有度(有 %s)" \
					% [sname, rk, ", ".join(rar.keys())]
			if float(rw[k]) <= 0.0:
				return "state '%s' 的 rarity_weight_mult['%s'] = %s —— 必须 > 0(0 等于把这一档从货架上删掉, 那是改规则不是加倾向)" \
					% [sname, rk, str(rw[k])]
	return ""


static func _director_key_ok(ks: String, path: String) -> String:
	if ks.begins_with("_"):
		return ""
	if _DIRECTOR_FORBIDDEN.has(ks):
		return "director.json 的 `%s%s` 是**明确禁用**的键 —— %s" % [path, ks, _DIRECTOR_FORBIDDEN[ks]]
	# 脸的参数不许在这里出现:Director **只排布脸, 不改脸**。一张脸是什么由
	# data/faces.json 定义, 从 Director 覆写等于同一个口径写两处(而且是按局数漂的那一处)。
	if _FACE_PARAMS.has(ks):
		return "director.json 的 `%s%s` 是**脸的参数**(data/faces.json)—— Director 只排布脸, 不改脸" \
			% [path, ks]
	return ""


## ⚠ 只在**状态条目内部**递归 —— 不扫 `states` 自己的键, 那是状态名(设计者起的),
## 撞上禁用词表是误伤(例:草案七状态里就有 `Mastery`)。
static func _director_no_forbidden(d: Dictionary, path: String) -> String:
	for k in d:
		var ks := String(k)
		var e := _director_key_ok(ks, path)
		if e != "":
			return e
		if d[k] is Dictionary:
			var sub := _director_no_forbidden(d[k], path + ks + ".")
			if sub != "":
				return sub
	return ""


static func validate_boons(d: Dictionary) -> String:
	for k in d:
		if k != "boons":
			return "boons.json unknown top-level key '%s'" % k
	if not d.has("boons") or not d["boons"] is Array:
		return "wants 'boons' array"
	var ids := {}
	for e in d["boons"]:
		if not e is Dictionary:
			return "boon entry wants object"
		for k in e:
			if not ["id", "name", "cn", "fx", "params"].has(k):
				return "boon '%s' unknown key '%s'" % [e.get("id", "?"), k]
		for k in ["id", "name", "cn", "fx", "params"]:
			if not e.has(k):
				return "boon '%s' missing '%s'" % [e.get("id", "?"), k]
		var id := String(e["id"])
		if ids.has(id):
			return "duplicate boon id '%s'" % id
		ids[id] = true
		if not e["params"] is Dictionary or e["params"].is_empty():
			return "boon '%s' has no params" % id
		for pk in e["params"]:
			if not _BOON_PARAMS.has(String(pk)):
				return "boon '%s' unknown param '%s'" % [id, pk]
	return ""


## 覆盖自证契约(docs/design/gates.md):**一条规则如果进不了模型, 它就不该进池子。**
## 每张进了池子的脸必须声明它在模型里走哪条通路, `tools/gate.gd` 照着这个声明
## 给它造配对对照臂。漏声明 = 直接红, 和 `_FACE_PARAMS` 两张表同一个思路:
## **强制作者做一次决定, 而不是默认走一条恰好不报错的路。**
## ⚠ 声明错通路是**静默**的(门会给它造一条测不到东西的臂然后放过它) —— 这个项目
## 栽过四次的「规则在游戏里, 不在模型里」全是这个形状。通路的含义见 docs/design/blinds.md §4。
## ⚠ **选错通路会把结论量反, 而且不报错。** 2026-08-07 第一次全量跑抓到: 用规则 bot 量
## freshsheet(翻篇)得到 **+1584 分**(脸让玩家变强!), 换成完美玩家是 **−790**。
## 规则 bot 不跨拍养缓存, 洗掉缓存反而帮它甩了烂牌。**攻击跨拍养牌或时间预算的脸必须走 solver。**
## ⚠ 「tape」不是通路(2026-08-10 修复):真人验证是另一条证据线, 用每张脸的
## `tape_required` 标志声明, 不顶替模型通路 —— 否则 tools/gate.gd 无臂可造,
## 门会当场红(实测 lastcall 就是这样死的)。时间窗类脸走 solver + weak_upper_bound
## (模型上界近零, 真人待定), 与铁律「测出近零不许改内容」同一条线。
const FACE_PROOFS := ["score", "solver", "belief", "target"]


## ⚑ **复合脸的语法门**(2026-08-27, docs/design/versus.md 复合语法节 + blinds.md §2.6)。
##
## 复合的语法是「**乙脸封掉甲脸的最优解**」, 不是随便两张叠加。语法本身守不住(那是设计
## 判断), 但它的**四条形式前提**守得住, 而且每一条漏掉都是**静默错**:
##   ① **恰两成分** —— 三张起就不是「一道题 + 一把锁」, 是围殴;玩家读不出题干。
##   ② **成分存在** —— 拼错 = 那一半参数凭空消失, 脸变软, 不报错。
##   ③ **成分先单独登过场**(自带 tier) —— 复合是「你见过的两件事咬在一起」, 零学习成本
##      的前提是两件事都见过;没 tier 的成分等于在复合里首发一条没人见过的规则。
##   ④ **异轴** —— 同轴叠加只是把同一个拨盘拧两下(= 刻度, 纪律 6 说那不算新内容),
##      而且会让 `enforce_axis_budget` 的围殴计数把一张脸算成一份、实际压两份。
## 外加两条「不许有隐性规则」:复合条目**自己不带 params**(否则合并顺序成了藏起来的规则),
## 两成分**同键不许冲突**(冲突时无论取谁都是在悄悄改一张已上线脸的数值)。
##
## ⚠ 这里只许用 `SectionMod.axes_of_params()` 这个**纯函数**, 不许用 `attack_axes(id)` ——
## 后者反过来读 `DB.faces()`, 而本函数跑在 faces.json 的**装载途中**, 会成环
## (同 `validate_ranking` 那条「刻意不调 tiers_of_entry」)。
static func _validate_face_combos(d: Dictionary) -> String:
	var by_id := {}
	for e in d["faces"]:
		by_id[String(e["id"])] = e
	for e in d["faces"]:
		if not e.has("combo"):
			continue
		var fid := String(e["id"])
		var own_params: Dictionary = e.get("params", {})
		if not own_params.is_empty():
			return "复合脸 '%s' 不许自带 params —— 参数只能来自两成分, 否则合并顺序成了隐性规则" % fid
		if e.has("base"):
			return "复合脸 '%s' 不许同时声明 base —— 档位与复合是两条扩池轴, 混用后图标回落说不清" % fid
		if not (e["combo"] is Array):
			return "复合脸 '%s' 的 combo 必须是成分 id 数组" % fid
		var comps: Array = e["combo"]
		if comps.size() != 2:
			return "复合脸 '%s' 有 %d 个成分 —— 复合恰两成分(versus.md:三张起是围殴, 读不出题干)" % [fid, comps.size()]
		if String(comps[0]) == String(comps[1]):
			return "复合脸 '%s' 的两个成分是同一张 '%s'" % [fid, comps[0]]
		var axes: Array = []          # 逐成分的轴集合
		var seen_params := {}         # param key -> 先声明它的成分 id
		for c in comps:
			var cid := String(c)
			if not by_id.has(cid):
				return "复合脸 '%s' 的成分 '%s' 不存在" % [fid, cid]
			var ce: Dictionary = by_id[cid]
			if ce.has("combo"):
				return "复合脸 '%s' 的成分 '%s' 自己也是复合 —— 复合不许套娃" % [fid, cid]
			if not (ce.has("tier") or ce.has("tiers")):
				return "复合脸 '%s' 的成分 '%s' 没有 tier —— 成分必须先单独登过场(versus.md 复合语法)" % [fid, cid]
			var cp: Dictionary = ce.get("params", {})
			for k in cp:
				if seen_params.has(String(k)):
					return "复合脸 '%s' 的两成分都写了 '%s'(%s 与 %s)—— 同键冲突, 取谁都是在悄悄改一张已上线脸的数值" \
						% [fid, k, seen_params[String(k)], cid]
				seen_params[String(k)] = cid
			var ax: Array = SectionMod.axes_of_params(cp)
			if ax.is_empty():
				return "复合脸 '%s' 的成分 '%s' 不挂任何攻击轴 —— 连「异轴」都判不了(给它的 param 补一条轴)" % [fid, cid]
			axes.append(ax)
		for a in axes[0]:
			if axes[1].has(a):
				return "复合脸 '%s' 的两成分同轴 '%s' —— 同轴叠加只是把同一个拨盘拧两下(versus.md:异轴)" % [fid, a]
	return ""


static func _validate_face_proof(d: Dictionary, tier_of: Dictionary) -> String:
	var proofs := {}
	for e in d["faces"]:
		if e.has("proof"):
			if not FACE_PROOFS.has(String(e["proof"])):
				return "face '%s' unknown proof channel '%s' (want one of %s)" \
					% [e["id"], e["proof"], ", ".join(FACE_PROOFS)]
			proofs[e["id"]] = true
	for fid in tier_of:
		if not proofs.has(fid):
			return "face '%s' is in a pool without a `proof` channel — see docs/design/blinds.md §4" % fid
	return ""


const _PREDICATES := ["kind", "kind_in", "same_as_prev", "diff_from_prev",
	"acted_late", "discards_eq", "discards_gte", "coins_gte", "base_gte",
	"last_phrase", "cache_mono_suit", "cache_mono_color", "top_rank_gte", "counter_gte",
	"first_phrase", "section_eq", "early_finish", "all_suits", "no_pair",
	"cache_all_faces", "cache_run", "cache_trio",
	"swaps_eq", "discard_batch_gte", "section_doubled",
	"acted_final", "early_discards",
	"target_streak",  # 2026-08-25 镜面改造:连续两拍达成旗条件(core/fx.gd::_when_ok)
	"chance"]         # 2026-08-25 赌具组:掷点谓词(Beat 预掷, 结算保持纯函数)
const _DO_KEYS := ["mult", "mult_add", "additive", "bonus", "bonus_target_pct", "bonus_pct",
	"coins", "per", "step", "cap", "mult_from_target_factor", "additive_face_value",
	"additive_low_value", "additive_cache_top", "chips_per_card", "card_filter",
	"coins_factor"]

## 计数器 spec 的合法键(2026-08-13 补, 与 per/acquire/shelf 同一条纪律:
## 拼错的计数器键会让成长/衰减/脉冲**静默不走**)。
const _COUNTER_KEYS := ["init", "decay_per_phrase", "floor", "on_discard",
	"on_early_finish", "pulse_on_early_finish",
	# 商店事件(子波 3):`Fx.on_shop_event` 的 kind 加前缀 `on_` —— 三者必须与
	# `Joker.notify_shop` 的调用方一致, 拼错会让成长**静默不涨**。
	"on_reroll", "on_buy", "on_target_swap"]

## 持有期恒生效的经济/规则参数(穷开心 skint 的 coin_cap)。
## 与 shelf(货架影响)、acquire(一次性)三分天下, 键都要锁。
const _HOLD_KEYS := ["coin_cap", "cache_scoring", "odds_mult",
	"section_life", "face_coins", "loan"]

## `per` 的合法值(计数来源)。⚠ 拼错 per 会让 `Fx._count` 静默返回 1.0 ——
## 效果从「按 N 计数」退化成「恒 ×1」,不报错。和 card_filter 同一条纪律:值也要锁。
const _PER_SOURCES := ["discard", "cache_face", "face_discard", "swapped_scoring",
	"second_left",
	"cache_rank_sum",  # 2026-08-25 回收:本拍直弃缓存牌的点数和(core/fx.gd::_count)
	"hidden_scoring"]  # 2026-08-25 盲奏:盖着上台的得分牌张数

## `acquire` 的合法键与 deck_rule 的合法值。曾经不校验 —— 拼错的 acquire 键
## 会让规则牌**静默什么都不做**(joker.gd on_acquire 查不到就跳过),
## 正是「规则在游戏里、不在模型里」栽过五次的那个形状,趁加 trim_low 一起锁死。
const _ACQUIRE_KEYS := ["wilds", "deck_rule", "trim_low"]
## ⚠ `twotone` 2026-08-16 拆成 `redtone` / `blacktone` 两张, **旧名已删** ——
## 留着它等于留一条没人实现的规则(`pattern.gd` 不再认它), 而拼错/过期的 deck_rule
## 会让规则牌**静默什么都不做**, 正是这条注释上面说的那个形状。
const _DECK_RULES := ["shortcut", "fourfingers", "redtone", "blacktone"]


## 小丑牌的覆盖自证通路。含义见 `validate_jokers` 里的注释与 docs/design/jokers.md。
## `shop` = 货架结构卡(联票/赞助/点唱机):不产分不产钱, 改的是**商店本身**,
## 三条旧通路都量不到 —— 仪器是 kit 的商店行为臂(开商店配对 A/B, 证物按卡声明)。
const _JOKER_PROOFS := ["score", "solver", "coin", "shop"]

## shelf 的合法键(2026-08-12 补, 外部审查 V2 的 shelf 半边就此结案)。
## 拼错 shelf 键 = 货架结构卡静默不生效, 与 acquire 白名单同一条纪律。
const _SHELF_KEYS := ["target_weight_mult", "target_guaranteed", "shelf_slots",
	"buy_limit", "price_delta", "rule_guaranteed",
	"copy_consumable"]   # 帕奇欧:离店复制一张消耗牌(2026-08-29)

## ⚑ `curve` = 时间形状, support 配额表的记账单位(2026-08-10 用户定分类三题后必填)。
## 15→18 张时配额表静默过期, 病根是「这张卡属于哪类」可以被忘掉 ——
## 和脸的 tier 同一个病同一个药:**强制作者做一次决定**。quota 见 docs/design/jokers_atlas.md §0。
const _JOKER_CURVES := ["burst", "fixed", "growth", "floating", "decay"]


## 效果 DSL 的校验(2026-08-21 评审:主角 effects 此前**完全不过白名单**, 未知谓词要到
## 运行期 `Fx._when_ok` 才 push_error, 测试期 load_error 仍为空)。
## `counters` = 该卡声明的计数器表:`per: counter:X` / `counter_gte: [X, n]` 的 X 必须在里面,
## 否则恒 0 = 卡静默失效(db.gd 自己说过的「静默不涨」)。
static func _validate_effects(effects: Array, owner: String, counters: Dictionary) -> String:
	for fx in effects:
		for wk in fx.get("when", {}):
			if not _PREDICATES.has(wk):
				return "unknown predicate '%s' (%s)" % [wk, owner]
			if wk == "kind" and not Pattern.Kind.has(String(fx["when"][wk])):
				return "unknown kind '%s' (%s)" % [fx["when"][wk], owner]
			if wk == "kind_in":
				for n in fx["when"][wk]:
					if not Pattern.Kind.has(String(n)):
						return "unknown kind '%s' (%s)" % [n, owner]
			if wk == "counter_gte":
				var cg = fx["when"][wk]
				if not (cg is Array) or cg.size() != 2 or not counters.has(String(cg[0])):
					return "counter_gte 引用了未声明的计数器 '%s' (%s)" % [str(cg), owner]
		for dk in fx.get("do", {}):
			if not _DO_KEYS.has(dk):
				return "unknown do key '%s' (%s)" % [dk, owner]
			if dk == "card_filter" and not ["red", "black", "rank_lte_5"].has(String(fx["do"][dk])):
				return "unknown card_filter '%s' (%s)" % [fx["do"][dk], owner]
			if dk == "per":
				var pv := String(fx["do"][dk])
				if pv.begins_with("counter:"):
					if not counters.has(pv.substr(8)):
						return "per 引用了未声明的计数器 '%s' (%s)" % [pv, owner]
				elif not _PER_SOURCES.has(pv) and not pv.begins_with("coins:"):
					return "unknown per source '%s' (%s)" % [pv, owner]
	return ""


## ⚑ 消耗牌的校验 —— 与 validate_jokers 同型(未知键直接红)。
## 额外守两条**只属于消耗牌**的契约:
##   ① `when` 只能是 phrase/shop/any —— 写错等于这张牌永远点不亮, 且不报错。
##   ② `action` 与 `boost` **至少有一个**, 否则它是一张用了什么也不发生的牌。
## ⚑ 消耗牌的立即动作 —— **加新键时三处齐落**:这里 · `view/phrase.gd::_apply_shop_action`
## · `tools/bot.gd::_apply_bot_action`。`tools/parity.py` 会机械核对后两处。
const _CONSUMABLE_ACTIONS := ["wilds", "trim_low", "deck_rule", "shelf_slots",
	"buy_limit", "price_delta", "rule_guaranteed", "free_reroll", "min_rarity",
	"copy_one_destroy_rest", "loan"]
## 当拍加成的通道 —— 与 `core/settle.gd` 里 phrase_boosts 那段消费的键一一对应。
const _CONSUMABLE_BOOSTS := ["bonus_pct", "mult", "bonus", "bonus_target_pct",
	"additive", "chance"]

static func validate_consumables(d: Dictionary) -> String:
	if not d.has("consumables"):
		return "wants 'consumables'"
	var ids := {}
	for e in d["consumables"]:
		for k in e:
			if not ["id", "name", "cn", "price", "fire", "fx", "action", "boost",
					"proof"].has(k) \
					and not String(k).begins_with("_"):
				return "consumable unknown key '%s' (%s)" % [k, e.get("id", "?")]
		var cid := String(e.get("id", ""))
		if cid == "":
			return "consumable without id"
		if ids.has(cid):
			return "duplicate consumable id '%s'" % cid
		ids[cid] = true
		# ⚑ `fire` = 什么时候自己打(2026-09-01 消耗牌全部自动触发, 取代旧的 `when`):
		# "buy"(买下即触发)· "next"(下一拍)· 1..6(遇到的第一个第 N 拍)。
		# ⚠ 拍号必须落在 1..PHRASES_PER_SECTION —— 写了个 7 的话它**永远等不到**,
		# 而那会是一张静默的废卡(「不报错的错」是这个项目最贵的一类)。
		var fv = e.get("fire", null)
		if typeof(fv) == TYPE_STRING:
			if not ["buy", "next"].has(String(fv)):
				return "consumable '%s' 的 fire '%s' 不认识, 字符串只能是 buy / next" % [cid, fv]
		elif typeof(fv) == TYPE_FLOAT or typeof(fv) == TYPE_INT:
			if int(fv) < 1 or int(fv) > GameConfig.PHRASES_PER_SECTION:
				return "consumable '%s' 的 fire 拍号 %d 越界(1..%d)—— 它会永远等不到" \
					% [cid, int(fv), GameConfig.PHRASES_PER_SECTION]
		else:
			return "consumable '%s' 缺 fire(什么时候自己打)" % cid
		if e.get("action", {}).is_empty() and e.get("boost", {}).is_empty():
			return "consumable '%s' 既没有 action 也没有 boost —— 用了什么都不会发生" % cid
		# ⚠ action 键必须在白名单里 —— **拼错一个字母 = 两侧都不执行, 且不报错**
		# (2026-08-30 教训:6/9 的键当时只有游戏侧实现, 而我用那份读数定了价)。
		for ak in e.get("action", {}):
			if not _CONSUMABLE_ACTIONS.has(String(ak)):
				return "consumable '%s' 的 action 键 '%s' 不认识, 只能是 %s" \
					% [cid, ak, str(_CONSUMABLE_ACTIONS)]
		# boost 走的是 Fx 的通道名, 与小丑牌同一批 —— 这里只挡明显的手滑。
		for bk in e.get("boost", {}):
			if not _CONSUMABLE_BOOSTS.has(String(bk)):
				return "consumable '%s' 的 boost 通道 '%s' 不认识, 只能是 %s" \
					% [cid, bk, str(_CONSUMABLE_BOOSTS)]
		if int(e.get("price", 0)) <= 0:
			return "consumable '%s' 价格必须为正" % cid
		# ⚠ `proof` 必填 —— 与小丑牌同一条锁:没声明 = 这张牌可以悄悄绕过 kit 那道门,
		# 而 2026-08-30 正是三张「游戏里是空白的」消耗牌没被任何单卡门抓到。
		if not ["score", "shop"].has(String(e.get("proof", ""))):
			return "consumable '%s' 的 proof '%s' 不认识, 只能是 score / shop" \
				% [cid, e.get("proof", "")]
	return ""


static func validate_jokers(d: Dictionary) -> String:
	if not d.has("jokers"):
		return "wants 'jokers'"
	var ids := {}
	for e in d["jokers"]:
		for k in e:
			if not ["id", "name", "cn", "kind", "rarity", "proof", "fx", "effects",
					"counters", "acquire", "shelf", "hold", "curve"].has(k) and not String(k).begins_with("_"):
				return "joker unknown key '%s' (%s)" % [k, e.get("id", "?")]
		# support 必填 curve(配额记账);target 不填 —— 它是 WHAT 不是 HOW, 不进配额表,
		# 填了等于同一个口径写两处。
		if String(e.get("kind", "")) == "support":
			if not e.has("curve"):
				return "support '%s' 没有 curve 声明(%s)—— 配额表的记账单位, 见 docs/design/jokers_atlas.md" \
					% [e.get("id", "?"), " / ".join(_JOKER_CURVES)]
			if not _JOKER_CURVES.has(String(e["curve"])):
				return "joker '%s' 的 curve '%s' 不认识, 只能是 %s" % [e["id"], e["curve"], str(_JOKER_CURVES)]
		elif e.has("curve"):
			return "target '%s' 不该有 curve(Target 不进 support 配额表)" % e.get("id", "?")
		# ⚠ `proof` = 这张牌**用什么仪器**证明「模型看得见它」(docs/design/jokers.md 验证方案)。
		# 和脸的 `proof` 同一个思路,连声明必填这条也一样 —— 漏声明 = 直接红。
		# **通路是按仪器分的, 不是按机制分的**:
		#   score  —— 效果直接改分,规则 bot 配对 A/B 就量得到
		#   solver —— 改的是**牌型规则或牌堆**(`acquire.deck_rule` / `wilds`),
		#             **必须用完美玩家**:规则 bot 未必会去用新规则, 量出来可能是 0 甚至反号
		#             (脸那边 `freshsheet` 两种 bot 的符号就是反的, 见 tools/gate.gd)
		#   coin   —— 只给钱不给分,**在分数臂里按定义恒等于 0**。拿分数验它只会得出
		#             「没接上」—— 和 `raisedbar` 一模一样, 必须走金币臂 + 行为臂。
		if not e.has("proof"):
			return "joker '%s' 没有 proof 通路声明 —— 见 docs/design/jokers.md 验证方案" % e.get("id", "?")
		if not _JOKER_PROOFS.has(String(e["proof"])):
			return "joker '%s' 的 proof '%s' 不认识, 只能是 %s" % [e["id"], e["proof"], str(_JOKER_PROOFS)]
		if ids.has(e["id"]):
			return "duplicate joker id '%s'" % e["id"]
		ids[e["id"]] = true
		# kind / rarity 是枚举, 拼错此前全静默(评审 D):rarity 退 4◆/权重 1、kind 写错 bot 永不买
		if not ["target", "support"].has(String(e.get("kind", ""))):
			return "joker '%s' kind 必须是 target/support(得 '%s')" % [e.get("id", "?"), e.get("kind", "")]
		if not economy().get("draft_rarity_weights", {}).has(String(e.get("rarity", ""))):
			return "joker '%s' rarity '%s' 不在 economy.json draft_rarity_weights 里" % [e.get("id", "?"), e.get("rarity", "")]
		var fe := _validate_effects(e.get("effects", []), String(e["id"]), e.get("counters", {}))
		if fe != "":
			return fe
		for ak in e.get("acquire", {}):
			if not _ACQUIRE_KEYS.has(String(ak)):
				return "unknown acquire key '%s' (%s)" % [ak, e["id"]]
			if String(ak) == "deck_rule" and not _DECK_RULES.has(String(e["acquire"][ak])):
				return "unknown deck_rule '%s' (%s)" % [e["acquire"][ak], e["id"]]
			# wilds 值 = 张数(2026-08-26):2 = 大小王开关(百搭), 3..6 = 按来源注入
			# (超级百搭 4)。SUITS 按下标取, 注入 suit 只用 2/3, 张数没有硬上限,
			# 但 >6 基本是手滑 —— 当场红比静默塞爆牌堆好。
			if String(ak) == "wilds" and (int(e["acquire"][ak]) < 2 or int(e["acquire"][ak]) > 6):
				return "acquire wilds 必须在 2..6(%s 给了 %s)" % [e["id"], e["acquire"][ak]]
		for sk in e.get("shelf", {}):
			if not _SHELF_KEYS.has(String(sk)):
				return "unknown shelf key '%s' (%s)" % [sk, e["id"]]
		for hk in e.get("hold", {}):
			if not _HOLD_KEYS.has(String(hk)):
				return "unknown hold key '%s' (%s)" % [hk, e["id"]]
		for cname in e.get("counters", {}):
			for ck in e["counters"][cname]:
				if not _COUNTER_KEYS.has(String(ck)):
					return "unknown counter key '%s' (%s)" % [ck, e["id"]]
	return ""


static func validate_sim(d: Dictionary) -> String:
	for k in ["runs", "cohorts", "kind_prior", "counterfactual_tv",
			"lonewolf_value", "ev", "chase", "solver"]:
		if not d.has(k):
			return "missing key '%s'" % k
	# 平衡贪心的权重 (docs/design/solver_roadmap.md)。lam < 0 会把「养牌」变成「主动毁缓存」;
	# lam_samples < 1 会让 cache_value 恒为 0, 于是 lam 静默失效 —— 那正是最难发现的
	# 一类失效:参数还在配置里写着, 行为却已经退化成单拍贪心。
	var sv = d["solver"]
	if typeof(sv) != TYPE_DICTIONARY or not sv.has("lam") or not sv.has("lam_samples"):
		return "solver wants {lam, lam_samples}"
	if float(sv["lam"]) < 0.0:
		return "solver.lam must be >= 0"
	if int(sv["lam_samples"]) < 1 and float(sv["lam"]) > 0.0:
		return "solver.lam_samples < 1 would silently disable a non-zero lam"
	# 同理:blind_samples < 1 会让盖牌脸静默退化成「玩家看得见」—— 脸还在池子里,
	# 效果却是零, 而目标分照着「有这张脸」的难度算。
	if not sv.has("blind_samples"):
		return "solver wants blind_samples (0 would silently un-hide every face-down card)"
	if int(sv["blind_samples"]) < 1:
		return "solver.blind_samples < 1 would silently disable the hiding faces"
	# 金币影子价的衰减指数 (tools/bot.gd 的 lam)。缺键会让 `float(null)` 静默变成 0,
	# 也就是"衰减静默关掉" —— 那正是这个参数存在的理由, 必须喊出来。
	# 负数会把它做成**反向**衰减(越到末尾金币越贵), 那是当前这个 bug 的加强版。
	var ev = d["ev"]
	if not ev.has("coin_decay"):
		return "ev wants coin_decay (missing = the coin's shadow price silently stops decaying)"
	if float(ev["coin_decay"]) < 0.0:
		return "ev.coin_decay must be >= 0 (negative makes coins get MORE expensive as the run ends)"
	var jids := {}
	for e in jokers():
		jids[e["id"]] = true
	for cid in d["ev"].get("cards", {}):
		if not jids.has(cid):
			return "ev card '%s' not in jokers" % cid
	# 反向:score/solver 通路的 support 必须有 ev.cards 条目 —— bot 的 _card_ev 缺臂 = 估值 0 =
	# 永远不买 = 这张卡在尺子里不存在(2026-08-21 评审:popup 就这么静默隐身)。
	# 白名单 = 不靠 ev.cards 估值的臂(求解器直算 / 无参数臂)。
	var no_prior := ["neonsign"]
	for e in jokers():
		var proof := String(e.get("proof", ""))
		if String(e.get("kind", "")) == "support" and proof in ["score", "solver"] \
				and not d["ev"]["cards"].has(e["id"]) and not no_prior.has(String(e["id"])):
			return "support '%s'(proof=%s)在 ev.cards 里没有条目 —— bot 估值恒 0, 永远不买" % [e["id"], proof]
	return ""


static func validate_ui(d: Dictionary) -> String:
	if not d.has("stage"):
		return "wants 'stage'"
	for k in d:
		if String(k).begins_with("_"):
			continue
		# `tutor_focus` = 教学关的分区指向矩形(2026-08-15)。⚑ 它进 ui.json 而不是
		# tutorial.json, 因为**坐标归 ui.json** 是既定铁律(改布局改文案 = 改 JSON);
		# tutorial.json 里只放**区域名**, `core/tutorial.gd` 也因此不认识像素。
		if not ["stage", "hud", "shop", "hand", "banner", "blindcard", "jokercard",
				"consumablecard", "tutor_focus", "patterns"].has(k):
			return "unknown section '%s'" % k
	# 交叉校验(2026-08-21 评审 D):blindcard 覆盖每张入池脸 + 每个 boon, jokercard 覆盖每张
	# 小丑牌;反向不许有孤儿条目(5 条退役卡的 jokercard 曾经一直躺在表里)。
	# 漏条目的形状是静默的:盲注卡退回只画脸名(规则读不到), 小丑卡退回英文 fx(带过期数字)。
	var live_faces := {}
	for f in faces().get("faces", []):
		live_faces[String(f["id"])] = f.has("tier") or f.has("tiers")
	var boon_ids := {}
	for b in boons().get("boons", []):
		boon_ids[String(b["id"])] = true
	var bc: Dictionary = d.get("blindcard", {})
	for fid in live_faces:
		if live_faces[fid] and not bc.has(fid):
			return "ui.blindcard 缺入池脸 '%s' 的 command(盲注卡会退回只画名字)" % fid
	for bid in boon_ids:
		if not bc.has(bid):
			return "ui.blindcard 缺 boon '%s' 的 command" % bid
	for k in bc:
		if not String(k).begins_with("_") and not live_faces.has(String(k)) and not boon_ids.has(String(k)):
			return "ui.blindcard 有孤儿条目 '%s'(既不是脸也不是 boon)" % k
	var jc: Dictionary = d.get("jokercard", {})
	var jids := {}
	for j in jokers():
		jids[String(j["id"])] = true
		if not jc.has(String(j["id"])):
			return "ui.jokercard 缺小丑牌 '%s' 的 trigger(卡面会退回英文 fx)" % j["id"]
	for k in jc:
		if not String(k).begins_with("_") and not jids.has(String(k)):
			return "ui.jokercard 有孤儿条目 '%s'(卡已退役, 删掉)" % k
	# ⚑ 同款交叉校验(2026-08-29 消耗牌开轴):consumablecard 覆盖每张消耗牌,
	# 反向不许有孤儿 —— 与 jokercard 同一条纪律(退役卡的条目曾一直躺在表里)。
	var ccard: Dictionary = d.get("consumablecard", {})
	var cids := {}
	# ⚠⚠ **不走 `_load`** —— 传一个「永远返回空」的假校验器会把 consumables.json
	# **未经校验地缓存下来**(`_load` 缓存后不再重验), 之后所有 `DB.consumables()`
	# 都跳过校验, 今天加的三层键白名单**全部失效**。⇒ 直接读文件, 只做交叉引用。
	var cfile := FileAccess.open("res://data/consumables.json", FileAccess.READ)
	var cparsed = JSON.parse_string(cfile.get_as_text()) if cfile != null else null
	var clist: Array = cparsed.get("consumables", []) if cparsed is Dictionary else []
	for ce in clist:
		cids[String(ce["id"])] = true
		if not ccard.has(String(ce["id"])):
			return "ui.consumablecard 缺消耗牌 '%s' 的 trigger(卡面会退回英文 fx)" % ce["id"]
	for ck in ccard:
		if not cids.has(String(ck)):
			return "ui.consumablecard 有孤儿条目 '%s'(消耗牌已不在池)" % ck
	return ""


## 起承転結的「同族递进」契约(2026-08-07 用户拍板 A′ 案, 见 docs/design/blinds.md §3)。
##
## 一个机制先以**软版**出现(起:安全地介绍它), 再以**同族硬版**回来(転:把它扭转)。
## 契约 = **软版出现的最后一段 < 硬版出现的第一段**。反过来就是先硬后软, 那不是教学弧,
## 是难度倒挂 —— 而且它不会报错, 只会让「起」变成一段莫名其妙的放水。
##
## ⚠ **哪个值更软是按参数定的, 不能自动推**(repeat_factor 越大越软 0.5>0.0,
## cache_evict 越小越软 1<3), 所以 soft/hard 由作者声明, 这里只校验:
## 两张脸真的同族(带同一个 param), 以及池子里的先后。
## ⚠ `first_tier_of` 是**最早出现的轮次**(`min(tiers)`), 不是主场 `tier` ——
## 这条断言问的是**顺序**("玩家先遇到哪个"), 而放开 `tiers` 之后主场答不了这个问题。
static func _validate_face_families(d: Dictionary, ids: Dictionary, first_tier_of: Dictionary) -> String:
	for fam in d.get("families", {}):
		var e: Dictionary = d["families"][fam]
		for role in ["soft", "hard"]:
			if not e.has(role):
				return "family '%s' wants both soft and hard" % fam
			if not ids.has(e[role]):
				return "family '%s' %s references unknown face '%s'" % [fam, role, e[role]]
			if not _face_params(d, String(e[role])).has(fam):
				return "family '%s': face '%s' does not carry that param — not the same family" \
					% [fam, e[role]]
		if String(e["soft"]) == String(e["hard"]):
			return "family '%s': soft and hard are the same face" % fam
		if not first_tier_of.has(e["soft"]) or not first_tier_of.has(e["hard"]):
			continue          # 有一档没入池 = 这条弧这一版没排, 不算错
		if int(first_tier_of[e["soft"]]) >= int(first_tier_of[e["hard"]]):
			return "family '%s': soft '%s' 最早在第 %d 轮, hard '%s' 最早在第 %d 轮 —— 先硬后软不是教学弧" \
				% [fam, e["soft"], int(first_tier_of[e["soft"]]), e["hard"], int(first_tier_of[e["hard"]])]
	return ""


static func _face_params(d: Dictionary, fid: String) -> Dictionary:
	for e in d["faces"]:
		if String(e["id"]) == fid:
			return e.get("params", {})
	return {}
