extends Probe

## 小丑牌的覆盖自证门 —— **每张进池子的小丑牌都要证明「它在模型里真的生效」**。
##   godot --headless --path . --script res://tools/kit.gd
##   SYNC5_KIT_ID=<id>   只验一张牌(加了一张新牌时用这个)
##                       实测 score 5s · coin 16s · **solver 56~84s**
##                       —— solver 那条慢是因为基准臂也得跑完美玩家, 躲不掉
##   SYNC5_KIT_N=<n>     改样本量(默认 score 120 / solver 40 / coin 150)
##
## ⚠ 全量 **309s**(实测于 `tools/gate.sh`, 无竞争)。其中 solver 通路占 ~180s ——
## 要压时间就调 `N_SOLVER`:硬判据(证物率)现在 z = 9.7~38.6, n 砍一半仍有 z >= 6.9。
## **别去砍 score/coin 的 n**, 那两条便宜(合计 ~90s), 砍了省不下什么。
##
## `tools/gate.gd` 的孪生兄弟:那边守**脸**, 这边守**小丑牌**。判据/口径/输出风格照抄它。
##
## ## 为什么这道门比脸的门更重要
##
## `tools/coin.gd` 实测**整个构筑值 4.2 倍**(有商店 18654 / 无商店 4410)——
## **分数的大头在小丑牌上**。而脸有 `gate.sh <face_id>`, 小丑牌一直**没有门**
## (design/jokers.md 验证方案里唯一的 ❌)。这个项目栽过**五次同一个形状**:
## 规则在游戏里生效、在模型里是空气, **五次都不报错**。代价不是"少一张卡",
## 是**目标分照着一个没发生过的难度算**, 一路静默。
##
## ## 判据(照抄 gate.gd)
##
## **配对 A/B**:同种子、同队列, **唯一的区别是这张卡装没装**。
## 通过 = **|z| >= 3.0 且 量级 >= 5%**, 两个都要满足 ——
## z 回答「这个读数信不信得过」, 量级回答「这个效应要不要管」;
## 蒙特卡洛的样本量是我们自己定的, 只看 z 等于让判据跟着预算走。
##
## ## 三条通路(按`用什么仪器证明`分, **不是**按机制分 —— `core/db.gd::validate_jokers` 锁着)
##
## ① **score**(16 张)—— 效果直接改分, 规则 bot 配对 A/B 就量得到。
##    ⚠ **商店必须关掉**:开着商店两臂会买到不同的牌, 差值里混进抽卡运气, 配对就白配了。
##    卡**直接装进槽位**, 不让 bot 去抽。
## ② **solver**(4 张)—— 改的是牌型判定规则(`acquire.deck_rule`)或牌堆组成(`wilds`)。
##    **必须用完美玩家**:规则 bot 未必会去用新规则, 拿它量可能得 0、甚至反号。
##    脸那边的实证:`freshsheet` 规则 bot **+1584**, 完美玩家 **−790** —— **符号是反的**
##    (`tools/gate.gd::_run_solver`)。别重蹈。
##    **硬判据是证物率不是分差**, 理由见 `_run_solver`。
## ③ **coin**(3 张)—— 只给钱不给分, **在分数臂里按定义恒等于 0**。拿分数验它只会得出
##    「没接上」, 和脸那边的 `raisedbar` 一模一样。所以**两段**证明:
##      (a) **金币臂** 关商店, 配对 A/B, 累计金币必须显著上升(干净、便宜);
##      (b) **行为臂** 开商店, **商店花费**必须跟着上去 —— 钱真的变成了购买力。
##    ⚠ 只验 (a) 会漏掉「钱到手了但没人花」——
##    **证明要落在做决定的那条路径上, 不是它的定义上**(`gate.gd::_run_target` 的血泪注释)。
##    ⚠ (b) 最初按「总分必须动」写, 实测被槽位混杂淹掉, 换成花费。全过程见 `_run_coin`。
##
## ## ⚠ 判据:必须同时报**触发率**, 不能只报分差
##
## 「量不到」对小丑牌有**三种**可能, 而不是脸那边的两种:
##   ① **没接进模型**(接线坏了) · ② **接上了但条件没发生**(bot 打法所致) ·
##   ③ **接上了但效应本来就微不足道**
## 很多卡的触发条件依赖**玩家行为**(`discards_eq:0` / `same_as_prev` / `last_phrase` /
## `acted_late`), 规则 bot 的打法可能让某个条件几乎不发生。**触发率就是分辨 ①② 的那个读数。**
##
## ⚠⚠ **触发率对 solver 通路那四张恒为 0, 而那不代表它们没触发** ——
## `Report.track_triggers` 数的是「结算时弹了 popup 的次数」, 而 `shortcut`/`fourfingers`/
## `twotone`/`wildcard` **没有 `effects`**(它们改的是规则/牌堆, 不进 popup 链)。
## 所以这四张改报**证物率**:装了它之后, 它该造出来的东西真的出现了吗 ——
## 顺子/同花的成手率, 或"打出的五张里含万能牌"的拍数占比。见 `WITNESS`。
##
## ## 四个坑(都是静默的)
##
## ① **装卡必须调 `on_acquire`** —— `deck_rule` / `wilds` 全在 `Joker.on_acquire(deck)` 里
##    生效。只把对象塞进 `run.joker_slots[k]` 而不调它, 那四张卡的效果**根本不存在**,
##    门会报"没接上", 而那是门自己的 bug。
## ② **`mirror` 的基准臂必须也装一张 Target** —— 它复制 Target 的一半, 没 Target 时恒等于 0。
##    **通则:每张卡的基准臂 = 它需要的前置装好、但它自己不装**(见 `PREREQ`)。
## ③ **槽位有语义**:`joker_slots[0]` 是 Target 槽, `1..3` 是 Support 槽(`core/settle.gd`)。
## ④ **成长卡要跑满全长**:`bassline` 要 12 次弃牌才第一次触发, `vinyl`/`glowstick`/
##    `momentum` 逐拍累积。所以每条臂都是**不死局打满 24 拍**, 不许用短局量。
##
## ## 口径
##
## · **一局的循环走 `RunLoop`**(一局的骨架只此一份), **统计走 `Stat`** —— 都不许再抄一份。
## · **全程无脸**(`faces = {}`):这里量的是这张卡, 不是它和脸的交互。
## · 不死局打满 24 拍, 和 `curve.gd` / `gate.gd` 同一个记账约定。
## · 报**标准误和 z** —— 没有标准误的差值等于没有结论。

