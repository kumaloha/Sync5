extends Probe

## 先验层 · 纯组合基准 —— 回答「**牌堆能给什么**」。
##   godot --headless --path . --script res://tools/prior.gd
##   SYNC5_PRIOR_N=2000000 godot --headless --path . --script res://tools/prior.gd
##
## ⚑ **为什么要它**(2026-08-14 用户提出先验/后验之分):
## `core/pattern.gd` 的 `BASE_MULT` 是按 `tools/attrib.gd` 的实测频率定的价,
## 而 attrib 自己的注释写着「频率是**策略下的分布**, 不是『牌堆能给什么』」——
## 也就是说倍率表的依据里**混着求解器的策略和缓存的选留**, 而不是这个游戏的组合可得性。
## 本探针补的正是缺的那一半, 于是同一个量有了**两把独立的尺子**。
##
## ⚠ **判定只有一份真相**:牌型判定全部走 `core/pattern.gd`,
## **本文件一行判定逻辑都不写** —— 重写一份就是第六次「规则在两处」。
## 它只做 pattern.gd 不做的两件事:① 按组合分布采样 ② **闭式自检**。
##
## ⚠ **口径(读数前先读这条)**:8 张 = 手牌 5 + 缓存 3, **iid 均匀抽取、不弃牌、不装任何卡**。
## 真实局里缓存那 3 张是玩家**选留**的, 所以本探针**不是**真实分布 ——
## 它是**零策略基线**, 与 attrib 的差值正好是「缓存 + 选留 + 弃牌值多少」。
## ⚠ 对牌型分布这个"基线"确实是下界(策略只会往上推);**对缓存类谓词不是**, 见下。
##
## ⚠ **规则牌全部配对**:同一手 8 张牌对所有规则集各算一遍(共用随机数),
## 所以 `Δp` 的噪声成对抵消 —— 这是项目铁律「比较任何两组东西必须共用随机数」。

const N_DEFAULT := 200000

## `tools/attrib.gd` 中性基准的实测值,抄自 `core/pattern.gd` 的 BASE_MULT 注释。
## ⚠ 只用于并排对照,**不是本探针的判据**:两者口径不同(那边带策略与缓存)。
## ⚠ pattern.gd 里两处基准的措辞不一致(一处写「不弃牌」、一处写「弃牌免费」),
## 已就地标注,别当成同一个基准读。
const ATTRIB_EQ := {
	"High Card": 6.1, "Pair": 27.2, "Two Pair": 33.5, "Three of a Kind": 5.5,
	"Straight": 11.0, "Flush": 10.7, "Full House": 5.1, "Four of a Kind": 0.7,
}

const ORDER: Array = [
	Pattern.Kind.HIGH_CARD, Pattern.Kind.PAIR, Pattern.Kind.TWO_PAIR,
	Pattern.Kind.THREE_KIND, Pattern.Kind.STRAIGHT, Pattern.Kind.FLUSH,
	Pattern.Kind.FULL_HOUSE, Pattern.Kind.FOUR_KIND,
	Pattern.Kind.STRAIGHT_FLUSH, Pattern.Kind.ROYAL_FLUSH,
]

## 规则集。⚠ 键名与 `Deck.rules` 一致 —— 那是唯一真相,别在这里另起名字。
const RULE_SETS: Array = [
	{"label": "(无规则)", "rules": {}},
	{"label": "shortcut 近道", "rules": {"shortcut": true}},
	{"label": "fourfingers 四指", "rules": {"fourfingers": true}},
	{"label": "twotone 双色调", "rules": {"twotone": true}},
	{"label": "近道+四指", "rules": {"shortcut": true, "fourfingers": true}},
]


## 前多少手做快/慢路径逐次对账。⚠ 别设成 0 —— 见 `_best_kind` 的注释。
const VERIFY_N := 2000

## ⚑ **谓词档位 —— 这张分类表本身就是产出**:它回答「**哪些卡先验能定价,
## 哪些必须等后验**」。现在账本把两类卡混在一起用同一套仪器,所以
## 行为卡的实测是必需的、组合卡的实测是**浪费**(那个数本来就算得出来)。
##
## ⚠ 求值**一律走 `Fx._when_ok`** —— 本文件不写任何谓词逻辑。
## 分类只说"这个键要的 ctx 字段组合层给不给得出",不重新实现它。
const PRED_EXACT: Array = ["kind", "kind_in", "all_suits", "no_pair", "top_rank_gte"]

## ⚠⚠ **缓存档的方向是谓词相关的,不是统一的下界** —— 我第一版写成了"下界",被数据推翻:
## 排练(缓存三连号)先验 10.48% 而实测 6%,**实测低于我声称的下界**。
## 根因:缓存里装的不是"选留的好牌",是**打不出去的剩牌** —— 好牌已经打出去了。
## 所以对"缓存要成型"类谓词,真实缓存可能**比随机更差**。别给这一档标方向,标"待不动点"。
const PRED_CACHE: Array = ["cache_mono_suit", "cache_run", "cache_trio", "cache_all_faces"]


func watchdog_sec() -> float:
	return 60.0


