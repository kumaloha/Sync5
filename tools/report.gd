class_name Report
extends RefCounted

## The sim's ledgers and printed reports (docs/design/tech.md split): per-section
## death/score/coin accumulators, joker presence/trigger counts, the
## playbook harvester. Pure bookkeeping — no RNG, no decisions.

var _sections: int


func _init(runs: int, sections: int) -> void:
	_sections = sections


var died_at: Array = []          # section index of death, _sections = cleared
## ⚑ 段分的**全样本**(2026-08-30 加)——定关卡分只能看它, 不能看均值。
## ⚠⚠ 实测:段产出均值是关卡分的 **3~4 倍**, 而通关率只有 **38~48%** ——
## 说明**方差极大**, 而 `full clear` 要求四段全过、一段失手就完。
## ⇒ 拿均值定一个受方差支配的量, 必错(我差点据此把关卡分抬到 2 倍)。
var section_scores: Array = []          # [段][局] 的原始段分
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

# ── 卡面覆盖账本(2026-08-30 加;回答「多少卡没进过赢局」)──
# ⚠⚠ **跨 cohort 不清零**(`reset()` 不碰它)—— 问「整把尺子跑完有几张卡进过赢局」
# 是全局问题, 按 cohort 分母算会把「这条路线用不上它」误读成「没人用它」。
# ⚑ **四列拆开才有意义** —— 旧口径只有最后一列(`run_records` 的局末槽位),
# 而「没进赢局」至少有四种完全不同的原因, 混在一个数里谁也答不了该改什么:
#   offered   上过货架几次      —— 排除「根本没被抽到」(候选池/稀有度权重的问题)
#   bought    装进槽位几次      —— **bot 的估值看不看得见它**(仪器问题, 08-30 已翻案一次)
#   held_win  赢局里装过        —— 装了到底能不能赢(**这一列才是内容强弱**)
#   final_win 赢局末仍在槽位    —— 旧口径。中途被替换掉的卡在这一列消失,
#                                 但它可能已经把前三段打过去了 ⇒ 旧口径系统性低估
var cov_offered: Dictionary = {}
var cov_bought: Dictionary = {}
var cov_held_win: Dictionary = {}
var cov_final_win: Dictionary = {}
var cov_runs := 0
var cov_wins := 0
var _cov_run: Dictionary = {}          # 本局装过的 id(每局开头清)
## ⚑⚑ **自然口径**(不含 `cfg.prefer` 的强制试用队列)—— 由 sim.gd 每 cohort 设 `cov_forced`。
## ⚠⚠ 少了这一刀, 上面那套读数会**全绿而且是假的**:`dead:1..4` 是**实验者按住 bot 的手**
## 让它买那 44 张卡, 而这四条队列每次 sim 都跑 ⇒ 合计口径下「有没有人装过」恒为真。
## 首跑就撞上了(69/69 全绿), 而这个数正是要用来判「bot 自己会不会用它」的。
## ⇒ **强制试用是干净的因果通道, 但它不能同时当观察值。**
var nat_offered: Dictionary = {}
var nat_bought: Dictionary = {}
var nat_held_win: Dictionary = {}
var nat_final_win: Dictionary = {}
var nat_runs := 0
var nat_wins := 0
var cov_forced := false                # 本 cohort 是不是强制试用队列
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
## ⚑ 消耗牌三个**新形状**的证物(2026-08-30 补)。此前它们借用了形状不对的证物 ——
## 加急(免费刷新)借 `discount`(那是价格折扣)· 挑高(货架不出普通卡)借 `rule_offer`
## (那是含规则牌店率)· 砧座(复制一张毁其余)借 `multi_shops`(那是双购店)——
## **kit.gd 的注释里写着正确的意图, 代码映射的却是另一个键**, 而借来的键根本不会动
## ⇒ 三张卡在单卡门里报红, 却红在「这卡没效果」而不是「证物挂错了」。
## 三个都是**零基线**读数:没有那张卡时恒 0(或近 0)。
var free_rerolls := 0     # 加急:免费刷新真的被用掉几次
var rich_shelves := 0     # 挑高:首发货架 0 张普通卡的店数
var anvil_copies := 0     # 砧座:复制成功几次
var perkeo_copies := 0    # 帕奇欧:离店时白得一张消耗牌几次(零基线证物)

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
	_cov_run = {}


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
	section_scores = []
	for _i in range(_sections):
		section_scores.append([])
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
	free_rerolls = 0
	rich_shelves = 0
	anvil_copies = 0
	perkeo_copies = 0
	eco = {}
	eco_runs = []
	last_eco = {}


