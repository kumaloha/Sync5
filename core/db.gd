class_name DB
extends RefCounted

## Data-config loader (design/tech.md). Loads data/*.json once and validates.
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
## lives in design/blinds.md, and `_`-prefixed keys are rejected there on
## purpose so the notes cannot silently grow back into the data file.

static var _cache: Dictionary = {}
static var _err := ""

const _RUN_KEYS := ["phrases_per_section", "phrases_per_shop", "sections_per_gig",
	"gigs_per_run", "blind_names", "gig_names", "section_targets", "gig_clocks",
	"warning_offset", "lock_offset", "late_act_window", "final_act_window",
	"early_finish_time", "early_discard_window", "early_lock_min",
	"hand_size", "cache_cap", "beat_budget", "death_spec"]
const _ECO_KEYS := ["starting_coins", "discard_cost", "section_clear_reward",
	"draft_rarity_weights", "joker_prices", "joker_price_overrides",
	"reroll", "joker_upgrade"]
const _TAPE_KEYS := ["enabled", "to_file", "dir", "max_events", "mute"]


## Forces every data file through its validator; "" = all clean.
static func load_error() -> String:
	run()
	economy()
	faces()
	boons()
	characters()
	jokers()
	sim()
	ui()
	tape()
	tutorial()
	director()
	tickets()
	return _err


static func run() -> Dictionary:
	return _load("run", func(d): return validate_run(d))


static func economy() -> Dictionary:
	return _load("economy", func(d): return validate_economy(d))


static func faces() -> Dictionary:
	return _load("faces", func(d): return validate_faces(d))


static func boons() -> Dictionary:
	return _load("boons", func(d): return validate_boons(d))


static func characters() -> Array:
	return _load("characters", func(d): return validate_characters(d)).get("characters", [])


static func jokers() -> Array:
	return _load("jokers", func(d): return validate_jokers(d)).get("jokers", [])


static func sim() -> Dictionary:
	return _load("sim", func(d): return validate_sim(d))


static func ui() -> Dictionary:
	return _load("ui", func(d): return validate_ui(d))


## 打点开关(core/tape.gd)。名字不叫 log —— `log` 是 GDScript 内置数学函数,
## 在类里同名会把它遮掉。
static func tape() -> Dictionary:
	return _load("tape", func(d): return validate_tape(d))


static func tutorial() -> Dictionary:
	return _load("tutorial", func(d): return validate_tutorial(d))


## 消耗品层(券)。`core/ticket.gd` 是它唯一的消费者。
static func tickets() -> Dictionary:
	return _load("tickets", func(d): return validate_tickets(d))


## ⚠ `scope` 写错会让券**静默地在错误的时机可用**, 而那不报错 —— 所以是白名单硬校验。
static func validate_tickets(d: Dictionary) -> String:
	var e := _keys_ok(d, ["reset_hour", "max_held", "tickets"])
	if e != "":
		return e
	if int(d["reset_hour"]) < 0 or int(d["reset_hour"]) > 23:
		return "reset_hour 必须在 0..23"
	if int(d["max_held"]) < 1:
		return "max_held 必须 >= 1"
	var seen: Array = []
	for t in d["tickets"]:
		for k in t:
			if not ["id", "cn", "name", "fx", "scope", "params"].has(String(k)) \
					and not String(k).begins_with("_"):
				return "ticket '%s' unknown key '%s'" % [t.get("id", "?"), k]
		var tid := String(t.get("id", ""))
		if tid == "" or seen.has(tid):
			return "ticket id 缺失或重复: '%s'" % tid
		seen.append(tid)
		if not ["phrase", "shop", "run"].has(String(t.get("scope", ""))):
			return "ticket '%s' scope 必须是 phrase/shop/run" % tid
		if String(t.get("fx", "")).split(" ", false).size() > 7:
			return "ticket '%s' 卡面超过 7 词(与小丑牌同一条 1.5 秒规矩)" % tid
	return ""


