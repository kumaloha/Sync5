class_name SectionMod
extends RefCounted

## Boss-face section modifiers — data shell over data/faces.json (docs/design/tech.md).
## Metadata + numeric params live in data; the apply sites stay where they
## were (Settle for the scoring twists, view/phrase.gd for clock & toll).
## All are announced in one line at section start (principle A1/A2); card
## text rule: EN, ≤7 words (D2) — loader-adjacent tests enforce it.

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


## 一张脸的**合法轮次集** —— `tiers` 优先, 缺省退回 `[tier]`(单轮)。
##
## ⚑ **为什么是集合而不是一个数**(2026-08-14 用户:「有大量只有一轮生效的盲注我不喜欢」):
## `tier` 单值等于宣称「难度是脸的固有属性」, 而 `docs/design/gates.md §6` 早就写了反面 ——
## **同一张脸放在 S1 和 S4 难度不一样**(构筑值 4.2 倍)。所以「这张脸属于哪轮」本来就该是
## **一个子集**, 不是一个点。
## ⚠⚠ 这不是新设计, 是**把 schema 放回它本来的宽度**:`tools/price.gd` 文件头写着
## 「定价表的大小是**合法放置数** = 4+5+7+6 = **22**, 不是 12」—— 12 张脸 22 个放置,
## 当年一张脸本来就能进多个段。定价仪器一直按「(脸, 段)」在量, **窄的是 schema 不是仪器**。
## ⚠ 放开不等于随便放:每个 (脸, 轮) 都要各自过价, 荒谬的放置(如 `patchin` 进 S1 ——
## 那时玩家还没有小丑牌, 效果为空)由作者在 `tiers` 里排除。
static func tiers_of_entry(e: Dictionary) -> Array:
	if e.has("tiers"):
		var out: Array = []
		for v in e["tiers"]:
			out.append(int(v))
		return out
	if e.has("tier"):
		return [int(e["tier"])]
	return []


## 这一段能掷到哪几张脸 —— **由每张脸自己的轮次集推导, 不再手写池子**
## (2026-08-07 用户拍板:「每次都要看塞在哪个轮次合适, 这也是脸的一个基础属性」)。
## 一张脸的归属只写一遍, 而且加新脸时不填 tier 会**直接报错**(core/db.gd), 和 `proof`
## 通路一样强制作者做一次决定 —— 手写池子时「塞哪轮」这个决定是可以被忘掉的。
## 轮次是 1..N(玩家口径的「第几轮」), section_idx 是 0 起, 差一。
static func pool_for(section_idx: int) -> Array:
	var out: Array = []
	for e in DB.faces().get("faces", []):
		if tiers_of_entry(e).has(section_idx + 1):
			out.append(String(e["id"]))
	return out


## 这张脸的**主场轮次**(1..N)—— 定价与门禁的基准位置。0 = 没入池(退役, 或还没决定)。
## ⚠ 它**不再等于**「这张脸只在这一轮出现」, 那个问题问 `tiers_of()`。
static func tier_of(mod_id: String) -> int:
	for e in DB.faces().get("faces", []):
		if String(e["id"]) == mod_id:
			return int(e.get("tier", 0))
	return 0


## 这张脸的全部合法轮次。空 = 没入池。
static func tiers_of(mod_id: String) -> Array:
	for e in DB.faces().get("faces", []):
		if String(e["id"]) == mod_id:
			return tiers_of_entry(e)
	return []


## 声明为「固定」的轮次 —— 只有一张脸, 每局都一样。见 docs/design/blinds.md §3:
## 固定的代价是新鲜感为零, 所以它**必须是显式声明的, 不能是排漏了**。
## ⚠ 不能直接 `.has(tier)` —— JSON 数字全是 float, `[4.0].has(4)` 是 **false** 且不报错。
static func tier_is_fixed(tier: int) -> bool:
	for v in DB.faces().get("fixed_tiers", []):
		if int(v) == tier:
			return true
	return false


## 这张脸在模型里走哪条通路 —— "score" / "belief" / "target"。
## "" = 没声明, 只可能发生在退役的脸上(进池子就必须声明, `DB.validate_faces` 锁着)。
## `tools/gate.gd` 照这个给每张脸造配对对照臂。见 docs/design/blinds.md §4。
static func proof(mod_id: String) -> String:
	for e in DB.faces().get("faces", []):
		if String(e["id"]) == mod_id:
			return String(e.get("proof", ""))
	return ""