const N_SCORE := 120       # 规则 bot, 无商店 —— ~0.026s/局。实测最弱的一张 z=19(n=250)
const N_SOLVER := 40       # 完美玩家 ~0.6s/局(带规则牌走 `_classify_ref` 慢路径)
const N_COIN := 150        # 金币臂效应巨大(实测最弱的 tipjar z=39 @300), 150 够

## **这条臂太贵, 单独封顶**。`wildcard` 让牌堆里有万能牌, 于是 `Pattern._score_five`
## 要对每张万能牌暴力代入 52 张 —— 求解器一拍调它 ~12 万次, 单局从 0.6s 涨到 **3.6s**。
## 它的效应又是这条通路里最大的几个之一(n=6 就有 z=3.7), 所以 15 局足够 (外推 z≈5.9)。
## ⚠ 封顶只减不增:`SYNC5_KIT_N` 调小时照样生效。
const ARM_CAP := {"wildcard": 15}

## ⚠⚠ **别指望用「加样本量」救一张卡**(2026-08-13 试过并撤回, 留档)。
## 判据有**两条**:|z|≥3(信不信得过)**且** 量级≥5%(要不要管)。
## 加样本只让标准误变小 → 只能改善 **z**;而**量级 = 效应/基准, 与 n 无关** ——
## 样本量对它一点用都没有。三重唱实测 z=1.81 **且** 量级 4.1%, 我一度按 power
## analysis 算出 n=80 准备加量, 算完才想起来:量级那条**加多少局都过不去**。
## ⚠ 顺带一个实现坑(当时也发现了):`_arm_n` 只作用于**实验臂**, 而
## `Stat.paired` 取 `mini(a, b)` —— 基准臂不跟着加, 加量根本不会生效。
const Z_MIN := 3.0         # 显著性:这个读数信不信得过
const MAG_MIN := 0.05      # 量级:效应占基准的比例, 低于它就是"不值得管"

## 槽位语义(core/settle.gd):0 = Target, 1..3 = Support。**装错位置行为会变。**
const TARGET_SLOT := 0
const SUPPORT_SLOT := 1

## **基准臂要装、实验臂也要装的前置**(坑 ②)。
## 判据:这张卡的效果**以另一张卡的存在为条件**时, 前置必须进基准臂 ——
## 否则量到的是「前置 + 它」的合力, 而不是它自己。
const PREREQ := {
	"mirror": ["twin"],    # 复制 Target 的一半 —— 没 Target 时它恒等于 0
	# ⚠ 打包(doggybag)一度挂在这里, 已撤 —— 它的条件是「段分达目标两倍」,
	# 而 kit 的臂是**单卡臂**(基准只装前置、不装构筑), 段分天生打不到 2×目标:
	# 加 PREREQ 救不回来(试过, 触发仍 0%)。那不是「前置」缺失, 是**这道门量的是
	# 单卡效应, 而这张卡的条件依赖整套构筑的输出**。撤出 json 挂仪器债, 欠的是
	# 一条「构筑臂」(与 declutter 欠 bot 弃牌策略块同批)。
}


## **量级豁免**(2026-08-13 补;`faces.json weak_upper_bound` 的小丑牌版)。
##
## 判据与脸那边逐字相同:通过 = |z|≥3 **且** 量级≥5%。有些卡**接上了、方向对、
## z 高得没话说**, 只是效应占基准不到 5% —— 那是「效应小」的结论, 不是覆盖缺陷。
## 允许豁免, 但**必须显式声明并写下理由**:与 `fixed_tiers` / `weak_upper_bound`
## 同一条原则 —— **豁免必须是有意的, 不能是漏掉的**。
## ⚠ 声明的是「对**这个 bot** 的上界效应小」, **不是**「这张卡没用」——
## 真人的弃牌/交换习惯与 bot 差得远(早锁 8% vs 78% 就是先例), 所以一律标「真人待定」。
## ⚠ 反向也锁(见 `_initialize` 末尾):声明了却其实量到 = 表过期, 该删条目。
const WEAK_MAGNITUDE := {
	"stageexit": "普通档 +30/张 × bot 的弃人头率 —— z=31.8 早已证明接上了, 量级 4.1%;真人待定",
}

## solver 通路那四张的**证物**:它该造出来的东西真的出现了吗。
## 触发率对它们恒为 0(没有 effects → 不弹 popup), 所以换这个读数。
## `*wild` = 特例:打出的五张里含万能牌的拍数占比。
const WITNESS := {
	"shortcut": ["STRAIGHT", "STRAIGHT_FLUSH", "ROYAL_FLUSH"],
	"fourfingers": ["STRAIGHT", "STRAIGHT_FLUSH", "ROYAL_FLUSH"],
	"twotone": ["FLUSH", "STRAIGHT_FLUSH", "ROYAL_FLUSH"],
	"wildcard": ["*wild"],
	# ⚠ 2026-08-12 流派批修仪器:第三种形状 —— **牌堆手术卡**(trim:不改判定规则、
	# 不进 popup 链, 改的是**抽牌分布本身**)。它不制造任何单一牌型, 证物率没有定义域
	# (「它该造出来的东西」是整摞牌的质量, 不是某个 kind);而分差正是它的全部效应,
	# 实测 +1319(z=6.22, 18.7% @ 默认 n)—— 不是 shortcut 那种「分差被替代方案稀释」
	# 的形状, 拿它当硬判据不算为平衡烧预算。`*score` 必须**显式声明**:
	# 没声明的无 effects 卡照旧报证物率假红 —— 那是门在喊「来声明」, 不许静默兜底。
	"trim": ["*score"],
}

