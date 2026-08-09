# 配置化（Data Config）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按 `design/13_Data_Config.md`（已拍板，含全部 v1 数据表）把 23 张小丑牌、8 主角、6 Boss 脸、关卡/经济数值、机器人信念表全部搬进 `data/*.json`，行为走效果 DSL，对外 API 不变。

**Architecture:** 新增 `core/db.gd`（带硬校验的加载器）+ `core/fx.gd`（when/do 效果解释器，小丑与主角共用）；`Joker/Character/SectionMod` 瘦身为数据壳，`GameConfig` 用 `static var` 从 DB 初始化保住所有 `GameConfig.X` 调用点；sim 的 `_target_mult` 从 jokers 表推导。**同一性契约**：现有 266 测试全绿 + sim 报告与 `scratchpad/sim_round3.txt`（封盘基线）逐行一致。

**Tech Stack:** Godot 4.6.2 / GDScript / JSON（`JSON.parse_string`）。

**本项目不是 git 仓库**：commit 步骤替换为「跑测试全绿 / 对 diff」。

**通用命令：**

```bash
godot --headless --path /Users/kuma/Projects/Sync5 --script res://tests/runner.gd
```

**关键坑（全程适用）**：
- `JSON.parse_string` 把所有数字解析成 **float**——凡是 int 语义的字段（目标分、价格、rank、idx…）读取处必须 `int()`。
- 新增 `class_name`（DB、Fx）后先 `godot --headless --path . --import`。
- `"_comment"` 键在所有校验循环里跳过。
- 数据文件内容**逐字来自 design/13 对应节**，不要手敲重写——spec 就是 v1 数据的权威。

---

### Task 1: DB 加载器 + run.json / economy.json + GameConfig 静态门面

**Files:**
- Create: `data/run.json`, `data/economy.json`（内容 = design/13 §run.json / §economy.json 代码块，去掉外层 ``` 围栏逐字落盘）
- Create: `core/db.gd`
- Modify: `core/config.gd`（全文重写）、`tools/sim.gd:19`
- Test: `tests/runner.gd`

- [ ] **Step 1: 写失败测试**

在 runner.gd `_test_run_structure()` 之前加入，并在 `_initialize()` 的 `_test_rules()` 之后注册 `_test_db()`：

```gdscript
# --- Data config (design/13): loader + validation ---
func _test_db() -> void:
	eq(DB.load_error(), "", "all data files load clean")
	eq(DB.run()["phrases_per_section"], 5, "run.json phrases per section")
	eq(int(DB.economy()["starting_coins"]), 6, "economy.json starting coins")
	# validation catches planted bad files
	check(DB.validate_run({"phrases_per_section": 5}) != "", "missing run key detected")
	check(DB.validate_economy({"starting_coins": 6, "typo_key": 1}) != "", "unknown economy key detected")
```

- [ ] **Step 2: 跑测试确认失败**

Expected: Parse Error `Identifier "DB" not declared`（先写测试后建类，编译错即失败信号）。

- [ ] **Step 3: 落两个 JSON + 写 core/db.gd**

`data/run.json` 与 `data/economy.json` 从 design/13 逐字物化。`core/db.gd`：

```gdscript
class_name DB
extends RefCounted

## Data-config loader (design/13). Loads data/*.json once, validates hard,
## fails loudly: any schema violation lands in load_error() and tests go red.

static var _cache: Dictionary = {}
static var _err := ""

const _RUN_KEYS := ["phrases_per_section", "sections_per_gig", "gigs_per_run",
	"blind_names", "section_targets", "gig_clocks", "warning_offset",
	"lock_offset", "late_act_window", "early_finish_time", "hand_size", "cache_cap"]
const _ECO_KEYS := ["starting_coins", "discard_cost", "section_clear_reward",
	"draft_rarity_weights", "joker_prices", "joker_price_overrides",
	"target_swap", "draft_skip_reward", "reroll"]


static func load_error() -> String:
	run(); economy(); jokers(); characters(); faces(); sim()
	return _err


static func run() -> Dictionary:
	return _load("run", func(d): return validate_run(d))

static func economy() -> Dictionary:
	return _load("economy", func(d): return validate_economy(d))

static func jokers() -> Array:
	return _load("jokers", func(d): return validate_jokers(d)).get("jokers", [])

static func characters() -> Array:
	return _load("characters", func(d): return validate_characters(d)).get("characters", [])

static func faces() -> Dictionary:
	return _load("faces", func(d): return validate_faces(d))

static func sim() -> Dictionary:
	return _load("sim", func(d): return validate_sim(d))


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
	_cache[fname] = parsed
	return parsed


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
	return ""


static func validate_economy(d: Dictionary) -> String:
	return _keys_ok(d, _ECO_KEYS)