## **8 选 5 的 argmax,只回 kind。**
##
## 为什么不直接 `Pattern.evaluate_best(8 张)`:那条路每个组合都建一个 9 键字典 +
## `resolved.duplicate()`,56 组合 × 5 规则集 = 一手 280 次字典分配 —— 实测 2 万手要 50s,
## 大样本跑不动。这里改成 `score_five`(零分配)找 argmax,**只对赢的那 5 张**建一次字典。
##
## ⚠ **本函数不含任何牌型判定** —— 分数与 kind 全部来自 `core/pattern.gd`。
## 它复制的只有一样东西:**8 选 5 的枚举顺序**(字典序),因为并列时保留哪一个由它决定。
## 这份复制由 `VERIFY_N` 的逐次对账守着。
static var _combos: Array = []
var _buf: Array = [null, null, null, null, null]
var _last_combo: PackedInt32Array = PackedInt32Array()


static func _ensure_combos() -> void:
	if not _combos.is_empty():
		return
	# 五重循环 = 字典序 = `Pattern._combo_helper` 的顺序
	for i0 in range(8):
		for i1 in range(i0 + 1, 8):
			for i2 in range(i1 + 1, 8):
				for i3 in range(i2 + 1, 8):
					for i4 in range(i3 + 1, 8):
						_combos.append(PackedInt32Array([i0, i1, i2, i3, i4]))


func _best_kind(cards: Array, rules: Dictionary) -> int:
	var best := -1
	var best_c: PackedInt32Array = _combos[0]
	for c in _combos:
		for j in range(5):
			_buf[j] = cards[c[j]]
		var s := Pattern.score_five(_buf, rules)
		if s > best:       # 严格 > ⇒ 并列保留字典序靠前的,与 evaluate_best 一致
			best = s
			best_c = c
	for j in range(5):
		_buf[j] = cards[best_c[j]]
	_last_combo = best_c
	return int(Pattern.evaluate_best(_buf, rules)["kind"])


