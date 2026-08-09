class_name Character
extends RefCounted

## Data shell over data/characters.json (design/tech.md). Same contract as Joker:
## apply(ctx) mutates the settle context and returns a popup text ("" =
## none). It runs AFTER every joker, so a character reads the totals the
## jokers built. idx doubles as the walk-sprite id (Walker.CREW order) —
## the loader enforces dense 0..N order. Balance pass = edit the JSON.

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