func cov_offer(id: String) -> void:
	cov_offered[id] = int(cov_offered.get(id, 0)) + 1
	if not cov_forced:
		nat_offered[id] = int(nat_offered.get(id, 0)) + 1


## 装进槽位/收进消耗品栏 —— **口径是「装上了」不是「上了货架」**。
func cov_install(id: String) -> void:
	cov_bought[id] = int(cov_bought.get(id, 0)) + 1
	_cov_run[id] = true
	if not cov_forced:
		nat_bought[id] = int(nat_bought.get(id, 0)) + 1


func record_run(slots: Array, died: int) -> void:
	var sup: Array = []
	for k in range(1, slots.size()):
		if slots[k] != null:
			sup.append(String(slots[k].id))
	sup.sort()
	run_records.append({"t": "" if slots[0] == null else String(slots[0].id),
		"sup": sup, "died": died})
	cov_runs += 1
	if not cov_forced:
		nat_runs += 1
	if died < _sections:
		return
	cov_wins += 1
	if not cov_forced:
		nat_wins += 1
	for id in _cov_run:
		cov_held_win[id] = int(cov_held_win.get(id, 0)) + 1
		if not cov_forced:
			nat_held_win[id] = int(nat_held_win.get(id, 0)) + 1
	for k in range(slots.size()):
		if slots[k] != null:
			var fid := String(slots[k].id)
			cov_final_win[fid] = int(cov_final_win.get(fid, 0)) + 1
			if not cov_forced:
				nat_final_win[fid] = int(nat_final_win.get(fid, 0)) + 1


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
	# ⚑ 段分的分位数 —— 关卡分该落在下沿附近(「打得差也够得着」的那条线)。
	var q_line := "  段分 p10/p25/中位: "
	for i in range(_sections):
		var v: Array = section_scores[i].duplicate()
		if v.is_empty():
			continue
		v.sort()
		q_line += "S%d:%d/%d/%d " % [i + 1,
			int(v[int(v.size() * 0.10)]), int(v[int(v.size() * 0.25)]),
			int(v[v.size() / 2])]
	print(q_line)
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
	print("    买卡净支出 %.1f±%.1f · 付费刷新 %.2f±%.2f"
		% [buy_ms[0], buy_ms[1], rr_ms[0], rr_ms[1]])
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
	# ⚠⚠ **这一行只印前 3 名, 不是全集** —— 必须把总数写出来。
	# 2026-08-30:「多少卡没进过赢局 65%/48%/45%」这一整串数字, 事后查明是**数这一行里
	# 出现过几个 id** 算出来的。14 条 cohort × 3 种阵容 ≈ 40 个槽位、还高度重复 ⇒
	# 它**结构上最多只能显示三十几张卡**, 无论内容多健康都会报出「一半的卡没进赢局」。
	# (同一批数据的真实覆盖率:自然口径 68/69。)
	# ⇒ **一个带截断的展示行, 被当成了普查。** 这就是「no silent caps」那条:
	# 界面砍掉的东西必须自己说出来, 否则下一个读它的人会把「没显示」读成「不存在」。
	var kit_line := "  winning kits(前 3 名, 共 %d 种阵容;⚠ 不是覆盖率, 覆盖率看文末): " % keys.size()
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