func _initialize() -> void:
	if env_str("SYNC5_PRIOR_MODE") == "discard":
		_run_discard()
		return
	if env_str("SYNC5_PRIOR_MODE") == "shelf":
		_run_shelf()
		return
	var n := env_int("SYNC5_PRIOR_N", N_DEFAULT)
	var t0 := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = env_int("SYNC5_PRIOR_SEED", 20260814)
	_ensure_combos()

	var deck: Array = []
	for s in range(4):
		for r in range(2, 15):
			deck.append(Card.new(r, s))
	var order := PackedInt32Array()
	order.resize(52)
	for i in range(52):
		order[i] = i

	# tallies[rule_idx][kind] = 次数
	var tallies: Array = []
	for _r in RULE_SETS:
		var t := PackedInt32Array()
		t.resize(ORDER.size())
		tallies.append(t)

	# 闭式自检用的两个**原始事件**(纯计数,不碰牌型判定)
	var flush_exist := 0
	var quad_exist := 0

	var cls := _classify_jokers()
	var jk_ok: Array = cls["ok"]
	var pred_hits := PackedInt32Array()
	pred_hits.resize(jk_ok.size())

	var eight: Array = [null, null, null, null, null, null, null, null]
	var suit_cnt := PackedInt32Array()
	suit_cnt.resize(4)
	var rank_cnt := PackedInt32Array()
	rank_cnt.resize(15)

	print("\n=== 先验层 · 纯组合基准(8 张 iid · 零策略 · 不弃牌) · N=%d ===" % n)

	for _i in range(n):
		# 部分 Fisher-Yates:只搅前 8 位,order 保持是一个排列 ⇒ 下一轮继续均匀
		for k in range(8):
			var j: int = k + (rng.randi() % (52 - k))
			var tmp: int = order[k]
			order[k] = order[j]
			order[j] = tmp
			eight[k] = deck[order[k]]

		for si in range(4):
			suit_cnt[si] = 0
		for ri in range(15):
			rank_cnt[ri] = 0
		for c in eight:
			suit_cnt[c.suit] += 1
			rank_cnt[c.rank] += 1
		for si in range(4):
			if suit_cnt[si] >= 5:
				flush_exist += 1
				break
		for ri in range(2, 15):
			if rank_cnt[ri] >= 4:
				quad_exist += 1
				break

		for r in range(RULE_SETS.size()):
			var rules: Dictionary = RULE_SETS[r]["rules"]
			var kind := _best_kind(eight, rules)
			# ⚠ 快路径与 `Pattern.evaluate_best` 的**逐次对账**(前 VERIFY_N 手)——
			# 快路径自己枚举 8 选 5, 一旦 pattern.gd 改了枚举顺序, 并列时会选到另一张牌
			# 而**分布只是悄悄偏一点**, 不报错。所以对账必须常驻, 不能靠人记得开。
			if _i < VERIFY_N:
				var slow: int = int(Pattern.evaluate_best(eight, rules)["kind"])
				if slow != kind:
					push_error("[prior] 快路径与 evaluate_best 不一致 (rules=%s): %d vs %d"
						% [str(rules), kind, slow])
					printerr("[prior] ABORT —— 快路径失效, 本次读数作废")
					quit(1)
					return
			tallies[r][kind] += 1
			# 谓词只在无规则档求值(r=0)。此刻 `_buf` / `_last_combo` 正好是它的结果。
			if r == 0:
				_eval_preds(eight, kind, jk_ok, pred_hits)

	_report_closed_form(n, flush_exist, quad_exist)
	_report_dist(n, tallies)
	_report_delta(n, tallies)
	_report_preds(n, jk_ok, pred_hits, cls["blocked"], cls["nofx"])

	print("\n[prior] %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)


## 闭式自检 —— 采样器对不对,由**精确算术**说了算,不由另一个采样说了算。
func _report_closed_form(n: int, flush_exist: int, quad_exist: int) -> void:
	var total := _c(52, 8)
	# 存在 5 张同花:某花色 ≥5 张。两个花色同时 ≥5 不可能(10 > 8),无需容斥。
	var f := 0.0
	for k in range(5, 9):
		f += 4.0 * _c(13, k) * _c(39, 8 - k)
	# 存在四条:某点数 4 张;两个点数各 4 张被数了两次,减回来。
	var q := 13.0 * _c(48, 4) - _c(13, 2)
	var ef := f / total
	var eq := q / total
	var sf := float(flush_exist) / n
	var sq := float(quad_exist) / n
	print("\n## 闭式自检(精确算术 vs 采样器)")
	print("| 事件 | 闭式(精确) | 采样 | 差 |")
	print("|---|---:|---:|---:|")
	print("| 8 张中存在 5 张同花 | %.4f%% | %.4f%% | %+.4fpp |" % [ef * 100, sf * 100, (sf - ef) * 100])
	print("| 8 张中存在四条 | %.4f%% | %.4f%% | %+.4fpp |" % [eq * 100, sq * 100, (sq - eq) * 100])
	var se_f := sqrt(ef * (1.0 - ef) / n) * 100.0
	var se_q := sqrt(eq * (1.0 - eq) / n) * 100.0
	print("(标准误 同花 ±%.4fpp · 四条 ±%.4fpp —— 差落在 2se 内才算采样器可信)" % [se_f, se_q])


func _report_dist(n: int, tallies: Array) -> void:
	print("\n## 牌型分布 · 无规则(P(=k) 与 P(≥k))")
	print("| 牌型 | 本探针 P(=k) | 本探针 P(≥k) | attrib 策略基准 P(=k) | 差(策略 − 组合) |")
	print("|---|---:|---:|---:|---:|")
	var t: PackedInt32Array = tallies[0]
	# P(≥k) 从高到低累计,先算好再顺序打印
	var ge := PackedInt32Array()
	ge.resize(ORDER.size())
	var cum := 0
	for i in range(ORDER.size() - 1, -1, -1):
		cum += t[i]
		ge[i] = cum
	for i in range(ORDER.size()):
		var kname: String = Pattern.NAMES[ORDER[i]]
		var p := 100.0 * t[i] / n
		var pg := 100.0 * ge[i] / n
		var has_a: bool = ATTRIB_EQ.has(kname)
		var a: float = float(ATTRIB_EQ.get(kname, 0.0))
		var acol := "%.1f%%" % a if has_a else "—"
		var dcol := "%+.1fpp" % (a - p) if has_a else "—"
		print("| %s | %.2f%% | %.2f%% | %s | %s |" % [kname, p, pg, acol, dcol])


## 规则牌 Δp —— **配对**(同一手牌算了每个规则集),所以这里的差没有跨样本噪声。
func _report_delta(n: int, tallies: Array) -> void:
	print("\n## 规则牌 Δp(配对 · 同一批 8 张牌)")
	print("| 规则集 | Δ顺子族 | Δ同花族 | Δ大牌型族(≥葫芦) | Δ高牌(负=救起来的拍) |")
	print("|---|---:|---:|---:|---:|")
	var base: PackedInt32Array = tallies[0]
	for r in range(RULE_SETS.size()):
		var t: PackedInt32Array = tallies[r]
		var d_str := _fam(t, [Pattern.Kind.STRAIGHT]) - _fam(base, [Pattern.Kind.STRAIGHT])
		var d_fl := (_fam(t, [Pattern.Kind.FLUSH, Pattern.Kind.STRAIGHT_FLUSH, Pattern.Kind.ROYAL_FLUSH])
			- _fam(base, [Pattern.Kind.FLUSH, Pattern.Kind.STRAIGHT_FLUSH, Pattern.Kind.ROYAL_FLUSH]))
		var big: Array = [Pattern.Kind.FULL_HOUSE, Pattern.Kind.FOUR_KIND,
			Pattern.Kind.STRAIGHT_FLUSH, Pattern.Kind.ROYAL_FLUSH]
		var d_big := _fam(t, big) - _fam(base, big)
		var d_hc := _fam(t, [Pattern.Kind.HIGH_CARD]) - _fam(base, [Pattern.Kind.HIGH_CARD])
		print("| %s | %+.2fpp | %+.2fpp | %+.2fpp | %+.2fpp |" % [
			RULE_SETS[r]["label"], 100.0 * d_str / n, 100.0 * d_fl / n,
			100.0 * d_big / n, 100.0 * d_hc / n])


func _fam(t: PackedInt32Array, kinds: Array) -> float:
	var s := 0.0
	for k in kinds:
		s += t[ORDER.find(k)]
	return s


## 把 roster 按「先验算不算得出」分三堆。**分类只看 `when` 用了哪些键**,
## 不重新实现任何谓词 —— 求值一律交给 `Fx._when_ok`。
func _classify_jokers() -> Dictionary:
	var ok: Array = []
	var blocked: Array = []
	var nofx: Array = []
	for j in DB.jokers():
		var jd: Dictionary = j
		var row := {
			"id": String(jd.get("id", "?")),
			"cn": String(jd.get("cn_name", jd.get("name", "?"))),
			"effects": jd.get("effects", []),
		}
		var effects: Array = row["effects"]
		if effects.is_empty():
			nofx.append(row)
			continue
		var keys := {}
		var missing: Array = []
		var uses_cache := false
		for e in effects:
			var ed: Dictionary = e
			for k in ed.get("when", {}):
				keys[String(k)] = true
			# ⚠ **`do` 也要分类** —— `fired` 的真相是「产生了 popup」(report.gd),
			# 而 `per` 计数为 0 时不产 popup。只看 `when` 会把秒表/镜面误判成"无条件 100%"。
			var dd: Dictionary = ed.get("do", {})
			var per := String(dd.get("per", ""))
			if per == "cache_face":
				uses_cache = true
			elif per != "":
				missing.append("per:" + per)
			if dd.has("mult_from_target_factor"):
				missing.append("target_factor(装没装 Target)")
		for k in keys:
			if PRED_EXACT.has(k):
				continue
			if PRED_CACHE.has(k):
				uses_cache = true
				continue
			missing.append(String(k))
		if missing.is_empty():
			row["cache"] = uses_cache
			row["uncond"] = keys.is_empty()
			ok.append(row)
		else:
			missing.sort()
			row["missing"] = missing
			blocked.append(row)
	return {"ok": ok, "blocked": blocked, "nofx": nofx}


## 求值一手牌上的全部可算谓词。⚠ `fired` 的口径 = **任一 effect 的 when 通过**,
## 与 `probbook.py` 的 support trigger 一致。
func _eval_preds(eight: Array, kind: int, jk_ok: Array, hits: PackedInt32Array) -> void:
	if jk_ok.is_empty():
		return
	var used := [false, false, false, false, false, false, false, false]
	for j in _last_combo:
		used[j] = true
	var rest: Array = []
	for i in range(8):
		if not used[i]:
			rest.append(eight[i])
	# ⚠ **口径与 `report.gd::track_triggers` 同源**:fired = **产生了 popup**。
	# 所以这里走 `Fx.apply_effects` 整条链, 不是自己判 `when` —— 「when 通过但数额为 0」
	# (包厢缓存没人头牌)在游戏里**不算触发**, 自己判会把它算成 100%。
	# 下面几个是 `_do` 的累加器/上下文, 给中性初值;跨卡累积无害(它们只被写不被读)。
	var ctx := {
		"kind": kind,
		"scoring_cards": _buf,
		"cache_cards": rest,
		"mult": 1.0, "additive": 0.0, "bonus": 0.0, "bonus_pct": 0.0,
		"coins_bonus": 0.0, "coins_factor": 1.0, "target_factor": 1.0,
		"discards": 0, "coins": 0,
	}
	for i in range(jk_ok.size()):
		if Fx.apply_effects(jk_ok[i]["effects"], {}, ctx) != "":
			hits[i] += 1


func _report_preds(n: int, jk_ok: Array, hits: PackedInt32Array, blocked: Array, nofx: Array) -> void:
	print("\n## 谓词先验 p̂(组合层算出来的,不是拍的)")
	print("| id | 名 | p̂ | 档 |")
	print("|---|---|---:|---|")
	for i in range(jk_ok.size()):
		var tier := "缓存 ⇒ **方向待定**" if bool(jk_ok[i].get("cache", false)) else "精确"
		if bool(jk_ok[i].get("uncond", false)):
			# ⚠ **卡面无 `when` ≠ 触发率 100%** —— `card_filter` / `per` 那一类的条件
			# 长在**数额**上(没有红牌 ⇒ 加 0 ⇒ 不产 popup ⇒ 不算 fired)。
			# 这一格是实测分出来的, 不是分类分出来的。
			tier = "无条件 ✓" if hits[i] == n else "**数额条件**(卡面无 when)"
		print("| %s | %s | %.2f%% | %s |" % [
			jk_ok[i]["id"], jk_ok[i]["cn"], 100.0 * hits[i] / n, tier])

	print("\n## ⚠ 先验**算不出来**的(缺的字段就是它必须等后验的理由)")
	print("| id | 名 | 缺什么 |")
	print("|---|---|---|")
	for b in blocked:
		print("| %s | %s | `%s` |" % [b["id"], b["cn"], ", ".join(b["missing"])])
	if not nofx.is_empty():
		var names: Array = []
		for x in nofx:
			names.append("%s(%s)" % [x["cn"], x["id"]])
		print("\n**无 effects(规则牌 / acquire 族,不入 fired)**:%s" % ", ".join(names))
	print("\n⚑ 上面两张表的**比例**就是本篇的论点:能算的那些,再去测就是拿带噪声的尺子量确定的数。")


## ============================================================================
## 模式二:**弃牌一步转移** —— 「用时间买频率」的兑换率
##   SYNC5_PRIOR_MODE=discard godot --headless --path . --script res://tools/prior.gd
##
## ⚑ **为什么它是先验而不是策略**:这里算的是「**如果你能弃 b 张且弃得最优**,分布是什么」。
## `b` 是关卡配置(时间闸门),不是玩家参数 —— 所以这条曲线不含任何 `θ`,是**上界**。
## 游戏的核心张力(CLAUDE.md:唯一的闸门是 8 秒钟)第一次有了数量表达。
##
## ⚠⚠ **本模式刻意不调 `Solver.best_discard`**,而那**不是**"又抄一份":
## 求解器的枚举是 `_subsets(base.keep.size())` —— 它只从**留缓存的 3 张**里选弃牌,
## 结构上**弃不了 4 张**(而真人实测最多弃 4,`beat_budget.discards` 已按此校准)。
## 先验要的是上界, 所以这里枚举**全部 8 张的子集**。
## ⇒ 副产品:两者之差**就是求解器那条结构盲区值多少分**(TODO 记着的仪器债)。
## ⚠ 计分仍然一行都不重写 —— 全部走 `Pattern`。
const DISC_HANDS := 400
const DISC_REFILL := 12      # 补牌采样组数(共用随机数:所有子集取同一批的前 k 张)
const DISC_MAX := 4          # 弃牌预算上限 = 真人实测上界

## 候选剪枝的档位:只把「边际价值最低的 M 张」当弃牌候选。
## ⚠ 这是给 `Solver.best_discard` 提速用的**近似**, 在这里先量它漏多少 ——
## 全枚举 C(8,1..4)=162 个子集, 剪到 M=5 只剩 30 个(**5.4 倍**), M=6 剩 56 个(2.9 倍)。
const PRUNE_M: Array = [4, 5, 6]


func _run_discard() -> void:
	var hands := env_int("SYNC5_PRIOR_HANDS", DISC_HANDS)
	var refill := env_int("SYNC5_PRIOR_REFILL", DISC_REFILL)
	var t0 := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = env_int("SYNC5_PRIOR_SEED", 20260814)
	_ensure_combos()

	var deck: Array = []
	for s in range(4):
		for r in range(2, 15):
			deck.append(Card.new(r, s))
	var order := PackedInt32Array()
	order.resize(52)
	for i in range(52):
		order[i] = i

	# subsets[k] = 大小为 k 的下标子集(k = 0..DISC_MAX)
	var subsets: Array = []
	for k in range(DISC_MAX + 1):
		subsets.append(_subsets_of_size(8, k))

	# 每个预算 b 一份:牌型计数 + 期望分累计 + 实际弃了几张
	var tal: Array = []
	var ssum := PackedFloat64Array()
	var dsum := PackedFloat64Array()
	ssum.resize(DISC_MAX + 1)
	dsum.resize(DISC_MAX + 1)
	for _b in range(DISC_MAX + 1):
		var t := PackedInt32Array()
		t.resize(ORDER.size())
		tal.append(t)
	# 求解器盲区对照。⚠ **逐手存起来做配对** —— 项目铁律:没有标准误的差值等于没有结论。
	var cap3_free: Array = []
	var cap3_keep: Array = []
	# 候选剪枝对照:全枚举 vs 只考虑「边际价值最低的 M 张」
	var full_ev: Array = []
	var prune_ev: Array = []
	for _i in range(PRUNE_M.size()):
		prune_ev.append([])

	print("\n=== 先验层 · 弃牌一步转移(最优弃牌上界) · %d 手 × %d 组补牌 ===" % [hands, refill])

	var eight: Array = [null, null, null, null, null, null, null, null]
	var trial: Array = []
	trial.resize(8)

	for _h in range(hands):
		for k in range(8):
			var j: int = k + (rng.randi() % (52 - k))
			var tmp: int = order[k]
			order[k] = order[j]
			order[j] = tmp
			eight[k] = deck[order[k]]
		# 共用随机数:一次抽好 refill 组各 DISC_MAX 张, 所有子集取前 |S| 张
		var pool: Array = []
		for _r in range(refill):
			var f: Array = []
			for k in range(DISC_MAX):
				var j2: int = 8 + k + (rng.randi() % (52 - 8 - k))
				var tmp2: int = order[8 + k]
				order[8 + k] = order[j2]
				order[j2] = tmp2
				f.append(deck[order[8 + k]])
			pool.append(f)

		# 逐个子集算期望最优分
		var best_ev := PackedFloat64Array()
		best_ev.resize(DISC_MAX + 1)
		var best_sub: Array = []
		best_sub.resize(DISC_MAX + 1)
		for b in range(DISC_MAX + 1):
			best_ev[b] = -1.0
			best_sub[b] = []
		# 盲区对照的枚举空间:最优切法**留在缓存**的那 3 张(= `Solver` 的 `base.keep`)
		var played := _best_combo(eight)
		var keep_idx := {}
		for i in range(8):
			keep_idx[i] = true
		for i in played:
			keep_idx.erase(int(i))
		var keep3_best := -1.0
		for k in range(DISC_MAX + 1):
			for sub in subsets[k]:
				var ev := _ev_of(eight, sub, k, pool, trial)
				for b in range(k, DISC_MAX + 1):
					if ev > best_ev[b]:
						best_ev[b] = ev
						best_sub[b] = sub
				# 盲区对照:同为 ≤3 张, 但只许从 `keep` 那 3 张里选
				if k <= 3 and _within_keep(sub, keep_idx) and ev > keep3_best:
					keep3_best = ev
		cap3_free.append(best_ev[3])
		cap3_keep.append(keep3_best)

		# ⚑ **剪枝对照**:只把「边际价值最低的 M 张」当弃牌候选, 再枚举其子集。
		# 这是给 `Solver.best_discard` 提速用的候选剪枝, **先在这里量它漏多少**,
		# 有数据再决定动不动求解器 —— 不给刚修好的东西盲加近似。
		# 边际价值 = 去掉这张后剩 7 张的最优分(越高 ⇒ 这张越不重要 ⇒ 越该弃)。
		var marg: Array = []
		for i in range(8):
			var seven: Array = []
			for k2 in range(8):
				if k2 != i:
					seven.append(eight[k2])
			marg.append([float(Pattern.best_score_of(seven)), i])
		marg.sort_custom(func(a, b): return a[0] > b[0])
		for mi in range(PRUNE_M.size()):
			var m: int = PRUNE_M[mi]
			var candi: Array = []
			for x in range(mini(m, 8)):
				candi.append(int(marg[x][1]))
			var pb := -1.0
			for k3 in range(1, DISC_MAX + 1):
				for pick in _subsets_of_size(candi.size(), k3):
					var sub2: Array = []
					for pi in pick:
						sub2.append(candi[int(pi)])
					var ev2 := _ev_of(eight, sub2, k3, pool, trial)
					if ev2 > pb:
						pb = ev2
			prune_ev[mi].append(pb)
		full_ev.append(best_ev[DISC_MAX])

		# 用最优子集重跑一遍, 统计牌型分布(便宜:refill × 56)
		for b in range(DISC_MAX + 1):
			ssum[b] += best_ev[b]
			dsum[b] += (best_sub[b] as Array).size()
			_tally_of(eight, best_sub[b], pool, trial, tal[b])

	_report_discard(hands, refill, tal, ssum, dsum, cap3_free, cap3_keep)
	_report_prune(full_ev, prune_ev)
	print("\n[prior:discard] %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)


## 弃掉 `sub`(|sub| = k)后的期望最优分。补牌取每组的前 k 张 —— 共用随机数。
func _ev_of(eight: Array, sub: Array, k: int, pool: Array, trial: Array) -> float:
	if k == 0:
		return float(Pattern.best_score_of(eight))
	var acc := 0.0
	for f in pool:
		var w := 0
		for i in range(8):
			if not sub.has(i):
				trial[w] = eight[i]
				w += 1
		for j in range(k):
			trial[w] = (f as Array)[j]
			w += 1
		acc += float(Pattern.best_score_of(trial))
	return acc / pool.size()


func _tally_of(eight: Array, sub: Array, pool: Array, trial: Array, t: PackedInt32Array) -> void:
	var k: int = (sub as Array).size()
	if k == 0:
		t[_best_kind(eight, {})] += 1
		return
	for f in pool:
		var w := 0
		for i in range(8):
			if not sub.has(i):
				trial[w] = eight[i]
				w += 1
		for j in range(k):
			trial[w] = (f as Array)[j]
			w += 1
		t[_best_kind(trial, {})] += 1


## 候选剪枝的代价 —— **提速多少 vs 丢多少最优性**。
## ⚠ 这张表的用途是「**有数据再决定动不动求解器**」, 不是既成事实的记录。
func _report_prune(full_ev: Array, prune_ev: Array) -> void:
	if full_ev.is_empty():
		return
	var full := Stat.mean(full_ev)
	print("\n## 候选剪枝:只考虑「边际价值最低的 M 张」丢多少最优性")
	print("| M | 子集数 | 相对全枚举 | 期望分 | **损失** | z |")
	print("|---:|---:|---:|---:|---:|---:|")
	print("| 8(全枚举) | 162 | 1.0× | %.1f | — | — |" % full)
	for i in range(PRUNE_M.size()):
		var m: int = PRUNE_M[i]
		var nsub := 0
		for k in range(1, DISC_MAX + 1):
			nsub += _subsets_of_size(mini(m, 8), k).size()
		var pm := Stat.mean(prune_ev[i])
		var pr := Stat.paired(prune_ev[i], full_ev)     # d = full − prune ≥ 0
		var z: float = float(pr["d"]) / maxf(1e-9, float(pr["se"]))
		print("| %d | %d | %.1f× | %.1f | **−%.2f%%** | %.1f |" % [
			m, nsub, 162.0 / maxf(1.0, float(nsub)), pm,
			100.0 * (full - pm) / full, z])
	print("\n⚠ 判据:损失若在 **0.5%% 以内**就买得起(它远小于本次扩枚举拿回的 9.3%);")
	print("   否则宁可慢 —— CLAUDE.md「不许为性能去砍这个数, 那是拿平衡换速度」。")


## 求解器只能弃「最优切法留在缓存的那 3 张」(`Solver.best_discard` 的 `base.keep`)。
## ⚠ **不是固定的后三张** —— 第一版我写成了下标 ≥5, 那是另一个更差的枚举空间,
## 会把盲区的代价**算大**。keep 必须由 `best_split` 的 argmax 定出来。
func _within_keep(sub: Array, keep: Dictionary) -> bool:
	for i in sub:
		if not keep.has(int(i)):
			return false
	return true


## 最优切法打出的 5 张下标(与 `Pattern.evaluate_best` 同序同 tie-break),
## 其补集就是 `Solver` 的 `base.keep`。
func _best_combo(cards: Array) -> PackedInt32Array:
	var best := -1
	var best_c: PackedInt32Array = _combos[0]
	for c in _combos:
		for j in range(5):
			_buf[j] = cards[c[j]]
		var s := Pattern.score_five(_buf, {})
		if s > best:
			best = s
			best_c = c
	return best_c


static func _subsets_of_size(n: int, k: int) -> Array:
	var res: Array = []
	var cur: Array = []
	_ss_rec(0, n, k, cur, res)
	return res


static func _ss_rec(start: int, n: int, k: int, cur: Array, res: Array) -> void:
	if cur.size() == k:
		res.append(cur.duplicate())
		return
	for i in range(start, n):
		cur.append(i)
		_ss_rec(i + 1, n, k, cur, res)
		cur.pop_back()


func _report_discard(hands: int, refill: int, tal: Array, ssum: PackedFloat64Array,
		dsum: PackedFloat64Array, cap3_free: Array, cap3_keep: Array) -> void:
	print("\n## 「用时间买频率」的兑换率:弃牌预算 b → 分布与期望分")
	print("| b | 期望分 | vs b=0 | 实际弃牌张数 | 顺子族 | 同花族 | ≥葫芦 | 高牌 |")
	print("|---:|---:|---:|---:|---:|---:|---:|---:|")
	var base := ssum[0] / hands
	for b in range(tal.size()):
		var t: PackedInt32Array = tal[b]
		var tot := 0
		for i in range(t.size()):
			tot += t[i]
		var s := ssum[b] / hands
		print("| %d | %.1f | %+.1f%% | %.2f | %.2f%% | %.2f%% | %.2f%% | %.2f%% |" % [
			b, s, 100.0 * (s - base) / base, dsum[b] / hands,
			100.0 * _fam(t, [Pattern.Kind.STRAIGHT]) / tot,
			100.0 * _fam(t, [Pattern.Kind.FLUSH, Pattern.Kind.STRAIGHT_FLUSH,
				Pattern.Kind.ROYAL_FLUSH]) / tot,
			100.0 * _fam(t, [Pattern.Kind.FULL_HOUSE, Pattern.Kind.FOUR_KIND,
				Pattern.Kind.STRAIGHT_FLUSH, Pattern.Kind.ROYAL_FLUSH]) / tot,
			100.0 * _fam(t, [Pattern.Kind.HIGH_CARD]) / tot])

	var free3 := Stat.mean(cap3_free)
	var keep3 := Stat.mean(cap3_keep)
	var pr := Stat.paired(cap3_keep, cap3_free)     # d = free − keep
	var z: float = float(pr["d"]) / maxf(1e-9, float(pr["se"]))
	var mag := 100.0 * float(pr["d"]) / keep3
	print("\n## ⚑ 求解器的结构盲区值多少(同为 ≤3 张,差别只在**能从哪几张里选**)")
	print("| 枚举空间 | 期望分 |")
	print("|---|---:|")
	print("| 全部 8 张任选 ≤3(先验上界) | %.1f |" % free3)
	print("| 只能从缓存那 3 张里选(= `Solver.best_discard` 的 `_subsets(base.keep)`) | %.1f |" % keep3)
	print("| **差(配对)** | **%+.1f ±%.1f · z=%.1f · 量级 %+.1f%%** |" % [pr["d"], pr["se"], z, mag])
	var verdict := "两条判据都过 ⇒ 这是要管的差异" if (absf(z) >= 3.0 and absf(mag) >= 5.0) \
		else ("显著但量级 <5% ⇒ 按纪律可豁免, 但要显式声明" if absf(z) >= 3.0 \
		else "不显著 ⇒ 加样本, 别据此下结论")
	print("\n**按项目自己的两条判据(|z| ≥ 3 **且** 量级 ≥ 5%%):%s**" % verdict)
	print("\n⚠ 口径:`refill=%d` 组补牌的样本期望, 组内共用随机数 ⇒ 子集之间的比较是**配对**的。" % refill)


## ============================================================================
## 模式三:**货架曝光** —— 一局里你能见到这张卡几次
##   SYNC5_PRIOR_MODE=shelf godot --headless --path . --script res://tools/prior.gd
##
## ⚑ **为什么这是先验**:曝光率只依赖池子组成、稀有度权重、商店次数与货架宽度 ——
## **全是配置,没有一个玩家参数**。所以它精确算得出来,不该由 sim 去数。
##
## ⚠⚠ **本模式不重写抽卡算法, 它是对那个算法的解析求解。**
## `view/shop.gd::_weighted_pick` = 按每卡权重**不放回**抽 `count` 张。
## 边际概率 `P(x 出现在 count 张里)` 有闭式(见 `_p_in_shelf`), 不必模拟。
## ⚠ 而那个算法**本身已经有两份**(`view/shop.gd` 与 `tools/bot.gd:522`),
## shop 的注释还写着「不许各写一份」—— **注释承诺了一个不存在的机制**, 记 TODO。
##
## ⚠ **口径**:`target_mult = 1.0`(不含独狼的 target 加成);不含付费刷新
## (刷新会增加曝光, 所以本表是**下界**);首张 Target 免费三选一是特例, 不在本表内。
func _run_shelf() -> void:
	var jokers: Array = DB.jokers()
	var eco: Dictionary = DB.economy()
	var wmap: Dictionary = eco["draft_rarity_weights"]
	var shops := env_int("SYNC5_PRIOR_SHOPS", 7)          # design/levels.md:一局 7 次商店
	var width := env_int("SYNC5_PRIOR_SHELF", 3)          # 货架 3 位

	var w: Array = []
	var total := 0.0
	for j in jokers:
		var jw := float(int(wmap.get(String((j as Dictionary).get("rarity", "")), 1)))
		w.append(jw)
		total += jw

	print("\n=== 先验层 · 货架曝光(解析,零采样) · %d 次商店 × %d 位 ===" % [shops, width])

	# 档级
	var by_r := {}
	for i in range(jokers.size()):
		var r := String((jokers[i] as Dictionary).get("rarity", ""))
		var e: Array = by_r.get(r, [0, 0.0])
		e[0] = int(e[0]) + 1
		e[1] = float(e[1]) + w[i]
		by_r[r] = e
	print("\n## 档级:名义权重 vs **实际占比**")
	print("| 档 | 张数 | 名义权重 | 实际档占比 | 一局期望出现张数 |")
	print("|---|---:|---:|---:|---:|")
	var rs: Array = by_r.keys()
	rs.sort()
	for r in rs:
		var e: Array = by_r[r]
		var share := float(e[1]) / total
		print("| %s | %d | %d | **%.1f%%** | %.2f |" % [
			r if r != "" else "(空)", int(e[0]),
			int(wmap.get(String(r), 1)), share * 100.0, share * shops * width])
	print("\n⚠ **名义权重 ≠ 实际档占比** —— 权重挂在**每张卡**上, 所以张数多的档整体更容易出。")

	# 卡级:每档挑代表 + 本轮改动过的三张
	print("\n## 卡级:一局至少见到一次的概率")
	print("| id | 名 | 稀有 | 单位概率 | **一局(%d 位)见到** | 12 局见到 |" % (shops * width))
	print("|---|---|---|---:|---:|---:|")
	var focus := ["twotone", "shortcut", "fourfingers", "jukebox", "mirror", "neonsign", "chord"]
	for i in range(jokers.size()):
		var jd: Dictionary = jokers[i]
		var jid := String(jd.get("id", ""))
		if not focus.has(jid):
			continue
		var per := _p_in_shelf(w, i, total, width)
		var once := 1.0 - pow(1.0 - per, shops)
		print("| %s | %s | %s | %.3f%% | **%.1f%%** | %.1f%% |" % [
			jid, String(jd.get("cn", jd.get("name", "?"))), String(jd.get("rarity", "")),
			per / width * 100.0, once * 100.0, (1.0 - pow(1.0 - once, 12)) * 100.0])

	print("\n⚠ 口径:target_mult=1.0(不含独狼)· **不含付费刷新** ⇒ 本表是**下界**。")
	quit(0)


## `P(卡 i 出现在按权重不放回抽的 count 张里)` —— **解析,不模拟**。
## 用互补事件 + 内层求和折叠:第三位的「都不是 x」可以整段合并成
## `(W − w_a − w_b − w_x) / (W − w_a − w_b)`, 于是 O(n³) 塌成 O(n²)。
## ⚠ 只实现 count ≤ 3(货架现值);更宽的货架(联票 4 选 2)要扩这里, 别在调用方凑。
func _p_in_shelf(w: Array, idx: int, total: float, count: int) -> float:
	var wx: float = w[idx]
	if count <= 0 or total <= 0.0:
		return 0.0
	if count == 1:
		return wx / total
	var n: int = w.size()
	var pnot := 0.0
	for a in range(n):
		if a == idx:
			continue
		var wa: float = w[a]
		var r1 := total - wa
		if r1 <= 0.0:
			continue
		var pa := wa / total
		if count == 2:
			pnot += pa * ((r1 - wx) / r1)
			continue
		for b in range(n):
			if b == idx or b == a:
				continue
			var wb: float = w[b]
			var r2 := r1 - wb
			if r2 <= 0.0:
				continue
			pnot += pa * (wb / r1) * ((r2 - wx) / r2)
	return 1.0 - pnot


## 组合数,用浮点算(C(52,8) ≈ 7.5e8,远在 double 精确整数范围内)。
func _c(n: int, k: int) -> float:
	if k < 0 or k > n:
		return 0.0
	var r := 1.0
	for i in range(k):
		r = r * (n - i) / (i + 1)
	return r