## shop 通路(货架结构卡)的证物声明 —— 与 WITNESS 同一条纪律:必须显式声明。
##   multi_shops = 每局「双购店」数(一次进店成交 ≥2;无联票在手时物理不可能 —— 基准≈0, 非严格零:bot 自己从货架买到联票的局会贡献几笔)
##   discount    = 每局实收折扣◆(基础价 − 实付;无赞助在手时≈0, 同上)
##   rule_offer  = 首发货架含规则牌的店比率(点唱机:成分证物)
## ⚠ 第一版用「成交数↑ / 均价↓」当证物, 双双死于**钉槽混杂**(实验臂钉死一个槽 →
## 少装一张卡, 效应同量级:联票 buys 差恰好 +0.0, 赞助花费 −5.9◆ z=−15 证明折扣
## 明明活着而均价只动 0.2)。教训 = 行为量会被槽位效应吃掉, **货架证物必须选
## 零基线的机械读数** —— 基准恒 0, 混杂无处藏身, 与 rule_offer 一次过 z=61 同理。
## ⚠ 第四种证物 `counter`(2026-08-13 子波 3):**商店事件驱动的成长卡**
## (淘碟/收藏家/转型)。它们不改货架、不产钱, 改的是自己的计数器 ——
## 而现有四条通路**没有一条**量得到:
##   · score 通路**关商店**(文件头:抽卡运气会混进配对)→ 商店事件根本不发生;
##   · coin 通路量金币与花费, 不量分数;
##   · shop 通路原有的三种证物都是**货架**读数, 而这三张不碰货架。
## 证物 = **一局结束时那张卡的计数器终值**:零基线(没有这张卡就没有这个计数器),
## 机械读数(商店真的发生过就必然涨), 与 shelf 三件套同一条判据。
## ⚠ 我第一版把它们声明成 `score` 通路并断言「开商店的臂量得到」——
## 实测三张全部触发 0%。**引用一条纪律前先确认它说的是什么。**
const SHOP_WITNESS := {
	"doublebill": "multi_shops",
	"sponsor": "discount",
	"jukebox": "rule_offer",
	"digger": "counter",
	"collector": "counter",
	"rebrand": "counter",
}