```

（`validate_jokers/characters/faces/sim` 本任务先放行（`return ""`）——各自的任务补齐，避免前向依赖；文件不存在也没关系，`load_error()` 只在测试查全量时才触发缺文件……**不对**：Step 1 的 `load_error()` 会因缺 jokers.json 报错。所以本任务的四个占位 validator 这样写，且 `load_error()` 只查已有文件：）

```gdscript
static func validate_jokers(_d: Dictionary) -> String: return ""
static func validate_characters(_d: Dictionary) -> String: return ""
static func validate_faces(_d: Dictionary) -> String: return ""
static func validate_sim(_d: Dictionary) -> String: return ""
```

且 Step 1 测试的 `load_error()` 断言改为本任务只查前两个文件：把 db.gd 的 `load_error()` 写成查 `run(); economy()`，后续任务每接入一个文件就在 `load_error()` 里加上对应调用（T2 加 faces，T3 加 characters，T4 加 jokers，T5 加 sim）——**每个任务结束时 `load_error()` 恰好覆盖已存在的文件**。

- [ ] **Step 4: 重写 core/config.gd 为静态门面**

全文替换（API 与常量名全部保留，值改从 DB 来；`static var` 在类加载时初始化）：

```gdscript
class_name GameConfig
extends RefCounted

## Facade over data/run.json + data/economy.json (design/13). Every name
## keeps its old call-site syntax — the numbers just live in data/ now.

static var _run: Dictionary = DB.run()
static var _eco: Dictionary = DB.economy()

# --- Run structure ---
static var PHRASES_PER_SECTION: int = int(_run["phrases_per_section"])
static var SECTIONS_PER_GIG: int = int(_run["sections_per_gig"])
static var GIGS_PER_RUN: int = int(_run["gigs_per_run"])
static var SECTIONS_PER_RUN: int = SECTIONS_PER_GIG * GIGS_PER_RUN
static var WALL_SECTIONS: Array = _walls()
static var BLIND_NAMES: Array = _run["blind_names"]
static var SECTION_TARGETS: Array = _ints(_run["section_targets"])

# --- Phrase timing ---
static var RESOLVE_FEEDBACK := 0.25
static var LATE_ACT_WINDOW: float = float(_run["late_act_window"])
static var EARLY_FINISH_TIME: float = float(_run["early_finish_time"])

# --- Card flow ---
static var HAND_SIZE: int = int(_run["hand_size"])
static var CACHE_CAP: int = int(_run["cache_cap"])
static var CACHE_MAX: int = CACHE_CAP

# --- Economy ---
static var STARTING_COINS: int = int(_eco["starting_coins"])
static var DISCARD_COST: int = int(_eco["discard_cost"])
static var SECTION_CLEAR_REWARD: int = int(_eco["section_clear_reward"])
static var DRAFT_RARITY_WEIGHTS: Dictionary = _eco["draft_rarity_weights"]
static var JOKER_PRICES: Dictionary = _eco["joker_prices"]
static var JOKER_PRICE_OVERRIDES: Dictionary = _eco["joker_price_overrides"]
static var TARGET_SWAP_PRICE: int = int(_eco["target_swap"]["price"])
static var TARGET_SWAP_CHANCE: float = float(_eco["target_swap"]["chance"])
static var TARGET_SWAP_FROM_SECTION: int = int(_eco["target_swap"]["from_section"])
static var DRAFT_SKIP_REWARD: int = int(_eco["draft_skip_reward"])
static var DRAFT_REROLL_BASE: int = int(_eco["reroll"]["base"])
static var DRAFT_REROLL_STEP: int = int(_eco["reroll"]["step"])


static func phrase_duration(section_idx: int) -> float:
	return float(_run["gig_clocks"][mini(gig_of(section_idx), GIGS_PER_RUN - 1)])

static func warning_time(duration: float) -> float:
	return duration - float(_run["warning_offset"])

static func lock_time(duration: float) -> float:
	return duration - float(_run["lock_offset"])

static func is_wall(section_idx: int) -> bool:
	return (section_idx + 1) % SECTIONS_PER_GIG == 0

static func gig_of(section_idx: int) -> int:
	@warning_ignore("integer_division")
	return section_idx / SECTIONS_PER_GIG

static func blind_name(section_idx: int) -> String:
	return String(BLIND_NAMES[section_idx % SECTIONS_PER_GIG])


static func _walls() -> Array:
	var out: Array = []
	for i in range(SECTIONS_PER_RUN):
		if is_wall(i):
			out.append(i)
	return out

static func _ints(a: Array) -> Array:
	var out: Array = []
	for v in a:
		out.append(int(v))
	return out