## B 轴 · 跨局序列表(design/difficulty.md §3)。`core/director.gd` 是它唯一的消费者。
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
	# 手速预算 (design/solver_roadmap.md): 求解器与模拟器共用的上限, 必须为正。
	# swaps 至少要够把任意「8 选 5」搬进手牌 —— 那需要 cache_cap 次交换,
	# 少于它, 求解器就够不到部分持法, 上界会被工具而不是被游戏限制。
	var bb = d["beat_budget"]
	if typeof(bb) != TYPE_DICTIONARY or not bb.has("discards") or not bb.has("swaps"):
		return "beat_budget wants {discards, swaps}"
	if int(bb["discards"]) < 0 or int(bb["swaps"]) < 0:
		return "beat_budget must be non-negative"
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
	return ""


static func validate_economy(d: Dictionary) -> String:
	return _keys_ok(d, _ECO_KEYS)


static func validate_tape(d: Dictionary) -> String:
	var e := _keys_ok(d, _TAPE_KEYS)
	if e != "":
		return e
	if not d["mute"] is Array:
		return "mute wants an array of event names"
	# 缓冲一满就落盘(或退化成环形), 0 会让每条事件都触发一次写文件
	if int(d["max_events"]) < 1:
		return "max_events must be >= 1"
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
	"zero_discard_factor", "lock_first", "request_factor", "joker_power"]
const _FACE_PARAMS_OTHER := ["time_penalty", "phrase_toll", "cache_evict",
	"cache_cap_delta", "target_mult", "hide_refill", "hide_faces",
	"discard_lock_last", "swap_lock_last", "discard_actions", "swap_actions",
	"action_limit", "cache_block_red", "refill_rank_min", "refill_rank_max",
	"cache_lock_phrases", "seal_lowest_start", "required_kinds", "variety_penalty",
	"seal_oldest_cache", "restore_with_initial_cache", "section_discard_budget",
	"exclusive_action_tracks"]
const _FACE_PARAMS := _FACE_PARAMS_SETTLE + _FACE_PARAMS_OTHER
const _BOON_PARAMS := ["score_replay_factor", "spotlight_cards",
	"previous_raw_factor", "ghost_first_discard"]


## faces.json is data-only (2026-08-09: design prose moved to design/blinds.md).
## ⚠ Unlike every other data file, `_`-prefixed keys are NOT treated as comments
## here — that exemption is exactly how the prose grew to 77.6% of the file
## before. Both the root object and each face entry are locked to a whitelist,
## so a stray `_why`/`_note` etc. added later fails loudly instead of quietly
## re-accumulating.
const _FACE_ROOT_KEYS := ["faces", "families", "fixed_tiers", "weak_upper_bound"]


static func validate_faces(d: Dictionary) -> String:
	for k in d:
		if not _FACE_ROOT_KEYS.has(k):
			return "faces.json unknown top-level key '%s' — it is data-only now, design notes belong in design/blinds.md" % k
	if not d.has("faces"):
		return "wants 'faces'"
	var ids := {}
	for e in d["faces"]:
		for k in e:
			if not ["id", "name", "cn", "fx", "params", "proof", "tape_required", "tier", "tiers",
					"min_run"].has(k):
				return "face '%s' unknown key '%s' — faces.json is data-only now, design notes belong in design/blinds.md §7" % [e.get("id", "?"), k]
		if e.has("tape_required") and not e["tape_required"] is bool:
			return "face '%s' tape_required wants bool" % e.get("id", "?")
		if ids.has(e["id"]):
			return "duplicate face id '%s'" % e["id"]
		var params: Dictionary = e.get("params", {})
		if params.is_empty():
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
			return "tier %d 只有 %d 张脸, 这一轮每局都一样 —— 想固定就写进 fixed_tiers(设计判据见 design/blinds.md §3)" % [t, cnt]
		if cnt > 1 and fixed.has(t):
			return "tier %d 声明成 fixed 却有 %d 张脸 —— 声明和内容对不上" % [t, cnt]
	# 覆盖自证的**量级豁免**(2026-08-08 用户拍板 A 案)。判据两条 —— |z|>=3(信不信得过)
	# **且** 量级>=5%(要不要管);量级不够时允许豁免, 但**必须显式声明**,
	# 和 `fixed_tiers` 同一条原则:**豁免必须是有意的, 不能是漏掉的**。
	# ⚠ 声明的是"对**完美玩家**的上界效应小", **不是**"这张脸没用" —— 见 design/blinds.md §5。
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