var _rng := RandomNumberGenerator.new()
var _only := ""
var _fail: Array = []
var _warn: Array = []
var _weak_seen: Dictionary = {}     # 本次真的用上了豁免的卡(反向检查用)


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	_only = Probe.env_str("SYNC5_KIT_ID")
	var n_score := Probe.env_int("SYNC5_KIT_N", N_SCORE)
	var n_solver := Probe.env_int("SYNC5_KIT_N", N_SOLVER)
	var n_coin := Probe.env_int("SYNC5_KIT_N", N_COIN)

	var cfg := _cohort()
	var by_channel := {"score": [], "solver": [], "coin": [], "shop": []}
	var seen := false
	# `SYNC5_KIT_ID` 支持**逗号分隔的多个 id**(2026-08-13 增量门)——
	# 一次改动通常碰好几张卡, 而一张一张跑要付好几遍基准臂的钱(基准臂是最贵的一段)。
	var wanted: Array = []
	if _only != "":
		for part in _only.split(","):
			var t := part.strip_edges()
			if t != "":
				wanted.append(t)
	for e in DB.jokers():
		var jid := String(e["id"])
		if not wanted.is_empty() and not wanted.has(jid):
			continue
		seen = true
		var ch := String(e.get("proof", ""))
		if not by_channel.has(ch):
			_fail.append("%s: proof 通路 '%s' 不认识" % [jid, ch])
			continue
		by_channel[ch].append(jid)
	if _only != "" and not seen:
		print("[kit] '%s' 不是任何一张小丑牌的 id" % _only)
		quit(1)
		return

	print("\n=== 小丑牌覆盖自证的门 (design/jokers.md 验证方案) ===")
	print("  队列 %s · score %d / solver %d / coin %d 局/臂 · 判据 |z| >= %.1f **且** 量级 >= %.0f%%"
		% [cfg.get("name", "?"), n_score, n_solver, n_coin, Z_MIN, MAG_MIN * 100.0])
	print("  问的不是「这张牌强不强」, 是「**模型看得见它吗**」。")
	print("  全程无脸、不死局打满 %d 拍(成长牌要跑满全长)。"
		% (GameConfig.SECTIONS_PER_RUN * GameConfig.PHRASES_PER_SECTION))

	if not by_channel["score"].is_empty():
		_run_score(cfg, by_channel["score"], n_score)
	if not by_channel["solver"].is_empty():
		_run_solver(cfg, by_channel["solver"], n_solver)
	if not by_channel["coin"].is_empty():
		_run_coin(cfg, by_channel["coin"], n_coin)
	if not by_channel["shop"].is_empty():
		_run_shop(cfg, by_channel["shop"], n_coin)

	# 反向锁:声明了豁免却其实量到了 = 表过期, 该删条目(同 weak_upper_bound 的反向检查)。
	# ⚠ 只在**全量**跑时查 —— 单卡模式(`SYNC5_KIT_ID`)本来就只跑一张, 其余当然"没用上"。
	if _only == "":
		for wid in WEAK_MAGNITUDE:
			if not _weak_seen.has(wid):
				_fail.append("%s 声明了量级豁免却其实量到了 —— 把它从 WEAK_MAGNITUDE 删掉" % wid)

	print("\n=== 判据 ===")
	for w in _warn:
		print("  ⚠ %s" % w)
	if _fail.is_empty():
		print("  ✅ 每张小丑牌都在模型里量到了效果 —— 目标分可以照着这批牌算")
	else:
		for f in _fail:
			print("  ❌ %s" % f)
		print("\n  「量不到」有**四种**可能, 必须当场分辨清楚, 不许放行:")
		print("    ① **没接进模型**(Settle/求解器读不到它的触发条件)—— 修接线;")
		print("    ② **接上了但条件没发生**(规则 bot 的打法让它几乎触发不了)——")
		print("       看同一行的触发率:接近 0% 就是这一种, 换个能触发它的玩法再量;")
		print("    ③ **接上了但效应本来就微不足道** —— 那是结论不是失败, 但要有人拍板;")
		print("    ④ **钱到手了但没人花**(coin 通路特有)—— 看那张卡下面那行「局末余额」:")
		print("       余额涨了而花费没涨 = 钱确实流到了商店那一刻, 是**模型里的买家不缺钱**。")
		print("       那不是卡的接线问题, 是 `bot._draft` 的问题 —— 修 bot, 别动卡。")
		print("  ⚠ 无论哪一种, **都不许为了让门变绿去改卡的数值或效果**。")
	print("\n[kit] %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(1 if not _fail.is_empty() else 0)


## --- ① score 通路:规则 bot, **无商店**。 ---
##
## ⚠ 商店必须关掉。开着商店两臂会各自买到不同的牌, 分差里混进了抽卡运气,
## 配对(同种子)那点方差控制会被整个淹掉。卡直接装进槽位, 不让 bot 去抽。
func _run_score(cfg: Dictionary, ids: Array, n: int) -> void:
	print("\n  ---- ① score 通路(规则 bot, 无商店) ----")
	var bases := {}
	for jid in ids:
		var pre: Array = _prereq(jid)
		var key := str(pre)
		if not bases.has(key):
			bases[key] = _play(cfg, _install(pre), false, false, n)
			print("    基准总分 %.0f   (基准臂装:%s)"
				% [Stat.mean(bases[key]["score"]), "空" if pre.is_empty() else str(pre)])
		var base: Dictionary = bases[key]
		var arm := _play(cfg, _install(pre + [jid]), false, false, n)
		_judge(jid, base["score"], arm["score"], Stat.mean(base["score"]),
			_trigger_txt(arm, jid))


## --- ② solver 通路:完美玩家, 无商店。 ---
##
## ⚠⚠ 这四张改的是**牌型判定规则**(`Deck.rules`)或**牌堆组成**(万能牌)。
## 规则 bot 未必会去用新规则 —— 它的 `_best_plan` 只在传了 `rules` 时才知道近道/四指,
## 而它的追牌启发本来就粗。拿它量可能得 0 甚至反号。完美玩家才是这条通路的尺子。
##
## ⚠⚠ **这条通路的硬判据是「证物率」而不是分差** —— 这是它和 score/coin 唯一的结构差异,
## 理由必须记清楚:
##   · 这四张**没有 `effects`**, 不进 popup 链, 所以触发率恒为 0 且**无意义** ——
##     不标出来, 读的人会以为它们一次都没触发;
##   · 门要回答的是**覆盖**(模型看得见这条规则吗), 不是平衡(它值几分)。
##     「装了 fourfingers 之后顺子成手率 9.6% → 35.8%」**直接回答了覆盖**;
##     分差只是它的下游, 而且被完美玩家的替代方案稀释过。
##   · 实证:`shortcut` 证物率 9.6% → 33.4%(规则显然进了模型), 分差只有 6.3%
##     (z=2.20 @ n=40) —— 把分差做到 z=3 要 ~100 局, 那 75 秒买到的是一个**平衡**结论,
##     不是覆盖结论。**为一个不归这道门管的问题烧预算, 换来的是一道跑不动或者常红的门**,
##     而常红的门等于没有门(`gate.gd::_run_sentinel` 同一条理由)。
## 所以:**证物率没有显著上升 = ❌ 没接上**;证物过了而分差没过 = **⚠**, 附实测数字。
##
## ⚠ 2026-08-10 批 3 修仪器:solver 通路出现了第二种形状 —— **带 effects 的织构卡**
## (伴唱/排练:不改判定规则, 改的是完美玩家愿不愿意为一个结算奖励**养缓存织构**)。
## WITNESS 表对它们没有定义, 证物率恒报「成手率 0→0%」的**假红**;它们进 popup 链,
## 分差和触发率都量得到。所以按 `has_effects()` 分岔:有 effects → 硬判据 = 分差;
## 无 effects → 照旧证物率。实测:伴唱 +631(z=4.06, 8.9%)/ 排练 +560(z=3.96, 7.9%)——
## 分差本身就过双判据, 不是「为平衡结论烧预算」那种情况。
func _run_solver(cfg: Dictionary, ids: Array, n: int) -> void:
	print("\n  ---- ②  solver 通路(完美玩家, 无商店) ----")
	print("    ⚠ 无 effects 的规则/牌堆卡:触发率恒 0 无意义, **硬判据 = 证物率**, 分差只作参考;")
	print("       带 effects 的织构卡:WITNESS 无定义, **硬判据 = 分差**, 触发率照报;")
	print("       牌堆手术卡(WITNESS 声明 *score):无单一证物牌型, **硬判据 = 分差**。")
	var bases := {}
	for jid in ids:
		var pre: Array = _prereq(jid)
		var key := str(pre)
		if not bases.has(key):
			bases[key] = _play(cfg, _install(pre), false, true, n)
			print("    基准总分 %.0f   (基准臂装:%s)"
				% [Stat.mean(bases[key]["score"]), "空" if pre.is_empty() else str(pre)])
		var base: Dictionary = bases[key]
		var arm := _play(cfg, _install(pre + [jid]), false, true, _arm_n(jid, n))
		if Joker.by_id(jid).has_effects():
			_judge(jid, base["score"], arm["score"], Stat.mean(base["score"]),
				_trigger_txt(arm, jid))
			continue
		var want_decl: Array = WITNESS.get(jid, [])
		if want_decl.size() == 1 and String(want_decl[0]) == "*score":
			# 牌堆手术卡(见 WITNESS 表注):无单一证物牌型, 分差即覆盖证明。
			_judge("%s: 分差(牌堆手术)" % jid, base["score"], arm["score"],
				Stat.mean(base["score"]), "无证物牌型, 分差为硬判据")
			continue
		var w0 := _witness_series(base, jid)
		var w1 := _witness_series(arm, jid)
		var wt := "%s%.0f→%.0f%%" % [_witness_name(jid), Stat.mean(w0) * 100.0,
			Stat.mean(w1) * 100.0]
		_judge("%s: 证物率" % jid, w0, w1, Stat.mean(w0), wt, true, true)
		_judge("%s: 分差(参考)" % jid, base["score"], arm["score"],
			Stat.mean(base["score"]), wt, false)


## --- ③ coin 通路:金币臂 + 行为臂。**别拿分数验它。** ---
##
## `lonewolf`/`tipjar`/`interest` 只给钱不给分, 在无商店的分数臂里**按定义恒等于 0**。
## 拿分数去验只会得出「没接上」—— 和脸那边的 `raisedbar` 一模一样。所以两段:
##   (a) **金币臂**:关商店, 配对 A/B, 累计金币必须显著上升 —— 干净、便宜,
##       但它只证到「钱到手了」;
##   (b) **行为臂**:开商店, **商店里的花费**必须跟着上去 —— 钱真的**变成了购买力**。
## 只验 (a) 会漏掉「钱到手了但没人花」。
## **证明要落在做决定的那条路径上, 不是它的定义上**(`gate.gd::_run_target` 的血泪注释)。
##
## ⚠⚠ **行为臂量的是「花费」而不是「总分」, 这是实测之后换掉的仪器**, 理由要记清楚:
## 第一版按「总分必须动」来判, 三张卡全部量到**负**的、不显著的分差
## (tipjar −672 ±523 / interest −1089 ±449 / lonewolf −14323)。根因不是卡没接上,
## 是**这把尺子有一处和效应同量级的混杂**:实验臂把一个槽位钉死了, 那个槽在基准臂里
## 是自由的 —— 一个普通 support 值 500~2800 分(见 score 通路), 而 tipjar 的 +9◆
## 按 `coin.gd` 的 κ 折算也就一两千分。**两个数量级相同、符号相反, 分差因此恒在 0 附近。**
## 换成「花费」就绕开了它:①花费直接落在 `bot._draft` 那条决定路径上;
## ②满槽之后 bot 走「买新替旧」照样花钱(design/levels.md), 所以钉死一个槽不堵住花费 ——
## 实测那点残余混杂只有 1~3◆(占基准花费 31◆ 的个位数), 不再和效应同量级。
## **教训和 `freshsheet` 是同一条:选错仪器会把结论量成一个不存在的问题。**
##
## ⚠ 总分那一列照旧印出来, 但**只作参考不作判据** —— 上面那段混杂在分数上没有消失,
## 尤其 `lonewolf`:它是 Target, 还附带「零弃牌起誓」(`bot._play_adaptive` 一见到它就
## return), 基准臂那边 bot 会照 `cfg.target` 抽到另一张 Target。
## **它那一行混着「换了一张 Target」和「整局不弃牌」两件事, 不是金币的读数。**
##
## ⚠ 每张卡下面还挂一行**局末余额**。它是分辨「①没接上」和「钱到手了但没人花」的读数:
## 钱要是根本没流到商店, 余额不会涨;**余额涨了而花费没涨 = 钱到了、买家不要**。
func _run_coin(cfg: Dictionary, ids: Array, n: int) -> void:
	print("\n  ---- ③a coin 通路 · 金币臂(规则 bot, 无商店, 量**累计金币**) ----")
	var cbase := _play(cfg, [], false, false, n)
	print("    基准一局金币 %.1f◆" % Stat.mean(cbase["coins"]))
	for jid in ids:
		var arm := _play(cfg, _install([jid]), false, false, n)
		_judge("%s: 累计金币" % jid, cbase["coins"], arm["coins"],
			Stat.mean(cbase["coins"]), _trigger_txt(arm, jid), true, true)

	print("\n  ---- ③b coin 通路 · 行为臂(规则 bot, **开商店**)—— ⚠ 整段**只作参考, 不作判据** ----")
	print("    覆盖已经由上面的金币臂证完(钱到没到账)。这一段问的是**这笔钱换不换得出分**,")
	print("    那是**平衡问题不是覆盖问题** —— 而铁律是「模型只定目标分, 不当内容裁判」。")
	print("    2026-08-09 实测:修好金币影子价(coin_decay 0→1)之后 bot 确实多买了")
	print("    (满槽后 0.32→0.97 次), 总分却几乎不动(z=0.15) —— 剩 3 拍买一张好卡也就")
	print("    ~139 分 / 全局 15000。**后期钱花不出去不是定价错, 是那时没什么值得买的了。**")
	print("       总分那一行同样只作参考 —— 钉死一个 support 槽的代价就有 500~2800 分,")
	print("       和效应同量级;`lonewolf` 是 Target, 它那行还混着「换掉了队列的 Target」")
	print("       和「整局不弃牌」, 量级到万, **完全不是金币的读数**。")
	var bbase := _play(cfg, [], true, false, n)
	print("    基准花费 %.1f◆ · 局末余额 %.1f◆ · 基准总分 %.0f"
		% [Stat.mean(bbase["spend"]), Stat.mean(bbase["coins"]), Stat.mean(bbase["score"])])
	for jid in ids:
		var arm := _play(cfg, _install([jid]), true, false, n)
		# ⚠⚠ `hard = false` —— **这是 2026-08-09 改的, 理由要记清楚**:
		# 第一版把「商店花费必须上升」当硬判据, 于是三张经济卡全红。但实测证明红的原因
		# 不是覆盖坏了(金币臂 z = +28 / +51 / +469, 钱明明白白到了账), 而是
		# **这笔钱在 24 拍 / 7 商店的结构下换不出分**。那是**平衡**结论, 不是覆盖缺陷。
		# 让一道覆盖门去判平衡, 它会**永远红** —— 而一道永远红的门, 下一个人就不看了,
		# 比没有门更糟。**门只回答「模型看得见它吗」。**
		# ⚠ 降级不等于删除:这一段照旧全量打印, 失败进 ⚠ 清单。它抓到过真东西
		# (bot 后半程完全不买牌, 见 tools/wallet.gd), 那条信息要留着, 只是不该当判罚。
		_judge("%s: 商店花费(参考)" % jid, bbase["spend"], arm["spend"],
			Stat.mean(bbase["spend"]), _trigger_txt(arm, jid), false, true)
		_judge("%s: 总分(参考)" % jid, bbase["score"], arm["score"],
			Stat.mean(bbase["score"]), _trigger_txt(arm, jid), false)
		# ⚠ **分辨「没接上」和「钱到手了但没人花」的那个读数。**
		# 钱如果根本没流到商店, 余额不会涨;余额涨了而花费没涨 = 钱到了、买家不要。
		var dbal: float = Stat.mean(arm["coins"]) - Stat.mean(bbase["coins"])
		print("        └ 局末余额 %+.1f◆   %s" % [dbal,
			"← 钱确实流到了商店那一刻, 只是没被花掉" if dbal > 1.0 else ""])


## --- ④ shop 通路:货架结构卡(联票/赞助/点唱机)。**三条旧通路按定义全量不到。** ---
##
## 它们不产分不产钱, 改的是**商店本身**(位数/价格/成分)。硬判据 = SHOP_WITNESS
## 声明的货架证物 —— 全部是**机械读数**(规则活着就必然动的量), 不是行为结论;
## 花费与总分只作参考(钉槽混杂, 同 coin 行为臂 2026-08-09 的理由)。
func _run_shop(cfg: Dictionary, ids: Array, n: int) -> void:
	print("\n  ---- ④ shop 通路(规则 bot, **开商店**)—— 货架结构卡, 证物按卡声明 ----")
	print("    硬判据(全部零基线机械读数, 见 SHOP_WITNESS 注):")
	print("    multi_shops=双购店数↑ · discount=实收折扣◆↑ · rule_offer=含规则牌店率↑")
	var base := _play(cfg, [], true, false, n)
	print("    基准:每局成交 %.2f 张 · 双购店 %.2f · 折扣 %.1f◆ · 含规则牌店率 %.0f%%"
		% [Stat.mean(_rec_series(base, "buys")), Stat.mean(_rec_series(base, "multi_shops")),
		Stat.mean(_rec_series(base, "discount")), Stat.mean(_rule_rate_series(base)) * 100.0])
	for jid in ids:
		# 前置环境(COHORT_PATCH):**两臂都用改造后的队列**, 否则基准与实验臂跑在
		# 不同世界里, 配对就白配了 —— 所以基准也要跟着重跑一遍。
		var jcfg := _cohort_for(jid)
		var jbase := base
		if jcfg != cfg:
			jbase = _play(jcfg, [], true, false, n)
			print("    ⚙ %s 用改造队列(%s):基准重跑, 每局成交 %.2f 张"
				% [jid, str(COHORT_PATCH[jid]), Stat.mean(_rec_series(jbase, "buys"))])
		var arm := _play(jcfg, _install([jid]), true, false, n)
		match String(SHOP_WITNESS.get(jid, "")):
			"multi_shops":
				_judge("%s: 双购店数" % jid, _rec_series(jbase, "multi_shops"),
					_rec_series(arm, "multi_shops"), Stat.mean(_rec_series(jbase, "multi_shops")),
					"货架证物=双购店(基准≈0)", true, true)
			"discount":
				_judge("%s: 实收折扣◆" % jid, _rec_series(jbase, "discount"),
					_rec_series(arm, "discount"), Stat.mean(_rec_series(jbase, "discount")),
					"货架证物=折扣(基准≈0)", true, true)
			"rule_offer":
				_judge("%s: 含规则牌店率" % jid, _rule_rate_series(jbase),
					_rule_rate_series(arm), Stat.mean(_rule_rate_series(jbase)),
					"货架证物=首发成分", true, true)
			"counter":
				# 商店事件驱动的成长:证物 = 一局末的计数器终值(基准恒 0)。
				# ⚠ 分差也报(参考):成长卡的分数效应本来就该被量到, 但它受
				# 「bot 会不会一直留着这张卡」影响, 所以硬判据放在机械读数上。
				_judge("%s: 计数器终值" % jid, _rec_series(jbase, "counter"),
					_rec_series(arm, "counter"), Stat.mean(_rec_series(jbase, "counter")),
					"成长证物=商店事件计数(基准恒0)", true, true)
				_judge("%s: 总分(参考)" % jid, jbase["score"], arm["score"],
					Stat.mean(jbase["score"]), "", false)
			_:
				_fail.append("%s: shop 通路缺 SHOP_WITNESS 声明" % jid)
				continue
		_judge("%s: 商店花费(参考)" % jid, jbase["spend"], arm["spend"],
			Stat.mean(jbase["spend"]), "", false)
		_judge("%s: 总分(参考)" % jid, jbase["score"], arm["score"],
			Stat.mean(jbase["score"]), "", false)


func _rec_series(d: Dictionary, key: String) -> Array:
	var out: Array = []
	for rec in d["runs"]:
		out.append(float(rec.get(key, 0.0)))
	return out


func _rule_rate_series(d: Dictionary) -> Array:
	var out: Array = []
	for rec in d["runs"]:
		var s: float = float(rec.get("shops", 0.0))
		out.append(0.0 if s <= 0.0 else float(rec.get("rule_shops", 0.0)) / s)
	return out


## 判据**两条**(照抄 `gate.gd::_judge`, 那是本项目所有读数的通用纪律):**显著** 且 **量级够**。
##   · **显著性(z)** 回答「这个读数信不信得过」;
##   · **量级(占基准的比例)** 回答「这个效应要不要管」。
## 蒙特卡洛的样本量是我们自己定的, **样本一大什么都会显著** —— 只看 z 等于让判据跟着预算走;
## 反过来只看量级又会把纯噪声当成大效应。
##
## `extra` = 触发率(score/coin 通路)或证物率(solver 通路)。**它是分辨「没接上」和
## 「接上了但条件没发生」的那个读数**, 所以每一行都必须带着它, 不许只报分差。
##
## `hard` = 这一行算不算判据。false 的行照样印、照样判, 但失败只进 ⚠ ——
## 用在**已知带混杂的参考读数**上(solver 的分差、coin 行为臂的总分), 理由各自写在调用处。
## ⚠ 参考行不许悄悄地印:一个没有判据的数字放在判据表里, 下一个人会当判据用。
## `want_up` = **方向也是判据**。用在那些「往下走根本不构成证明」的读数上:
## 金币臂(卡是产钱的)、花费(要证的是购买力变大)、证物率(规则该让它变多)。
## ⚠ 没有这一条时, `interest` 的花费 −2.9◆ 会因为 |z|=8.3、量级 9.6% 而被判成
## **✓ 量到了** —— 一个方向相反的强读数被当成了证据。**显著 ≠ 证明。**
func _judge(label: String, a: Array, b: Array, base: float, extra: String,
		hard: bool = true, want_up: bool = false) -> float:
	var p := Stat.paired(a, b)
	var z: float = p["d"] / maxf(0.001, p["se"])
	# base = 0 时量级判据恒真(同 gate.gd):比例在零基准上没有意义。
	var mag: float = absf(p["d"]) / absf(base) if absf(base) > 0.0001 else 1.0
	var sig: bool = absf(z) >= Z_MIN
	var big: bool = mag >= MAG_MIN
	var wrong_way: bool = want_up and p["d"] <= 0.0
	var verdict := "✓ 量到了"
	var why := ""
	if wrong_way:
		why = "方向反了(要的是上升)"
	elif not big:
		why = "量级不够"
	elif not sig:
		why = "量级够但不显著"
	# 量级豁免要**在行内就看得出来**(照 `gate.gd` 的 "⚠ 豁免(上界效应小, 已声明)")。
	# ⚠ 第一版只在 `_fail`/`_warn` 分流时豁免, 行里照旧印 ❌ —— 于是出现「印着 ❌
	# 却放行」的行, 而**一个自相矛盾的读数会让下一个人整体不信这道门**。
	var jid := label.split(":")[0].strip_edges()
	var exempt: bool = hard and why == "量级不够" and sig and p["d"] > 0.0 \
		and WEAK_MAGNITUDE.has(jid)
	if why != "":
		verdict = ("⚠ 豁免(效应小, 已声明)" if exempt
			else ("❌ " if hard else "⚠ 参考:") + why)
	# ⚠ z 大到某个程度就没有信息了, 只有噪声:`neonsign` 是无条件 +80、24 拍 +1920,
	# 逐局几乎一模一样(实测 se=0.0117), z 印出来是 **+163607** —— 数字没错,
	# 但它长得像一个爆掉的读数, 下一个人会先怀疑仪器坏了。封顶印 `>1000` 即可。
	# ⚠ **别写成「确定性」** —— se 是 0.0117 不是 0(显示的 ±0.0 只是四舍五入),
	# 少数局确实有差异。封顶是如实说"显著到不用再看", 断言零方差是另一回事。
	var zs := (">+1000" if z > 0.0 else "<-1000") if absf(z) > 1000.0 else "%+8.2f" % z
	print("    %-24s %+9.1f  ±%.1f   z = %8s  %6.1f%%   %-14s %s"
		% [label, p["d"], p["se"], zs, mag * 100.0, extra, verdict])
	if why != "":
		var msg := "%s: 差 %.1f ±%.1f (z=%.2f, 占基准 %.1f%%) —— %s。%s" \
			% [label, p["d"], p["se"], z, mag * 100.0, why, extra]
		# 量级豁免:显著、方向对、只是效应小 —— 声明过的降级成 ⚠(见 WEAK_MAGNITUDE)。
		# ⚠ 只豁免「量级不够」这一种:不显著或方向反了照旧红, 那两种是覆盖缺陷。
		if exempt:
			_warn.append("%s —— 已声明量级豁免(%s)" % [msg, WEAK_MAGNITUDE[jid]])
			_weak_seen[jid] = true
		elif hard:
			_fail.append(msg)
		else:
			_warn.append(msg + "(参考行, 不作判据)")
	elif p["d"] < 0.0 and hard:
		# 不是覆盖问题(它显然接上了), 但一张让玩家**打得更低**的小丑牌是设计事故。
		_warn.append("%s: 效果是 %+.1f —— 装上它反而**变差**了, 确认是有意的" % [label, p["d"]])
	return p["d"]


## 这条臂实际跑几局(`ARM_CAP` 只减不增)。
## ⚠ 基准臂照旧跑满 —— `Stat.paired` 取 `mini(a, b)`, 而两边第 r 局用的是同一个种子,
## 所以短的那条臂和基准的**前 n 局**逐局配对, 配对性没有损失。
func _arm_n(jid: String, n: int) -> int:
	return mini(n, int(ARM_CAP.get(jid, n)))


## 这张卡的前置(基准臂也要装的东西)。
func _prereq(jid: String) -> Array:
	return (PREREQ[jid] as Array).duplicate() if PREREQ.has(jid) else []


## id 列表 → [[槽位, id], ...]。槽位由卡自己的 kind 决定(坑 ③)。
func _install(ids: Array) -> Array:
	var out: Array = []
	for jid in ids:
		var j := Joker.by_id(String(jid))
		if j == null:
			_fail.append("装不上 '%s' —— 不在 jokers.json 里" % jid)
			continue
		out.append([TARGET_SLOT if j.kind == "target" else SUPPORT_SLOT, String(jid)])
	return out


## 触发率:`presence` = 装着它结算了几拍, `trigger` = 其中弹了 popup 的几拍。
## ⚠ solver 通路那四张没有 effects, 这个数**恒为 0 且无意义** —— 那边走 `_witness`。
func _trigger_txt(arm: Dictionary, jid: String) -> String:
	var pres := float((arm["pres"] as Dictionary).get(jid, 0))
	if pres <= 0.0:
		return "触发 n/a"
	return "触发 %.0f%%" % (100.0 * float((arm["trig"] as Dictionary).get(jid, 0)) / pres)


## 证物率(solver 通路):这张卡该造出来的东西, 占了这一局多少拍。
## ⚠ **必须逐局给出一个数**, 不能只给全臂的合计 —— 配对检验要的是逐局的差,
## 合计只有一个数, 连标准误都算不出来, 而**没有标准误的差值等于没有结论**。
func _witness_series(arm: Dictionary, jid: String) -> Array:
	var want: Array = WITNESS.get(jid, [])
	var wild: bool = want.has("*wild")
	var out: Array = []
	for rec in arm["runs"]:
		var beats: float = maxf(1.0, float(rec["beats"]))
		if wild:
			out.append(float(rec["wild"]) / beats)
			continue
		var hit := 0.0
		for nm in want:
			hit += float((rec["kinds"] as Dictionary).get(int(Pattern.Kind[String(nm)]), 0.0))
		out.append(hit / beats)
	return out


## 这一列印的是什么证物 —— 读的人不该去翻代码才知道 33% 是什么的 33%。
func _witness_name(jid: String) -> String:
	return "万能牌" if (WITNESS.get(jid, []) as Array).has("*wild") else "成手率"


## 第一条真实人群队列就够 —— 这里量的是「这张牌有没有效果」, 不是流派强弱。
func _cohort() -> Dictionary:
	for c in DB.sim()["cohorts"]:
		if String(c.get("bot", "")) == "random" or bool(c.get("no_jokers", false)):
			continue
		return c
	return {}


## **前置环境**(2026-08-13 子波 3;`PREREQ` 的推广)。
##
## `PREREQ` 解决的是「这张卡需要**另一张卡**在场」;这里解决的是
## 「这张卡需要**队列本身**允许某件事发生」。
## 实例:转型(rebrand)的成长挂在换旗上, 而默认队列 `cfg.target` 是**强制固定** Target 的
## —— bot 侧有一条门「强制 target 的队列不许换旗(除非 cfg.pivot)」, 那是
## 「实验者的随机分配是整条 pipeline 唯一干净的因果通道」这条设计决定的必然结果。
## 于是换旗在这条队列里**物理上不发生**, 证物恒 0, 而那不是卡的接线问题。
## ⚠ **不是放水**:两条臂用**同一个**改造后的队列, 配对性完全保留 ——
## 改的只是「这个实验在什么环境里做」, 不是判据。
## ⚠ 补丁要打到**换旗真的会发生**的那个队列上, 不是「打开开关」就行:
## 默认队列的 Target 是 `twin`, 而它的 `counterfactual_tv = 2.6` **是全表最高** ——
## bot 换任何旗都是负收益, 所以光加 `pivot: true` 之后它照旧一次不换(实测计数器仍 0)。
## `wolfpivot` 的形状才对:独狼(1.7)起手弱 + pivot 开 → 换旗是它的既定弧线。
const COHORT_PATCH := {
	"rebrand": {"name": "kit:wolfpivot", "target": "lonewolf", "pivot": true},
}


func _cohort_for(jid: String) -> Dictionary:
	var c := _cohort()
	if not COHORT_PATCH.has(jid):
		return c
	var patched := c.duplicate(true)
	for k in COHORT_PATCH[jid]:
		patched[k] = COHORT_PATCH[jid][k]
	return patched


## 一条臂:打 n 局不死局, 每局把 `install` 里的卡钉在指定槽位上。
## 返回 {score, coins, spend, trig, pres, runs}(前三项逐局一个数, 供配对检验)。
##
## `spend` = 起始金币 + 一局总收入 − 局末余额。**无脸时商店是唯一的出口**
## (入场费只有 `cover` 那张脸会收, 这里全程无脸), 所以它就是「在商店里花掉了多少」。
##
## ⚠ **`on_acquire` 必须调**(坑 ①):`deck_rule` / `wilds` 全在那里生效。只把对象塞进
## `joker_slots[k]` 而不调它, solver 通路那四张的效果**根本不存在**, 门会报"没接上" ——
## 而那是门自己的 bug。`RunLoop` 没有开局钩子(不许改它), 所以在**第一拍的 `on_begin`**
## 里装 —— 那是 `Beat.begin` 之后、玩家动手**之前**, 决策与结算全程都看得见这张卡。
## 唯一的代价:第一拍的初始 5 张是从"还没掺万能牌"的牌堆里发的(24 拍里的 1 拍)。
##
## ⚠ **每局都要新的 `Joker` 实例** —— 成长牌的计数器在 `Joker.state` 上, 跨局共用会让
## `vinyl`/`bassline`/`momentum` 越跑越大, 而且不报错。
##
## ⚠ **每拍重新钉一次**:开商店时 bot 会往槽位里买东西、可能顶掉我们要量的那张卡。
## 量的是"这张卡的效果", 不是"bot 会不会留着它"。
##
## ⚠ **GDScript 的 lambda 按值捕获局部变量** —— 计数器一律装进 Dictionary(引用类型)。
##
## ⚠ st 的记账口径同 `gate.gd`(只记 n/score/disc, 不记 mult/kinds)—— 那是 `bot._draft`
## 给卡定价的输入, **"顺手补全"等于改了买牌行为**。
func _play(cfg: Dictionary, install: Array, shop: bool, perfect: bool, n: int) -> Dictionary:
	var scores: Array = []
	var coins: Array = []
	var spend: Array = []
	var runs: Array = []
	var rep := Report.new(n, GameConfig.SECTIONS_PER_RUN)
	rep.reset()
	var bot := Bot.new(_rng, rep)
	var pcfg := cfg.duplicate()
	pcfg["bot"] = "perfect" if perfect else "adaptive"
	for r in range(n):
		# ⚠ 配对的全部意义在这一行:每条臂的第 r 局用完全相同的种子。
		_rng.seed = 620000 + r
		var st := {"n": 0.0, "disc": 0.0, "rep": 0.0, "late": 0.0, "early": 0.0,
			"zerod": 0.0, "faces": 0.0, "chord": 0.0, "tgt": 0.0,
			"score": 0.0, "mult": 0.0, "kinds": {}}
		var pinned := {}                     # 槽位 -> 这一局专属的 Joker 实例
		for pair in install:
			pinned[int(pair[0])] = Joker.by_id(String(pair[1]))
		var once := {"done": false}
		# ⚠ **GDScript 的 lambda 按值捕获局部变量** —— int 计数器在闭包里 `+=` 传不出来,
		# 而 Dictionary 是引用类型所以正常。一半状态正常、一半静默丢失, 输出仍是合理的数字。
		var rec := {"beats": 0.0, "wild": 0.0, "kinds": {}, "income": 0.0}
		var o := RunLoop.Opts.new()
		o.rng = _rng
		o.deck_seed = r * 17 + 5
		# o.faces 留空 —— 全程无脸, 所以不掷脸;选主角是唯一消耗随机数的一步,
		# 和 RunLoop 内部「建 Run → 抽主角」的顺序天然一致, 不需要在外面预抽。
		o.player = "adaptive"                # 实际策略由 pcfg["bot"] 分派(见 RunLoop.Opts)
		o.cfg = pcfg
		o.shop = shop
		o.mortal = false
		o.st = st
		o.tally_mult_kinds = false
		o.on_begin = func(run: Run, _p: Phrase) -> void:
			for slot in pinned:
				if run.joker_slots[slot] != pinned[slot]:
					run.joker_slots[slot] = pinned[slot]
			if not once["done"]:
				once["done"] = true
				for slot in pinned:
					pinned[slot].on_acquire(run.deck)     # ⚠ 坑 ①
		o.on_beat = func(run: Run, p: Phrase, outcome: Dictionary, _ctx: Dictionary) -> void:
			st["disc"] += float(p.discards_used)
			rep.track_triggers(run.joker_slots, outcome)
			rec["income"] += float(outcome["coins"])
			var res: Dictionary = outcome.get("res", {})
			rec["beats"] += 1.0
			var kk := int(res.get("kind", -1))
			rec["kinds"][kk] = float((rec["kinds"] as Dictionary).get(kk, 0.0)) + 1.0
			# 万能牌的证物看**打出去的原始五张**(`res.cards`), 不是代入后的 `resolved` ——
			# 后者已经把万能牌换成了它冒充的那张牌, 看不出万能牌来过。
			for c in res.get("cards", []):
				if c != null and c.is_wild():
					rec["wild"] += 1.0
					break
		o.on_section = func(_run: Run, _s: int, _sc: int, _c: int) -> void:
			rec["income"] += float(GameConfig.SECTION_CLEAR_REWARD)
		# shop 通路的货架证物:Report 的计数器是全 arm 累计的, 逐局取差分
		# (联票=成交数 / 赞助=均价的分母 / 点唱机=含规则牌店率)。
		var b0 := rep.buys_total
		var s0 := rep.shops_n
		var r0 := rep.rule_shops_n
		var m0 := rep.multi_shops_n
		var d0 := rep.discount_coins
		var res_run := RunLoop.play(o, bot)
		rec["buys"] = float(rep.buys_total - b0)
		rec["shops"] = float(rep.shops_n - s0)
		rec["rule_shops"] = float(rep.rule_shops_n - r0)
		rec["multi_shops"] = float(rep.multi_shops_n - m0)
		rec["discount"] = float(rep.discount_coins - d0)
		# 被钉的那张卡的计数器终值(商店成长族的证物)。⚠ 取**这一局那个实例**的 state:
		# `pinned` 每局新建, 所以它就是「这一局涨到多少」;基准臂没有这张卡 → 恒 0。
		var cend := 0.0
		for slot in pinned:
			for cname in pinned[slot].state:
				cend = maxf(cend, float(pinned[slot].state[cname]))
		rec["counter"] = cend
		scores.append(res_run["total"])
		coins.append(float(res_run["coins"]))
		spend.append(float(GameConfig.STARTING_COINS) + float(rec["income"])
			- float(res_run["coins"]))
		runs.append(rec)
	return {"score": scores, "coins": coins, "spend": spend, "runs": runs,
		"trig": rep.trigger_n, "pres": rep.presence_n}