```

注意删掉的东西:`PHRASE_DURATION` 常量（只有 config 自己用,gig_clocks 取代）。
`grep -rn "PHRASE_DURATION" --include="*.gd"` 确认无其他引用后再删,有就保留为
`static var PHRASE_DURATION: float = float(_run["gig_clocks"][1])`。

- [ ] **Step 5: 修 sim.gd 的 const 初始化位点**

`tools/sim.gd:19` `const SECTIONS := GameConfig.SECTIONS_PER_RUN` →
`var SECTIONS: int = GameConfig.SECTIONS_PER_RUN`（成员 var 在 `_initialize` 前就绪）。

- [ ] **Step 6: import + 跑测试确认全绿**

```bash
godot --headless --path /Users/kuma/Projects/Sync5 --import
```

Run: 测试命令。Expected: `0 failed`（266 + 新增 _test_db 条数）。原 `_test_run_structure`/`_test_modifiers` 等全部数值断言就是搬家正确性的回归网。

---

### Task 2: faces.json + SectionMod 数据壳 + Settle 参数化

**Files:**
- Create: `data/faces.json`（design/13 §faces.json 逐字，static 含 `"bonus_disabled": true`）
- Modify: `core/modifier.gd`（全文重写）、`core/settle.gd:60-84`、`core/db.gd`
- Test: `tests/runner.gd`（`_test_modifiers` 尾部加参数断言）

- [ ] **Step 1: 加失败测试**

`_test_modifiers()` 末尾追加：

```gdscript
	eq(SectionMod.target_power("unplugged"), 0.5, "unplugged param from data")
	eq(SectionMod.target_power(""), 1.0, "no face -> full power")
	check(SectionMod.bonus_disabled("static"), "static disables bonuses")
	eq(SectionMod.repeat_factor("norepeat"), 0.5, "norepeat factor from data")
	eq(SectionMod.zero_discard_factor("rotation"), 0.5, "rotation factor from data")
```

跑测试，Expected: Parse Error（`target_power` 不存在）。

- [ ] **Step 2: 落 faces.json,重写 modifier.gd**

```gdscript
class_name SectionMod
extends RefCounted

## Boss-face section modifiers — data shell over data/faces.json (design/13).
## Metadata + numeric params live in data; the apply sites stay where they
## were (Settle for scoring twists, view/phrase.gd for clock & toll).

var id: String
var name: String
var cn_name: String
var fx_text: String


func _init(e: Dictionary) -> void:
	id = String(e["id"])
	name = String(e["name"])
	cn_name = String(e["cn"])
	fx_text = String(e["fx"])


static func roster() -> Array:
	var out: Array = []
	for e in DB.faces().get("faces", []):
		out.append(SectionMod.new(e))
	return out


static func by_id(p_id: String) -> SectionMod:
	for m in roster():
		if m.id == p_id:
			return m
	return null


static func pool_for(section_idx: int) -> Array:
	return DB.faces().get("pools", {}).get(str(section_idx), [])


static func roll(section_idx: int, rng: RandomNumberGenerator) -> String:
	var pool := pool_for(section_idx)
	if pool.is_empty():
		return ""
	return pool[rng.randi_range(0, pool.size() - 1)]


static func _param(mod_id: String, key: String, dflt: float) -> float:
	for e in DB.faces().get("faces", []):
		if String(e["id"]) == mod_id:
			return float(e.get("params", {}).get(key, dflt))
	return dflt


static func time_penalty(mod_id: String) -> float:
	return _param(mod_id, "time_penalty", 0.0)

static func phrase_toll(mod_id: String) -> int:
	return int(_param(mod_id, "phrase_toll", 0.0))

static func target_power(mod_id: String) -> float:
	return _param(mod_id, "target_power", 1.0)

static func repeat_factor(mod_id: String) -> float:
	return _param(mod_id, "repeat_factor", 1.0)

static func zero_discard_factor(mod_id: String) -> float:
	return _param(mod_id, "zero_discard_factor", 1.0)

static func bonus_disabled(mod_id: String) -> bool:
	for e in DB.faces().get("faces", []):
		if String(e["id"]) == mod_id:
			return bool(e.get("params", {}).get("bonus_disabled", false))
	return false
```

- [ ] **Step 3: Settle 改读参数**

`core/settle.gd` 四处硬编码改为（语义与现值逐位相同）：

```gdscript
			if i == 0 and pre_mult > 0.0:
				ctx.target_factor = ctx.mult / pre_mult
				var tp := SectionMod.target_power(mod)
				if tp < 1.0 and ctx.target_factor > 1.0:
					var hf: float = 1.0 + (ctx.target_factor - 1.0) * tp
					ctx.mult = pre_mult * hf
					ctx.target_factor = hf
```

```gdscript
		if SectionMod.bonus_disabled(mod):
			ctx.bonus = 0
		var score := int(round(float(eff_base) * total_mult + float(ctx.bonus)))
		var rf := SectionMod.repeat_factor(mod)
		if rf < 1.0 and ctx.prev_kind == ctx.kind and int(ctx.kind) > Pattern.Kind.HIGH_CARD:
			score = int(score * rf)
		var zf := SectionMod.zero_discard_factor(mod)
		if zf < 1.0 and int(ctx.discards) == 0:
			score = int(score * zf)
```

（`score / 2` 与 `int(score * 0.5)` 对正数同值。）

- [ ] **Step 4: db.gd 补 faces 校验 + load_error 接入**

```gdscript
static func validate_faces(d: Dictionary) -> String:
	if not d.has("faces") or not d.has("pools"):
		return "wants 'faces' and 'pools'"
	var ids := {}
	for e in d["faces"]:
		for k in e:
			if not ["id", "name", "cn", "fx", "params"].has(k) and not String(k).begins_with("_"):
				return "face unknown key '%s'" % k
		if ids.has(e["id"]):
			return "duplicate face id '%s'" % e["id"]
		ids[e["id"]] = true
	for w in d["pools"]:
		for fid in d["pools"][w]:
			if not ids.has(fid):
				return "pool '%s' references unknown face '%s'" % [w, fid]
	return ""