## 教学关脚本(design/difficulty.md §4)。`core/tutorial.gd` 是它唯一的消费者。
## ⚠ 这里守的是**结构**, 不是内容:拍长多少、教哪几步是设计, 由用户直接改 JSON。
static func validate_tutorial(d: Dictionary) -> String:
	for k in d:
		if String(k).begins_with("_"):
			continue
		if not ["components", "steps"].has(k):
			return "tutorial.json unknown top-level key '%s'" % k
	if not d.has("components") or not (d["components"] is Array) or d["components"].is_empty():
		return "tutorial.json wants a non-empty 'components' whitelist"
	if not d.has("steps") or not (d["steps"] is Array) or d["steps"].is_empty():
		return "tutorial.json wants a non-empty 'steps' array"
	var known: Array = []
	for c in d["components"]:
		known.append(String(c))
	# 亮过的部件 —— 同一个部件解锁两次是脚本写错了(第二次是死行, 而且读起来像它会再亮一遍)。
	var seen: Array = []
	for i in range(d["steps"].size()):
		var st = d["steps"][i]
		if not (st is Dictionary):
			return "tutorial step %d wants an object" % i
		for k in st:
			if not ["seconds", "unlock", "require", "command", "signal", "focus"].has(String(k)):
				return "tutorial step %d unknown key '%s'" % [i, k]
		# ⚠⚠ **写错一个动作名, 那一步永远推进不了, 而且不报错** —— 玩家会**卡死在教学关里**,
		# 而这是个只有真人玩才发现得了的死法(探针不走 view, 不产生这些动作)。
		# 所以这条必须是硬校验, 和「focus 指向未知区域」同一类静默失败。
		var req := String(st.get("require", ""))
		if req != "" and not Tutorial.ACTIONS.has(req):
			return "tutorial step %d require 未知动作 '%s'(白名单: %s)" \
				% [i, req, ", ".join(Tutorial.ACTIONS)]
		# 指向一块不存在的区域 = **画不出来而且不报错**, 正是这个项目最贵的那类静默失败。
		# ⚠ 白名单来自 `ui.json` 的 `tutor_focus`(坐标归 ui.json 那条铁律)。
		# ⚠ 这里嵌套调 `ui()` 是安全的:`_load` 有缓存, 且 ui 的校验不反过来读 tutorial(无环)。
		var known_regions: Array = []
		for rk in ui().get("tutor_focus", {}):
			if not String(rk).begins_with("_"):
				known_regions.append(String(rk))
		for r in st.get("focus", []):
			if not known_regions.has(String(r)):
				return "tutorial step %d focus 指向未知区域 '%s'(白名单在 data/ui.json 的 tutor_focus: %s)" \
					% [i, r, ", ".join(known_regions)]
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
	return ""


