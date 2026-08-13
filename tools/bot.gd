class_name Bot
extends RefCounted

## The sim's player model (design/tech.md split): play decisions, draft EV,
## pivot logic and the beliefs behind them (data/sim.json + derivations
## from data/jokers.json). Shares the caller's RNG INSTANCE — consumption
## order is the determinism contract, do not reorder calls.

var _rng: RandomNumberGenerator
var _rep: Report

var SIM: Dictionary = DB.sim()
var KIND_PRIOR: Dictionary = _int_keys(SIM["kind_prior"])
var TARGET_TF: Dictionary = SIM["target_tf"]
var COUNTERFACTUAL_TV: Dictionary = SIM["counterfactual_tv"]
## 求解买牌往前推演几拍。实测 M=6 约 0.48 秒/局(M=3 是 0.23s, M=12 是 0.95s)。
## ⚠ 截断是显式近似:远期牌堆状态本来就不可信, 而且两条臂共用补牌, 差里噪声成对抵消。
const DRAFT_BEATS := 6
## 买牌收益往前看几拍的上限。⚠ **它同时是金币影子价的归一化基准**(见 `_draft` 的 lam),
## 两处必须是同一个数 —— 分开写死会让 `coin_decay` 的语义静默变形。
const DRAFT_HORIZON := 20.0
var EV: Dictionary = SIM["ev"]
var CHASE: Dictionary = SIM["chase"]
var SOLVER: Dictionary = SIM["solver"]      # 平衡贪心的 lam / lam_samples (design/solver_roadmap.md)


func _init(rng: RandomNumberGenerator, rep: Report) -> void:
	_rng = rng
	_rep = rep


func _int_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[int(k)] = d[k]
	return out


## Draft algorithm — no hand-tuned taste table. Every candidate is priced by
## measured behavior: "in MY run, how much score per phrase does this card add,
## and is that worth the coins?" Rates blend the run ledger with priors so the
## first drafts are not noise-driven.

func _rate(st: Dictionary, key: String, prior: float) -> float:
	var w: float = float(EV["blend_w"])
	return (float(st[key]) + prior * w) / (float(st["n"]) + w)


## First-effect channel amount of a joker, straight from data/jokers.json —
## the bot prices what the card actually pays, no hand copy.
func _amt(id: String) -> float:
	for e in DB.jokers():
		if String(e["id"]) == id:
			for fx in e.get("effects", []):
				# chips_per_card / additive_low_value 是 2026-08-10 批 3 的新操作码 ——
				# 前者返回每张的 chips, 后者返回「按多少计」的面值;期望命中数在 ev.cards 里。
				for ch in ["mult_add", "additive", "bonus", "bonus_pct", "coins",
						"chips_per_card", "additive_low_value"]:
					if fx.get("do", {}).has(ch):
						var raw = fx["do"][ch]
						return 0.0 if raw is Dictionary else float(raw)
	return 0.0


## glowstick average lifetime pct = init/2 (linear decay to 0), from data.
func _glow_avg() -> float:
	for e in DB.jokers():
		if String(e["id"]) == "glowstick":
			return float(e["counters"]["pct"]["init"]) * 0.5
	return 0.30


## mirror's copy power, from the opcode parameter in data.
func _mirror_power() -> float:
	for e in DB.jokers():
		if String(e["id"]) == "mirror":
			for fx in e.get("effects", []):
				if fx.get("do", {}).has("mult_from_target_factor"):
					return float(fx["do"]["mult_from_target_factor"])
	return 0.5


