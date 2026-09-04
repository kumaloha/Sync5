class_name Bot
extends RefCounted

## The sim's player model (docs/design/tech.md split): play decisions, draft EV,
## pivot logic and the beliefs behind them (data/sim.json + derivations
## from data/jokers.json). Shares the caller's RNG INSTANCE — consumption
## order is the determinism contract, do not reorder calls.

var _rng: RandomNumberGenerator
var _rep: Report

var SIM: Dictionary = DB.sim()
var KIND_PRIOR: Dictionary = _int_keys(SIM["kind_prior"])
var COUNTERFACTUAL_TV: Dictionary = SIM["counterfactual_tv"]
## 求解买牌往前推演几拍。实测 M=6 约 0.48 秒/局(M=3 是 0.23s, M=12 是 0.95s)。
## ⚠ 截断是显式近似:远期牌堆状态本来就不可信, 而且两条臂共用补牌, 差里噪声成对抵消。
const DRAFT_BEATS := 6
## 买牌收益往前看几拍的上限。⚠ **它同时是金币影子价的归一化基准**(见 `_draft` 的 lam),
## 两处必须是同一个数 —— 分开写死会让 `coin_decay` 的语义静默变形。
const DRAFT_HORIZON := 20.0
var EV: Dictionary = SIM["ev"]
var CHASE: Dictionary = SIM["chase"]
var SOLVER: Dictionary = SIM["solver"]      # 平衡贪心的 lam / lam_samples (docs/design/solver_roadmap.md)
## 「玩家为自己的卡凑弃牌张数」的偏置表(2026-08-13)。id → 想凑到几张。
## ⚠ 在 data/ 里而不是代码里 —— 与 `ev.timing` 同一条纪律:加一张吃弃牌张数的卡时
## 只改 JSON, 而**忘了改不会报错**(那张卡就成了「玩家从不为它调整打法」的死卡)。
var DISCARD_BIAS: Dictionary = SIM["ev"].get("discard_bias", {})


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
## `_amt` **不管**的 do 键 —— 它们不是「数额」通道(修饰符 / 由专门的臂处理)。
## ⚑ 存在的意义是给 `tools/parity.py` 第 ⑤ 层对账:**jokers.json 里出现的每个 `do` 键,
## 要么在 `_amt` 的白名单里, 要么在这张表里** —— 加了新操作码却忘了教 `_amt`,
## 当场红, 而不是等某张卡的 EV 悄悄变成 0 或负数。
const NON_AMOUNT_KEYS := ["per", "cap", "step", "card_filter",
	"additive_cache_top", "additive_face_value"]


func _amt(id: String) -> float:
	for e in DB.jokers():
		if String(e["id"]) == id:
			for fx in e.get("effects", []):
				# chips_per_card / additive_low_value 是 2026-08-10 批 3 的新操作码 ——
				# 前者返回每张的 chips, 后者返回「按多少计」的面值;期望命中数在 ev.cards 里。
				# ⚠⚠ **`bonus_target_pct` 必须换算成分数再返回** —— 它是**比例**不是点数,
				# 原样返回 0.8 会被 EV 公式当成「0.8 分」, 比返回 0 还糟(那是错的数, 不是没数)。
				# 换算基准 = **一局的平均每拍目标**(四段平均), 因为 `_amt` 没有段上下文,
				# 而买牌决策本来就是「这张卡这一整局值多少」。
				if fx.get("do", {}).has("bonus_target_pct"):
					var pr = fx["do"]["bonus_target_pct"]
					return 0.0 if pr is Dictionary else float(pr) * _avg_beat_target()
				# ⚠⚠ **`coins_factor` 返回的是「倍数」不是「点数」**(与 `mult_from_target_factor`
				# 同族), 因为它的臂写的是 `(_amt(id) - 1.0)` —— 要的就是这个倍数。
				# 2026-08-30 补:漏了这一条的后果**不是少算一点**, 而是 `_amt` 落到末尾
				# `return 0.0` ⇒ `(0.0 - 1.0) = -1` ⇒ **版税的 EV 变成负数**,
				# 而买牌的 `best_gain` 从 0.0 起比 ⇒ **这张卡永远不可能被选中**。
				# 实测:装机率 **0.0%**(全池唯一一张一次都没被买过的), 而它用修好的
				# 单卡门量出来是 **+1191.7 分/局(占基准 15.5%)** —— 一张 common 的两倍。
				# ⇒ **「没进过赢局」的最后一张卡, 病根是一张白名单漏了一个键。**
				if fx.get("do", {}).has("coins_factor"):
					var cf = fx["do"]["coins_factor"]
					return 0.0 if cf is Dictionary else float(cf)
				# ⚠ `mult` 同样返回**倍数**(全员 ×1.2 → 1.2):2026-09-04 前它在 NON_AMOUNT_KEYS 里,
				# `_amt("fullcast")` 落到 0 ⇒ 臂恒 0, 装机率全靠地板撑 —— 与版税同病。
				# 现在全员走重放估值, 这一条是给**任何**还走手写臂的 mult 卡兜底:臂按 `(_amt − 1)` 写。
				if fx.get("do", {}).has("mult"):
					var mf = fx["do"]["mult"]
					return 0.0 if mf is Dictionary else float(mf)
				for ch in ["mult_add", "additive", "bonus", "bonus_pct", "coins",
						"chips_per_card", "additive_low_value"]:
					if fx.get("do", {}).has(ch):
						var raw = fx["do"][ch]
						return 0.0 if raw is Dictionary else float(raw)
	return 0.0


## 一局的平均每拍目标 —— `bonus_target_pct` 换算成分数用。
## ⚠ 从 `GameConfig.SECTION_TARGETS` 推导, **不许抄第二份**:目标分改了它要跟着改。
func _avg_beat_target() -> float:
	var t := 0.0
	for v in GameConfig.SECTION_TARGETS:
		t += float(v)
	var n := float(GameConfig.SECTION_TARGETS.size())
	if n <= 0.0:
		return 0.0
	return t / n / float(GameConfig.PHRASES_PER_SECTION)


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
var _no_arm_warned: Dictionary = {}
var _zero_ev_warned: Dictionary = {}
## EV **合法**为 0 的卡 —— 它们的价值取决于场上有没有别的东西:
##   `loadeddice` 灌铅骰:没有赌卡时确实一文不值(`gambles == 0`)
##   `mirror`     镜面:没有旗时没有倍率可镜(`_target_peak("") - 1.0 == 0`)
## ⚠ 这是**声明, 不是豁免** —— 不在表里的卡一旦 EV ≤0 就响警告, 因为那多半是
## 「白名单漏了个键」那一类(2026-08-30 版税:`coins_factor` 没进 `_amt` ⇒ 负 EV ⇒ 永不购买)。
## ⚑ 一个会为正常情况响的警告等于没有警告 —— 这个项目已经有过一次
## 「warning 一直在打印, 我一直没看」(帕奇欧)。**声明清楚, 让它保持安静。**
## ⚠ 顺带记一条设计事实:**组合卡在贪心 bot 眼里天然被低估** —— 它只看「现在装上值多少」,
## 看不见「先买 A 再买 B」。灌铅骰装机率 1% 就是这个形状, 不是它弱。
## ⚑ 2026-09-04 加 `skint`:它的臂 = ×1.3 减去金币上限没收的购买力(影子价), 在现行经济下**常为负**
## (−45 ~ −190), 而 lift 实测装了它通关率 −13pt —— bot 不买是对的。此前它靠 evsync 误导入的
## evbook 读数(112.4, cf 标着「hold 卡本尺不适用」)当地板才被买到 43%;地板摘掉后这条警告就该安静。
const CONTEXT_ZERO_OK := ["loadeddice", "mirror", "skint"]


## ⚑ 估值地板(2026-08-30):手写信念表**系统性低估** —— 实测 bot 从没买过的卡里
## EV 最高的 glowstick(215.9)高于它买过的任何一张(gueststar 187.4), 23 张 EV 为正的
## 卡完全在视野外, 而强制试用它们的四组通关率**全部高于正常路线均值**。
## ⇒ 拿 `cf.gd` 的实测 EV 兜底:公式算低了就用实测值。
## ⚠ **只当地板不当替代** —— evbook 量的是「装着一整局」的均值, 答不了
## 「现在买值不值」(剩余拍数 / 当前构筑 / 替换谁), 那些仍归公式。
func _card_ev(id: String, st: Dictionary, slots: Array, phrases_left: int) -> float:
	if _is_replayable(id):
		return _card_ev_replay(id, st, slots)
	# 地板取两把尺子的较大者:cf(真人 Tape, 效果卡)/ kit(钉卡打满 24 拍, 成长/持有/概率卡的到达值)。
	# 2026-09-04 lift:「低用高值」剩下的全是手写臂的卡(ensemble +42.9pt 却装机 3%), 病在先验, 不在臂形。
	var _floor: float = maxf(float(EV.get("measured", {}).get(id, 0.0)),
		float(EV.get("measured_kit", {}).get(id, 0.0))) * MEASURED_W
	var v := maxf(_floor, _card_ev_formula(id, st, slots, phrases_left))
	# ⚑ **EV ≤ 0 的支援卡 = 永远不会被买**(`best_gain` 从 0.0 起比)。
	# 这与「缺臂」是同一类失败, 只是更隐蔽:臂在、公式跑了、结果是 0 或负数。
	# 2026-08-30 版税就是这样隐身的(`_amt` 白名单漏了 `coins_factor` ⇒ `(0−1)=−1`),
	# 而它是全池唯一一张装机率 0.0% 的卡。⇒ 与缺臂同款:响一声, 只响一次。
	if v <= 0.0 and not CONTEXT_ZERO_OK.has(id) and not _zero_ev_warned.has(id):
		_zero_ev_warned[id] = true
		push_warning("[bot] _card_ev 估值 ≤0: '%s' 永远不会被买(公式给 %.2f, 地板 %.2f)"
			% [id, _card_ev_formula(id, st, slots, phrases_left), _floor])
	return v