## ⚑⚑ 卡面覆盖率报表(2026-08-30)——「多少卡没进过赢局」这个数**必须拆开看**。
##
## 起因:08-30 这个数字从 65% 一路走到 48%, 而**一张卡的内容都没改** ——
## 推动它的全是仪器修复(`ev.measured` 地板 / bot 侧补齐 6 个 action 键 / 帕奇欧补臂)。
## 教训写在 LESSONS「65% 的卡没进过赢局是仪器问题」:
## **旧口径测的是「bot 会不会用」×「卡强不强」的乘积**, 而前者被证明有系统偏差。
##
## 所以这里按**四道闸门**逐张列, 每张卡卡在哪一道一目了然:
##   ① 上过货架吗   —— 没上 = 候选池/权重的问题(结构)
##   ② 被装上过吗   —— 上了没人装 = **估值看不见**(仪器)
##   ③ 赢局里装过吗 —— 装了从没赢 = **内容真的弱**(唯一该改内容的一格)
##   ④ 赢局末还在吗 —— 旧口径。②③ 都过、④ 不过 = **被换掉了**, 不是弱
func print_coverage(label: String, pool_ids: Array) -> void:
	if nat_runs == 0:
		return
	print("\n\n=== %s 覆盖率 ===" % label)
	print("  四道闸门:上架 → 装上 → 赢局里装过 → 赢局末仍在槽位")
	_cov_block("自然口径(不含 dead:N 强制试用)", pool_ids, nat_offered, nat_bought,
		nat_held_win, nat_final_win, nat_runs, nat_wins)
	_cov_block("含强制试用(dead:N 是实验者按住 bot 的手, 只能当因果通道不能当观察值)",
		pool_ids, cov_offered, cov_bought, cov_held_win, cov_final_win, cov_runs, cov_wins)


func _cov_block(title: String, pool_ids: Array, offered: Dictionary, bought: Dictionary,
		held: Dictionary, final: Dictionary, runs: int, wins: int) -> void:
	var never_offered: Array = []
	var never_bought: Array = []
	var never_won: Array = []
	var replaced: Array = []
	var ok: Array = []
	for id in pool_ids:
		var sid := String(id)
		if int(offered.get(sid, 0)) == 0:
			never_offered.append(sid)
		elif int(bought.get(sid, 0)) == 0:
			never_bought.append(sid)
		elif int(held.get(sid, 0)) == 0:
			never_won.append(sid)
		elif int(final.get(sid, 0)) == 0:
			replaced.append(sid)
		else:
			ok.append(sid)
	var n := pool_ids.size()
	print("\n  ── %s · %d 局 / %d 赢局 ──" % [title, runs, wins])
	print("   ① 从没上过货架   %2d/%d (%.0f%%)  %s"
		% [never_offered.size(), n, 100.0 * never_offered.size() / n, " ".join(PackedStringArray(never_offered))])
	print("   ② 上架但没人装   %2d/%d (%.0f%%)  %s"
		% [never_bought.size(), n, 100.0 * never_bought.size() / n, " ".join(PackedStringArray(never_bought))])
	print("   ③ 装过但从没赢   %2d/%d (%.0f%%)  %s"
		% [never_won.size(), n, 100.0 * never_won.size() / n, " ".join(PackedStringArray(never_won))])
	print("   ④ 赢过但被换掉   %2d/%d (%.0f%%)  %s"
		% [replaced.size(), n, 100.0 * replaced.size() / n, " ".join(PackedStringArray(replaced))])
	print("   ⑤ 赢局末在场     %2d/%d (%.0f%%)" % [ok.size(), n, 100.0 * ok.size() / n])
	print("   ⇒ 旧口径「进赢局」= ⑤ = %.0f%%;按「赢局里装过」算 = %.0f%%"
		% [100.0 * ok.size() / n, 100.0 * (ok.size() + replaced.size()) / n])
	var rate := {}
	for id in pool_ids:
		var sid2 := String(id)
		var off := int(offered.get(sid2, 0))
		if off >= 20:
			rate[sid2] = float(bought.get(sid2, 0)) / float(off)
	var rk := rate.keys()
	rk.sort_custom(func(x, y) -> bool: return float(rate[x]) < float(rate[y]))
	# ⚑ **全表, 不截断** —— 「有没有进过赢局」是个会饱和的二值(1 万局下几乎必然为真),
	# 真正的内容信号是**连续量**:同样上了货架, 这张卡被选中的比例。
	print("   装机率(装上/上架, 上架≥20 者全列, 升序;⚠ 这是「bot 选不选它」不是「它强不强」):")
	var line := "    "
	for i in range(rk.size()):
		line += "%s:%.0f%% " % [rk[i], 100.0 * float(rate[rk[i]])]
		if (i + 1) % 8 == 0:
			print(line)
			line = "    "
	if line.strip_edges() != "":
		print(line)
	var cold: Array = []
	for id in rk:
		if float(rate[id]) < 0.05:
			cold.append(String(id))
	print("   ⇒ 冷门(装机率 <5%%)%d/%d 张: %s"
		% [cold.size(), pool_ids.size(), " ".join(PackedStringArray(cold))])
