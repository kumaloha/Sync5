class_name Report
extends RefCounted

## The sim's ledgers and printed reports (docs/design/tech.md split): per-section
## death/score/coin accumulators, joker presence/trigger counts, the
## playbook harvester. Pure bookkeeping — no RNG, no decisions.

var _runs: int
var _sections: int


func _init(runs: int, sections: int) -> void:
	_runs = runs
	_sections = sections


var died_at: Array = []          # section index of death, _sections = cleared
var phrase_score_sum: Array = []
var phrase_score_n: Array = []
var coins_at_section: Array = []
var coins_at_n: Array = []
var kind_count: Dictionary = {}
var support_drafted: Dictionary = {}   # id -> runs that ever held it
var trigger_n: Dictionary = {}         # id -> settles with a popup
var presence_n: Dictionary = {}        # id -> settles while installed
var discards_sum := 0
var discards_n := 0
var run_records: Array = []
var pivots_n := 0
var wall_mod: Dictionary = {}   # "S8 static" -> [runs, deaths]
# 货架证物(kit shop 通路;bot._draft 记账): 进店数 / 首发含规则牌的店数 / 成交总数 /
# 双购店数(一次进店成交 ≥2, 无联票时物理不可能) / 实收折扣(基础价 − 实付, 无赞助恒 0)。
# ⚠ 后两个是**零基线**证物 —— 第一版用「成交数/均价」被钉槽混杂吃掉(实验臂钉死一个
# 槽位, 少装一张卡的效应与被量的效应同量级), 零基线读数混杂无处藏身。
var shops_n := 0
var rule_shops_n := 0
var buys_total := 0
var multi_shops_n := 0
var discount_coins := 0


func reset() -> void:
	died_at = []
	phrase_score_sum = []
	phrase_score_n = []
	coins_at_section = []
	coins_at_n = []
	for i in range(_sections):
		phrase_score_sum.append(0.0)
		phrase_score_n.append(0)
		coins_at_section.append(0.0)
		coins_at_n.append(0)
	kind_count = {}
	support_drafted = {}
	trigger_n = {}
	presence_n = {}
	discards_sum = 0
	discards_n = 0
	run_records = []
	pivots_n = 0
	wall_mod = {}
	shops_n = 0
	rule_shops_n = 0
	buys_total = 0
	multi_shops_n = 0
	discount_coins = 0


func record_run(slots: Array, died: int) -> void:
	var sup: Array = []
	for k in range(1, slots.size()):
		if slots[k] != null:
			sup.append(String(slots[k].id))
	sup.sort()
	run_records.append({"t": "" if slots[0] == null else String(slots[0].id),
		"sup": sup, "died": died})


func track_triggers(slots: Array, outcome: Dictionary) -> void:
	var fired := {}
	for pu in outcome["popups"]:
		var s := int(pu["slot"])
		if s >= 0 and s < slots.size() and slots[s] != null:
			fired[slots[s].id] = true
	for j in slots:
		if j == null:
			continue
		presence_n[j.id] = int(presence_n.get(j.id, 0)) + 1
		if fired.has(j.id):
			trigger_n[j.id] = int(trigger_n.get(j.id, 0)) + 1



## 上一次 print_report 算出的通关率 —— 给 sim.gd 的尺子自检用(见那边 _sanity)。
var last_clear := 0.0