## Expected extra score per phrase if this support joins the build now.
## Formula shapes are the bot's brain (code); priors/weights come from
## sim.json, card amounts from jokers.json (multiplication order kept
## exactly — the A/B identity check is byte-strict).
func _card_ev(id: String, st: Dictionary, slots: Array, phrases_left: int) -> float:
	var bw: float = float(EV["blend_w"])
	var n: float = maxf(1.0, float(st["n"]))
	var mult_mean: float = (float(st["mult"]) + float(EV["mult_prior"]) * bw) / (n + bw)
	var score_mean: float = (float(st["score"]) + float(EV["score_prior"]) * bw) / (n + bw)
	var coin_val: float = float(EV["coin_score_ratio"]) * score_mean
	var tid := "" if slots[0] == null else String(slots[0].id)
	var future := float(phrases_left)
	var gh: float = float(EV["growth_horizon"])
	var p: Dictionary = EV["cards"].get(id, {})
	match id:
		"encore", "finale", "turnover", "chord":
			return _rate(st, String(p["rate"]), float(p["prior"])) * _amt(id) * mult_mean
		"tipjar":
			return _rate(st, String(p["rate"]), float(p["prior"])) * _amt(id) * coin_val
		"neonsign":
			return _amt(id) * mult_mean
		"vinyl":   # low prior: growth must be earned by measured discards
			return _rate(st, String(p["rate"]), float(p["prior"])) * _amt(id) * (future * gh) * mult_mean
		"chorus":
			return float(p["fixed_rate"]) * _amt(id) * score_mean
		"interest":
			return float(p["coin_mult"]) * coin_val
		"momentum":
			return _rate(st, String(p["rate"]), float(p["prior"])) * _amt(id) * (future * gh) * score_mean
		"vip":
			return _rate(st, String(p["rate"]), float(p["prior"])) * float(p["boost"]) * mult_mean
		"glowstick":
			return _glow_avg() * score_mean * minf(future, float(EV["glowstick_horizon"])) \
				/ float(EV["glowstick_horizon"])
		"bassline":
			return _amt(id) * (_rate(st, String(p["rate"]), float(p["prior"])) * future * gh / 12.0) * score_mean
		"mirror":
			var tf: float = float(TARGET_TF.get(tid, 1.0))
			return _rate(st, String(p["rate"]), float(p["prior"])) * (tf - 1.0) * _mirror_power() * score_mean
		"shortcut", "fourfingers", "twotone", "trim":
			var ot: Array = p["on_target"]
			var bm: float = score_mean / maxf(1.0, mult_mean)
			return (float(ot[1]) * float(ot[2]) * bm) if tid == String(ot[0]) \
				else float(p["off_target"]) * score_mean
		"wildcard":
			var tb: Array = p["target_bonus"]
			var bonus: float = float(tb[1]) if tid in tb[0] else 0.0
			return (float(p["base"]) + bonus) * score_mean
		# ---- 2026-08-10 批 3。缺这些臂时兜底 0.0 = bot 永远不买新卡 →
		# 货架 2/3 死货 → 金币边际价值塌平, gate 单调性哨兵当场红(起始金币 −3→0 无差)。
		# 数额照旧 _amt 从 json 推导, 行为先验(fixed_rate/hits/pairs)在 ev.cards。 ----
		"variation":
			return (1.0 - _rate(st, String(p["rate"]), float(p["prior"]))) * _amt(id) * mult_mean
		"reprise":
			return _rate(st, String(p["rate"]), float(p["prior"])) * _amt(id) * score_mean
		"opener":
			return float(p["fixed_rate"]) * _amt(id) * score_mean
		"rainbow", "nopair", "rehearsal", "fullcast":
			return float(p["fixed_rate"]) * _amt(id) * mult_mean
		# ---- 2026-08-12 流派批(design/archetypes.md)。族内件/缓存件/经济件,
		# 数额照旧 _amt 推导;行为先验(fixed_rate/coin_steps/avg_top/avg_faces)在 ev.cards。----
		"duo", "triad":     # 族内 chips 件:含对/含三条 × 数额 × 倍率链(additive 吃全倍率)
			return float(p["fixed_rate"]) * _amt(id) * mult_mean
		"duet", "triplebill":   # 族内 pct 件:比例 × 均分
			return float(p["fixed_rate"]) * _amt(id) * score_mean
		"backer":           # +1 chip / 2◆:持币档数 × 倍率链
			return _amt(id) * float(p["coin_steps"]) * mult_mean
		"bench":            # 缓存最高点数计 chips:先验点数 × 倍率链
			return float(p["avg_top"]) * mult_mean
		"boxseats":         # 缓存人头 ×1.2/张:边际倍率 × 均分
			return _amt(id) * float(p["avg_faces"]) * score_mean
		# ---- 2026-08-13 引擎波次·子波1(design/jokers_atlas.md §2.9/2.12/2.13/2.15)----
		# ---- 2026-08-13 子波 2:计时族。触发率来自 `ev.timing` 的同一张偏置表 ——
		# **打法先验与估值先验必须同源**, 否则 bot 会买一张它自己不会去打的卡。----
		# ---- 2026-08-13 子波 3:商店成长族。成长挂**付费动作**(A4✓), 所以价值
		# = 一局预期发生几次 × 每次数额 × 到那时还剩多少拍(growth 的老口径)。----
		"digger", "collector":
			return _amt(id) * float(p["events"]) * (future * gh) * mult_mean
		"rebrand":
			return _amt(id) * float(p["events"]) * (future * gh) * score_mean
		"curtain":          # 压哨 pct:比例 × 均分
			return float(p["fixed_rate"]) * _amt(id) * score_mean
		"stopwatch":        # 每剩 1 秒 pct:期望秒数 × 每秒比例 × 均分
			return float(p["avg_seconds"]) * _amt(id) * score_mean
		"earlyout":         # 早弃 bonus:比例 × 数额 × 倍率链
			return float(p["fixed_rate"]) * _amt(id) * mult_mean
		"stilllife", "declutter", "stageexit", "segue", "freeze":
			# 五张都是「行为触发 × 数额」:先验触发率 × 数额 × 量纲(bonus 吃倍率链,
			# pct 吃均分)。⚠ 触发率是 bot 打法的先验, 不是真人 —— 定价锚仍是 Tape。
			var pct: bool = id in ["declutter", "freeze"]
			return float(p["fixed_rate"]) * _amt(id) * (score_mean if pct else mult_mean)
		"skint":
			# 常驻 ×1.3 **减去金币上限的代价**。
			# ⚠⚠ 第一版只写了上面那半句(`_amt(id) * score_mean`), 于是 bot **100% 买它**,
			# 买完经济锁死在 cap —— `gate.sh` 的单调性哨兵当场红:
			# 「起始金币 +3 应该变容易, 实际 −0.00 段」。**多给的钱进不了口袋, 哨兵是对的。**
			# 代价的口径:上限没收的是**购买力** —— 本局本来会攒到的持币(实测局末
			# 34.7◆, S9)减去 cap, 按 bot 自己的金币折分率计价, 再按「还剩多少局面花它」
			# 折现(与 `lam` 的 horizon 折现同一个道理:钱的价值在于还能买到多少分)。
			var cap := 0.0
			for e in DB.jokers():
				if String(e["id"]) == id:
					cap = float(e.get("hold", {}).get("coin_cap", 0))
			var span: float = float(GameConfig.SECTIONS_PER_RUN
				* GameConfig.PHRASES_PER_SECTION)
			var forgone: float = maxf(0.0, float(p["hoard"]) - cap) * (future / maxf(1.0, span))
			return _amt(id) * score_mean - forgone * coin_val
		"royalty":          # 牌型金币翻倍:一拍多出的◆ ≈ 均金币 × (factor−1)
			return float(p["coins_per_beat"]) * (_amt(id) - 1.0) * coin_val
		"doggybag":         # 超标两倍才给:低频事件 × 3◆
			return float(p["fixed_rate"]) * _amt(id) * coin_val
		# ---- 货架结构卡(shop 通路, 2026-08-12 流派批二波):不产分, 价值全在商店侧,
		# 折成◆当量再乘 coin_val —— 先验粗, 覆盖由 kit 商店臂证, 强弱等真人 Tape。----
		"sponsor":          # 未来购买每张省 1◆
			return float(p["saves"]) * coin_val
		"doublebill":       # 每店多一次成交的期权
			return float(p["option_ev"]) * coin_val
		"jukebox":          # 定向搜索:追牌型流派(顺/同花)才值钱
			return float(p["search_ev"]) * coin_val * (2.0 if tid in ["stair", "mono"] else 1.0)
		"superfan":
			return _amt(id) * float(p["pairs"]) * score_mean
		"warmtone", "cooltone", "undertone":
			return _amt(id) * float(p["hits"]) * mult_mean
		"bassclef":
			return (_amt(id) - float(p["avg_low_rank"])) * float(p["hits"]) * mult_mean
	return 0.0