```

`load_error()` 加 `faces()`。

- [ ] **Step 5: 跑测试确认全绿**

---

### Task 3: Fx 解释器 + characters.json + Character 数据壳

**Files:**
- Create: `core/fx.gd`、`data/characters.json`（design/13 §characters.json 逐字）
- Modify: `core/character.gd`（全文重写）、`core/db.gd`
- Test: 现有 `_test_character`（行为回归网）+ `_test_db` 追加

- [ ] **Step 1: 写 core/fx.gd（when/do 解释器,小丑与主角共用）**

```gdscript
class_name Fx
extends RefCounted

## Effect-DSL interpreter (design/13). Entities carry
## effects: [{when, do}] — `when` predicates AND together, `do` writes one
## settle channel. Popup strings are generated per channel, matching the
## legacy hand-written formats byte-for-byte.


static func apply_effects(effects: Array, state: Dictionary, ctx: Dictionary) -> String:
	var popup := ""
	for e in effects:
		if not _when_ok(e.get("when", {}), state, ctx):
			continue
		var text := _do(e["do"], state, ctx)
		if popup == "" and text != "":
			popup = text
	return popup


static func _when_ok(w: Dictionary, state: Dictionary, ctx: Dictionary) -> bool:
	for k in w:
		var v = w[k]
		match String(k):
			"kind":
				if int(ctx.kind) != int(Pattern.Kind[String(v)]): return false
			"kind_in":
				var hit := false
				for n in v:
					if int(ctx.kind) == int(Pattern.Kind[String(n)]):
						hit = true
				if not hit: return false
			"same_as_prev":
				if int(ctx.prev_kind) != int(ctx.kind): return false
			"diff_from_prev":
				if int(ctx.prev_kind) == -99 or int(ctx.prev_kind) == int(ctx.kind): return false
			"acted_late":
				if not bool(ctx.acted_late): return false
			"discards_eq":
				if int(ctx.discards) != int(v): return false
			"discards_gte":
				if int(ctx.discards) < int(v): return false
			"coins_gte":
				if int(ctx.coins) < int(v): return false
			"base_gte":
				if int(ctx.base_score) < int(v): return false
			"last_phrase":
				if int(ctx.get("phrase_idx", -1)) != GameConfig.PHRASES_PER_SECTION - 1: return false
			"cache_mono_suit":
				var cards: Array = ctx.get("cache_cards", [])
				if cards.is_empty(): return false
				var suits := {}
				for c in cards:
					if not c.is_wild():
						suits[c.suit] = true
				if suits.size() > 1: return false
			"top_rank_gte":
				var top := 0
				for c in ctx.get("scoring_cards", []):
					top = maxi(top, int(c.rank))
				if top < int(v): return false
			"counter_gte":
				if float(state.get(String(v[0]), 0.0)) < float(v[1]): return false
			_:
				push_error("[Fx] unknown predicate '%s'" % k)
				return false
	return true


## Count multiplier from `per` / `step`.
static func _count(d: Dictionary, state: Dictionary, ctx: Dictionary) -> float:
	var per := String(d.get("per", ""))
	var c := 1.0
	if per == "discard":
		c = float(int(ctx.discards))
	elif per.begins_with("counter:"):
		c = float(state.get(per.substr(8), 0.0))
	elif per.begins_with("coins:"):
		c = float(int(ctx.coins) / int(per.substr(6)))
	if d.has("step"):
		c = float(int(c) / int(d["step"]))
	return c


static func _do(d: Dictionary, state: Dictionary, ctx: Dictionary) -> String:
	# escape-hatch opcodes first (design/13: the irreducible two)
	if d.has("mult_from_target_factor"):
		var tf: float = float(ctx.get("target_factor", 1.0))
		if tf > 1.0:
			var mf: float = 1.0 + (tf - 1.0) * float(d["mult_from_target_factor"])
			ctx.mult *= mf
			return "×%.1f" % mf
		return ""
	if d.has("additive_face_value"):
		var val := int(d["additive_face_value"])
		var boost := 0
		for c in ctx.get("scoring_cards", []):
			if c.rank >= 11 and c.rank <= 13:
				boost += val - c.rank
		if boost > 0:
			ctx.additive += boost
			return "+%d" % boost
		return ""

	var cnt := _count(d, state, ctx)
	if cnt <= 0.0:
		return ""
	for ch in ["mult", "mult_add", "additive", "bonus", "bonus_pct", "coins"]:
		if not d.has(ch):
			continue
		var raw = d[ch]
		var amt: float = float(state.get(String(raw["counter"]), 0.0)) if raw is Dictionary \
			else float(raw)
		var contrib: float = amt * cnt
		if d.has("cap"):
			contrib = minf(contrib, float(d["cap"]))
		match ch:
			"mult":
				ctx.mult *= contrib
				return "×%d" % int(contrib) if absf(contrib - roundf(contrib)) < 0.001 \
					else "×%.1f" % contrib
			"mult_add":
				var f: float = 1.0 + contrib
				ctx.mult *= f
				return "×%.2f" % f
			"additive":
				if int(round(contrib)) == 0: return ""
				ctx.additive += int(round(contrib))
				return "+%d" % int(round(contrib))
			"bonus":
				ctx.bonus += int(round(contrib))
				return "+%d" % int(round(contrib))
			"bonus_pct":
				if contrib < 0.001: return ""
				ctx.bonus_pct += contrib
				return "+%d%%" % int(round(contrib * 100.0))
			"coins":
				if int(round(contrib)) == 0: return ""
				ctx.coins_bonus += int(round(contrib))
				return "+%d◆" % int(round(contrib))
	push_error("[Fx] do has no known channel: %s" % str(d))
	return ""