## 出现在任意一段池子里的脸, 按段序去重。门要遍历的就是这一批。
static func pooled_ids() -> Array:
	var out: Array = []
	for idx in GameConfig.WALL_SECTIONS:
		for fid in pool_for(idx):
			if not out.has(fid):
				out.append(fid)
	return out


## Roll this section's modifier id ("" = no modifier). Deterministic under a
## seeded RNG so the sim stays resumable.
## ⚑⚑ `exclude` = 本局已经掷到过的脸 —— **「重复必须是有意的, 不能是偶然的」**。
##
## 这条守卫在 2026-08-07 `tier` 收成单值时被删过一次(叫 `arc`), 理由是「一张脸一个 tier
## 之后跨段复现在结构上表达不出来, 它守着一个不可能发生的情况」——
## 而 `docs/design/blinds.md §3` 当场留了后手:**「将来真要让一张脸跨轮出现,
## 把 tier 改成数组并把那条守卫加回来。」** 2026-08-14 放开 `tiers` = 那个「将来」到了。
##
## ⚠ 没有它会怎样:`roll` 是**每段独立均匀掷**, 一张脸跨轮之后同一局撞两次的概率立刻非零,
## 而那是**偶然**重复 —— 玩家读到的是「这游戏在偷懒」, 不是教学弧。
## ⚠ 教学弧那条(soft 早于 hard)管的是**族内先后**, 管不了**同一张脸**撞两次, 两条互不替代。
## ⚑ 将来 Director 要**有意**安排复现时, 由它显式指定脸、绕开 `roll` —— 有意的那条路
## 从来不经过这里, 所以这里可以无条件排除。
## ⚑ 这张脸在「第 `run_index` 局」解锁了没有(`min_run`, 缺省 0 = 一直有)。
##
## ⚠ `run_index <= 0` = **不设限, 全部解锁**。这是给探针/模型的口径, 也是缺省值 ——
## 选它是为了让**既有探针逐字节不变**:模型一直假设全部脸可用, 悄悄砍掉一张
## 会让所有历史读数与新读数不可比, 而且**不报错**。
## ⚠⚠ **所以真实局数必须由调用方显式传进来, `core/` 绝不自己去读存档** ——
## 从 SaveState 偷读会让同一份纯逻辑在「这台机器玩过几局」下产出不同结果,
## 那正是 2026-08-15 `flow_probe` 事故的形状(实验条件静默依赖机器本地状态)。
static func unlocked_at(id: String, run_index: int) -> bool:
	if run_index <= 0:
		return true
	# ⚠ `faces` 是**数组**不是字典 —— 走现成的 `_entry()`。第一版写成 `.get(id, {})`,
	# 那会静默返回空 ⇒ `min_run` 恒 0 ⇒ **门形同虚设, 而且一声不吭**。
	return run_index >= int(_entry(id).get("min_run", 0))


static func roll(section_idx: int, rng: RandomNumberGenerator, exclude: Array = [],
		run_index: int = -1) -> String:
	var pool_all := pool_for(section_idx)
	# ⚠ 先按解锁筛, 再按 exclude 筛 —— 反过来会让「没解锁的那张」占掉 exclude 的名额。
	var pool: Array = []
	for id in pool_all:
		if unlocked_at(String(id), run_index):
			pool.append(id)
	if pool.is_empty():
		pool = pool_all      # 全被锁住时退回全池, 同下面那条:宁可重复也不要漏一堵墙
	if pool.is_empty():
		return ""
	var fresh: Array = []
	for id in pool:
		if not exclude.has(id):
			fresh.append(id)
	# ⚠ 池子被排空时**退回全池**而不是返回 "" —— 「这一段没有脸」是个真实的规则差异
	# (4 段全是墙), 用它来表达「排布挤不下了」会静默改变游戏。宁可重复也不要漏一堵墙。
	if fresh.is_empty():
		fresh = pool
	return fresh[rng.randi_range(0, fresh.size() - 1)]


