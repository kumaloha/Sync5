class_name SectionMod
extends RefCounted

## Boss-face section modifiers — data shell over data/faces.json (design/tech.md).
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


## 这一段能掷到哪几张脸 —— **由每张脸自己的 `tier` 推导, 不再手写池子**
## (2026-08-07 用户拍板:「每次都要看塞在哪个轮次合适, 这也是脸的一个基础属性」)。
## 一张脸的归属只写一遍, 而且加新脸时不填 tier 会**直接报错**(core/db.gd), 和 `proof`
## 通路一样强制作者做一次决定 —— 手写池子时「塞哪轮」这个决定是可以被忘掉的。
## `tier` 是 1..N(玩家口径的「第几轮」), section_idx 是 0 起, 差一。
static func pool_for(section_idx: int) -> Array:
	var out: Array = []
	for e in DB.faces().get("faces", []):
		if int(e.get("tier", 0)) == section_idx + 1:
			out.append(String(e["id"]))
	return out


## 这张脸属于第几轮(1..N)。0 = 没入池(退役, 或还没决定塞哪轮)。
static func tier_of(mod_id: String) -> int:
	for e in DB.faces().get("faces", []):
		if String(e["id"]) == mod_id:
			return int(e.get("tier", 0))
	return 0


## 声明为「固定」的轮次 —— 只有一张脸, 每局都一样。见 design/blinds.md §3:
## 固定的代价是新鲜感为零, 所以它**必须是显式声明的, 不能是排漏了**。
## ⚠ 不能直接 `.has(tier)` —— JSON 数字全是 float, `[4.0].has(4)` 是 **false** 且不报错。
static func tier_is_fixed(tier: int) -> bool:
	for v in DB.faces().get("fixed_tiers", []):
		if int(v) == tier:
			return true
	return false


## 这张脸在模型里走哪条通路 —— "score" / "belief" / "target"。
## "" = 没声明, 只可能发生在退役的脸上(进池子就必须声明, `DB.validate_faces` 锁着)。
## `tools/gate.gd` 照这个给每张脸造配对对照臂。见 design/blinds.md §4。
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
static func roll(section_idx: int, rng: RandomNumberGenerator) -> String:
	var pool := pool_for(section_idx)
	if pool.is_empty():
		return ""
	return pool[rng.randi_range(0, pool.size() - 1)]


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


## Whether the flat-bonus channel is zeroed (static).
static func bonus_disabled(mod_id: String) -> bool:
	for e in DB.faces().get("faces", []):
		if String(e["id"]) == mod_id:
			return bool(e.get("params", {}).get("bonus_disabled", false))
	return false