## Free-choice target pick: read the run's own pattern distribution and take
## the target whose tiers pay best against it (lonewolf discounted for its
## no-discard vow).
## Expected mult gain per phrase of a target id against this run's measured
## pattern distribution (blended with priors). COUNTERFACTUAL_TV (sim.json)
## drives PIVOT decisions — the run's own measured distribution is biased by
## the current flag and cannot imagine playing differently.
func _target_value(tid: String, st: Dictionary) -> float:
	var bw: float = float(EV["blend_w"])
	var n: float = maxf(1.0, float(st["n"]))
	if tid == "lonewolf":
		# 独狼 2026-08-07 重做成**经济/节奏卡**(不给倍率, 不弃牌就给金币 + Target 出现率 ×3)。
		# 旧估值按「高牌频率 × ×4 × 起誓折扣」算 —— 那两样都没了, 留着会让 anytarget 队列
		# 系统性高估它。改成把**金币折算成等效倍率**, 和其他 Target 同一把尺子:
		# 一枚金币值 coin_score_ratio × 本局均分, 除以基础分(均分/均倍率) → 等效倍率增益。
		var per := 0.0
		for e in DB.jokers():
			if String(e["id"]) == "lonewolf":
				for fx in e.get("effects", []):
					per += float(fx.get("do", {}).get("coins", 0.0))
		var mm2: float = (float(st["mult"]) + float(EV["mult_prior"]) * bw) / (n + bw)
		return per * float(EV["coin_score_ratio"]) * mm2
	var v := 0.0
	for k in KIND_PRIOR:
		var pk: float = (float(st["kinds"].get(int(k), 0.0)) + float(KIND_PRIOR[k]) * bw) / (n + bw)
		v += pk * (_target_mult(tid, int(k)) - 1.0)
	return v


func _pick_target_ev(st: Dictionary, candidates: Array) -> Joker:
	var best = null
	var best_v := -1.0
	for j in candidates:
		var v := _target_value(j.id, st)
		if v > best_v:
			best_v = v
			best = j
	return best