## 实测地板的折扣 —— 不给满值:evbook 是**事后**均值(含玩家已经把构筑配好的局面),
## 而买入决策发生在**事前**。0.5 是保守起步, 归数值批标定。
## ⚑ 量纲已核(2026-08-30 code review):`ev.measured` 与 `_card_ev` 都是**分/拍**,
## `horizon` 在调用点外乘(`ev * horizon - lam * price`)。公式里那些 `* future`
## 是成长牌**自身的累积特性**(每拍涨一点), 不是量纲转换 —— 两者可以直接 maxf。
const MEASURED_W := 0.5


## ⚑⚑ 反事实重放估值(2026-09-04)。效果卡的 EV **不再手写臂**:在本局已经打过的每一拍上
## 跑两次 `Settle.run`, 只差「装不装这张卡」, 差值的均值就是它在**我这一局**里的边际
## (分/拍;金币通道按 coin_val 折分)。这是 `tools/cf.gd` 在真人 Tape 上用了一个月的
## 同一把尺, 搬进 bot 自己的局。
##
## 它一次修掉手写臂的三类**结构**错(2026-09-04 `_evcmp` 全池对照, 真人 Tape 24 局 332 拍):
##   · **条件均值** —— 全员/三和弦/三重只在大牌上触发, 臂用全局均分 ⇒ 低估 3 倍;
##   · **通道载体** —— 灯牌/回响/彩虹/静物…是乘法链**之后**的扁平奖励, 臂又乘了一遍均倍率
##     ⇒ 整族高估 3.5 倍(排练 41 倍, 早弃 30 倍);
##   · **过期先验** —— 静场放宽后 `fixed_rate` 还是 0.12, 账本里零弃率实测 0.51。
## 重放没有这些参数:判定走 core/fx.gd(一行不重写), 载体由 core/settle.gd 的公式自己决定,
## 触发率与条件分从本局历史里直接读出, 真实构筑(装在当前槽位旁边)自动成立,
## 新操作码**自动**被正确估值 —— 「加了新操作码却忘了教 bot」这一整类事故对效果卡不再存在。
##
## ⚠ **不走重放、保留手写臂的几类**(`DB.replay_valued` 按数据判, 不按 id 列表):
##   成长/衰减/计数器/持有 —— state 跨拍, 单拍差值读 0 或读初值(cf.gd 同一条豁免);
##   概率卡 —— `luck_rolls` 按槽序预掷, 多一张卡整列错位(2026-08-30 code review 那条);
##   货架/入场类(shelf/acquire)与 proof=shop —— 价值不在结算链里。
## 先验:无历史时 = `ev.measured`(真人 Tape 的实测 EV);没量过的卡取已量卡的**中位数**
## —— 不引入新的手写数。收缩权重复用 `blend_w`:首店只打过 3 拍, 先验占 2/3;局末 0.2。
## ⚠ 已知边界:时机卡(尾声/谢幕/早弃…)的触发在历史里按 bot **未持卡**时的打法计,
## 持卡后它会刻意压哨(`_timing_flags`), 这份适应重放看不见 ⇒ 这一族偏低。
## 手写臂原本也只用基础率(finale prior 0.25), 没有更差;真要修得让打法先验进估值, 归数值批。
var _replay_ok: Dictionary = {}
var _prior_median := -1.0

func _is_replayable(id: String) -> bool:
	if _replay_ok.has(id):
		return bool(_replay_ok[id])
	var ok := false
	for e in DB.jokers():
		if String(e["id"]) == id:
			ok = DB.replay_valued(e)      # 判据只此一份(core/db.gd), validate_sim 用的同一个
			break
	_replay_ok[id] = ok
	return ok


func _prior_ev(id: String) -> float:
	var m: Dictionary = EV.get("measured", {})
	if m.has(id):
		return float(m[id])
	if _prior_median < 0.0:
		var vals: Array = m.values()
		vals.sort()
		_prior_median = 0.0 if vals.is_empty() else float(vals[vals.size() / 2])
	return _prior_median


func _card_ev_replay(id: String, st: Dictionary, slots: Array) -> float:
	var prior := _prior_ev(id)
	var hist: Array = st.get("hist", [])
	if hist.is_empty():
		return prior
	# 已持有 ⇒ 边际 = 拿掉它少多少;候选 ⇒ 装进第一个空支援槽, 满槽时**追加**一格 ——
	# 量的是「多一张它」的边际, 换掉谁归 `_draft` 的比价(它减 weak_ev)。
	var with_slots: Array = slots.duplicate()
	var without: Array = slots.duplicate()
	var held := -1
	for i in range(1, slots.size()):
		if slots[i] != null and String(slots[i].id) == id:
			held = i
	if held >= 0:
		without[held] = null
	else:
		var cand := Joker.by_id(id)
		if cand == null:
			return prior
		var k := Joker.first_free_support(with_slots)
		if k >= 0:
			with_slots[k] = cand
		else:
			with_slots.append(cand)
	var bw: float = float(EV["blend_w"])
	var n: float = maxf(1.0, float(st["n"]))
	var score_mean: float = (float(st["score"]) + float(EV["score_prior"]) * bw) / (n + bw)
	var coin_val: float = float(EV["coin_score_ratio"]) * score_mean
	var sum := 0.0
	for h in hist:
		var a: Dictionary = Settle.run(h["res"], with_slots, h["ctx"])
		var b: Dictionary = Settle.run(h["res"], without, h["ctx"])
		sum += float(a["score"]) - float(b["score"]) \
			+ (float(a["coins"]) - float(b["coins"])) * coin_val
	return (sum + bw * prior) / (float(hist.size()) + bw)


