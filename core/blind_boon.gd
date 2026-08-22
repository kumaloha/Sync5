class_name BlindBoon
extends RefCounted

var id: String
var name: String
var cn_name: String
var fx_text: String


func _init(e: Dictionary) -> void:
	id = String(e["id"])
	name = String(e["name"])
	cn_name = Lingo.pick(e)   # 名字带语言(1.1 英文化):en 挑现成的 name 字段
	fx_text = String(e["fx"])


static func roster() -> Array:
	var out: Array = []
	for e in DB.boons().get("boons", []):
		out.append(BlindBoon.new(e))
	return out


static func ids() -> Array:
	var out: Array = []
	for boon in roster():
		out.append(boon.id)
	return out


static func by_id(p_id: String) -> BlindBoon:
	for boon in roster():
		if boon.id == p_id:
			return boon
	return null


## `seen` = {boon_id: 见过几次}(context.md 岔 #4 批「Boon 也走 novelty」)。
## 非空且 Director.novelty_on() 时收缩到最少见的那批;恒一次掷点, 空 seen 逐字节退回。
static func roll(rng: RandomNumberGenerator, seen: Dictionary = {}) -> String:
	var pool := ids()
	if pool.is_empty():
		return ""
	if not seen.is_empty() and Director.novelty_on():
		var kept: Array = []
		var best := -1
		for id in pool:
			var c := int(seen.get(String(id), 0))
			if best < 0 or c < best:
				best = c
				kept = [id]
			elif c == best:
				kept.append(id)
		pool = kept
	return String(pool[rng.randi_range(0, pool.size() - 1)])


static func _param(boon_id: String, key: String, dflt: float) -> float:
	for e in DB.boons().get("boons", []):
		if String(e["id"]) == boon_id:
			return float(e.get("params", {}).get(key, dflt))
	return dflt


static func score_replay_factor(boon_id: String) -> float:
	return _param(boon_id, "score_replay_factor", 0.0)


static func spotlight_cards(boon_id: String) -> int:
	return int(_param(boon_id, "spotlight_cards", 0.0))


static func previous_raw_factor(boon_id: String) -> float:
	return _param(boon_id, "previous_raw_factor", 0.0)


static func ghost_first_discard(boon_id: String) -> bool:
	return _param(boon_id, "ghost_first_discard", 0.0) > 0.0