## ⚠ `cache` / `done_phrases` 是 2026-08-08 为**求解买牌**加的(design/solving.md 第三部分), 默认值维持原行为。
## 求解版只在 `cfg["solve_draft"]` 打开时启用 —— **规则 bot 永久保留手写表当回归基线**
## (`design/history_parametric.md` 的既有决定), 而且它跑 9000 局, 换上去会慢一个量级。
func _draft(slots: Array, cfg: Dictionary, deck: Deck, coins: int, st: Dictionary, phrases_left: int, section: int, faces: Dictionary = {}, cache: Array = [], done_phrases: int = 0, run = null) -> int:
	var want := "target" if slots[0] == null else "support"
	var owned: Array = []
	for j in slots:
		if j != null:
			owned.append(j.id)
	# Target 回池(2026-08-06 用户拍板):首张免费三选一是唯一特例, 之后 Target 与
	# Support **同池**按稀有度抽 —— 换旗的专属骰子(chance/from_section)已删。
	# ⚠ 强制 target 的队列不许换旗(除非 cfg.pivot):`cfg.target` 是**实验者的随机分配**,
	# 是整条 pipeline 唯一干净的因果通道(design/solver_roadmap.md), 让 bot 自己换掉就没了。
	var allow_target: bool = bool(cfg.get("pivot", false)) \
		or String(cfg.get("target", "")) == ""
	var candidates: Array = []
	for j in Joker.pool():
		if owned.has(j.id):
			continue
		if want == "target":
			if j.kind == "target":
				candidates.append(j)
		elif j.kind == "support" or allow_target:
			candidates.append(j)
	if want == "target":
		var pick = null
		var forced := String(cfg.get("target", ""))
		for j in candidates:
			if j.id == forced:
				pick = j
		if pick == null:
			pick = _pick_target_ev(st, candidates)
		slots[0] = pick
		pick.on_acquire(deck)
		return coins
	# supports: value = EV/phrase × horizon, cost in the same score currency
	var solve_draft: bool = bool(cfg.get("solve_draft", false))
	# 确定性 —— 同一次商店的全部候选共用它(见下面的两层公共随机数)。
	var draft_seed: int = section * 1009 + done_phrases * 31 + 7
	var bw: float = float(EV["blend_w"])
	var score_mean: float = (float(st["score"]) + float(EV["score_prior"]) * bw) \
		/ (maxf(1.0, float(st["n"])) + bw)
	var horizon: float = minf(float(phrases_left), DRAFT_HORIZON)
	# a coin's worth, in score。⚑ **它必须随剩余购买机会衰减**(2026-08-09):
	# 金币在本作**零终局价值**(段分清零、工资固定、局末余额一文不值), 它唯一的价值
	# 就是「还能买到多少分」。而 bot 自己的收益公式说一次购买付 `ev × horizon` ——
	# horizon 收缩时同一笔钱能换到的分同比收缩, 影子价理应同比往下走。
	# 旧算法只有前半句(`coin_score_ratio × 本局均分`), **随均分上涨、不随机会衰减**
	# (`tools/wallet.gd` 实测 17.7 → 54.3), 而收益边随 `phrases_left` 收缩 ——
	# 两边同时朝「别买」走, 门槛 ev 从 3 爆到 ∞, 后半程购买完全停止:
	# 满槽后整局只再买 0.27 次、78% 不愿换、局末白剩 34.7◆ 一分终局价值没有的钱。
	# 形状 = 归一化 horizon 的幂律, **只有一个数, 不引入第二套机制**:
	#   coin_decay = 0 —— `pow(x, 0) == 1`, **精确复现旧行为**(默认值, 既有读数一个不动)
	#   coin_decay = 1 —— lam 严格正比于 horizon;此时 horizon 在
	#                     `ev·h > lam₀·(h/H)·price` 两边约掉, 判据退化成
	#                     「这张牌的每金币价值打不打得过典型值」, 与剩余时间无关
	#   更大           —— 一离开满 horizon 就几乎归零
	# ⚠ 归一化必须用 `DRAFT_HORIZON` 本身:首店的 horizon 恰好被 cap 到它,
	# 所以**任何 decay 下第一次商店都不变**, 参数因此单调可读。
	# ⚠ 扫描见 `tools/decay.gd` —— 和跨拍那个 lam 一样, **不许拍脑袋**。
	var lam: float = float(EV["coin_score_ratio"]) * score_mean \
		* pow(horizon / DRAFT_HORIZON, float(EV["coin_decay"]))
	# 货架位数与两个「必定出」补丁 —— **与 view/shop.gd::_deal 同一套规则**(shelf API 收口)。
	var offer := _weighted_pick(candidates, Joker.slots_shelf_size(slots),
		Joker.slots_target_mult(slots))
	# 「必定出 Target」(独狼的卡面效果):抽完若一张 Target 都没有, 顶掉最后一位。
	# ⚠ 只在**允许换旗**时生效 —— 强制 target 的队列是实验者的随机分配, 不能被卡面绕过。
	if allow_target and Joker.slots_guarantee_target(slots):
		var has_t := false
		for j in offer:
			if j.kind == "target":
				has_t = true
		if not has_t:
			var tp: Array = []
			for j in candidates:
				if j.kind == "target":
					tp.append(j)
			if not tp.is_empty() and not offer.is_empty():
				offer[offer.size() - 1] = tp[_rng.randi_range(0, tp.size() - 1)]
	# 「必定出规则牌」(点唱机)—— 同上;两补丁同时顶位时各占一头(规则牌顶第一位)。
	if Joker.slots_rule_guaranteed(slots):
		var has_r := false
		for j in offer:
			if j.is_rule_card():
				has_r = true
		if not has_r:
			var rp: Array = []
			for j in candidates:
				if j.is_rule_card():
					rp.append(j)
			if not rp.is_empty() and not offer.is_empty():
				offer[0] = rp[_rng.randi_range(0, rp.size() - 1)]
	# 商店行为臂的证物记账(kit `shop` 通路):每店一记, 首发货架含规则牌就记一次。
	_rep.shops_n += 1
	for j in offer:
		if j.is_rule_card():
			_rep.rule_shops_n += 1
			break
	# 换旗:货架上**真的抽到** Target 时才发生(不再有专属骰子), 买入顶掉旧的、无回收。
	for tj in offer:
		if tj.kind != "target":
			continue
		var tprice := Economy.shelf_price(tj, slots)
		if coins < tprice:
			break
		var mm: float = (float(st["mult"]) + float(EV["mult_prior"]) * bw) \
			/ (maxf(1.0, float(st["n"])) + bw)
		var base_mean: float = score_mean / maxf(1.0, mm)
		var gain: float = (float(COUNTERFACTUAL_TV.get(tj.id, 1.0))
			- float(COUNTERFACTUAL_TV.get(String(slots[0].id), 1.0))) * base_mean
		# the preview turns faces into routing: a wolf that SEES norepeat
		# or rotation on the next wall pivots with far less hesitation
		var hyst := 1.5
		var next_face := ""
		for w in GameConfig.WALL_SECTIONS:
			if w > section:
				next_face = String(faces.get(w, ""))
				break
		if String(slots[0].id) == "lonewolf" and next_face in ["norepeat", "rotation"]:
			hyst = 0.6
		if gain * horizon > lam * float(tprice) * hyst:
			coins -= tprice
			# 与游戏侧同序:先发事件(收藏家/转型), 再装卡 —— 新旗不给自己记一次。
			Joker.notify_shop(slots, "buy")
			if slots[0] != null:
				Joker.notify_shop(slots, "target_swap")
			slots[0] = tj
			tj.on_acquire(deck)
			coins = Economy.cap_held(coins, slots)     # 装卡后修剪(同编排器)
			_rep.pivots_n += 1
			_rep.buys_total += 1
			_rep.discount_coins += maxi(0, Economy.joker_price(tj, true) - tprice)
			# 换旗即离店(联票的续买不覆盖 pivot —— 换旗是路线决策, 不是囤货)。
			return coins
		break
	# 联票:一次进店最多成交 buy_limit 张(限额随槽位实时读 —— 买到联票当店多一次)。
	# 两轮尝试的语义不变:第一轮什么都没买才允许一次付费刷新。
	var buys := 0
	for attempt in range(2):
		var empty_slot := -1
		for k in range(1, slots.size()):
			if slots[k] == null:
				empty_slot = k
				break
		var best = null
		var best_gain := 0.0
		var best_cost := 0
		for j in offer:
			# Target 回池后货架里可能混着 Target, 它走上面那段换旗路径(顶掉槽 0),
			# 不参与 support 的装槽/替换比价。⚠ 不显式跳过的话,
			# `joker_price(j)` 少传 has_target 会把它算成**免费**。
			if j.kind == "target":
				continue
			var price := Economy.shelf_price(j, slots)
			# ⚑ 求解买牌(design/solving.md 第三部分):不查手写表, 直接**在已知的脸序列下算边际价值**。
			# 前提是「四段的脸开局全可见」(design/solving.md §2.2)—— 用户 2026-08-08:
			# 「没有脸信息就没有选牌策略」。
			# ⚠ 量纲:card_value 给的是 M 拍的**总分差**, 而下面按「每拍 EV × horizon」算,
			# 所以要除以 M。除错了不会报错, 只会让买牌整体变贵或变便宜。
			var ev: float
			if solve_draft and run != null:
				var k_rep: int = -1 if empty_slot >= 0 else _weakest_slot(slots)
				# ⚠⚠ **同一次商店里全部候选共用同一个 sim_seed** —— 否则比较候选 A 和 B 时
				# 它们拿到不同的补牌, 噪声会吃掉真实差异。这和 λ 扫描那次是同一个坑
				# (独立采样让「λ 越大分越低」, 差点判定用户的设计不成立)。
				# 公共随机数在这里有**两层**:臂内(装 vs 不装, card_value 保证)、
				# 臂间(候选 A vs 候选 B, 这个 seed 保证)。
				ev = Draft.card_value(j, run, k_rep, draft_seed,
					float(SOLVER["lam"]), int(SOLVER["lam_samples"]))
			else:
				ev = _card_ev(j.id, st, slots, phrases_left)
			if empty_slot >= 0:
				if price > coins:
					continue
				var gain := ev * horizon - lam * float(price)
				if gain > best_gain:
					best_gain = gain
					best = j
					best_cost = price
			else:
				# replace: candidate must beat the weakest owned card by enough
				var weak_k := 1
				var weak_ev := 1.0e18
				for k2 in range(1, slots.size()):
					var oe := _card_ev(slots[k2].id, st, slots, phrases_left)
					if oe < weak_ev:
						weak_ev = oe
						weak_k = k2
				var refund := Economy.sell_value(slots[weak_k])
				if price > coins + refund:
					continue
				# ⚠ 求解版的 `ev` **已经是「换掉最弱那张」的净边际值**(card_value 传了 k_rep),
				# 再减一次 weak_ev 就是把替换成本算两遍。手写版的 ev 是绝对值, 才需要减。
				var gain2 := (ev * horizon if solve_draft else (ev - weak_ev) * horizon) \
					- lam * float(price - refund)
				if gain2 > best_gain:
					best_gain = gain2
					best = j
					best_cost = price - refund
			pass
		if best != null:
			if empty_slot >= 0:
				coins -= best_cost
				Joker.notify_shop(slots, "buy")            # 收藏家(装卡前, 同编排器)
				slots[empty_slot] = best
				best.on_acquire(deck)
				coins = Economy.cap_held(coins, slots)     # 装卡后修剪(同编排器)
				_rep.support_drafted[best.id] = int(_rep.support_drafted.get(best.id, 0)) + 1
			else:
				var weak_k := 1
				var weak_ev := 1.0e18
				for k2 in range(1, slots.size()):
					var oe := _card_ev(slots[k2].id, st, slots, phrases_left)
					if oe < weak_ev:
						weak_ev = oe
						weak_k = k2
				coins = Economy.grant(coins, Economy.sell_value(slots[weak_k]), slots) \
					- Economy.shelf_price(best, slots)
				Joker.notify_shop(slots, "buy")            # 替换也是一次购买(同编排器)
				slots[weak_k] = best
				best.on_acquire(deck)
				coins = Economy.cap_held(coins, slots)     # 装卡后修剪(同编排器)
				_rep.support_drafted[best.id] = int(_rep.support_drafted.get(best.id, 0)) + 1
			buys += 1
			_rep.buys_total += 1
			if buys >= 2:
				_rep.multi_shops_n += 1        # 双购店:联票的零基线证物
			_rep.discount_coins += maxi(0,
				Economy.joker_price(best) - Economy.shelf_price(best, slots))
			# 联票:限额未满 → 同一货架摘掉已购的那张继续挑(与 view/phrase.gd 的
			# sold 流程同构;不重掷 —— 重掷就成了免费刷新)。
			if buys >= Joker.slots_buy_limit(slots):
				return coins
			offer.erase(best)
			continue
		# nothing worth buying: one paid reroll if rich, else just walk away
		# (2026-08-06: leaving the shop pays nothing — the skip reward is gone)
		if attempt == 0 and buys == 0 and coins >= Economy.reroll_cost(0) + 6:
			coins -= Economy.reroll_cost(0)
			Joker.notify_shop(slots, "reroll")             # 淘碟(同编排器)
			# ⚠ 刷新后的货架沿用既有行为:只重掷、不重放两个「必定出」补丁 ——
			# 游戏侧 redeal 会重放, 这是 bot 的既有保真缺口, 记档不扩大(证物只数首发)。
			offer = _weighted_pick(candidates, Joker.slots_shelf_size(slots))
			continue
		break
	return coins