## Counter feeding, replaces the hand-written growth hooks.
static func init_state(counters: Dictionary) -> Dictionary:
	var st: Dictionary = {}
	for cname in counters:
		if counters[cname].has("init"):
			st[cname] = float(counters[cname]["init"])
	return st


static func on_discard(counters: Dictionary, state: Dictionary, n: int) -> void:
	if n <= 0:
		return
	for cname in counters:
		if String(counters[cname].get("on_discard", "")) == "sum":
			state[cname] = float(state.get(cname, 0.0)) + float(n)


static func on_phrase_end(counters: Dictionary, state: Dictionary, x: Dictionary) -> void:
	for cname in counters:
		var spec: Dictionary = counters[cname]
		if spec.has("on_early_finish") and bool(x.get("early_finish", false)):
			state[cname] = float(state.get(cname, 0.0)) + float(spec["on_early_finish"])
		if spec.has("decay_per_phrase"):
			state[cname] = maxf(float(spec.get("floor", 0.0)),
				float(state.get(cname, 0.0)) - float(spec["decay_per_phrase"]))
```

**格式核对表**（与旧手写弹字逐字节一致，测试把关）：twin `×3`（mult 整数分支）、
bassline `×1.25`（mult_add %.2f）、mirror `×1.5`（opcode %.1f）、vinyl `+9`、
momentum/glowstick/chorus `+NN%`、tipjar/interest `+N◆`、纹身师 `+1◆`。
旧代码 `state` 存 int(vinyl n/momentum stacks),Fx 统一 float——所有比较/输出处
已用 int(round())/float() 归一,行为一致（测试验证）。

- [ ] **Step 2: import + 落 characters.json + 重写 character.gd**

```gdscript
class_name Character
extends RefCounted

## Data shell over data/characters.json (design/13). Same contract as Joker:
## apply(ctx) runs AFTER every joker and reads the totals they built.
## idx doubles as the walk-sprite id (Walker.CREW order).

var idx: int
var cn_name: String
var title: String
var fx_text: String
var _effects: Array


func _init(e: Dictionary) -> void:
	idx = int(e["idx"])
	cn_name = String(e["cn"])
	title = String(e["title"])
	fx_text = String(e["fx"])
	_effects = e.get("effects", [])


func apply(ctx: Dictionary) -> String:
	return Fx.apply_effects(_effects, {}, ctx)


static func roster() -> Array:
	var out: Array = []
	for e in DB.characters():
		out.append(Character.new(e))
	return out
```

- [ ] **Step 3: db.gd 补 characters 校验 + load_error 接入**

```gdscript
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
```

`_test_db` 追加：

```gdscript
	eq(Character.roster().size(), 8, "8 characters from data")
	check(DB.validate_characters({"characters": [{"idx": 1, "cn": "x", "title": "t", "fx": "f"}]}) != "",
		"non-dense idx detected")
```

- [ ] **Step 4: 跑测试确认全绿**

`_test_character` 的行为断言（8 个被动逐个）是解释器的第一道回归网。

---

### Task 4: jokers.json + Joker 数据壳（counters/acquire/opcodes 全量接通）

**Files:**
- Create: `data/jokers.json`（design/13 §jokers.json 逐字）
- Modify: `core/joker.gd`（全文重写）、`core/db.gd`
- Test: 现有 `_test_jokers`/`_test_settle`/`_test_wild`/`_test_rules`（最重的回归网）

- [ ] **Step 1: 落 jokers.json + 重写 joker.gd**

```gdscript
class_name Joker
extends RefCounted

## Data shell over data/jokers.json (design/13). Hook contract unchanged
## (apply/on_acquire/on_discard/on_swap/on_phrase_end/on_section_end);
## behaviors are DSL effects interpreted by Fx, growth counters are fed by
## the generic hooks reading the entry's `counters` spec.

var id: String
var name: String
var cn_name: String
var kind: String
var rarity: String
var fx_text: String
var state: Dictionary = {}
var _effects: Array
var _counters: Dictionary
var _acquire: Dictionary