func print_report(cfg: Dictionary) -> void:
	var name := String(cfg.get("name", "?"))
	var attempts: Array = []
	var passes: Array = []
	for i in range(_sections):
		attempts.append(0)
		passes.append(0)
	var clears := 0
	for d in died_at:
		var dd := int(d)
		if dd >= _sections:
			clears += 1
		for i in range(_sections):
			if dd > i:
				attempts[i] += 1
				passes[i] += 1
			elif dd == i:
				attempts[i] += 1
	print("\n=== %s · %d runs ===" % [name, died_at.size()])
	var pass_line := "  reach%%: "
	for i in range(_sections):
		pass_line += "S%d:%d%% " % [i + 1, int(round(100.0 * float(passes[i]) / float(died_at.size())))]
	print(pass_line)
	last_clear = 100.0 * float(clears) / float(died_at.size())
	print("  full clear: %.1f%%" % last_clear)
	if pivots_n > 0:
		print("  target pivots: %d (%.1f%% of runs)" % [pivots_n, 100.0 * float(pivots_n) / float(died_at.size())])
	if not wall_mod.is_empty():
		var wkeys := wall_mod.keys()
		wkeys.sort()
		var wline := "  wall faces (death%% among reachers): "
		# ⚠ 有些脸这把尺子**量不到**, 印出来的 0% 是假的, 不是「这张脸不疼」。
		# 盖牌族靠的是求解器的不完全信息(tools/solver.gd 的 belief/score),
		# 而 sim 跑的是规则机器人 —— 它压根不读 `Phrase.hidden`, 全程上帝视角。
		# 实测对照:blind.gd 量出 blindspot −25%、facedown −33%(完美玩家),
		# 同一批脸在这里是 0-13%。**不标出来就会被当成「这张脸没用」而删掉。**
		var unseen: Array = []
		for k in wkeys:
			var n: int = wall_mod[k][0]
			var d: int = wall_mod[k][1]
			if n >= 30:
				var fid := String(k).split(" ")[-1]
				var blindish := SectionMod.hide_refill(fid) or SectionMod.hide_faces(fid)
				wline += "%s:%d%%%s(%d) " % [k, int(round(100.0 * float(d) / float(n))),
					"⊘" if blindish else "", n]
				if blindish and not unseen.has(fid):
					unseen.append(fid)
		print(wline)
		if not unseen.is_empty():
			print("  ⊘ = 规则机器人看不见这张脸(它不读 Phrase.hidden), 上面的数字无意义 —— %s"
				% [unseen])
			print("    量盖牌族请用 tools/blind.gd(完美玩家 + 上帝视角 A/B)")
	var death_n := {}
	for dd2 in died_at:
		death_n[int(dd2)] = int(death_n.get(int(dd2), 0)) + 1
	var death_line := "  deaths at: "
	for i in range(_sections):
		death_line += "S%d:%d%% " % [i + 1, int(round(100.0 * float(death_n.get(i, 0)) / float(died_at.size())))]
	print(death_line)
	print_playbooks()
	var score_line := "  avg phrase score: "
	for i in range(_sections):
		if phrase_score_n[i] > 0:
			score_line += "S%d:%d " % [i + 1, int(phrase_score_sum[i] / float(phrase_score_n[i]))]
	print(score_line)
	var coin_line := "  avg coins at section end: "
	for i in range(_sections):
		if coins_at_n[i] > 0:
			coin_line += "S%d:%.1f " % [i + 1, coins_at_section[i] / float(coins_at_n[i])]
	print(coin_line)
	print("  avg discards/phrase: %.2f" % (float(discards_sum) / maxf(1.0, float(discards_n))))
	var kinds := kind_count.keys()
	kinds.sort()
	var kind_line := "  patterns: "
	var total_k := 0
	for k in kinds:
		total_k += int(kind_count[k])
	for k in kinds:
		if int(k) >= 0:
			kind_line += "%s:%d%% " % [Pattern.NAMES[int(k)].split(" ")[0], int(round(100.0 * float(kind_count[k]) / float(total_k)))]
	print(kind_line)
## The routine harvester: what kits actually win, and what each support is
## worth. This list is the requirements doc for the S5/S8/S10 boss modifiers.
func print_playbooks() -> void:
	var clears_recs: Array = []
	for rec in run_records:
		if int(rec["died"]) >= _sections:
			clears_recs.append(rec)
	if clears_recs.size() < 10:
		return
	var kit_n := {}
	for rec in clears_recs:
		var key := String(rec["t"]) + " + " + " / ".join(PackedStringArray(rec["sup"]))
		kit_n[key] = int(kit_n.get(key, 0)) + 1
	var keys := kit_n.keys()
	keys.sort_custom(func(x, y) -> bool: return int(kit_n[x]) > int(kit_n[y]))
	var kit_line := "  winning kits: "
	for i in range(mini(3, keys.size())):
		kit_line += "[%s]×%d  " % [keys[i], int(kit_n[keys[i]])]
	print(kit_line)
	var lift_line := "  support lift: "
	var lifts := {}
	for j in Joker.pool():
		if j.kind != "support":
			continue
		var with_c := 0
		var with_n := 0
		var wo_c := 0
		var wo_n := 0
		for rec in run_records:
			var held: bool = (rec["sup"] as Array).has(j.id)
			var cleared: bool = int(rec["died"]) >= _sections
			if held:
				with_n += 1
				if cleared: with_c += 1
			else:
				wo_n += 1
				if cleared: wo_c += 1
		if with_n >= 50 and wo_n >= 50:
			lifts[j.id] = 100.0 * (float(with_c) / float(with_n) - float(wo_c) / float(wo_n))
	var lids := lifts.keys()
	lids.sort_custom(func(x, y) -> bool: return float(lifts[x]) > float(lifts[y]))
	for id in lids:
		lift_line += "%s:%+.0f%% " % [id, float(lifts[id])]
	print(lift_line)


	if not presence_n.is_empty():
		var trig_line := "  support trigger%% (drafted runs): "
		var ids := presence_n.keys()
		ids.sort()
		for id in ids:
			var pn := int(presence_n[id])
			if pn == 0:
				continue
			trig_line += "%s:%d%%(%d) " % [id, int(round(100.0 * float(trigger_n.get(id, 0)) / float(pn))), int(support_drafted.get(id, 0))]
		print(trig_line)