func _weighted_pick(candidates: Array, count: int, target_mult: float = 1.0) -> Array:
	var pool := candidates.duplicate()
	var picked: Array = []
	while picked.size() < count and not pool.is_empty():
		var total := 0
		for j in pool:
			total += _shelf_weight(j, target_mult)
		var roll := _rng.randi_range(1, maxi(1, total))
		for k in range(pool.size()):
			roll -= _shelf_weight(pool[k], target_mult)
			if roll <= 0:
				picked.append(pool[k])
				pool.remove_at(k)
				break
	return picked


## 稀有度权重 × 卡面声明的货架加成(现在只有独狼的 "more Targets")。
func _shelf_weight(j, target_mult: float) -> int:
	var w := int(GameConfig.DRAFT_RARITY_WEIGHTS.get(j.rarity, 1))
	if j.kind == "target":
		w = int(round(float(w) * target_mult))
	return maxi(1, w)


# ============================== BOT PLAY ==============================

## Play out one phrase's decisions. Returns {early, late} timing flags.
func _play_phrase(p: Phrase, cfg: Dictionary, slots: Array, section: int, mod: String = "") -> Dictionary:
	var bot := String(cfg.get("bot", "random"))
	var tid := "" if slots[0] == null else String(slots[0].id)
	match bot:
		"random":
			_play_random(p, slots)
		"adaptive":
			_play_adaptive(p, slots, tid, section, mod)
		"perfect":
			# 默认走 sim.json 里扫出来的 lam;队列可以覆盖(λ 扫描探针就靠这个)
			_play_perfect(p, slots, mod,
				float(cfg.get("lam", SOLVER["lam"])),
				int(cfg.get("lam_samples", SOLVER["lam_samples"])), section,
				float(cfg.get("eps", 0.0)))
	return _timing_flags(slots)


## 玩家打向自己的卡 —— 装了压哨卡就更常压哨, 装了早锁卡就更常早锁。
##
## ⚠⚠ **2026-08-13 数据化(子波 2 的重构点)**。旧版三宗罪, 每条都咬过人:
##   ① **概率写死在代码里** —— 违「数值与内容全部在 data/」, 调平衡要改 .gd;
##   ② **只认 `finale` / `momentum` 两个卡名** —— 每加一张时机卡就要来改一次代码,
##      而**忘了改不会报错**, 那张卡在模型里就是「玩家从不为它调整打法」;
##   ③ **`elif` 是隐式优先级** —— 同时持有压哨卡和早锁卡时只有前者生效,
##      这条规则从没人写下来过, 也没人验证过它是不是想要的。
## 现在:偏置表在 `sim.json ev.timing`, 多张卡**取最大值**(玩家打向最强的那张),
## 早/晚两轴各自独立取值 —— 同时持有两轴的卡时两边都抬, 不再互相吞掉。
##
## ⚠ 这是**行为改动**:`finale` / `momentum` 的既有实测强度会移动, 与 probe 修正同批解释。
## ⚠ 真人锚:早锁率实测 **8%**(bot 78%)—— 表里的数是 **bot 的打法先验, 不是真人**,
## 定价一律锚 Tape(numbers.md §1「p_bot ≫ p_人 → 定价锚真人」)。
func _timing_flags(slots: Array) -> Dictionary:
	var tim: Dictionary = EV.get("timing", {})
	var base: Dictionary = tim.get("base", {})
	var cards: Dictionary = tim.get("cards", {})
	var want := {"late": float(base.get("late", 0.25)),
		"early": float(base.get("early", 0.25)),
		"final_second": 0.0, "discards_before": 0.0}
	for j in slots:
		if j == null or not cards.has(j.id):
			continue
		var bias: Dictionary = cards[j.id]
		for k in want:
			if bias.has(k):
				want[k] = maxf(float(want[k]), float(bias[k]))
	# 一次掷点决定「这一拍偏早还是偏晚」, 早晚互斥(物理上如此), 其余量条件化在它之上。
	var roll := _rng.randf()
	var late: bool = roll < float(want["late"])
	var early: bool = not late and roll > 1.0 - float(want["early"])
	# 谢幕的窗口在尾声之内:只有已经压哨的拍才可能压到最后一秒。
	var final_sec: bool = late and _rng.randf() < float(want["final_second"])
	# 秒表:剩余秒数 —— 早锁的拍剩得多, 压哨的拍几乎为零。
	var secs: float = float(tim.get("seconds_left_early", 3.2)) if early else 0.0
	# 早弃:弃牌都赶在早锁线之前(装了早弃卡的玩家会刻意这么打)。
	var early_disc: bool = _rng.randf() < float(want["discards_before"])
	return {"early": early, "late": late, "final": final_sec,
		"secs_left": secs, "early_discards": early_disc}


