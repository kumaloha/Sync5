class_name Fx
extends RefCounted

## Effect-DSL interpreter (design/tech.md). Entities carry
## effects: [{when, do}] — `when` predicates AND together, `do` writes one
## settle channel. Popup strings are generated per channel, matching the
## legacy hand-written formats byte-for-byte (tests enforce it).


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
				if int(ctx.kind) != int(Pattern.Kind[String(v)]):
					return false
			"kind_in":
				var hit := false
				for n in v:
					if int(ctx.kind) == int(Pattern.Kind[String(n)]):
						hit = true
				if not hit:
					return false
			"same_as_prev":
				if int(ctx.prev_kind) != int(ctx.kind):
					return false
			"diff_from_prev":
				if int(ctx.prev_kind) == -99 or int(ctx.prev_kind) == int(ctx.kind):
					return false
			"acted_late":
				if not bool(ctx.acted_late):
					return false
			"discards_eq":
				if int(ctx.discards) != int(v):
					return false
			"discards_gte":
				if int(ctx.discards) < int(v):
					return false
			"coins_gte":
				if int(ctx.coins) < int(v):
					return false
			"base_gte":
				if int(ctx.base_score) < int(v):
					return false
			"last_phrase":
				if int(ctx.get("phrase_idx", -1)) != GameConfig.PHRASES_PER_SECTION - 1:
					return false
			"cache_mono_suit":
				var cards: Array = ctx.get("cache_cards", [])
				if cards.is_empty():
					return false
				var suits := {}
				for c in cards:
					if not c.is_wild():
						suits[c.suit] = true
				if suits.size() > 1:
					return false
			"top_rank_gte":
				var top := 0
				for c in ctx.get("scoring_cards", []):
					top = maxi(top, int(c.rank))
				if top < int(v):
					return false
			"counter_gte":
				if float(state.get(String(v[0]), 0.0)) < float(v[1]):
					return false
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
		@warning_ignore("integer_division")
		c = float(int(ctx.coins) / int(per.substr(6)))
	if d.has("step"):
		@warning_ignore("integer_division")
		c = float(int(c) / int(d["step"]))
	return c


static func _do(d: Dictionary, state: Dictionary, ctx: Dictionary) -> String:
	# escape-hatch opcodes first (design/tech.md: the irreducible two)
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
				return ("×%d" % int(round(contrib))) if absf(contrib - roundf(contrib)) < 0.001 \
					else ("×%.1f" % contrib)
			"mult_add":
				var f: float = 1.0 + contrib
				ctx.mult *= f
				return "×%.2f" % f
			"additive":
				if int(round(contrib)) == 0:
					return ""
				ctx.additive += int(round(contrib))
				return "+%d" % int(round(contrib))
			"bonus":
				ctx.bonus += int(round(contrib))
				return "+%d" % int(round(contrib))
			"bonus_pct":
				if contrib < 0.001:
					return ""
				ctx.bonus_pct += contrib
				return "+%d%%" % int(round(contrib * 100.0))
			"coins":
				if int(round(contrib)) == 0:
					return ""
				ctx.coins_bonus += int(round(contrib))
				return "+%d◆" % int(round(contrib))
	push_error("[Fx] do has no known channel: %s" % str(d))
	return ""


## ---- Counter feeding (replaces the hand-written growth hooks) ----

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