func _init(e: Dictionary) -> void:
	id = String(e["id"])
	name = String(e["name"])
	cn_name = String(e["cn"])
	kind = String(e["kind"])
	rarity = String(e["rarity"])
	fx_text = String(e["fx"])
	_effects = e.get("effects", [])
	_counters = e.get("counters", {})
	_acquire = e.get("acquire", {})
	state = Fx.init_state(_counters)


func on_acquire(deck: Deck) -> void:
	if deck == null:
		return
	if _acquire.has("wilds"):
		deck.enable_wilds()
	if _acquire.has("deck_rule"):
		deck.rules[String(_acquire["deck_rule"])] = true


func on_discard(n: int) -> void:
	Fx.on_discard(_counters, state, n)


func on_swap() -> void:
	pass


func on_phrase_end(x: Dictionary) -> void:
	Fx.on_phrase_end(_counters, state, x)


func on_section_end() -> void:
	pass


func apply(ctx: Dictionary) -> String:
	return Fx.apply_effects(_effects, state, ctx)


static func by_id(p_id: String) -> Joker:
	for j in pool():
		if j.id == p_id:
			return j
	return null


static func pool() -> Array:
	var out: Array = []
	for e in DB.jokers():
		out.append(Joker.new(e))
	return out
```

（`enable_wilds()` 语义 = 洗两张王进牌库,与 `"wilds": 2` 对应——若 Deck API 带张数
参数则传 `int(_acquire["wilds"])`,以 `core/deck.gd` 实际签名为准。）

- [ ] **Step 2: db.gd 补 jokers 校验 + load_error 接入**

```gdscript
const _PREDICATES := ["kind", "kind_in", "same_as_prev", "diff_from_prev",
	"acted_late", "discards_eq", "discards_gte", "coins_gte", "base_gte",
	"last_phrase", "cache_mono_suit", "top_rank_gte", "counter_gte"]
const _DO_KEYS := ["mult", "mult_add", "additive", "bonus", "bonus_pct",
	"coins", "per", "step", "cap", "mult_from_target_factor", "additive_face_value"]

static func validate_jokers(d: Dictionary) -> String:
	if not d.has("jokers"):
		return "wants 'jokers'"
	var ids := {}
	for e in d["jokers"]:
		for k in e:
			if not ["id", "name", "cn", "kind", "rarity", "fx", "effects",
					"counters", "acquire"].has(k) and not String(k).begins_with("_"):
				return "joker unknown key '%s' (%s)" % [k, e.get("id", "?")]
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
	return ""
```

`_test_db` 追加（含跨表引用检查的断言）：

```gdscript
	eq(Joker.pool().size(), 23, "23 jokers from data")
	eq(Joker.by_id("twin").fx_text, "Pair ×3, Two Pair ×5", "joker text roundtrip")
	for oid in GameConfig.JOKER_PRICE_OVERRIDES:
		check(Joker.by_id(String(oid)) != null, "price override id '%s' exists" % oid)
	check(DB.validate_jokers({"jokers": [{"id": "x", "name": "X", "cn": "x", "kind": "support",
		"rarity": "common", "fx": "f", "effects": [{"when": {"typo": 1}, "do": {"bonus": 1}}]}]}) != "",
		"unknown predicate detected")
```

- [ ] **Step 3: 跑测试确认全绿**

`_test_jokers`（每张牌的行为断言）+ `_test_settle`（结算链）+ `_test_wild`（百搭）
+ `_test_rules`（规则牌）全绿 = DSL 解释器与 23 张牌数据的同一性证明。任何红条
先怀疑 DSL 语义（尤其 per/step/cap 与 int/float 边角），对照 design/13 的映射修。

---

### Task 5: sim.json + 机器人信念表接入 + `_target_mult` 推导

**Files:**
- Create: `data/sim.json`（design/13 §sim.json 逐字）
- Modify: `tools/sim.gd`（常量表 → DB;`_card_ev`/`_target_value`/`_p_chase`/`_target_mult`/cohorts）、`core/db.gd`
- Test: `_test_db` 追加 + Task 6 的 A/B 对拍

- [ ] **Step 1: db.gd 补 sim 校验 + load_error 接入**

```gdscript
static func validate_sim(d: Dictionary) -> String:
	for k in ["runs", "cohorts", "kind_prior", "target_tf", "counterfactual_tv",
			"lonewolf_value", "ev", "chase"]:
		if not d.has(k):
			return "missing key '%s'" % k
	var jids := {}
	for e in jokers():
		jids[e["id"]] = true
	for cid in d["ev"].get("cards", {}):
		if not jids.has(cid):
			return "ev card '%s' not in jokers" % cid
	return ""