func _notify_discard(slots: Array, n: int) -> void:
	for j in slots:
		if j != null:
			j.on_discard(n)


## 完美玩家 (design/solver_roadmap.md / §5)。**没有任何手写规矩** —— 直接调数学侧的
## `Solver`, 把 8 张可见牌的最优「计分 5 / 留缓存 3」切法搬进手牌。
##
## 它存在的唯一理由是**一致性测试**:数学 D 和模拟器必须对同一个局面给出同一个答案。
## 两边共用 `Solver` + 真实 `Pattern`/`Settle`, 所以剩下的任何差异都来自
## 「枚举 vs 采样」和牌堆消耗 —— 那正是 design/solver_roadmap.md 要单独验的近似。
##
## `lam` = 平衡贪心的权重(2026-08-06 用户拍板取代 DP):
##     value(切法) = 本拍得分 + lam · E[下一拍得分 | 留下的 3 张]
## lam = 0 就是单拍贪心。**lam 由 `tools/lam.gd` 扫出来, 不许拍脑袋。**
##
## v1 **不弃牌**(d = 0):弃牌的代价是跨拍的金币影子价。
## 孤立一拍地看, 最优解永远是把钱花光 —— 那是 `design/history_adversarial.md` §7 警告的幻想区。
## 所以先把「切法」这一维做干净, 弃牌随后同样用影子价接进来。
##
## ⚠ 已知近似:传给 Settle 的上下文缺 prev_kind / character / 时机旗
## (它们在 sim 的循环里、bot 决策时还不存在)。小丑牌倍率是全的, 所以流派差异看得见;
## 「禁回」这类跨拍谓词看不见。DP 上来时要把上下文一起穿进来。
func _play_perfect(p: Phrase, slots: Array, mod: String = "",
		lam: float = 0.0, lam_samples: int = 3, section: int = 0,
		eps: float = 0.0) -> void:
	var extra := {
		"prev_kind": -99, "acted_late": false, "discards": p.discards_used,
		"coins": p.coins, "phrase_idx": 0, "mod": mod, "character": null,
	}
	# ① 弃牌(2026-08-06 起**免费**, 只受手速预算限制 —— 金币影子价 κ 因此整个消失,
	#    求解器少一个要扫的参数)。弃的是「这拍用不上的那 3 张」, 计分的 5 张不动。
	# 不完全信息(盖牌脸):求解器只能按信念挑, 记账仍按真值。`blind` 是本拍
	# 玩家看不见的那几张在 visible 里的下标, `bs` 是给它们的替身采样组数。
	# 完全信息时两者都是空/0, 老路径逐位不变(tests/runner.gd 锁着)。
	var bs: int = GameConfig.BLIND_SAMPLES
	var dur := Run.phrase_duration_for(section, mod)
	var d_max: int = GameConfig.beat_discards(dur, section)
	if d_max > 0:
		var vis0: Array = []
		vis0.append_array(p.hand)
		vis0.append_array(p.cache)
		if vis0.size() >= GameConfig.HAND_SIZE:
			var hid0 := p.hidden_indices(vis0)
			var subs0 := Solver.make_subs(p.deck, _rng, hid0.size(), bs) if not hid0.is_empty() else []
			# ⚠⚠ **基线必须无噪声** —— `best_discard` 的收益是
			#     `gain = mean(弃牌后, 零噪声 best_score) − base.score`。
			# 若 base 带噪声, 噪声选中次优切法时 base.score 被压低, gain 就被
			# **系统性抬高** → ε 越大越狂弃牌。那不是"噪声玩家做了略差的决定",
			# 而是一个人为偏置, 会把 ε 扫描的读数整个污染。
			# 两个口径必须一致, 这里取零噪声那一侧。
			# **建模选择(design/solving.md 第二部分)**:ε 目前只建模「打哪 5 张」的决策噪声,
			# 不建模「弃不弃牌」的噪声 —— 真人两个都会错, 这是显式声明的近似。
			var b0 = Solver.best_split(vis0, slots, extra, p.deck.rules, hid0, subs0)
			if b0 != null:
				# ⚠ 暗补脸下弃牌**要按盲的算** —— 否则求解器以为弃完能看见新牌,
				# 会系统性高估弃牌, 而这张脸整个就是关于弃牌决策的。
				var blind_refill: int = bs if SectionMod.hide_refill(mod) else 0
				var drop := Solver.best_discard(vis0, slots, extra, p.deck, _rng,
					999, d_max, 0.0, lam_samples, 0.0, p.deck.rules, b0, blind_refill)
				if not drop.is_empty():
					_do_discard(p, b0.keep, drop, slots)

	# ② 切法:重新看 8 张(弃牌后已补), 选「计分 5 / 留缓存 3」
	var visible: Array = []
	visible.append_array(p.hand)
	visible.append_array(p.cache)
	if visible.size() < GameConfig.HAND_SIZE:
		return
	var hid := p.hidden_indices(visible)
	var subs := Solver.make_subs(p.deck, _rng, hid.size(), bs) if not hid.is_empty() else []
	var best = Solver.best_split_lookahead(visible, slots, extra, p.deck,
		_rng, lam, lam_samples, p.deck.rules, hid, subs, eps)
	if best == null:
		return
	# 把选中的 5 张搬进手牌:手牌里不该留的 ←→ 缓存里该上场的, 逐对交换。
	# 缓存 3 格 → 最多 3 次, 手速预算 5 次, 够(db.gd 有断言锁住这条)。
	var want := {}
	for c in best.hold:
		want[c] = true
	for _pass in range(GameConfig.CACHE_CAP):
		var hi := -1
		for i in range(p.hand.size()):
			if not want.has(p.hand[i]):
				hi = i
				break
		if hi < 0:
			break
		var ci := -1
		for j in range(p.cache.size()):
			if want.has(p.cache[j]):
				ci = j
				break
		if ci < 0:
			break
		p.swap_with_cache(hi, ci)


## 把「要弃 keep 里的第几张」翻译成 Phrase 认的 (手牌下标, 缓存下标) 两组。
## keep 的 3 张可能散落在手牌和缓存里 —— 按对象身份找位置, 不靠下标推算。
func _do_discard(p: Phrase, keep: Array, drop_idx: Array, slots: Array) -> void:
	var hi: Array = []
	var ci: Array = []
	for i in drop_idx:
		if i < 0 or i >= keep.size():
			continue
		var card = keep[i]
		var at := p.hand.find(card)
		if at >= 0:
			hi.append(at)
			continue
		at = p.cache.find(card)
		if at >= 0:
			ci.append(at)
	var n := hi.size() + ci.size()
	if n > 0 and p.can_discard(n) and p.discard_selected(hi, ci):
		_notify_discard(slots, n)