func _card_ev_formula(id: String, st: Dictionary, slots: Array, phrases_left: int) -> float:
	var bw: float = float(EV["blend_w"])
	var n: float = maxf(1.0, float(st["n"]))
	var mult_mean: float = (float(st["mult"]) + float(EV["mult_prior"]) * bw) / (n + bw)
	var score_mean: float = (float(st["score"]) + float(EV["score_prior"]) * bw) / (n + bw)
	var coin_val: float = float(EV["coin_score_ratio"]) * score_mean
	var future := float(phrases_left)
	var gh: float = float(EV["growth_horizon"])
	var p: Dictionary = EV["cards"].get(id, {})
	# ⚑ 2026-09-04 起这里只剩**重放量不到**的卡(成长/衰减/计数器/持有/概率/货架);
	# 效果卡全部走 `_card_ev_replay`。16 条早已转生/删除的卡的死臂同日清掉
	# (advance/chorus/opener/popup/superwild/trim/…)。
	match id:
		"vinyl":   # low prior: growth must be earned by measured discards
			return _rate(st, String(p["rate"]), float(p["prior"])) * _amt(id) * (future * gh) * mult_mean
		"momentum":
			return _rate(st, String(p["rate"]), float(p["prior"])) * _amt(id) * (future * gh) * score_mean
		"glowstick":
			return _glow_avg() * score_mean * minf(future, float(EV["glowstick_horizon"])) \
				/ float(EV["glowstick_horizon"])
		"bassline":
			# 步长从 jokers.json 推导(不许手抄第二份 —— 12 弃/档时代这里就是抄死的 12.0,
			# 2026-08-25 提速到 8 弃/档时被抓)。
			var bl_step := 8.0
			for e in DB.jokers():
				if String(e["id"]) == id:
					bl_step = float(e["effects"][0]["do"].get("step", bl_step))
			return _amt(id) * (_rate(st, String(p["rate"]), float(p["prior"])) * future * gh / bl_step) * score_mean
		# ---- 2026-08-13 子波 3:商店成长族。成长挂**付费动作**(A4✓), 所以价值
		# = 一局预期发生几次 × 每次数额 × 到那时还剩多少拍(growth 的老口径)。----
		"digger", "collector":
			return _amt(id) * float(p["events"]) * (future * gh) * mult_mean
		"rebrand":
			return _amt(id) * float(p["events"]) * (future * gh) * score_mean
		"perkeo":
			# ⚑ 帕奇欧(2026-08-30 补):离店复制一张消耗牌 ⇒ 价值 = 每局离店次数 ×
			# 一张消耗牌的均值。⚠ 加卡当天**没接这条臂**, warning 一直在打印
			# (「_card_ev 缺臂:'perkeo' 估值恒 0」)而我一直没看 ——
			# 注释里就写着「快闪就这么隐身了一周」, **同一个坑又踩一次**。
			# ⇒ 每局 7 次商店 × 栏位有空的概率(约半数)× 一张消耗牌的单次价值(≈200 分)
			return float(p["events"]) * float(p["value"]) * gh
		"freeze":
			# 早锁脉冲(计数器, 装卡当拍未武装):先验触发率 × 比例 × 均分。
			# ⚠ 触发率是 bot 打法的先验, 不是真人 —— 定价锚仍是 Tape。
			return float(p["fixed_rate"]) * _amt(id) * score_mean
		"skint":
			# 常驻 ×1.3 **减去金币上限的代价**。
			# ⚠⚠ 第一版只写了上面那半句(`_amt(id) * score_mean`), 于是 bot **100% 买它**,
			# 买完经济锁死在 cap —— `gate.sh` 的单调性哨兵当场红:
			# 「起始金币 +3 应该变容易, 实际 −0.00 段」。**多给的钱进不了口袋, 哨兵是对的。**
			# 代价的口径:上限没收的是**购买力** —— 本局本来会攒到的持币(实测局末
			# 34.7◆, S9)减去 cap, 按 bot 自己的金币折分率计价, 再按「还剩多少局面花它」
			# 折现(与 `lam` 的 horizon 折现同一个道理:钱的价值在于还能买到多少分)。
			# ⚠ 2026-09-04:它的 evbook 读数(112.4)曾被 evsync 当地板导入, 盖过这条负 EV
			# ⇒ 装机率 43% 而 lift −13pt。cf 备注早写着「hold 卡本尺不适用」, evsync 现在听了。
			var cap := 0.0
			for e in DB.jokers():
				if String(e["id"]) == id:
					cap = float(e.get("hold", {}).get("coin_cap", 0))
			var span: float = float(GameConfig.SECTIONS_PER_RUN
				* GameConfig.PHRASES_PER_SECTION)
			var forgone: float = maxf(0.0, float(p["hoard"]) - cap) * (future / maxf(1.0, span))
			return _amt(id) * score_mean - forgone * coin_val
		# ---- 2026-08-25 对抗批·波2(docs/design/versus.md):乘法出口里的成长两张。----
		"fastforward":      # 每次提前收工 ×+0.1 永久:早收率 × 成长视野
			return _rate(st, String(p["rate"]), float(p["prior"])) * _amt(id) * (future * gh) * score_mean
		"deejay":           # 每次进店 ×+0.05 永久:预期进店次数 × 成长视野
			return _amt(id) * float(p["events"]) * (future * gh) * score_mean
		# ---- 2026-08-25 波3:合奏/赌具组。先验为设计估值, kit/price 后归仪器。----
		"ensemble":         # 八选五的期望增益, 平摊成均分比例
			return float(p["gain"]) * score_mean
		"allin":            # EV=×1.25, 方差是产品
			return float(p["gain"]) * score_mean
		"loadeddice":       # 概率放大器:强度 = 场上赌卡数
			var gambles := 0
			for j2 in slots:
				if j2 != null and j2.chance_rolls_needed() > 0:
					gambles += 1
			return float(p["gain_per_gamble"]) * float(gambles) * score_mean
		"gueststar":        # 租赁:超额数值 × 只活一段的折价
			return _amt(id) * score_mean * float(p["rental"])
		"matador":          # 斗牛士:被咬率 × 每口的◆(数额从 hold 读, 不手抄)
			var mt_coins := 0.0
			for e in DB.jokers():
				if String(e["id"]) == id:
					mt_coins = float(e.get("hold", {}).get("face_coins", 0))
			return float(p["bites_per_beat"]) * mt_coins * coin_val
	# ⚠ 落到这里 = 这张卡在 bot 眼里**一文不值**, 永远不买 ⇒ 尺子里从不存在(2026-08-21 评审:
	# 快闪就这么隐身了一周)。shop/coin 通路的卡本就不走这条(求解器/货架臂各有去处);
	# score/solver 通路缺臂就响一声 —— 但只响一次, 别把 sim 日志灌满。
	if not _no_arm_warned.has(id):
		_no_arm_warned[id] = true
		push_warning("[bot] _card_ev 缺臂: '%s' 估值恒 0, 这张卡在尺子里永远不会被买" % id)
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


