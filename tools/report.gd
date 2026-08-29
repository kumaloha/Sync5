class_name Report
extends RefCounted

## The sim's ledgers and printed reports (docs/design/tech.md split): per-section
## death/score/coin accumulators, joker presence/trigger counts, the
## playbook harvester. Pure bookkeeping — no RNG, no decisions.

var _sections: int


func _init(runs: int, sections: int) -> void:
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
var consumables_bought := 0
var consumables_used := 0
var pivots_n := 0
var pivots_held := 0      ## 其中「本局持有过转型」的换旗次数
var swap_runs_held := 0   ## 本局持有过转型的局数
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

# ── 经济 v2 收支账本(2026-08-27;对照 docs/design/levels.md 经济 v2「怎么调」四条健康带)──
# **旁路记账, 只记事实**:钱真的动了 / 拒绝真的发生了。不消耗 RNG、不碰任何决策。
# `eco` = 当前一局的累加器(sim.gd 每局 `eco_begin_run()`, 记账口用 `eco_add()`),
# `eco_runs` = 每局一条的定案(`eco_commit_run()`)。⚠ 其他探针的 Bot 也会往 `eco` 里
# 写(买卡/拒弃的记账口在 bot.gd)—— 没人 begin/commit 就只是攒在一个没人读的
# 字典里, 零副作用。键与口径:
#   spend_discard  弃牌总支出◆(= 弃牌张数 × DISCARD_COST, 在结算回调按 p.discards_used 记)
#   disc_cards     弃牌总张数(含缓存直弃/回收献祭/轮换强弃 —— 与 discards_used 同口径)
#   spend_buy      买卡净支出◆(= 每次成交前后余额差:含换旗/替换的回收抵扣与上限修剪)
#   spend_reroll   付费刷新支出◆
#   income_kind    牌型金币总收入◆(**只看牌型** = res.coins, 不含小丑加成/系数 —— 健康带口径)
#   deny_money     「想弃但金币不足」次数(bot 已定下要弃的张数, coins < 张数×单价;
#                  ⚠ bot 的 κ 自我约束在这之前发生, 所以拒绝很少 ≠ 钱不紧, 要连 κ 一起读)
#   kappa_cut      κ 门槛砍掉的弃牌张数(plan 增益 < κ×张数, 决策前的自我约束 —— 上一条的另一半)
#   broke_beats    软破产拍数(**决策时** 0◆:发牌后动手前 coins==0, 一张都弃不起)
#   beats / zerod_beats  总拍数 / 零弃牌拍数(弃牌分布「塌零」判据的分母与分子)
var eco: Dictionary = {}
var eco_runs: Array = []
## print_report 算完的经济摘要挂在这, 给 sim.gd 的跨队列健康带对照用(同 last_clear)。
var last_eco: Dictionary = {}


func eco_begin_run() -> void:
	eco = {}


func eco_add(key: String, v: int) -> void:
	eco[key] = int(eco.get(key, 0)) + v


func eco_commit_run(end_coins: int, cleared: bool) -> void:
	eco["end"] = end_coins
	eco["cleared"] = 1 if cleared else 0
	eco_runs.append(eco)
	eco = {}


static func eco_mean_se(vals: Array) -> Array:
	var n := vals.size()
	if n == 0:
		return [0.0, 0.0]
	var s := 0.0
	for v in vals:
		s += float(v)
	var m := s / float(n)
	if n < 2:
		return [m, 0.0]
	var q := 0.0
	for v in vals:
		q += (float(v) - m) * (float(v) - m)
	return [m, sqrt(q / float(n - 1)) / sqrt(float(n))]


static func eco_median(vals: Array) -> float:
	if vals.is_empty():
		return 0.0
	var s := vals.duplicate()
	s.sort()
	var n := s.size()
	if n % 2 == 1:
		return float(s[n / 2])
	return (float(s[n / 2 - 1]) + float(s[n / 2])) * 0.5


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
	consumables_bought = 0
	consumables_used = 0
	pivots_n = 0
	pivots_held = 0
	swap_runs_held = 0
	wall_mod = {}
	shops_n = 0
	rule_shops_n = 0
	buys_total = 0
	multi_shops_n = 0
	discount_coins = 0
	eco = {}
	eco_runs = []
	last_eco = {}


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
	if consumables_bought > 0 or consumables_used > 0:
		print("  消耗牌:买 %.2f 张/局 · 用 %.2f 张/局"
			% [float(consumables_bought) / maxf(1.0, float(died_at.size())),
			float(consumables_used) / maxf(1.0, float(died_at.size()))])
	if pivots_n > 0:
		print("  target pivots: %d (%.1f%% of runs)" % [pivots_n, 100.0 * float(pivots_n) / float(died_at.size())])
		# ⚑ 分两列(2026-08-29):可控卡的触发率**因持有而改变**, 只报总平均会被未持有的局
		# 稀释成一个谁也不是的数(与 probbook「基线 vs 持有态」同一条纪律)。
		if swap_runs_held > 0:
			print("    持有转型的局:%.2f 次/局(%d 局)· 未持有:%.2f 次/局"
				% [float(pivots_held) / float(swap_runs_held), swap_runs_held,
				float(pivots_n - pivots_held) / maxf(1.0, float(died_at.size() - swap_runs_held))])
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
	_print_economy()