## ---- B 轴 · Director(design/difficulty.md §3) ----
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
##   ② 价格 —— 定价先过 design/numbers.md 的宪法, 不许从这里绕;
##   ③ 「必定出某张牌」—— 2026-08-06 用户拍板「不应该有任何卡有固定概率」,
##      活法是**把保证写在卡面上**(独狼/点唱机), 不是藏进 Director 的掷点;
##   ④ 读 context —— 2026-08-14 拍板作废的那三节(Inputs / 行为模型 / 掌握度)。
const _DIRECTOR_FORBIDDEN := {
	"target_mult": "铁律「Director 不许调目标分」(design/difficulty.md §3)—— 玩家看得见的数不许按局数漂",
	"section_targets": "目标分表在 data/run.json, 它对所有人、对每一局都是同一张",
	"death_spec": "难度形状是 A 轴的设计常量(data/run.json), 不是 B 轴的手段",
	"gig_clocks": "拍长玩家感觉得到(时间是唯一压力货币)—— 教学关可以放宽, 正式局不许按局数漂",
	"joker_prices": "定价先过 design/numbers.md 的三轴框架与六步 SOP, 不许从 Director 绕",
	"price_delta": "同上;货架价格增减是卡面效果(赞助), 不是 Director 的口",
	"reroll": "同上",
	"joker_upgrade": "同上 —— 升级曲线锚在「一局白剩多少钱」, 见 economy.json 的注释",
	"discard_cost": "同上",
	"starting_coins": "同上",
	"section_clear_reward": "同上",
	"target_guaranteed": "「不应该有任何卡有固定概率」(2026-08-06 用户拍板)—— 保证要写在**卡面**上(独狼), 不许藏进掷点",
	"rule_guaranteed": "同上(点唱机)",
	"target_weight_mult": "同上:货架上 Target 的权重是卡面效果, 不是按局数的暗改",
	"inputs": "2026-08-14 用户拍板「不读 context」—— Director 只按局数索引, 不看玩家做了什么",
	"player_model": "同上(levels.md 的 Recent behavior model 已作废)",
	"tendency": "同上",
	"mastery": "同上(Joker learning states 已作废)",
	"rolling_window": "同上",
}


## 跨局序列表(design/difficulty.md §3)。`core/director.gd` 是它唯一的消费者。
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
	var e := _keys_ok(d, _DIRECTOR_KEYS)
	if e != "":
		return e
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
			return "state '%s': %s —— Director 一局只调两样(脸的排布 + 货架), 见 design/difficulty.md §3" \
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


## 覆盖自证契约(design/gates.md):**一条规则如果进不了模型, 它就不该进池子。**
## 每张进了池子的脸必须声明它在模型里走哪条通路, `tools/gate.gd` 照着这个声明
## 给它造配对对照臂。漏声明 = 直接红, 和 `_FACE_PARAMS` 两张表同一个思路:
## **强制作者做一次决定, 而不是默认走一条恰好不报错的路。**
## ⚠ 声明错通路是**静默**的(门会给它造一条测不到东西的臂然后放过它) —— 这个项目
## 栽过四次的「规则在游戏里, 不在模型里」全是这个形状。通路的含义见 design/blinds.md §4。
## ⚠ **选错通路会把结论量反, 而且不报错。** 2026-08-07 第一次全量跑抓到: 用规则 bot 量
## freshsheet(翻篇)得到 **+1584 分**(脸让玩家变强!), 换成完美玩家是 **−790**。
## 规则 bot 不跨拍养缓存, 洗掉缓存反而帮它甩了烂牌。**攻击跨拍养牌或时间预算的脸必须走 solver。**
## ⚠ 「tape」不是通路(2026-08-10 修复):真人验证是另一条证据线, 用每张脸的
## `tape_required` 标志声明, 不顶替模型通路 —— 否则 tools/gate.gd 无臂可造,
## 门会当场红(实测 lastcall 就是这样死的)。时间窗类脸走 solver + weak_upper_bound
## (模型上界近零, 真人待定), 与铁律「测出近零不许改内容」同一条线。
const FACE_PROOFS := ["score", "solver", "belief", "target"]


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
			return "face '%s' is in a pool without a `proof` channel — see design/blinds.md §4" % fid
	return ""