func _play_random(p: Phrase, slots: Array) -> void:
	for i in range(_rng.randi_range(0, 2)):
		p.swap_with_cache(_rng.randi_range(0, 4), _rng.randi_range(0, GameConfig.CACHE_CAP - 1))
	var k := _rng.randi_range(0, 2)
	if k > 0 and p.can_discard(k):
		var idx: Array = []
		while idx.size() < k:
			var v := _rng.randi_range(0, 4)
			if not idx.has(v):
				idx.append(v)
		if p.discard_selected(idx, []):
			_notify_discard(slots, k)


## Adaptive bot — the player model the user described: look at the hand,
## chase whichever big hand is closest to done, weighted by the target's
## payoff. Free cache swaps pull material in first, then paid discards chase
## the chosen plan.
func _play_adaptive(p: Phrase, slots: Array, target_id: String, section: int, mod: String = "") -> void:
	# free swaps: any trial swap that raises the best plan's EV sticks
	var rules: Dictionary = p.deck.rules
	for ci in range(p.cache.size()):
		for hi in range(p.hand.size()):
			var before: float = float(_best_plan(p.hand, target_id, 3, rules)["ev"])
			# ⚠ 试探走 probe:牌要真的对调才算得出 EV, 但**试探不是玩家动作**。
			# 不这么分, 每拍 15 次试探会让「本拍零交换」在模型里永不成立
			# (静物的 kit 触发率 0% 就是这个 —— 病在 bot 的记账, 不在卡)。
			if not p.swap_with_cache(hi, ci, true):
				continue                    # 守卫拒绝(封条/墨迹/红灯):这一对换不了
			var after: float = float(_best_plan(p.hand, target_id, 3, rules)["ev"])
			if after <= before:
				p.swap_with_cache(hi, ci, true)   # revert, 同样不计数
			else:
				p.commit_probe_swap()             # 留下了 = 玩家真的动了手
	if target_id == "lonewolf":
		return                              # the vow: zero discards
	# 弃牌免费(2026-08-06 用户拍板)后, **金币不再是闸门, 时间才是**。
	# 旧代码是手写的 `cap = 3 if dur>=12 else 2` 再和金币取小 —— 两条都作废:
	# 前者是该退役的手写判断, 后者的约束已经不存在。改走数据里的手速预算,
	# 它按实际拍长缩放, 所以「赶场」-2s 第一次真正咬合(8s→2 张, 6s→1 张)。
	var dur := Run.phrase_duration_for(section, mod)
	var d_max: int = GameConfig.beat_discards(dur, section)
	if d_max <= 0:
		return
	var plan: Dictionary = _best_plan(p.hand, target_id, d_max, rules)
	if bool(plan.get("keep_all", false)):
		return
	var keep: Array = plan["keep"]
	var idx: Array = []
	for i in range(p.hand.size()):
		if not keep.has(i) and idx.size() < d_max:
			idx.append(i)
	if not idx.is_empty() and p.can_discard(idx.size()) and p.discard_selected(idx, []):
		_notify_discard(slots, idx.size())
	# Forced Rotation: any non-vow build tosses its worst card rather than
	# eat the ×0.5 (Lone Wolf keeps the vow — ×4 halved still beats ×1)
	if mod == "rotation" and p.discards_used == 0 and target_id != "lonewolf" and p.can_discard(1):
		# toss the worst card OUTSIDE the scoring five — round 17's version
		# tossed the lowest rank and kept breaking its own pairs
		var best_now := p.current_best()
		var scoring := {}
		for c in best_now.get("cards", []):
			scoring[c] = true
		var lo := -1
		for i in range(p.hand.size()):
			if scoring.has(p.hand[i]):
				continue
			if lo < 0 or p.hand[i].rank < p.hand[lo].rank:
				lo = i
		if lo < 0:
			lo = 0
			for i in range(p.hand.size()):
				if p.hand[i].rank < p.hand[lo].rank:
					lo = i
		if p.discard_selected([lo], []):
			_notify_discard(slots, 1)


## Typical made-hand value for plan EVs: (pattern chips + a representative
## rank sum) × pattern mult. Reads Pattern.BASE_CHIPS/BASE_MULT so a ladder
## rebalance reaches the bot without a hand copy.
func _pat_val(kind: int, rsum: float) -> float:
	return (float(Pattern.BASE_CHIPS[kind]) + rsum) * float(Pattern.BASE_MULT[kind])