## ⚠ `cache` / `done_phrases` 是 2026-08-08 为**求解买牌**加的(docs/design/solving.md 第三部分), 默认值维持原行为。
## 求解版只在 `cfg["solve_draft"]` 打开时启用 —— **规则 bot 永久保留手写表当回归基线**
## (`docs/design/history_parametric.md` 的既有决定), 而且它跑 9000 局, 换上去会慢一个量级。
func _draft(slots: Array, cfg: Dictionary, deck: Deck, coins: int, st: Dictionary, phrases_left: int, section: int, faces: Dictionary = {}, cache: Array = [], done_phrases: int = 0, run = null) -> int:
	# ⚑ 消耗牌先处理(2026-08-29)。**必须在开头** —— `_draft` 后面有多个
	# `return coins`(买到卡就返回), 放末尾等于只有「什么都没买」时才执行:
	# 实测买入 0.15 张/局、使用 0.07, 这一层几乎不存在。
	# ⚠ 同族形状:kit 的 UNREACHABLE 分支、shop 的 for-else 空转 —— **多出口函数里
	# 追加的代码, 默认是不可达的**, 除非你数过每一个 return。
	# ⚠ 「本店」类授予每店清零 —— 忘了清就把一次性效果做成了永久 buff,
	# 而那正是这些牌当初该被挪出小丑牌的理由(见 view/shop.gd::close 同款)。
	_g_shelf = 0
	_g_extra_buys = 0
	_g_price = 0
	_g_free_reroll = 0
	_cfg_no_cons = bool(cfg.get("no_consumables", false))
	# 挑高:保证期 = **整次进店**(含刷新)⇒ 上一次进店的残留在这里清掉,
	# 本次进店用掉它才重新点亮(`_apply_bot_action`)。与游戏侧 `Shop.open()` 同刻。
	_g_min_rarity = ""
	_cons_bought = false
	# ⚑⚑ **进店事件**(2026-09-03)——与游戏侧 `view/phrase.gd::_open_draft` **成对**。
	# ⚠ 发在任何购买之前, 两侧同刻;漏一侧 = 「规则在游戏里、不在模型里」第八次。
	Joker.notify_shop(slots, "enter")
	# ⚑⚑ **钉卡臂的商店类消耗牌要在 reset 之后补**(2026-09-03)。
	#
	# 病根:`kit.gd` 在 `on_begin`(**每拍开头**)注入钉住的消耗牌并就地执行 action,
	# 而「本店」类授予在**进店这一刻**被上面那几行清零 ⇒ 时序是
	# 「拍首给 → 打完这拍 → 进店擦掉 → 商店没有授予地跑」。
	# ⇒ **商店类消耗牌在 kit 里永远不可能生效**, 五张全部报 `0.0 ±0.0`
	#   (doublebill / sponsor / encorecall / highroller / advance),
	#   而 anvil(改构筑, 立即生效)与 perkeo(离店触发)不走这条路, 所以它们是好的。
	# ⚠ 上面那段 reset **是对的** —— 真实对局里授予产生于**店内**, 在 reset 之后。
	#   错的是注入时机, 所以修在这里(补一次), 不是把 reset 删掉。
	# ⚠ 只补**本店类**的六个键 —— 牌堆类(wilds/trim)与构筑类(anvil)已在拍首生效过,
	#   在这里再执行一遍等于每店复利一次。**「每拍补满」是钉卡臂的语义, 不是叠加。**
	for cid in _pinned_cons:
		for e in DB.consumables():
			if String(e["id"]) != String(cid):
				continue
			var act: Dictionary = e.get("action", {})
			var shop_act := {}
			for k in ["shelf_slots", "extra_buys", "price_delta",
					"rule_guaranteed", "free_reroll", "min_rarity"]:
				if act.has(k):
					shop_act[k] = act[k]
			if not shop_act.is_empty():
				_apply_bot_action(run, slots, {"id": String(cid), "action": shop_act})
			break
	coins = _consumables_in_shop(run, coins, slots)
	var want := "target" if slots[0] == null else "support"
	var owned: Array = []
	for j in slots:
		if j != null:
			owned.append(j.id)
	# Target 回池(2026-08-06 用户拍板):首张免费三选一是唯一特例, 之后 Target 与
	# Support **同池**按稀有度抽 —— 换旗的专属骰子(chance/from_section)已删。
	# ⚠ 强制 target 的队列不许换旗(除非 cfg.pivot):`cfg.target` 是**实验者的随机分配**,
	# 是整条 pipeline 唯一干净的因果通道(docs/design/solver_roadmap.md), 让 bot 自己换掉就没了。
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
		for cj in candidates:
			_rep.cov_offer(String(cj.id))
		_rep.cov_install(String(pick.id))
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
	# ⚑ 2026-09-04 起系数是 **coin_cost_ratio**(成本侧), 与产币卡估值用的 coin_score_ratio
	# (价值侧)分开 —— 同一个数用两处的后果见 sim.json `_comment_coin_cost_ratio`。
	var lam: float = float(EV["coin_cost_ratio"]) * score_mean \
		* pow(horizon / DRAFT_HORIZON, float(EV["coin_decay"]))
	# 货架位数与两个「必定出」补丁 —— **与 view/shop.gd::_deal 同一套规则**(shelf API 收口)。
	var _shelf_n: int = maxi(Joker.slots_shelf_size(slots), _g_shelf)
	var offer := _weighted_pick(candidates, _shelf_n,
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
	# ⚠⚠ **「必定出规则牌」的两段货架补丁已删(2026-08-30 二批转生)** ——
	# 规则牌(近道/四指/黑调/红调)全部转生为消耗牌, 而它们是**仅有的**带 `acquire`
	# 的小丑牌 ⇒ 这两段在小丑牌货架上**永远找不到目标, 静默什么都不做**。
	# 点唱机的目标已搬到**消耗牌位**(见 `_consumables_in_shop` 的 `_g_rule`),
	# 与游戏侧 `view/phrase.gd::_roll_consumable` 同一份语义。
	# 挑高(消耗牌):**这次商店**不再出普通卡, **含刷新** —— 与游戏侧同义。
	# ⚠⚠ 2026-08-30 用户改判:旧版只管下一次发牌, 而「用户宁愿走刷新」⇒ 买了不如不买。
	# 清零挪到进店(`_draft` 开头), 刷新处重放同一份过滤器。
	offer = _rich_only(offer, candidates)
	# 商店行为臂的证物记账(kit `shop` 通路):每店一记。
	# ⚠ 「首发货架含规则牌」那一记**已改口径** —— 规则牌 2026-08-30 全部转生为消耗牌,
	# 小丑牌货架上永远不会再有 ⇒ 证物改记「消耗牌位出规则牌的店数」(见 `_consumables_in_shop`)。
	_rep.shops_n += 1
	# 覆盖账本的第一道闸门:这张卡**上过货架**。记在补丁全部生效之后 ——
	# 量的是玩家真正看见的那三张, 不是抽出来又被顶掉的那张。
	for oj in offer:
		_rep.cov_offer(String(oj.id))
	# 挑高的零基线证物:**首发货架一张普通卡都没有**的店数。
	# ⚠ 记在补丁全部生效之后 —— 量的就是玩家看见的那三张。
	var _commons := 0
	for oj3 in offer:
		if oj3.rarity == "common":
			_commons += 1
	if _commons == 0 and not offer.is_empty():
		_rep.rich_shelves += 1
	# 换旗:货架上**真的抽到** Target 时才发生(不再有专属骰子), 买入顶掉旧的、无回收。
	for tj in offer:
		if tj.kind != "target":
			continue
		var tprice := _price_now(tj, slots)
		if coins < tprice:
			break
		var mm: float = (float(st["mult"]) + float(EV["mult_prior"]) * bw) \
			/ (maxf(1.0, float(st["n"])) + bw)
		var base_mean: float = score_mean / maxf(1.0, mm)
		var gain: float = (float(COUNTERFACTUAL_TV.get(tj.id, 1.0))
			- float(COUNTERFACTUAL_TV.get(String(slots[0].id), 1.0))) * base_mean
		# ⚑⚑ **换旗动作本身的回报**(2026-08-29):上面那行只算「新旗比旧旗好多少」,
		# 而转型这类卡奖励的是**换这个动作**, 与两面旗谁强无关。漏了它, bot 换到
		# 最优旗之后就永远不再换(实测 0.88 次/局)⇒ **「反复换旗」这条打法在 sim 里
		# 根本不存在**, 于是无论设计侧怎么加卡都量不出来。
		# ⚠ 是永久加成 ⇒ 乘 horizon(剩余拍数), 与 gain 同尺度。
		for sj in slots:
			if sj != null:
				gain += sj.swap_bonus_pct() * base_mean
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
		# ⚑ 换旗的**净**成本 = 新旗价 − 旧旗折半回收(2026-08-29 对齐游戏侧)。
		# 游戏侧 `view/phrase.gd` 08-27 就补上了这笔回收(真人报「target 无法替换
		# 老 target」时查出的规则不一致), 而这里一直按**全价**判门槛、且换完不退钱
		# —— 「规则在游戏里、不在模型里」的**第六次**。后果不是差几个金币:
		# 门槛高 50% ⇒ 实测换旗只有 0.88 次/局 ⇒ **转型(每次换旗 +40%)这张
		# 换旗打法的核心卡拿不到燃料**, 于是 sim 量出「灵活打法不值钱」的假结论。
		var trefund: int = Economy.sell_value(slots[0]) if slots[0] != null else 0
		if gain * horizon > lam * float(tprice - trefund) * hyst:
			var coins_before_pivot := coins
			coins -= tprice
			# 与游戏侧同序:先发事件(收藏家/转型), 再装卡 —— 新旗不给自己记一次。
			Joker.notify_shop(slots, "buy")
			if slots[0] != null:
				Joker.notify_shop(slots, "target_swap")
				if trefund > 0:
					coins = Economy.grant(coins, trefund, slots)
			slots[0] = tj
			tj.on_acquire(deck)
			_rep.cov_install(String(tj.id))
			coins = Economy.cap_held(coins, slots)     # 装卡后修剪(同编排器)
			# 经济账本:买卡净支出 = 成交前后余额差(含上限修剪;旁路, 不动决策)。
			_rep.eco_add("spend_buy", coins_before_pivot - coins)
			_rep.pivots_n += 1
			# 分列口径:这次换旗时手上有没有「奖励换旗」的卡(转型 …)。
			for hj in slots:
				if hj != null and hj.swap_bonus_pct() > 0.0:
					_rep.pivots_held += 1
					break
			_rep.buys_total += 1
			_rep.discount_coins += maxi(0, Economy.joker_price(tj, true) - tprice)
			# ⚑⚑ 换旗**不再离店**(2026-08-29,与游戏侧同改):换旗占掉当店唯一成交名额
			# 会让「奖励换旗的卡」和「换旗」互斥 —— 实测持有转型的局换旗 0.65 次 <
			# 未持有的 0.94 次, 拿着奖励卡的人反而换得少。换旗是路线决策, 不是囤货,
			# 名额该留给买卡。⇒ 换完继续走下面的买卡循环。
			break
		break
	# 联票:一次进店最多成交 `基础名额 + 联票给的额外张数`(限额随槽位实时读)。
	# ⚑⚑ **2026-09-02 由取大改成加法**(与游戏侧同改, 完整口径见
	# `view/shop.gd::granted_extra_buys`):取大时联票买掉的正是它要给的那次成交 ⇒
	# 净得 0 张、净亏 3◆。加法之后 = 1 + 2 = 3 次, 联票占第 1 次 ⇒ 还能再买 2 张。
	# 两轮尝试的语义不变:第一轮什么都没买才允许一次付费刷新。
	# ⚑ 5 选 1:消耗牌与小丑牌**共用成交名额**(见 `_cons_bought` 的注释)。
	var buys := 1 if _cons_bought else 0
	for attempt in range(2):
		# ⚑⚑ **名额要在挑之前查, 不是买完之后**(2026-09-03)。
		#
		# 下面那处 `if buys >= 上限: return` 在 `buys += 1` **之后** —— 没有联票时
		# 上限是 1, 而买过消耗牌的店 `buys` 从 1 起步 ⇒ bot **照样再买一张小丑牌**,
		# 然后才发现超额。**游戏给 1 次成交, 模型给自己 2 次。**
		# 「5 选 1」是 2026-08-31 用户拍的板, 游戏侧 `view/phrase.gd::_on_consumable_bought`
		# 是**买之前**判的(`if _shop_buys < buy_limit` 才继续), 两侧从那天起就对不上。
		# ⚠ 后果不是少算一点:bot 的构筑系统性地比真人厚, 而**目标分正是拿它标的**。
		# ⚑ 照出它的是 kit 的一行基准 ——「双购店 1.92/局」, 而那条证物的注释写着
		#   「无联票在手时物理不可能, 基准≈0」。**注释和读数打架时, 读数赢。**
		if buys >= Joker.slots_buy_limit(slots) + _g_extra_buys:
			return coins
		# 规则在 `Joker.first_free_support`(唯一真相, 2026-08-16 收口)。
		# ⚑ bot 这一份**本来就是对的**(只看 1..3), 错的是 `view/shop.gd`——
		# 这次是「规则在模型里、不在游戏里」, 与此前五次方向相反。
		var empty_slot := Joker.first_free_support(slots)
		var best = null
		var best_gain := 0.0
		var best_cost := 0
		# ⚑ `cfg.prefer` —— 实验者指定的**优先买**清单(2026-08-30)。
		# 用途:强制 bot 试用那些「从没进过赢局」的卡, 分辨两件事 ——
		#   **它真的弱**(用了也赢不了) vs **只是 bot 的估值看不见它**(用了就能赢)。
		# ⚠ 这是**实验者的随机分配**, 与 `cfg.target` 同性质:它是干净的因果通道,
		# 不能让 bot 自己的偏好污染。所以只加一条「买得起就优先」, 不改 EV 计算。
		var prefer: Array = cfg.get("prefer", [])
		if not prefer.is_empty():
			for j in offer:
				if j.kind != "target" and prefer.has(String(j.id)) \
						and coins >= _price_now(j, slots) and slots.has(null):
					best = j
					best_gain = 1e9      # 压过一切正常比价
					best_cost = _price_now(j, slots)
					break
		# 满槽时「换掉谁」只算一次:槽位在候选循环里不变, 逐候选重算是白跑三张卡的估值
		# (重放估值下 = 3 张 × 24 拍 × 2 次结算, 2026-09-04)。
		var weak_k := 1
		var weak_ev := 1.0e18
		var refund := 0
		if empty_slot < 0:
			for k2 in range(1, slots.size()):
				var oe := _card_ev(slots[k2].id, st, slots, phrases_left)
				if oe < weak_ev:
					weak_ev = oe
					weak_k = k2
			refund = Economy.sell_value(slots[weak_k])
		for j in offer:
			# Target 回池后货架里可能混着 Target, 它走上面那段换旗路径(顶掉槽 0),
			# 不参与 support 的装槽/替换比价。⚠ 不显式跳过的话,
			# `joker_price(j)` 少传 has_target 会把它算成**免费**。
			if j.kind == "target":
				continue
			var price := _price_now(j, slots)
			# 预支风控:欠债时买入预算扣掉段末还款储备 —— runloop 段末自动扣款,
			# bot 把还款钱花掉 = 自己判自己死。
			# ⚠ 2026-08-30 三批转生:读的是 `run.debt`(消耗牌记下的待还), 不再是持仓。
			# 买不起的候选**先跳过再估值**(估值有成本;判据不变, 它们本来也进不了比价)。
			var reserve := 0 if run == null else int(run.debt)
			if empty_slot >= 0 and price > coins - reserve:
				continue
			if empty_slot < 0 and price > coins + refund:
				continue
			# ⚑ 求解买牌(docs/design/solving.md 第三部分):不查手写表, 直接**在已知的脸序列下算边际价值**。
			# 前提是「四段的脸开局全可见」(docs/design/solving.md §2.2)—— 用户 2026-08-08:
			# 「没有脸信息就没有选牌策略」。
			# ⚠ 量纲:card_value 给的是 M 拍的**总分差**, 而下面按「每拍 EV × horizon」算,
			# 所以要除以 M。除错了不会报错, 只会让买牌整体变贵或变便宜。
			var ev: float
			if solve_draft and run != null:
				var k_rep: int = -1 if empty_slot >= 0 else _weakest_slot(slots, st)
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
				var gain := ev * horizon - lam * float(price)
				if gain > best_gain:
					best_gain = gain
					best = j
					best_cost = price
			else:
				# replace: candidate must beat the weakest owned card by enough
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
			var coins_before_buy := coins
			if empty_slot >= 0:
				coins -= best_cost
				Joker.notify_shop(slots, "buy")            # 收藏家(装卡前, 同编排器)
				slots[empty_slot] = best
				best.on_acquire(deck)
				coins = Economy.cap_held(coins, slots)     # 装卡后修剪(同编排器)
				_rep.support_drafted[best.id] = int(_rep.support_drafted.get(best.id, 0)) + 1
				_rep.cov_install(String(best.id))
			else:
				# 换掉的就是比价时那张最弱的(候选循环外算好的 weak_k, 槽位中途没变)。
				coins = Economy.grant(coins, Economy.sell_value(slots[weak_k]), slots) \
					- _price_now(best, slots)
				Joker.notify_shop(slots, "buy")            # 替换也是一次购买(同编排器)
				slots[weak_k] = best
				best.on_acquire(deck)
				coins = Economy.cap_held(coins, slots)     # 装卡后修剪(同编排器)
				_rep.support_drafted[best.id] = int(_rep.support_drafted.get(best.id, 0)) + 1
				_rep.cov_install(String(best.id))
			# 经济账本:买卡净支出 = 成交前后余额差(替换含回收抵扣与上限修剪)。
			_rep.eco_add("spend_buy", coins_before_buy - coins)
			buys += 1
			_rep.buys_total += 1
			if buys >= 2:
				_rep.multi_shops_n += 1        # 双购店:联票的零基线证物
			_rep.discount_coins += maxi(0,
				Economy.joker_price(best) - _price_now(best, slots))
			# 联票:限额未满 → 同一货架摘掉已购的那张继续挑(与 view/phrase.gd 的
			# sold 流程同构;不重掷 —— 重掷就成了免费刷新)。
			if buys >= Joker.slots_buy_limit(slots) + _g_extra_buys:
				return coins
			offer.erase(best)
			continue
		# nothing worth buying: one paid reroll if rich, else just walk away
		# (2026-08-06: leaving the shop pays nothing — the skip reward is gone)
		var _rr_free: bool = _g_free_reroll > 0
		if attempt == 0 and buys == 0 \
				and (_rr_free or coins >= Economy.reroll_cost(0) + 6):
			if _rr_free:
				_g_free_reroll -= 1          # 加急(消耗牌):免费刷新一次
				_rep.free_rerolls += 1       # 零基线证物:没有加急时恒 0
			else:
				coins -= Economy.reroll_cost(0)
				_rep.eco_add("spend_reroll", Economy.reroll_cost(0))   # 经济账本:付费刷新
			Joker.notify_shop(slots, "reroll")             # 淘碟(同编排器)
			# ⚠ 刷新后只重掷, 不重放「必定出 Target」那个补丁(既有保真缺口, 不扩大);
			# ⚑ **但挑高要重放** —— 它的保证期是整次进店(含刷新), 不重放就等于
			# 「刷一次就失效」, 而那正是它输给「直接刷新」的原因(用户 2026-08-30 改判)。
			offer = _rich_only(
				_weighted_pick(candidates, Joker.slots_shelf_size(slots)), candidates)
			for oj2 in offer:
				_rep.cov_offer(String(oj2.id))
			continue
		break
	return coins


## ⚑ 消耗牌:买 + 在商店里用(2026-08-29 开轴时同批接进 bot)。
##
## ⚠ **不接就等于这一层不存在** —— 转生当天实测:消耗牌在 sim 里使用率 **0%**,
## 「多少卡没进赢局」的比例因此**一动不动**(35% → 35%), 绝对数从 50 掉到 45
## 也只是分母变小(把最不容易进赢局的 9 张挪走了)。**问题跟着搬家, 没被解决。**
## ⇒ 用户 2026-08-29:「需要升级下机器人, 让他看到这几张必须用, 试试胜率」。
##
## 策略刻意简单(**先让它会用, 不追求最优**):
##   买 —— 栏位有空 + 买得起 + 买完还剩得下下一次刷新的钱
##   用 —— shop 类进店就用(一次性, 攒着没有额外价值);
##         phrase 类留给拍内决策(见 `_consumable_in_beat`)
## 挑高的过滤器 —— **首发与刷新共用这一份**(各写一遍就是「两个家」)。
## 语义:把货架里的普通卡换成非普通卡;换不满就整份放弃(宁可不生效, 不给半份)。
func _rich_only(offer: Array, candidates: Array) -> Array:
	if _g_min_rarity == "":
		return offer
	var rich: Array = []
	for j in offer:
		if j.rarity != "common":
			rich.append(j)
	if rich.size() >= offer.size():
		return offer
	for j in candidates:
		if rich.size() >= offer.size():
			break
		if j.rarity != "common" and not rich.has(j):
			rich.append(j)
	return rich if rich.size() == offer.size() else offer


## 本店实价 —— **唯一真相**:所有比价/成交都走它, 别散着调 `Economy.shelf_price`。
## 赞助(消耗牌)的本店降价叠在这里, 地板 1◆(免费只属于首张 Target 那个特例, 与游戏侧同)。
func _price_now(j, slots: Array) -> int:
	var base := Economy.shelf_price(j, slots)
	return base if base <= 0 else maxi(1, base + _g_price)


## 本店授予(消耗牌的商店类 action)。**与 `view/shop.gd` 的 `_grant_*` 同名同义** ——
## 2026-08-30 逐键核对发现这 6 个键**只在游戏侧实现**, bot 会买、会「用掉」,
## 但用了什么都不发生 ⇒ 我用那份读数给它们定的 8◆ 是**在「它们是空白卡」的世界里量的**。
## ⚠ 每店开头清零 —— 「本店」类就是一次性。
var _g_shelf := 0
var _g_extra_buys := 0
## ⚑ 钉卡臂(kit)钉住的消耗牌 id —— **只给探针用**, 正常对局恒空。
## 商店类的授予要在进店 reset **之后**补一次, 理由见 `_draft` 里那段注释。
var _pinned_cons: Array = []
## 待领的预支借款 —— `_apply_bot_action` 记账, 调用点用 `_take_borrow()` 就近兑现。
## ⚠ 必须**每个**调用点都兑现, 漏一个就是「借了但钱没到」, 而那不报错。
var _pending_borrow := 0


## 领走待领借款并清零。⚠ 走 `Economy.grant` 收口(要吃穷开心的 coin_cap, 同游戏侧)。
func _take_borrow(coins: int, slots: Array) -> int:
	if _pending_borrow == 0:
		return coins
	var got := _pending_borrow
	_pending_borrow = 0
	return Economy.grant(coins, got, slots)
var _g_price := 0
var _cfg_no_cons := false      # cfg.no_consumables 的缓存(拍内烧牌也要读)
var _g_rule := false
var _g_free_reroll := 0
var _g_min_rarity := ""
## ⚑⚑ **5 选 1**(2026-08-31):3 小丑 + 2 消耗是同一个池子, 一次进店只成交 1 张。
## ⇒ 买了消耗牌就**占掉小丑牌那次购买** —— 分开数等于又给了消耗牌一个专属名额。
var _cons_bought := false


func _consumables_in_shop(run, coins: int, slots: Array) -> int:
	if run == null:
		return coins
	# ⚑ `cfg.no_consumables` —— 对照组开关(2026-08-30 用户问「sim 要不要因为新卡更新」)。
	# ⚠ 现有的 `no_jokers` 是**关掉整个商店**实现的, 连消耗牌一起没了 ⇒ 隔离不出这一层。
	# 有了它才答得了「消耗牌这一层值多少」—— 与 `baseline(no jokers)` 之于小丑牌同理。
	if bool(_cfg_no_cons):
		return coins
	# ⚑⚑ **「先用掉手上的」整段已删(2026-09-01)** —— 消耗牌全部自动触发之后,
	# 离店那一刻手上**不可能有商店类的卡**(`fire: "buy"` 买下即执行, 根本不进队列)。
	# 队列里只剩时机卡, 而它们等的是拍号, 不是商店。
	# ② 帕奇欧:离店时复制一张消耗牌 —— **与游戏侧 `_perkeo_on_exit` 对齐**。
	# ⚠ 2026-08-30 补:开轴当天只接了游戏侧, bot 侧漏了 ⇒ sim 里帕奇欧是**纯废卡**
	# (rare, 占一个槽, 什么也不做), bot 算出价值 0、永不购买, 这张牌永远进不了读数。
	# 「规则在游戏里、不在模型里」的**第七次**。
	# ⚠ 队列没有上限了 ⇒ 摘掉 `consumable_room()` 这道门。
	# ⚑ 射程同时变窄:能被复制的只剩时机卡(与游戏侧 `_perkeo_on_exit` 同一句注释)。
	if Joker.slots_copy_consumable(slots):
		var src: Array = run.consumables.duplicate()
		if not src.is_empty():
			var pk = src[_rng.randi_range(0, src.size() - 1)]   # bot 侧用自己的 rng(探针复现)
			for e in DB.consumables():
				if String(e["id"]) == pk.id:
					var used2: Dictionary = run.take_consumable(Consumable.new(e))
					if not used2.is_empty():
						_apply_bot_action(run, slots, used2)
						coins = _take_borrow(coins, slots)   # 帕奇欧复制到预支时
					_rep.cov_install(String(e["id"]))
					_rep.perkeo_copies += 1    # 零基线证物:没有帕奇欧时恒 0(kit SHOP_WITNESS)
					break
	# ③ 再买 —— 一店最多一张(与游戏侧「货架只出一张」同构)
	# ⚑ 货架 **2 格**(2026-08-31, 与游戏侧 `_roll_consumables` 同一份语义):
	# 掷两张互不重复的, **最多成交一张**(「2 选 1」, 供给不变、选择变多)。
	# ⚠ bot 的挑法刻意简单:买得起的里面挑**贵的那张**(价格是我们唯一的强度代理,
	# 而消耗牌的 EV 尺 `ccf.gd` 还没覆盖全池)。**先让它会选, 不追求最优。**
	var held := {}
	for c in run.consumables:
		if c != null:
			held[c.id] = true
	var pool: Array = []
	for e in DB.consumables():
		if not held.has(String(e["id"])):
			pool.append(e)
	var offer2: Array = []
	for i2 in range(2):
		if pool.is_empty():
			break
		var use := pool
		if i2 == 0 and _g_rule:
			_g_rule = false
			var rp: Array = []
			for e in pool:
				if Consumable.new(e).is_rule_card():
					rp.append(e)
			if not rp.is_empty():
				use = rp
		var picked = use[_rng.randi_range(0, use.size() - 1)]
		offer2.append(picked)
		pool.erase(picked)
	if offer2.is_empty():
		return coins
	var best = null
	for e in offer2:
		var c2 := Consumable.new(e)
		_rep.cov_offer(String(c2.id))          # 两张都算上架
		if c2.is_rule_card():
			_rep.rule_shops_n += 1
		# ⚠ 欠债时留出还款储备(与买卡同一条风控) —— 段末付不起 = run 死。
		if coins < c2.price + 3 + int(run.debt):
			continue
		if best == null or c2.price > best.price:
			best = c2
	if best == null:
		return coins
	coins -= best.price
	# ⚑ 买下即触发(2026-09-01):`fire: "buy"` 的直接返回它的 action, 就地执行;
	# 时机卡返回空字典 = 它排队去了。⚠ 预支的借款要改**本地 coins**, 所以在这里结算。
	var bought: Dictionary = run.take_consumable(best)
	if not bought.is_empty():
		_apply_bot_action(run, slots, bought)
		# ⚑ 预支已收口进 `_apply_bot_action`(上面那次调用就记了账), 这里只兑现 ——
		# **同一件事不许有第二套机制**, 而这里原本就是那第二套。
		coins = _take_borrow(coins, slots)
		_rep.consumables_used += 1
	_rep.cov_install(String(best.id))
	_rep.eco_add("spend_buy", best.price)
	_rep.consumables_bought += 1
	_cons_bought = true          # 占掉这次进店的成交名额(5 选 1)
	return coins


## ⚑⚑ **不再是决策, 是到点自动打**(2026-09-01 用户拍板:消耗牌全部自动触发)。
## 原来这里有一条「只在段末两拍考虑、差得越多越该烧」的启发式 —— 那条臂**整个删了**,
## 因为「烧在哪一拍」这个决策本身没有了。⇒ 模型侧因此比游戏侧更简单, 而且两侧
## **共用同一份判据**(`Run.age_consumables` + `due_consumables`), 不再各写一套。
## ⚠ 顺序与游戏侧一致:先推进年龄, 再取到期的 —— 反了「下一拍」就永远等不到。
func _consumable_in_beat(run, p, section: int, pidx: int) -> void:
	if run == null or _cfg_no_cons:
		return
	run.age_consumables()
	for used in run.due_consumables(pidx + 1):
		_apply_bot_action(run, run.joker_slots, used)
		# 拍内的金币容器是 `p.coins`(与 core/beat.gd 同一份)。
		p.coins = _take_borrow(p.coins, run.joker_slots)
		_rep.consumables_used += 1



## 消耗牌的立即动作在 bot 侧的执行。⚠ 只做**模型看得见**的那几种:
## 牌堆类(注入万能/移除低牌)与构筑类(砧座)真的改状态;
## 商店类(4选2/降价/必出规则牌)在 bot 的一次性货架里没有对应物, 记账但不改 ——
## **这是已知的保真缺口, 写在这里而不是假装它生效了**(与 reroll 不重放补丁同款处理)。
func _apply_bot_action(run, slots: Array, used: Dictionary) -> void:
	var act: Dictionary = used.get("action", {})
	# ⚑⚑ **预支(loan)此前只在购买路径里实现, 不在这个共用口里**(2026-09-03 修)。
	# 游戏侧是在共用的 `_apply_shop_action` 里处理的(view/phrase.gd::「预支:当场借」),
	# 而 bot 侧写在 `_consumables_in_shop` 的成交分支里 ⇒ **凡是走这个共用口的路径**
	# (kit 的钉卡注入 / 拍内到点队列 / 帕奇欧复制)**借款静默不发生**。
	# 实测:`advance` 在 kit 里恒 `0.0 ±0.0`, 而同批的另外四张商店类卡修好之后都活了。
	# ⚠⚠ `parity.py` 第 ② 层**放过了它** —— 它查「"loan" 这个字符串两侧都出现过吗」,
	#   而 bot 侧确实出现过, 只是在错的地方。**静态尺查得到「有没有」, 查不到「在不在对的地方」。**
	# ⚠ 这里改不了调用方的局部 `coins`(bot 的金币是一路传下去的局部变量, `run.coins` 没人用),
	#   所以只记**待领额**, 由各调用点就近兑现(`_take_borrow`)。repay 直接进 run.debt。
	if act.has("loan"):
		var ln: Dictionary = act["loan"]
		_pending_borrow += int(ln.get("borrow", 0))
		run.debt += int(ln.get("repay", 0))
	# ---- 商店类六键(2026-08-30 补齐;此前只在游戏侧实现)----
	if act.has("shelf_slots"):
		_g_shelf = maxi(_g_shelf, int(act["shelf_slots"]))
	if act.has("extra_buys"):
		# ⚠ **累加**, 与游戏侧 `Shop.grant_shelf` 同款 —— 一店买到第二张联票要再给一次。
		_g_extra_buys += int(act["extra_buys"])
	if act.has("price_delta"):
		_g_price += int(act["price_delta"])
	if act.has("rule_guaranteed"):
		_g_rule = true
	if act.has("free_reroll"):
		_g_free_reroll += int(act["free_reroll"])
	if act.has("min_rarity"):
		_g_min_rarity = String(act["min_rarity"])
	if act.has("wilds"):
		run.deck.add_wilds(String(used["id"]), int(act["wilds"]))
	if act.has("trim_low"):
		run.deck.trim_low_ranks()
	if act.has("deck_rule"):
		# 规则牌(2026-08-30 二批转生):烙进牌堆, 与 `view/phrase.gd` 两条通路同义。
		# ⚠ 这一支是 `parity.py` 第 ② 层当场抓出来的 —— 数据里加了新 action 键,
		# 游戏侧已有而 bot 侧没有, 正是「规则在游戏里、不在模型里」那个形状。
		run.deck.rules[String(act["deck_rule"])] = true
	if act.has("copy_one_destroy_rest"):
		# 与游戏侧同:只在 support(槽 1..3)里掷 —— 留 Target 时复制无处可放。
		var owned: Array = []
		for i in range(1, slots.size()):
			if slots[i] != null:
				owned.append(i)
		if owned.size() >= 2:
			var keep: int = owned[_rng.randi_range(0, owned.size() - 1)]
			var kept = slots[keep]
			for i in range(slots.size()):
				if i != keep:
					slots[i] = null
			for i in range(1, slots.size()):
				if slots[i] == null and kept.kind == "support":
					slots[i] = Joker.by_id(kept.id)
					_rep.anvil_copies += 1     # 零基线证物:没有砧座时恒 0
					break


## 货架抽卡 —— 算法在 `Economy.weighted_pick`(**唯一真相**,2026-08-15 收口)。
## ⚠ **这个方法必须留着**:`tools/wallet.gd` 的 SpyBot 用 `super._weighted_pick(...)`
## 覆盖它来记录货架内容。收的是算法,不是这个覆盖点。
## ⚠ 传 `_rng` 而不是走全局 —— 探针要复现性,这是它与 `view/shop.gd` 唯一的正当差异。
func _weighted_pick(candidates: Array, count: int, target_mult: float = 1.0) -> Array:
	return Economy.weighted_pick(candidates, count, target_mult, _rng)


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


## 完美玩家 (docs/design/solver_roadmap.md / §5)。**没有任何手写规矩** —— 直接调数学侧的
## `Solver`, 把 8 张可见牌的最优「计分 5 / 留缓存 3」切法搬进手牌。
##
## 它存在的唯一理由是**一致性测试**:数学 D 和模拟器必须对同一个局面给出同一个答案。
## 两边共用 `Solver` + 真实 `Pattern`/`Settle`, 所以剩下的任何差异都来自
## 「枚举 vs 采样」和牌堆消耗 —— 那正是 docs/design/solver_roadmap.md 要单独验的近似。
##
## `lam` = 平衡贪心的权重(2026-08-06 用户拍板取代 DP):
##     value(切法) = 本拍得分 + lam · E[下一拍得分 | 留下的 3 张]
## lam = 0 就是单拍贪心。**lam 由 `tools/lam.gd` 扫出来, 不许拍脑袋。**
##
## v1 **不弃牌**(d = 0):弃牌的代价是跨拍的金币影子价。
## 孤立一拍地看, 最优解永远是把钱花光 —— 那是 `docs/design/history_adversarial.md` §7 警告的幻想区。
## 所以先把「切法」这一维做干净, 弃牌随后同样用影子价接进来。
##
## ⚠ 已知近似:传给 Settle 的上下文缺 prev_kind / 时机旗
## (它们在 sim 的循环里、bot 决策时还不存在)。小丑牌倍率是全的, 所以流派差异看得见;
## 「禁回」这类跨拍谓词看不见。DP 上来时要把上下文一起穿进来。
func _play_perfect(p: Phrase, slots: Array, mod: String = "",
		lam: float = 0.0, lam_samples: int = 3, section: int = 0,
		eps: float = 0.0) -> void:
	var extra := {
		"prev_kind": -99, "acted_late": false, "discards": p.discards_used,
		"coins": p.coins, "phrase_idx": 0, "mod": mod,
	}
	# ① 弃牌(2026-08-06 起**免费**, 只受手速预算限制 —— 金币影子价 κ 因此整个消失,
	#    求解器少一个要扫的参数)。弃的是「这拍用不上的那 3 张」, 计分的 5 张不动。
	# 不完全信息(盖牌脸):求解器只能按信念挑, 记账仍按真值。`blind` 是本拍
	# 玩家看不见的那几张在 visible 里的下标, `bs` 是给它们的替身采样组数。
	# 完全信息时两者都是空/0, 老路径逐位不变(tests/runner.gd 锁着)。
	var bs: int = GameConfig.BLIND_SAMPLES
	var dur := Run.phrase_duration_for(section, mod, p.phrase_idx)
	# ⚑ 动作粒度(2026-08-27, 新基线):beat_discards 现在是**动作次数**预算 ——
	# 求解器一拍只弃一批, 消耗 1 个动作;单批张数上限走 discard_batch(随拍长缩放,
	# 赶场在两层都咬得住)。旧口径把张数当动作数, 弃 6 结构性不可达(拆迁的 UNREACHABLE)。
	var d_act: int = GameConfig.beat_discards(dur, section)
	var d_cards: int = GameConfig.discard_batch(dur, section)
	if d_act > 0 and d_cards > 0:
		var vis0: Array = []
		vis0.append_array(p.hand)
		vis0.append_array(p.cache)
		if vis0.size() >= GameConfig.HAND_SIZE:
			var hid0 := p.hidden_indices(vis0)
			var subs0 := Solver.make_subs(p.deck, _rng, hid0.size(), bs,
				_known_attrs(p, vis0, hid0)) if not hid0.is_empty() else []
			# ⚠⚠ **基线必须无噪声** —— `best_discard` 的收益是
			#     `gain = mean(弃牌后, 零噪声 best_score) − base.score`。
			# 若 base 带噪声, 噪声选中次优切法时 base.score 被压低, gain 就被
			# **系统性抬高** → ε 越大越狂弃牌。那不是"噪声玩家做了略差的决定",
			# 而是一个人为偏置, 会把 ε 扫描的读数整个污染。
			# 两个口径必须一致, 这里取零噪声那一侧。
			# **建模选择(docs/design/solving.md 第二部分)**:ε 目前只建模「打哪 5 张」的决策噪声,
			# 不建模「弃不弃牌」的噪声 —— 真人两个都会错, 这是显式声明的近似。
			var b0 = Solver.best_split(vis0, slots, extra, p.deck.rules, hid0, subs0)
			if b0 != null:
				# ⚠ 暗补脸下弃牌**要按盲的算** —— 否则求解器以为弃完能看见新牌,
				# 会系统性高估弃牌, 而这张脸整个就是关于弃牌决策的。
				var blind_refill: int = bs if SectionMod.hide_refill(mod) else 0
				var drop := Solver.best_discard(vis0, slots, extra, p.deck, _rng,
					999, d_cards, 0.0, lam_samples, 0.0, p.deck.rules, b0, blind_refill)
				if not drop.is_empty():
					# ⚠ 2026-08-14:`best_discard` 返回的是 **visible 下标**(枚举已扩到全 8 张),
					# 不再是 `b0.keep` 的下标 —— 传错数组会静默弃错牌。
					_do_discard(p, vis0, drop, slots)

	# ② 切法:重新看 8 张(弃牌后已补), 选「计分 5 / 留缓存 3」
	var visible: Array = []
	visible.append_array(p.hand)
	visible.append_array(p.cache)
	if visible.size() < GameConfig.HAND_SIZE:
		return
	var hid := p.hidden_indices(visible)
	var subs := Solver.make_subs(p.deck, _rng, hid.size(), bs,
		_known_attrs(p, visible, hid)) if not hid.is_empty() else []
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


## 属性级信念的「已知半张」表(2026-08-27, 蒙色/蒙点入池的必修)。
## hid 里每个下标当前看得见哪一半:蒙点(hide_ranks)花色是真值、点数 -1;蒙色反之;
## 整张盖住(盖牌族)两者都 -1。全 -1 时返回**空表** —— `make_subs` 走老路径,
## 全盲族的读数逐位不变(RNG 消耗个数两条路径本来就相同)。
func _known_attrs(p: Phrase, visible: Array, hid: Array) -> Array:
	var out: Array = []
	var any := false
	for i in hid:
		var c: Card = visible[int(i)]
		var kr := p.visible_rank_of(c)
		var ks := p.visible_suit_of(c)
		if kr >= 0 or ks >= 0:
			any = true
		out.append({"rank": kr, "suit": ks})
	return out if any else []


## 把「要弃 keep 里的第几张」翻译成 Phrase 认的 (手牌下标, 缓存下标) 两组。
## keep 的 3 张可能散落在手牌和缓存里 —— 按对象身份找位置, 不靠下标推算。
## `cards` = 下标的宿主数组(现在是 visible 全 8 张;2026-08-14 前是 `base.keep` 那 3 张)。
## 本函数对宿主是什么不敏感 —— 它按**牌对象**去 hand/cache 里定位, 所以弃手牌天然就支持。
func _do_discard(p: Phrase, cards: Array, drop_idx: Array, slots: Array) -> void:
	var hi: Array = []
	var ci: Array = []
	for i in drop_idx:
		if i < 0 or i >= cards.size():
			continue
		var card = cards[i]
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
	# 经济账本:随机 bot 想弃 k 张但金币不足(掷点在前, 记账不消耗 RNG)。
	if _rep != null and k > 0 and p.coins < Economy.discard_cost(k):
		_rep.eco_add("deny_money", 1)
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
	# 静场の誓(2026-08-25/26):持有静场时, **手牌已成才静**(keep_all 拍白拿 +0.4),
	# 手牌还烂照常筛牌 —— 第一版整局全静, kit 实测 −940(机会成本 −1300 抵不回 +400):
	# 那不是玩家会做的事, 是仪器在自欺(与「凑不到就别凑」同一条判据)。
	for hj in slots:
		if hj != null and hj.id == "hush":
			var vow_plan: Dictionary = _best_plan(p.hand, target_id, 3, p.deck.rules)
			if bool(vow_plan.get("keep_all", false)):
				return
			break
	# ⚠ 洗牌臂已随机制退役删除(2026-09-01)—— 万能牌改为「弃牌补牌时自然循环出来」,
	# 而那条路径 bot 走的是普通弃牌决策, 不需要单独一条臂。
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
	# ⚑ 动作粒度(2026-08-27, 新基线):beat_discards 现在是**动作次数**预算 ——
	# 规则 bot 的 plan 弃牌一批算 1 个动作(真人一次跨区多选就是一个手势),
	# 单批张数上限走 discard_batch(随拍长缩放, 赶场在两层都咬得住)。
	# 旧口径把张数当动作数, 弃 6 结构性不可达 —— 拆迁(wrecker)在 kit 挂 UNREACHABLE 正是这个。
	var dur := Run.phrase_duration_for(section, mod, p.phrase_idx)
	var d_max: int = mini(GameConfig.discard_batch(dur, section), p.hand.size())
	if GameConfig.beat_discards(dur, section) <= 0 or d_max <= 0:
		return
	var plan: Dictionary = _best_plan(p.hand, target_id, d_max, rules)
	if bool(plan.get("keep_all", false)):
		return
	var keep: Array = plan["keep"]
	var idx: Array = []
	for i in range(p.hand.size()):
		if not keep.has(i) and idx.size() < d_max:
			idx.append(i)
	# ⚑ 经济 v2 · 弃牌影子价 κ(2026-08-26, 弃牌 1◆/张):免费时代 plan 更优就弃,
	# 收费后「弃一张要值一张的钱」—— plan 相对 keep_all 的期望增益打不过
	# κ × 张数就少弃(从计划外的尾巴先砍)。κ 挂 DISCARD_COST 乘法:免费世界自动归零,
	# 旧读数逐位不变。初值是方向锚(sim.json ev.discard_kappa, 分/◆), decay.gd 精扫归 ⑥。
	var kappa: float = float(EV.get("discard_kappa", 0.0)) * float(GameConfig.DISCARD_COST)
	if kappa > 0.0:
		var plan_gain: float = float(plan.get("ev", 0.0)) - float(plan.get("ev0", 0.0))
		var idx_before_kappa := idx.size()
		while idx.size() > 0 and plan_gain < kappa * float(idx.size()):
			idx.pop_back()
		# 经济账本(旁路, 只记事实):κ 自我约束砍掉的张数 —— 「想弃但金币不足」的
		# 拒绝口径测不到它(bot 决策前就收手了), 所以单独记一列(report.gd eco 注释)。
		if _rep != null and idx.size() < idx_before_kappa:
			_rep.eco_add("kappa_cut", idx_before_kappa - idx.size())
	# ⚑ **玩家为自己的卡调整弃牌张数**(2026-08-13 还的仪器债;同 `_timing_flags` 的思路)。
	# 拆迁(单拍弃满 6 张 → 成牌 ×3.5)这类卡的收益远大于
	# 「多弃一张让手牌变差」的损失, 所以装了它们的玩家会**凑够张数**。
	# ⚠ 这是「能力 ≠ 动机」那条判据的落地:把 `beat_budget` 从 2 校准到 3 只是让
	# 弃 3 张**可达**, bot 照旧只弃 plan 说该弃的 —— 不给动机, 那两张卡永远量不到。
	# ⚠ **只在 plan 本来就要弃牌时才凑**(`idx` 非空):plan 说 keep_all 时手牌已经很好,
	# 硬凑会砸掉现成的牌型 —— 那不是玩家会做的事, 是仪器在自欺。
	var want_cards := 0
	for j in slots:
		if j != null:
			want_cards = maxi(want_cards, int(DISCARD_BIAS.get(j.id, 0)))
	# ⚠⚠ **凑不到就别凑**(2026-08-13 实测踩到):`beat_budget` 是 3 时给断舍离
	# (要 4 张)凑牌 —— 弃到上限 3 张、条件仍不满足, 于是**白弃一张手牌**:
	# kit 实测 **−961 分 / 触发 0%**。而门差点放行它(z 和量级都过, 只有符号是负的)。
	# 判据:**目标张数够不到时, 这个偏置整个不生效** —— 打不成的牌不值得为它赔手牌。
	# 钱不够弃 want 张(经济 v2 弃牌 1◆/张)同样算够不到 —— 半批弃出去条件照样不满足。
	# ⚑ 动作粒度(2026-08-27)后凑张数**跨区、缓存先行**:一次多选 = 一个动作,
	# 直弃缓存牌不拆手牌(原位随机补, 代价只是缓存质量), 是真人凑「弃 6」时先圈的那几张;
	# 手牌**仍然最多只多弃一张**(2026-08-13 实测校正不变:断舍离第一版「装了就凑」
	# 触发率 0%→86% 但分差 −330 —— 真人只在手牌本来就烂时才顺手凑, 不会为触发拆现成牌型。
	# 多弃一张手牌的代价小, 多弃三张是在赌;缓存牌不在此列, 它们本来就不在成牌里)。
	var batch_cap: int = GameConfig.discard_batch(dur, section)
	var cache_idx: Array = []
	if want_cards > idx.size() and not idx.is_empty() and want_cards <= batch_cap \
			and p.can_discard(want_cards):
		var free_cache: Array = []
		var blocked: Dictionary = p.discard_blocked_cache()
		for cj in range(p.cache.size()):
			var cc = p.cache[cj]
			if cc != null and not blocked.has(cc):
				free_cache.append(cj)
		# 可及性判断在动手之前:缓存全下 + 手牌至多再一张仍够不到 want ⇒ 整个不凑
		# (否则先弃掉的缓存牌就是白赔的 —— 与「白弃一张手牌」同一形状)。
		if idx.size() + free_cache.size() + 1 >= want_cards:
			for cj in free_cache:
				if idx.size() + cache_idx.size() >= want_cards:
					break
				cache_idx.append(cj)
			if want_cards > idx.size() + cache_idx.size():
				for i in range(p.hand.size()):
					if idx.size() + cache_idx.size() >= want_cards:
						break
					if not idx.has(i):
						idx.append(i)
	var n_batch: int = idx.size() + cache_idx.size()
	# 经济账本(报表线, 2026-08-27 合并织回):想弃但金币不足 —— can_discard 会因此拒绝。
	if _rep != null and n_batch > 0 and p.coins < Economy.discard_cost(n_batch):
		_rep.eco_add("deny_money", 1)
	if n_batch > 0 and p.can_discard(n_batch) and p.discard_selected(idx, cache_idx):
		_notify_discard(slots, n_batch)
	# 回收の经营(2026-08-25 打法先验):持有回收 = 每拍把缓存最小的一张直弃换奖励分
	# (它的设计就是献祭;原位补进来的新牌随后一起进切法)。封/锁的缓存牌不碰。
	for rj in slots:
		if rj != null and rj.id == "recycle":
			var low_ci := -1
			var low_rank := 99
			var blocked: Dictionary = p.discard_blocked_cache()
			for cj in range(p.cache.size()):
				var cc = p.cache[cj]
				if cc != null and cc.rank < low_rank and not blocked.has(cc):
					low_rank = cc.rank
					low_ci = cj
			if _rep != null and low_ci >= 0 and p.coins < Economy.discard_cost(1):
				_rep.eco_add("deny_money", 1)   # 经济账本:回收想献祭但付不起
			if low_ci >= 0 and p.can_discard(1) and p.discard_selected([], [low_ci]):
				_notify_discard(slots, 1)
			break
	# Forced Rotation: any non-vow build tosses its worst card rather than
	# eat the ×0.5 (Lone Wolf keeps the vow — ×4 halved still beats ×1)
	if _rep != null and mod == "rotation" and p.discards_used == 0 \
			and target_id != "lonewolf" and p.coins < Economy.discard_cost(1):
		_rep.eco_add("deny_money", 1)   # 经济账本:轮换想弃一张避 ×0.5 但付不起
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
	var ev_keep_all: float = cur_score * _target_mult(target_id, cur_kind)
	plans.append({"ev": ev_keep_all, "keep": [], "keep_all": true})

	# flush chase: majority suit (or color, under Two-Tone), any rank works
	# ⚠ 双色调拆两张之后, 「按颜色追」只在**装了那一色**时成立 —— 沿用旧的单开关
	# 会让 bot 在只装黑调时也去追红同花, 那是一条游戏里不存在的策略。
	var two_red: bool = bool(rules.get("redtone", false))
	var two_black: bool = bool(rules.get("blacktone", false))
	var two: bool = two_red or two_black
	var suit_n := {}
	for c in hand:
		if not c.is_wild():
			# 只有装了对应颜色的那张牌, 这一色才折叠成一个"花色";另一色照旧按真花色分。
			var folded: bool = (two_red and c.is_red()) or (two_black and not c.is_red())
			var sk: int = (1 if c.is_red() else 0) if folded else c.suit + 2
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
	# 经济 v2:带上 keep_all 基准(可能被上面的 top>=13 抬过), 弃牌 κ 门槛要拿它算增益。
	best = best.duplicate()
	best["ev0"] = float(plans[0]["ev"])
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
## data/jokers.json effects, killing the hand-copied tier table (docs/design/tech.md).
## Tiers guarded by extra conditions (lonewolf's discards/top-rank) are NOT
## unconditional payouts and are skipped, matching the old table exactly.
## 一张 Target 的**峰值**倍率(它覆盖的牌型里最高的那档)—— 镜面估值用。从 _target_mult 推导,
## 不再读 sim.json 的手抄表(那张表 08-21 已删:同一口径的第二份必过期)。
func _target_peak(target_id: String) -> float:
	var best := 1.0
	for k in Pattern.Kind.values():
		best = maxf(best, _target_mult(target_id, int(k)))
	return best


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
func _weakest_slot(slots: Array, st: Dictionary) -> int:
	var weak_k := 1
	var weak_ev := 1.0e18
	for k in range(1, slots.size()):
		if slots[k] == null:
			continue
		var oe := _card_ev(String(slots[k].id), st, slots, 1)
		if oe < weak_ev:
			weak_ev = oe
			weak_k = k
	return weak_k