```

`_test_db` 追加：`eq(int(DB.sim()["runs"]), 1000, "sim.json runs")`。

- [ ] **Step 2: sim.gd 接线**

逐处替换（保持算法结构，只换数字来源）：

```gdscript
var SIM: Dictionary = DB.sim()
var RUNS: int = int(SIM["runs"])
var SECTIONS: int = GameConfig.SECTIONS_PER_RUN
var KIND_PRIOR: Dictionary = _int_keys(SIM["kind_prior"])
var TARGET_TF: Dictionary = SIM["target_tf"]
var COUNTERFACTUAL_TV: Dictionary = SIM["counterfactual_tv"]
var EV: Dictionary = SIM["ev"]
var CHASE: Dictionary = SIM["chase"]

func _int_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[int(k)] = d[k]
	return out
```

cohort 列表（`_initialize` 里的字面量数组）→ `for c in SIM["cohorts"]: _run_cohort(c)`
（baseline 也在数据里,删掉单独那行）。

`_target_mult` 改为从 jokers 表推导（一次建缓存）：

```gdscript
var _tmult: Dictionary = {}    # tid -> {kind_int: mult}

func _target_mult(target_id: String, kind: int) -> float:
	if _tmult.is_empty():
		for e in DB.jokers():
			if String(e["kind"]) != "target":
				continue
			var tiers := {}
			for fx in e.get("effects", []):
				var m: float = float(fx.get("do", {}).get("mult", 0.0))
				if m <= 0.0:
					continue
				var w: Dictionary = fx.get("when", {})
				if w.has("kind"):
					tiers[int(Pattern.Kind[String(w["kind"])])] = m
				for n in w.get("kind_in", []):
					tiers[int(Pattern.Kind[String(n)])] = m
			_tmult[String(e["id"])] = tiers
	return float(_tmult.get(target_id, {}).get(kind, 1.0))
```

（独狼的 when 带 `discards_eq/top_rank_gte` 条件,推导表会给 HIGH_CARD→4.0;
旧 `_target_mult` 对独狼返回 1.0——`_target_value` 里独狼走 `lonewolf_value`
专门分支不经过这张表,行为不变;分支参数改读 `SIM["lonewolf_value"]`：）

```gdscript
	if tid == "lonewolf":
		var lw: Dictionary = SIM["lonewolf_value"]
		var ph: float = (float(st["kinds"].get(0, 0.0)) + float(lw["high_prior"]) * 6.0) / (n + 6.0)
		return ph * float(lw["mult"]) * float(lw["vow_discount"])
```

`_p_chase` 三个常数 → `CHASE`：

```gdscript
	return pow(clampf(q * float(d) / float(need) * float(CHASE["gain"]), 0.0,
		float(CHASE["cap"])), float(need))
# 且 d < need 时 return float(CHASE["floor"])
```

`_card_ev` 重写——公式结构保持,数额从 jokers 表取（`_amt(id)` = 第一条效果的
通道数额）,先验/权重从 `EV["cards"]`：

```gdscript
func _amt(id: String) -> float:
	for e in DB.jokers():
		if String(e["id"]) == id:
			for fx in e.get("effects", []):
				for ch in ["mult_add", "additive", "bonus", "bonus_pct", "coins"]:
					if fx.get("do", {}).has(ch):
						var raw = fx["do"][ch]
						return 0.0 if raw is Dictionary else float(raw)
	return 0.0


func _card_ev(id: String, st: Dictionary, slots: Array, phrases_left: int) -> float:
	var n: float = maxf(1.0, float(st["n"]))
	var bw: float = float(EV["blend_w"])
	var mult_mean: float = (float(st["mult"]) + float(EV["mult_prior"]) * bw) / (n + bw)
	var score_mean: float = (float(st["score"]) + float(EV["score_prior"]) * bw) / (n + bw)
	var coin_val: float = float(EV["coin_score_ratio"]) * score_mean
	var tid := "" if slots[0] == null else String(slots[0].id)
	var future := float(phrases_left)
	var horizon: float = float(EV["growth_horizon"])
	var p: Dictionary = EV["cards"].get(id, {})
	match id:
		"encore", "finale", "chord":
			return _rate(st, String(p["rate"]), float(p["prior"])) * _amt(id) * mult_mean
		"turnover":
			return _rate(st, String(p["rate"]), float(p["prior"])) * _amt(id) * mult_mean
		"tipjar":
			return _rate(st, String(p["rate"]), float(p["prior"])) * _amt(id) * coin_val
		"neonsign":
			return _amt(id) * mult_mean
		"vinyl":
			return _rate(st, String(p["rate"]), float(p["prior"])) * _amt(id) * (future * horizon) * mult_mean
		"chorus":
			return float(p["fixed_rate"]) * _amt(id) * score_mean
		"interest":
			return float(p["coin_mult"]) * coin_val
		"momentum":
			return _rate(st, String(p["rate"]), float(p["prior"])) * _amt(id) * (future * horizon) * score_mean
		"vip":
			return _rate(st, String(p["rate"]), float(p["prior"])) * float(p["boost"]) * mult_mean
		"glowstick":
			return (_glow_avg() * score_mean) * minf(future, float(EV["glowstick_horizon"])) \
				/ float(EV["glowstick_horizon"])
		"bassline":
			return _amt(id) * (_rate(st, String(p["rate"]), float(p["prior"])) * future * horizon / 12.0) * score_mean
		"mirror":
			var tf: float = float(TARGET_TF.get(tid, 1.0))
			return _rate(st, String(p["rate"]), float(p["prior"])) * (tf - 1.0) * 0.5 * score_mean
		"shortcut", "fourfingers", "twotone":
			var ot: Array = p["on_target"]
			var bm: float = score_mean / maxf(1.0, mult_mean)
			return (float(ot[1]) * float(ot[2]) * bm) if tid == String(ot[0]) \
				else float(p["off_target"]) * score_mean
		"wildcard":
			var tb: Array = p["target_bonus"]
			var bonus: float = float(tb[1]) if tid in tb[0] else 0.0
			return (float(p["base"]) + bonus) * score_mean
	return 0.0


