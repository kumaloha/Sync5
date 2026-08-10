class_name BlindBoon
extends RefCounted

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


static func roll(rng: RandomNumberGenerator) -> String:
	var pool := ids()
	if pool.is_empty():
		return ""
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