const _PREDICATES := ["kind", "kind_in", "same_as_prev", "diff_from_prev",
	"acted_late", "discards_eq", "discards_gte", "coins_gte", "base_gte",
	"last_phrase", "cache_mono_suit", "top_rank_gte", "counter_gte",
	"first_phrase", "section_eq", "early_finish", "all_suits", "no_pair",
	"cache_all_faces", "cache_run", "cache_trio",
	"swaps_eq", "discard_batch_gte", "section_doubled",
	"acted_final", "early_discards"]
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
const _HOLD_KEYS := ["coin_cap"]

## `per` 的合法值(计数来源)。⚠ 拼错 per 会让 `Fx._count` 静默返回 1.0 ——
## 效果从「按 N 计数」退化成「恒 ×1」,不报错。和 card_filter 同一条纪律:值也要锁。
const _PER_SOURCES := ["discard", "cache_face", "face_discard", "swapped_scoring",
	"second_left"]

## `acquire` 的合法键与 deck_rule 的合法值。曾经不校验 —— 拼错的 acquire 键
## 会让规则牌**静默什么都不做**(joker.gd on_acquire 查不到就跳过),
## 正是「规则在游戏里、不在模型里」栽过五次的那个形状,趁加 trim_low 一起锁死。
const _ACQUIRE_KEYS := ["wilds", "deck_rule", "trim_low"]
## ⚠ `twotone` 2026-08-16 拆成 `redtone` / `blacktone` 两张, **旧名已删** ——
## 留着它等于留一条没人实现的规则(`pattern.gd` 不再认它), 而拼错/过期的 deck_rule
## 会让规则牌**静默什么都不做**, 正是这条注释上面说的那个形状。
const _DECK_RULES := ["shortcut", "fourfingers", "redtone", "blacktone"]


## 小丑牌的覆盖自证通路。含义见 `validate_jokers` 里的注释与 design/jokers.md。
## `shop` = 货架结构卡(联票/赞助/点唱机):不产分不产钱, 改的是**商店本身**,
## 三条旧通路都量不到 —— 仪器是 kit 的商店行为臂(开商店配对 A/B, 证物按卡声明)。
const _JOKER_PROOFS := ["score", "solver", "coin", "shop"]

## shelf 的合法键(2026-08-12 补, 外部审查 V2 的 shelf 半边就此结案)。
## 拼错 shelf 键 = 货架结构卡静默不生效, 与 acquire 白名单同一条纪律。
const _SHELF_KEYS := ["target_weight_mult", "target_guaranteed", "shelf_slots",
	"buy_limit", "price_delta", "rule_guaranteed"]