## glowstick average lifetime pct = init/2 (linear decay to 0), from data.
func _glow_avg() -> float:
	for e in DB.jokers():
		if String(e["id"]) == "glowstick":
			return float(e["counters"]["pct"]["init"]) * 0.5
	return 0.30
```

（`bassline` 一条:旧式 `0.25 * (...) * score_mean` 的 0.25 = `_amt("bassline")`
= mult_add 数额 ✓;`mirror` 的 0.5 与 jokers 表 opcode 参数同源,保留字面 0.5
会复活漂移——改读 `Joker` 表:`float(_mirror_power())`,实现同 `_glow_avg` 模式读
`mult_from_target_factor` 值。）

- [ ] **Step 3: 跑测试全绿 + sim 冒烟**

测试命令全绿后,快速冒烟(完整 A/B 在 Task 6):

```bash
godot --headless --path /Users/kuma/Projects/Sync5 --check-only --script res://tools/sim.gd
```

---

### Task 6: A/B 同一性验证 + 文档同步

**Files:**
- Modify: `CLAUDE.md`、`design/13_Data_Config.md`(status 行)
- 基线: `_sim_baseline_r3.txt`(项目根,封盘 round-3 报告的拷贝,改造前基线;
  对拍完成后删除该文件)

- [ ] **Step 1: 全量测试并记录新基线**

Run: 测试命令。Expected `0 failed`,记下 `N passed`(266 + _test_db 系列)。

- [ ] **Step 2: sim A/B 对拍**

```bash
godot --headless --path /Users/kuma/Projects/Sync5 --script res://tools/sim.gd > /tmp/sim_after.txt 2>&1
```

```bash
diff <(grep -v "Godot Engine\|total.*s$" /tmp/sim_after.txt) <(grep -v "Godot Engine\|total.*s$" /Users/kuma/Projects/Sync5/_sim_baseline_r3.txt)
```

Expected: **零差异**(sim 全程有种子,两次基线跑已证逐字节可复现)。任何 diff =
搬家改了行为 = bug,回对应任务修——**不许用「数值差不多」糊弄过去**。

- [ ] **Step 3: 截图冒烟**

```bash
godot --path /Users/kuma/Projects/Sync5 --script res://tools/draft_sheet.gd
```

Read `_shot_draft.png`:卡面文字/价格/稀有度渲染正常(view 只读字段,应零变化)。

- [ ] **Step 4: 文档同步**

- `design/13` status 行 → `Status: **shipped** — all six data files live, A/B identical.`
- `CLAUDE.md`:测试基线数更新;架构铁律区加一行:
  「**数值与内容全部在 `data/*.json`**(schema 见 `design/13`):改卡/改平衡 = 改 JSON,
  `core/db.gd` 硬校验,未知键/坏引用直接红。新增小丑牌优先用 DSL,加操作码要过 D1 的门槛」;
  进度区加一行配置化完成。
- 记忆文件 `project_sync5_state.md` 更新(配置化基线 + A/B 同一性结论)。

- [ ] **Step 5: 终检**

对照 design/13 逐节核对:六份文件、DSL 全词汇有 loader 校验、`_target_mult` 已推导、
镜面 0.5 无第二份、266+ 全绿、A/B 零差异。

---

## Self-Review 结论

- **Spec 覆盖**:六份数据文件(T1×2/T2/T3/T4/T5)、DSL 解释器(T3)、数据壳三件(T2/T3/T4)、
  GameConfig/Economy 门面(T1,Economy 读 GameConfig 静态变量故零改动)、sim 信念表+推导(T5)、
  验证契约(T6)——design/13 各节均有对应任务。
- **类型一致**:`DB.load_error()/run()/economy()/jokers()/characters()/faces()/sim()`、
  `Fx.apply_effects/init_state/on_discard/on_phrase_end`、`SectionMod.target_power/
  repeat_factor/zero_discard_factor/bonus_disabled` 各处引用同名;Joker/Character 字段名
  与旧版完全一致(cn_name/fx_text/state/idx…),调用方不动。
- **无占位**:数据文件内容以 design/13 为唯一来源逐字物化;所有代码块给全文。
  已知的两个实现期自由度已注明处理办法(Deck.enable_wilds 签名、PHRASE_DURATION 引用检查)。