## ⚑⚑ **一局的四张脸 —— 唯一真相。**
##
## 2026-08-14 数了一下:这段 `for w in WALL_SECTIONS: faces[w] = roll(w, rng)` 被抄了
## **7 份**(游戏 `core/run.gd` + 探针 `sim`/`curve`/`decomp`/`wallet`/`decay`/`formal`)。
## 单值 `tier` 时七份等价, 所以没人发现;而 `exclude`(不许偶然重复)只加在游戏那一份上,
## 立刻就是第 6 次「**规则在游戏里, 不在模型里**」—— 这个项目最贵的一类错。
##
## ⚠ **RNG 消耗与旧代码逐次相同**:每个墙段恰好一次 `randi_range`, 顺序照 `WALL_SECTIONS`。
## 单轮时代 `exclude` 永远筛不掉东西(没有脸能出现在两个池子里), 所以**输出逐字节不变**。
## ⚠ `formal.gd` 原来遍历的是 `range(SECTIONS_PER_RUN)` 而不是 `WALL_SECTIONS` ——
## 四段全是墙时两者相同, 但 `is_wall` 一变就会静默分叉。收口顺手把这条也抹平了。
## ⚑ `run_index` = **这是第几局(1 起)**, `<= 0` = 不设限。见 `unlocked_at`。
## ⚠ **RNG 消耗不受它影响** —— 每个墙段仍恰好一次 `randi_range`, 顺序照 `WALL_SECTIONS`。
## 解锁只改**候选集**, 不改**抽几次**, 所以探针的随机流不会因为这个参数而错位。
static func roll_run(rng: RandomNumberGenerator, run_index: int = -1) -> Dictionary:
	var out := {}
	var drawn: Array = []
	for w in GameConfig.WALL_SECTIONS:
		var f := roll(int(w), rng, drawn, run_index)
		out[int(w)] = f
		if f != "":
			drawn.append(f)
	return out


## Does this face change anything `Settle` computes?
##
## ⚠ Performance-critical, and **wrong answers here are silent scoring bugs**.
## `Solver._settle_identity()` uses it to skip the entire settlement chain when
## no joker / character / face can move the score — the zero-allocation path
## that is worth 4× on solver probes. It used to test `mod == ""`, i.e. it gave
## up on ANY face; but most faces (cache eviction, capacity, hiding, tolls,
## the clock, the target multiplier) never reach Settle at all.
## The classification lives in `core/db.gd::_FACE_PARAMS_SETTLE` so that adding
## a param forces a decision instead of defaulting to the fast — and wrong — path.
static func affects_settle(mod_id: String) -> bool:
	if mod_id == "":
		return false
	for e in DB.faces().get("faces", []):
		if String(e["id"]) == mod_id:
			for k in e.get("params", {}):
				if DB._FACE_PARAMS_SETTLE.has(String(k)):
					return true
			return false
	return false


static func _param(mod_id: String, key: String, dflt: float) -> float:
	for e in DB.faces().get("faces", []):
		if String(e["id"]) == mod_id:
			return float(e.get("params", {}).get(key, dflt))
	return dflt


static func _entry(mod_id: String) -> Dictionary:
	for e in DB.faces().get("faces", []):
		if String(e["id"]) == mod_id:
			return e
	return {}


## Extra seconds shaved off the phrase clock by this modifier.
static func time_penalty(mod_id: String) -> float:
	return _param(mod_id, "time_penalty", 0.0)


## Coins charged at each phrase start under this modifier.
static func phrase_toll(mod_id: String) -> int:
	return int(_param(mod_id, "phrase_toll", 0.0))


## Target factor scale (1.0 = full power; unplugged 0.5).
static func target_power(mod_id: String) -> float:
	return _param(mod_id, "target_power", 1.0)


## Final-score scale on a repeated made hand (1.0 = no tax).
static func repeat_factor(mod_id: String) -> float:
	return _param(mod_id, "repeat_factor", 1.0)


## Final-score scale on zero-discard phrases (1.0 = no tax).
static func zero_discard_factor(mod_id: String) -> float:
	return _param(mod_id, "zero_discard_factor", 1.0)


## Cache cards randomly evicted at phrase end (lostpage 1 / freshsheet 3).
## The next phrase's start() tops the cache back up, so this is a *refresh*,
## not a shrink — it attacks 跨拍养牌, which is a mechanic Balatro has no
## equivalent of (warm.gd measured it at +24.6 分 / +10.4%).
static func cache_evict(mod_id: String) -> int:
	return int(_param(mod_id, "cache_evict", 0.0))


## Effective cache capacity under this face (smallstage: 3 -> 2).
## ⚠ This is the ONE face that changes the size of the choice set rather than
## the value of a choice: 八选五 becomes 七选五, so the solver's split count
## drops C(8,5)=56 -> C(7,5)=21. Solver reads `visible.size()`, so it adapts
## with no change; view lays the row out at CACHE_CAP width, so the freed 3rd
## slot simply shows empty — which is the rule's own visual tell.
static func cache_cap(mod_id: String) -> int:
	return maxi(0, GameConfig.CACHE_CAP + int(_param(mod_id, "cache_cap_delta", 0.0)))