## ⚑ `curve` = 时间形状, support 配额表的记账单位(2026-08-10 用户定分类三题后必填)。
## 15→18 张时配额表静默过期, 病根是「这张卡属于哪类」可以被忘掉 ——
## 和脸的 tier 同一个病同一个药:**强制作者做一次决定**。quota 见 design/jokers_atlas.md §0。
const _JOKER_CURVES := ["burst", "fixed", "growth", "floating", "decay"]


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
				return "support '%s' 没有 curve 声明(%s)—— 配额表的记账单位, 见 design/jokers_atlas.md" \
					% [e.get("id", "?"), " / ".join(_JOKER_CURVES)]
			if not _JOKER_CURVES.has(String(e["curve"])):
				return "joker '%s' 的 curve '%s' 不认识, 只能是 %s" % [e["id"], e["curve"], str(_JOKER_CURVES)]
		elif e.has("curve"):
			return "target '%s' 不该有 curve(Target 不进 support 配额表)" % e.get("id", "?")
		# ⚠ `proof` = 这张牌**用什么仪器**证明「模型看得见它」(design/jokers.md 验证方案)。
		# 和脸的 `proof` 同一个思路,连声明必填这条也一样 —— 漏声明 = 直接红。
		# **通路是按仪器分的, 不是按机制分的**:
		#   score  —— 效果直接改分,规则 bot 配对 A/B 就量得到
		#   solver —— 改的是**牌型规则或牌堆**(`acquire.deck_rule` / `wilds`),
		#             **必须用完美玩家**:规则 bot 未必会去用新规则, 量出来可能是 0 甚至反号
		#             (脸那边 `freshsheet` 两种 bot 的符号就是反的, 见 tools/gate.gd)
		#   coin   —— 只给钱不给分,**在分数臂里按定义恒等于 0**。拿分数验它只会得出
		#             「没接上」—— 和 `raisedbar` 一模一样, 必须走金币臂 + 行为臂。
		if not e.has("proof"):
			return "joker '%s' 没有 proof 通路声明 —— 见 design/jokers.md 验证方案" % e.get("id", "?")
		if not _JOKER_PROOFS.has(String(e["proof"])):
			return "joker '%s' 的 proof '%s' 不认识, 只能是 %s" % [e["id"], e["proof"], str(_JOKER_PROOFS)]
		if ids.has(e["id"]):
			return "duplicate joker id '%s'" % e["id"]
		ids[e["id"]] = true
		for fx in e.get("effects", []):
			for wk in fx.get("when", {}):
				if not _PREDICATES.has(wk):
					return "unknown predicate '%s' (%s)" % [wk, e["id"]]
				if wk == "kind" and not Pattern.Kind.has(String(fx["when"][wk])):
					return "unknown kind '%s' (%s)" % [fx["when"][wk], e["id"]]
				if wk == "kind_in":
					for n in fx["when"][wk]:
						if not Pattern.Kind.has(String(n)):
							return "unknown kind '%s' (%s)" % [n, e["id"]]
			for dk in fx.get("do", {}):
				if not _DO_KEYS.has(dk):
					return "unknown do key '%s' (%s)" % [dk, e["id"]]
				if dk == "card_filter" and not ["red", "black", "rank_lte_5"].has(String(fx["do"][dk])):
					return "unknown card_filter '%s' (%s)" % [fx["do"][dk], e["id"]]
				if dk == "per":
					var pv := String(fx["do"][dk])
					if not _PER_SOURCES.has(pv) and not pv.begins_with("counter:") \
							and not pv.begins_with("coins:"):
						return "unknown per source '%s' (%s)" % [pv, e["id"]]
		for ak in e.get("acquire", {}):
			if not _ACQUIRE_KEYS.has(String(ak)):
				return "unknown acquire key '%s' (%s)" % [ak, e["id"]]
			if String(ak) == "deck_rule" and not _DECK_RULES.has(String(e["acquire"][ak])):
				return "unknown deck_rule '%s' (%s)" % [e["acquire"][ak], e["id"]]
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


static func validate_characters(d: Dictionary) -> String:
	if not d.has("characters"):
		return "wants 'characters'"
	var arr: Array = d["characters"]
	for i in range(arr.size()):
		if int(arr[i]["idx"]) != i:
			return "idx must be dense 0..N in order (slot %d)" % i
		for k in arr[i]:
			if not ["idx", "cn", "title", "fx", "effects"].has(k) and not String(k).begins_with("_"):
				return "character unknown key '%s'" % k
	return ""


static func validate_sim(d: Dictionary) -> String:
	for k in ["runs", "cohorts", "kind_prior", "target_tf", "counterfactual_tv",
			"lonewolf_value", "ev", "chase", "solver"]:
		if not d.has(k):
			return "missing key '%s'" % k
	# 平衡贪心的权重 (design/solver_roadmap.md)。lam < 0 会把「养牌」变成「主动毁缓存」;
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
				"tutor_focus"].has(k):
			return "unknown section '%s'" % k
	return ""


## 起承転結的「同族递进」契约(2026-08-07 用户拍板 A′ 案, 见 design/blinds.md §3)。
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