## Enumerate chase plans for this hand and return the best by EV:
## {ev, keep: hand indices to commit to, keep_all}. Probabilities are crude —
## they only need to rank plans the way a player's gut would.
func _best_plan(hand: Array, target_id: String, d: int, rules: Dictionary = {}) -> Dictionary:
	var plans: Array = []
	var cur := Pattern.evaluate_best(hand)
	var cur_kind := int(cur.get("kind", 0))
	var cur_score := float(cur.get("score", 0))
	plans.append({"ev": cur_score * _target_mult(target_id, cur_kind),
		"keep": [], "keep_all": true})

	# flush chase: majority suit (or color, under Two-Tone), any rank works
	var two: bool = bool(rules.get("twotone", false))
	var suit_n := {}
	for c in hand:
		if not c.is_wild():
			var sk: int = (1 if c.is_red() else 0) if two else c.suit
			suit_n[sk] = int(suit_n.get(sk, 0)) + 1
	var best_suit := -1
	var m := 0
	for su in suit_n:
		if int(suit_n[su]) > m:
			m = int(suit_n[su])
			best_suit = su
	if m >= 3 and m < 5:
		var keep_f: Array = []
		for i in range(hand.size()):
			var mk: int = (1 if hand[i].is_red() else 0) if two else hand[i].suit
			if hand[i].is_wild() or mk == best_suit:
				keep_f.append(i)
		var need_f := 5 - keep_f.size()
		var pf := _p_chase(((26.0 if two else 13.0) - float(m)) / 47.0, d, need_f)
		plans.append({"ev": pf * _pat_val(Pattern.Kind.FLUSH, 40.0) * _target_mult(target_id, Pattern.Kind.FLUSH)
			+ (1.0 - pf) * _pat_val(Pattern.Kind.HIGH_CARD, 45.0), "keep": keep_f, "keep_all": false})

	# straight chase: best 5-rank window (wheel included), duplicates are dead
	var have := {}
	for i in range(hand.size()):
		if not hand[i].is_wild() and not have.has(hand[i].rank):
			have[hand[i].rank] = i
	var windows: Array = []
	for lo in range(2, 11):
		windows.append(range(lo, lo + 5))
	windows.append([14, 2, 3, 4, 5])
	var best_keep: Array = []
	for w in windows:
		var ks: Array = []
		for r in w:
			if have.has(r):
				ks.append(int(have[r]))
		if ks.size() > best_keep.size():
			best_keep = ks
	if best_keep.size() >= 3 and best_keep.size() < 5:
		var need_s := 5 - best_keep.size()
		if bool(rules.get("fourfingers", false)):
			need_s = maxi(1, need_s - 1)
		var qs: float = 4.0 * float(need_s) / 47.0
		if bool(rules.get("shortcut", false)):
			qs *= 1.5
		var ps := _p_chase(qs, d, need_s)
		plans.append({"ev": ps * _pat_val(Pattern.Kind.STRAIGHT, 40.0) * _target_mult(target_id, Pattern.Kind.STRAIGHT)
			+ (1.0 - ps) * _pat_val(Pattern.Kind.HIGH_CARD, 45.0), "keep": best_keep, "keep_all": false})

	# rank chases: pair -> trips, trips -> full house, two pair -> full house
	var rank_n := {}
	for c in hand:
		if not c.is_wild():
			rank_n[c.rank] = int(rank_n.get(c.rank, 0)) + 1
	var pairs: Array = []
	var trip_rank := -1
	for r in rank_n:
		if int(rank_n[r]) == 2:
			pairs.append(r)
		elif int(rank_n[r]) >= 3:
			trip_rank = r
	if trip_rank >= 0:
		var keep_t: Array = []
		for i in range(hand.size()):
			if not hand[i].is_wild() and hand[i].rank == trip_rank:
				keep_t.append(i)
		var pt := _p_chase(3.0 / 47.0, d, 1)
		plans.append({"ev": pt * _pat_val(Pattern.Kind.FULL_HOUSE, 35.0) * _target_mult(target_id, Pattern.Kind.FULL_HOUSE)
			+ (1.0 - pt) * _pat_val(Pattern.Kind.THREE_KIND, 30.0) * _target_mult(target_id, Pattern.Kind.THREE_KIND),
			"keep": keep_t, "keep_all": false})
	elif pairs.size() >= 2:
		var keep_2: Array = []
		for i in range(hand.size()):
			if not hand[i].is_wild() and pairs.has(hand[i].rank):
				keep_2.append(i)
		var p2 := _p_chase(4.0 / 47.0, d, 1)
		plans.append({"ev": p2 * _pat_val(Pattern.Kind.FULL_HOUSE, 35.0) * _target_mult(target_id, Pattern.Kind.FULL_HOUSE)
			+ (1.0 - p2) * _pat_val(Pattern.Kind.TWO_PAIR, 45.0) * _target_mult(target_id, Pattern.Kind.TWO_PAIR),
			"keep": keep_2, "keep_all": false})
	elif pairs.size() == 1:
		var keep_p: Array = []
		for i in range(hand.size()):
			if not hand[i].is_wild() and hand[i].rank == int(pairs[0]):
				keep_p.append(i)
		var pp := _p_chase(2.0 / 47.0, d, 1)
		plans.append({"ev": pp * _pat_val(Pattern.Kind.THREE_KIND, 30.0) * _target_mult(target_id, Pattern.Kind.THREE_KIND)
			+ (1.0 - pp) * _pat_val(Pattern.Kind.PAIR, 35.0) * _target_mult(target_id, Pattern.Kind.PAIR),
			"keep": keep_p, "keep_all": false})

	# lone wolf: value the hand as it stands, swaps chase A/K elsewhere
	if target_id == "lonewolf" and cur_kind == Pattern.Kind.HIGH_CARD:
		var top := 0
		for c in hand:
			if not c.is_wild():
				top = maxi(top, c.rank)
		if top >= 13:
			plans[0]["ev"] = cur_score * 4.0

	var best: Dictionary = plans[0]
	for pl in plans:
		if float(pl["ev"]) > float(best["ev"]):
			best = pl
	return best


## Crude completion probability: per-draw hit chance q, d draws, `need` hits.
func _p_chase(q: float, d: int, need: int) -> float:
	if need <= 0:
		return 1.0
	if d < need:
		return float(CHASE["floor"])
	return pow(clampf(q * float(d) / float(need) * float(CHASE["gain"]), 0.0,
		float(CHASE["cap"])), float(need))


var _tmult: Dictionary = {}    # tid -> {kind_int: mult}, derived from data


## What the installed target pays for a settled kind — derived from
## data/jokers.json effects, killing the hand-copied tier table (design/tech.md).
## Tiers guarded by extra conditions (lonewolf's discards/top-rank) are NOT
## unconditional payouts and are skipped, matching the old table exactly.
func _target_mult(target_id: String, kind: int) -> float:
	if _tmult.is_empty():
		for e in DB.jokers():
			if String(e["kind"]) != "target":
				continue
			var tiers := {}
			for fx in e.get("effects", []):
				var m: float = float(fx.get("do", {}).get("mult", 0.0))
				if m <= 0.0:
					continue
				var w: Dictionary = fx.get("when", {})
				var conditional := false
				for wk in w:
					if wk != "kind" and wk != "kind_in":
						conditional = true
				if conditional:
					continue
				if w.has("kind"):
					tiers[int(Pattern.Kind[String(w["kind"])])] = m
				for kn in w.get("kind_in", []):
					tiers[int(Pattern.Kind[String(kn)])] = m
			_tmult[String(e["id"])] = tiers
	return float(_tmult.get(target_id, {}).get(kind, 1.0))



## 槽里最弱的那张(槽 0 是 Target, 不参与 support 的替换)。求解买牌用它定「换掉谁」。
func _weakest_slot(slots: Array) -> int:
	var weak_k := 1
	var weak_ev := 1.0e18
	for k in range(1, slots.size()):
		if slots[k] == null:
			continue
		var oe := _card_ev(String(slots[k].id), {"n": 1.0, "score": 0.0, "mult": 0.0,
			"disc": 0.0, "rep": 0.0, "late": 0.0, "early": 0.0, "zerod": 0.0,
			"faces": 0.0, "chord": 0.0, "tgt": 0.0, "kinds": {}}, slots, 1)
		if oe < weak_ev:
			weak_ev = oe
			weak_k = k
	return weak_k