## 经济节:每队列的收支读数(键的口径见上面 eco 的声明注释)。
## ⚠ 健康带按**真人口径**标(levels.md:bot 世界恒比真人松, bot 弃 0.6 vs 真人 1.5-3),
## 这里是 bot 尺 —— 只看方向与相对变化, 不许拿这里的数字直接去调 economy.json。
func _print_economy() -> void:
	last_eco = {}
	if eco_runs.is_empty():
		return
	var n := eco_runs.size()
	var end_vals: Array = []
	var clear_end: Array = []
	var beats := 0.0
	var zerod := 0.0
	var broke := 0.0
	var deny := 0.0
	var cards := 0.0
	var inc := 0.0
	for r in eco_runs:
		end_vals.append(float(r.get("end", 0)))
		if int(r.get("cleared", 0)) == 1:
			clear_end.append(float(r.get("end", 0)))
		beats += float(r.get("beats", 0))
		zerod += float(r.get("zerod_beats", 0))
		broke += float(r.get("broke_beats", 0))
		deny += float(r.get("deny_money", 0))
		cards += float(r.get("disc_cards", 0))
		inc += float(r.get("income_kind", 0))
	var bdiv := maxf(1.0, beats)
	var end_ms := eco_mean_se(end_vals)
	var disc_ms := eco_mean_se(_eco_vals("spend_discard"))
	var buy_ms := eco_mean_se(_eco_vals("spend_buy"))
	var rr_ms := eco_mean_se(_eco_vals("spend_reroll"))
	var inc_ms := eco_mean_se(_eco_vals("income_kind"))
	var deny_ms := eco_mean_se(_eco_vals("deny_money"))
	var kap_ms := eco_mean_se(_eco_vals("kappa_cut"))
	print("  经济(◆/局, mean±SE, n=%d):" % n)
	print("    局末余额 %.1f±%.1f · 中位数 %.1f(通关局中位数 %.1f, n=%d)"
		% [end_ms[0], end_ms[1], eco_median(end_vals), eco_median(clear_end), clear_end.size()])
	print("    弃牌支出 %.1f±%.1f(%.2f 张/拍)· 零弃牌拍 %.1f%%"
		% [disc_ms[0], disc_ms[1], cards / bdiv, 100.0 * zerod / bdiv])
	var rsh_ms := eco_mean_se(_eco_vals("spend_reshuffle"))
	print("    买卡净支出 %.1f±%.1f · 付费刷新 %.2f±%.2f · 洗牌 %.2f±%.2f"
		% [buy_ms[0], buy_ms[1], rr_ms[0], rr_ms[1], rsh_ms[0], rsh_ms[1]])
	print("    牌型金币收入 %.1f±%.1f(%.2f◆/拍, 只看牌型不含小丑加成)"
		% [inc_ms[0], inc_ms[1], inc / bdiv])
	print("    金币不足拒弃 %.2f±%.2f 次/局(%.2f%% 拍)· κ 门槛砍弃 %.2f±%.2f 张/局"
		% [deny_ms[0], deny_ms[1], 100.0 * deny / bdiv, kap_ms[0], kap_ms[1]])
	print("    软破产拍(决策时 0◆)%.2f%%" % [100.0 * broke / bdiv])
	last_eco = {"n": n, "end_mean": end_ms[0], "end_med": eco_median(end_vals),
		"end_med_clear": eco_median(clear_end), "clears": clear_end.size(),
		"disc_per_beat": cards / bdiv, "zerod_pct": 100.0 * zerod / bdiv,
		"broke_pct": 100.0 * broke / bdiv, "deny_pct": 100.0 * deny / bdiv,
		"income_run": inc_ms[0], "income_beat": inc / bdiv, "buy_run": buy_ms[0]}


func _eco_vals(key: String) -> Array:
	var out: Array = []
	for r in eco_runs:
		out.append(float(r.get(key, 0)))
	return out
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