## Final-score scale on a hand type other than the section's FIRST (setlist).
## 1.0 = no lock. See the card's `_why` for why halving beats 判废.
static func lock_first(mod_id: String) -> float:
	return _param(mod_id, "lock_first", 1.0)


## Section target multiplier (raisedbar 1.5). 1.0 = unchanged.
static func target_mult(mod_id: String) -> float:
	return _param(mod_id, "target_mult", 1.0)


## --- 信息隐藏族(2026-08-07)。原作最大的两族之一, 我们此前一张都没有。 ---
## 盖牌**不改任何数值**, 只拿走视野, 所以它是唯一一族要求求解器从
## 完全信息走向**不完全信息**的脸(见 tools/solver.gd 的 belief/score 分工)。
## ⚠ 在实时游戏里它比原作重:原作是回合制, 少点信息就是少点信息;
## 我们一拍 8 秒, 看不清就得花时间推, 而时间是唯一的闸门。

## blindspot: cards drawn to replace a discard come back face down.
static func hide_refill(mod_id: String) -> bool:
	return _param(mod_id, "hide_refill", 0.0) > 0.0


## facedown: every J/Q/K is face down for the phrase.
static func hide_faces(mod_id: String) -> bool:
	return _param(mod_id, "hide_faces", 0.0) > 0.0


static func discard_lock_last(mod_id: String) -> float:
	return _param(mod_id, "discard_lock_last", 0.0)


static func swap_lock_last(mod_id: String) -> float:
	return _param(mod_id, "swap_lock_last", 0.0)


## Time-window gates are shared by the view and probes so the exact boundary
## ("the final two seconds" includes 2.00) cannot drift between call sites.
static func discard_open(mod_id: String, seconds_left: float) -> bool:
	var close_last := discard_lock_last(mod_id)
	return close_last <= 0.0 or seconds_left > close_last


static func swap_open(mod_id: String, seconds_left: float) -> bool:
	var close_last := swap_lock_last(mod_id)
	return close_last <= 0.0 or seconds_left > close_last


static func discard_action_limit(mod_id: String) -> int:
	return int(_param(mod_id, "discard_actions", -1.0))


static func swap_action_limit(mod_id: String) -> int:
	return int(_param(mod_id, "swap_actions", -1.0))


static func action_limit(mod_id: String) -> int:
	return int(_param(mod_id, "action_limit", -1.0))


static func cache_blocks_red(mod_id: String) -> bool:
	return _param(mod_id, "cache_block_red", 0.0) > 0.0


static func refill_rank_min(mod_id: String) -> int:
	return int(_param(mod_id, "refill_rank_min", 2.0))


static func refill_rank_max(mod_id: String) -> int:
	return int(_param(mod_id, "refill_rank_max", 15.0))


static func cache_lock_phrases(mod_id: String) -> int:
	return int(_param(mod_id, "cache_lock_phrases", 0.0))


static func seals_lowest_start(mod_id: String) -> bool:
	return _param(mod_id, "seal_lowest_start", 0.0) > 0.0


static func seals_oldest_cache(mod_id: String) -> bool:
	return _param(mod_id, "seal_oldest_cache", 0.0) > 0.0


static func required_kinds(mod_id: String) -> int:
	return int(_param(mod_id, "required_kinds", 0.0))


## 曲目税的罚档(裁决 #8):每缺一种, 目标乘 (1 + penalty)。数值在 faces.json。
static func variety_penalty(mod_id: String) -> float:
	return _param(mod_id, "variety_penalty", 0.0)


static func restores_with_initial_cache(mod_id: String) -> bool:
	return _param(mod_id, "restore_with_initial_cache", 0.0) > 0.0


static func section_discard_budget(mod_id: String) -> int:
	return int(_param(mod_id, "section_discard_budget", -1.0))


static func exclusive_action_tracks(mod_id: String) -> bool:
	return _param(mod_id, "exclusive_action_tracks", 0.0) > 0.0


static func request_factor(mod_id: String) -> float:
	return _param(mod_id, "request_factor", 1.0)


static func joker_power(mod_id: String) -> float:
	return _param(mod_id, "joker_power", 1.0)


static func tape_required(mod_id: String) -> bool:
	return bool(_entry(mod_id).get("tape_required", false))


## Whether the flat-bonus channel is zeroed (static).
static func bonus_disabled(mod_id: String) -> bool:
	for e in DB.faces().get("faces", []):
		if String(e["id"]) == mod_id:
			return bool(e.get("params", {}).get("bonus_disabled", false))
	return false
