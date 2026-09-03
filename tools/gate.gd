extends Probe

## 覆盖自证的门 —— **每张进池子的脸都要证明「它在模型里真的生效」**。
##   godot --headless --path . --script res://tools/gate.gd
##   SYNC5_GATE_FACE=<id>   只验一张脸(加了一张新脸时用这个, 十几秒)
##   SYNC5_GATE_N=<n>       改样本量(默认 score 250 / belief 60)
##
## 规格 = `docs/design/gates.md`。一句话:**一条规则如果进不了模型, 它就不该进池子。**
##
## 为什么要有这道门:这个项目栽过**四次同一个形状**的事故 —— 规则在游戏里生效,
## 在模型里是空气, 而**四次都不报错**:
##   ① 赶场 −2s(弃牌收费时代求解器根本不弃牌, 砍时间等于没砍)
##   ② cover 入场费(我读代码断定它零效果并退役了它, 实测 −518.1 分 ±123)
##   ③ 盖牌族(求解器看得见全部 8 张, 把牌盖起来对它零效果)
##   ④ 「最多弃 2 张」(求解器的上限本来就是 2 张 → 约束是空的)
## 事故的代价不是"少一张脸", 是**目标分照着一个没发生过的难度算**, 而且一路静默。
##
## 判据 = **配对 A/B**:同种子、同队列, 唯一的区别是这张脸在不在。
## 分差不显著 = 没接上(或者它本来就是空气规则)。**两种都该拦下来。**
## 通路按 `faces.json` 每张脸的 `proof` 字段分派 —— 声明错通路门会静默放过, 所以
## 那个字段是必填的(`DB.validate_faces` 锁着), 含义见 docs/design/blinds.md §4。
##
## 口径全部按项目铁律:配对(逐局作差)、报标准误和 z、不死局打满 24 拍。
## 同 `tools/coin.gd` / `tools/blind.gd`。**没有标准误的差值等于没有结论。**

const N_SCORE := 250       # 规则 bot, ~50 局/秒
const N_SOLVER := 150      # 完美玩家(求解器 8.4ms/拍), ~0.37 秒/局。lostpage 是最弱的一张
const N_BELIEF := 60       # ORACLE A/B 的效应巨大(z≈17), 60 局够了
const Z_MIN := 3.0         # 显著性:这个读数信不信得过
const MAG_MIN := 0.05      # 量级:效应占基准的比例, 低于它就是"不值得管"(见 _judge)

var _rng := RandomNumberGenerator.new()
var _only := ""
var _fail: Array = []
## 本条臂内的读数(label → {d, z, sig, big})。**每条臂开头清空** —— 变体只跟
## **同一条臂**里的基础脸比, 跨臂比是拿两把尺量同一个东西。
var _measured: Dictionary = {}
## 本条臂里 `_judge` 追加的那条红(label → 原字符串), 供变体和解时**精确摘除**
## (按前缀删会误伤另一条臂里同名的那条)。
var _fail_of: Dictionary = {}
var _warn: Array = []


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	_only = Probe.env_str("SYNC5_GATE_FACE")
	var n_score := Probe.env_int("SYNC5_GATE_N", N_SCORE)
	var n_solver := Probe.env_int("SYNC5_GATE_N", N_SOLVER)
	var n_belief := Probe.env_int("SYNC5_GATE_N", N_BELIEF)
	# ⚑⚑ **分片**(2026-09-03):`SYNC5_GATE_SHARD="i/n"` —— 只跑第 i 片(0 起)。
	# 起因:09-03 全量门 6h+,而 `gate.sh` 写的预算是 ≤10 分钟。wall-clock =
	# max(脸门, 卡门) = max(5h+, 48min) ⇒ **脸门是唯一的瓶颈**,而 28 张 solver 脸
	# 互相独立。用户 08-26:「门拖了一周工期」。
	# ⚠ 分片只切**按脸**的四条通路;单调性/哨兵是**全局**的, 只在 0 号片跑(见下)。
	var shard := Probe.env_str("SYNC5_GATE_SHARD")
	var shard_i := 0
	var shard_n := 1
	if shard != "":
		var sp: PackedStringArray = shard.split("/")
		if sp.size() == 2:
			shard_i = int(sp[0])
			shard_n = maxi(1, int(sp[1]))

	var cfg := _cohort()
	var ids := SectionMod.pooled_ids()
	# `SYNC5_GATE_FACE` 支持**逗号分隔的多个 id**(2026-08-13 增量门):一次改动常碰
	# 好几张脸, 逐张跑要重复付基准臂的钱 —— 而基准臂正是这段最贵的部分。
	if _only != "":
		var wanted: Array = []
		for part in _only.split(","):
			var t := part.strip_edges()
			if t == "":
				continue
			if not ids.has(t):
				print("[gate] '%s' 不在任何池子里 —— 没有池子就不需要自证" % t)
				quit(1)
				return
			wanted.append(t)
		if wanted.is_empty():
			print("[gate] SYNC5_GATE_FACE 里没有有效 id")
			quit(1)
			return
		# ⚠ **保持池内顺序**而不是照参数顺序 —— 同族软硬弧的检查依赖池序,
		# 而调用方给的顺序是「git diff 吐出来的顺序」, 没有语义。
		var kept: Array = []
		for fid in ids:
			if wanted.has(fid):
				kept.append(fid)
		ids = kept

	print("\n=== 覆盖自证的门 (docs/design/gates.md) ===")
	print("  队列 %s · score %d / solver %d / belief %d 局/臂 · 判据 |z| >= %.1f **且** 量级 >= %.0f%%"
		% [cfg.get("name", "?"), n_score, n_solver, n_belief, Z_MIN, MAG_MIN * 100.0])
	print("  问的不是「这张脸难不难」, 是「**模型看得见它吗**」。")

	var by_channel := {"score": [], "solver": [], "belief": [], "target": []}
	for fid in ids:
		var ch := SectionMod.proof(fid)
		if not by_channel.has(ch):
			_fail.append("%s: 没有 proof 通路声明" % fid)
			continue
		by_channel[ch].append(fid)

	if shard_n > 1:
		for ch2 in by_channel.keys():
			by_channel[ch2] = _shard_of(by_channel[ch2], shard_i, shard_n)
		print("  [分片 %d/%d] 本片负责:score %d · solver %d · belief %d · target %d 张"
			% [shard_i, shard_n, by_channel["score"].size(), by_channel["solver"].size(),
				by_channel["belief"].size(), by_channel["target"].size()])

	if not by_channel["score"].is_empty():
		_timed("① score", func() -> void: _run_score(cfg, by_channel["score"], n_score),
			by_channel["score"].size(), n_score)
	if not by_channel["solver"].is_empty():
		_timed("①b solver", func() -> void: _run_solver(cfg, by_channel["solver"], n_solver),
			by_channel["solver"].size(), n_solver)
	if not by_channel["belief"].is_empty():
		_timed("② belief", func() -> void: _run_belief(cfg, by_channel["belief"], n_belief),
			by_channel["belief"].size(), n_belief)
	if not by_channel["target"].is_empty():
		_timed("③ target", func() -> void: _run_target(cfg, by_channel["target"], n_score),
			by_channel["target"].size(), n_score)
	# ⚠ 单调性/哨兵是**全局**的(不按脸), 只在 0 号片跑一次 —— 每片都跑等于白付 N 倍。
	if _only == "" and shard_i == 0:
		_timed("④ 单调性", func() -> void: _run_monotonic(cfg, n_score), 5, n_score)
		_timed("⑤ 哨兵", func() -> void: _run_sentinel(cfg, n_score), 1, n_score)

	print("\n=== 判据 ===")
	for w in _warn:
		print("  ⚠ %s" % w)
	if _fail.is_empty():
		print("  ✅ 每张脸都在模型里量到了效果 —— 目标分可以照着这批脸算")
	else:
		for f in _fail:
			print("  ❌ %s" % f)
		print("\n  「量不到」有两种可能, 都必须当场查清楚, 不许放行:")
		print("    ① 规则没接进模型(求解器/bot 读不到它)—— 修接线;")
		print("    ② 规则接上了但它本来就是空气(约束不 binding)—— 那张脸该退役或重做。")
	print("\n[gate] %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(1 if not _fail.is_empty() else 0)


## --- ① score 通路:规则 bot + 开着商店。分数/经济两条线都在这条臂里。 ---
func _run_score(cfg: Dictionary, ids: Array, n: int) -> void:
	print("\n  ---- ① score 通路(规则 bot, 带商店) ----")
	_measured.clear(); _fail_of.clear()
	var base := _play_score(cfg, "", n)
	print("    基准总分 %.0f" % Stat.mean(base))
	for fid in ids:
		var arm := _play_score(cfg, fid, n)
		_judge(fid, base, arm, Stat.mean(base), _weak_declared(fid))
	_reconcile_variants()


## --- ①b solver 通路:攻击**跨拍养牌**或**时间预算**的脸, 必须拿完美玩家当尺子。 ---
##
## ⚠⚠ 这条通路是这道门跑第一次就挣回本钱的地方。用规则 bot 量出来的是:
##   freshsheet **+1584**(z=+7.9)· lostpage **+1020**(z=+6.4)· rush −267(z=−1.76, 量不到)
## 换成完美玩家:
##   freshsheet **−790**(z=−5.1)· lostpage **−393**(z=−2.8)· rush **−823**(z=−5.4)
## **两张脸的符号是反的。** 根因不是 bug:规则 bot 不跨拍养缓存, 它留在缓存里的本来就是
## 挑剩的烂牌, 把缓存整个洗掉是在**帮它**; 而完美玩家 λ=0.2 真在养牌(warm.gd 实测 +10.4%),
## 洗缓存对它是纯损失。rush 同理 —— 规则 bot 几乎用不满弃牌预算, 砍时间砍不到它头上。
## **教训:「模型看得见这张脸吗」这个问题, 答案取决于你拿哪个模型去看。**
func _run_solver(cfg: Dictionary, ids: Array, n: int) -> void:
	print("\n  ---- ①b solver 通路(完美玩家, 无商店) ----")
	_measured.clear(); _fail_of.clear()
	var base := _play_perfect(cfg, "", false, n)
	print("    基准总分 %.0f" % Stat.mean(base))
	for fid in ids:
		var arm := _play_perfect(cfg, fid, false, n)
		_judge(fid, base, arm, Stat.mean(base), _weak_declared(fid))
	_reconcile_variants()


## --- ② belief 通路:必须用完美玩家 —— 规则 bot 全程上帝视角, 量这一族恒等于 0。 ---
##
## 对照臂 = `Solver.ORACLE`:同一局、同一批随机数、同一张脸, 唯一的区别是
## **求解器看不看得见盖着的牌**。两条臂的差 = 那几张牌的信息值。
## 盖牌不改任何数值, 所以「脸的效果」和「信息的价值」**应该相等**(blind.gd 实测差 2% 以内);
## 差 ≈ 0 就说明信念机制根本没接上, 那这一族只是画面效果。
func _run_belief(cfg: Dictionary, ids: Array, n: int) -> void:
	print("\n  ---- ② belief 通路(完美玩家 · ORACLE A/B) ----")
	print("    ⚠ 这一栏量的是「求解器真的被蒙住了吗」, 不是难度。")
	for fid in ids:
		var blinded := _play_perfect(cfg, fid, false, n)
		var oracle := _play_perfect(cfg, fid, true, n)
		var d := _judge("%s: 上帝 − 蒙住" % fid, blinded, oracle)
		if d < 0.0:
			_fail.append("%s: 上帝视角反而打得更低 —— 信念机制接反了" % fid)


## --- ③ target 通路:不走分数, 走目标分。纯算术, 不跑局。 ---
##
## raisedbar 这类脸在不死局的分数臂里**按定义恒等于 0**(它一分不改), 所以拿分数去验
## 它只会得出「没接上」。它的通路是 `core/run.gd::section_target`, 直接验算即可 ——
## **便宜的证明就该用便宜的方法, 不必为了统一而去跑蒙特卡洛。**
## ⚠ **算术验算不够。** 我第一版只验了 `core/run.gd`(游戏侧)就放行, 而 `tools/sim.gd`
## 判生死时直接读表、根本没乘 target_mult —— 游戏里 ×1.5, 模型里当它不存在。
## 那正是这道门要拦的东西, 却被这道门自己漏掉了。所以第二段是**行为臂**:
## 真的判一遍生死, 通关段数必须掉下来。**证明要落在做决定的那条路径上, 不是它的定义上。**
func _run_target(cfg: Dictionary, ids: Array, n: int) -> void:
	print("\n  ---- ③ target 通路(目标分) ----")
	for fid in ids:
		if SectionMod.required_kinds(fid) > 0:
			_check_kind_gate(fid)
			continue
		var mult := SectionMod.target_mult(fid)
		var run := Run.new()
		var moved := false
		for idx in GameConfig.WALL_SECTIONS:
			run.section_idx = idx
			run.run_faces = {}
			var plain := run.target()
			run.run_faces = {idx: fid}
			var raised := run.target()
			if raised != plain:
				moved = true
			if raised != int(round(float(plain) * mult)):
				_fail.append("%s: S%d 目标 %d -> %d, 但 target_mult 是 %.2f"
					% [fid, idx + 1, plain, raised, mult])
		print("    %-28s target_mult = %.2f  %s"
			% [fid, mult, "✓ 目标分随之变化" if moved else "❌ 目标分纹丝不动"])
		if not moved:
			_fail.append("%s: 目标分完全没动 —— 没接上 core/run.gd" % fid)
	# 2026-08-10 起给行为臂传真实基准与豁免位:trilogy 实测 0.0 ±0.0 —— 规则 bot
	# 六拍里天然打出 ≥3 种牌型(对子/两对/高牌), 配额对它不 binding。这是「对仪器是
	# 空气」不是「没接上」(_check_kind_gate 的翻盘验算证明接上了), 所以要走豁免通道,
	# 而豁免只在「量级小」分支生效 —— 不传基准时量级恒真, 豁免永远够不着。
	var base := _play_sections(cfg, "", 1.0, 0, n)
	for fid in ids:
		var arm := _play_sections(cfg, fid, 1.0, 0, n)
		_judge("%s: 通关段数(判生死)" % fid, base, arm, Stat.mean(base), _weak_declared(fid))


## required_kinds 族(trilogy):2026-08-13 裁决 #8 起是**税不是硬门** ——
## 种数配额并进 `Run.variety_mult`(缺一种目标 ×(1+penalty)), 悲观实时。
## 算术验算:同一个 run, 种数从满配额到缺一/缺二, target() 必须按罚档单调上升;
## 且 cleared 随「同一份分数 vs 涨过税的目标」正确翻转。
## 行为臂(通关段数)与 target_mult 族共用上面那段。
func _check_kind_gate(fid: String) -> void:
	var kinds := SectionMod.required_kinds(fid)
	var pen := SectionMod.variety_penalty(fid)
	var ok := true
	var run := Run.new()
	run.section_idx = 0
	run.run_faces = {0: fid}
	run.section_kinds = {}
	for i in kinds:
		run.section_kinds["kind_%d" % i] = true
	var base_t := run.target()
	for missing in [1, 2]:
		run.section_kinds.erase("kind_%d" % (kinds - missing))
		var want := int(round(float(base_t) * (1.0 + pen * float(missing)) \
			/ (1.0 + pen * 0.0)))
		if run.target() != want:
			ok = false
	# cleared 翻转:分数够基准目标、但缺一种 → 税后目标没够到 = 不许过
	run.section_kinds = {"a": true, "b": true}
	run.phrase_in_section = GameConfig.PHRASES_PER_SECTION - 1
	run.section_score = base_t + 1
	var out := run.advance()
	if bool(out["cleared"]):
		ok = false
	print("    %-28s variety_penalty = %.2f  %s"
		% [fid, pen, "✓ 缺种即加税(判生死接上了)" if ok else "❌ target 没有随缺种上升"])
	if not ok:
		_fail.append("%s: target()/cleared 没有随缺种上涨 —— variety_mult 没接进 core/run.gd" % fid)


## --- ④ 结构单调性(docs/design/gates.md):无论数值怎么调都必须成立的方向。 ---
##
## 便宜, 而且抓的正是最难发现的那类事故:`bot_targets` 失效那次, 表被静默截断成
## 放水盘之后, 「调高目标」和「通关变难」的关系当场就断了 —— 但没人在看那个关系。
func _run_monotonic(cfg: Dictionary, n: int) -> void:
	print("\n  ---- ④ 结构单调性 ----")
	var lo := _play_sections(cfg, "", 0.6, 0, n)
	var mid := _play_sections(cfg, "", 1.0, 0, n)
	var hi := _play_sections(cfg, "", 1.6, 0, n)
	_mono("目标分 ×0.6 → ×1.0", lo, mid, false)
	_mono("目标分 ×1.0 → ×1.6", mid, hi, false)
	var poor := _play_sections(cfg, "", 1.0, -3, n)
	var rich := _play_sections(cfg, "", 1.0, 3, n)
	_mono("起始金币 −3 → 0", poor, mid, true)
	_mono("起始金币 0 → +3", mid, rich, true)
	# 脸加狠 → 必须更难。norepeat/rerun 是同一个参数的软硬两档(0.5 / 0.0),
	# 天然就是这条断言的现成素材 —— 不必为它造一张假脸。
	if SectionMod.by_id("norepeat") != null and SectionMod.by_id("rerun") != null:
		var soft := _play_sections(cfg, "norepeat", 1.0, 0, n)
		var hard := _play_sections(cfg, "rerun", 1.0, 0, n)
		_mono("禁回 0.5 → 炒冷饭 0.0", soft, hard, false)
	# ⚠ 拼写保护:`KNOWN_FLAT` 的 key 必须逐字对上某条断言的 label ——
	# 拼错会让豁免**静默失效**(门照旧红, 而作者一头雾水), 与 faces.json 的
	# `weak_upper_bound` 拼错 id 是同款坑, 那边已经挡掉了, 这边照做。
	for fl in KNOWN_FLAT:
		if not _flat_seen.has(fl):
			_fail.append("KNOWN_FLAT 里的 '%s' 没有对上任何一条单调性断言 —— 拼错了, 或者那条断言已经改名"
				% fl)


## **已知零效应**的单调性断言(2026-08-13 补;同 `faces.json weak_upper_bound` 与
## `kit.gd WEAK_MAGNITUDE` 的哲学)。
##
## 起因:金币那两条断言量出的效应**恒为零**, 于是它们的绿灯完全取决于四舍五入的符号
## —— 08-12 `+0.00 ✓`、08-13 `−0.00 ❌`, **同一个零**。那不是在守护不变量, 是在抛硬币,
## 而**一道靠运气变绿的门和一道永远红的门一样没用**。
##
## 「零」这个读数本身早被裁定过:S9(`tools/wallet.gd` 200 局)——
## **「经济卡近乎无价值是游戏事实,不是模型缺陷」**:买不起只占 0.1%、局末余额 34.7◆、
## 后期钱花不出去是因为那时没什么值得买的了。往一个已经溢出的桶里再加 3 枚金币,
## 当然什么都不会发生。
##
## ⚠ 声明的语义是「**这个旋钮对当前 bot 的通关段数没有边际效应**」,
## **不是**「这个旋钮不重要」—— 真人的购买力约束与 bot 差得远。所以一律标「真人待定」。
## ⚠ 反向锁在 `_mono` 里:声明了却实测有明显效应 = 表过期, 当场红要求删条目。
## ⚠ **别把它当放宽阈值的口子**:方向反了且量级**超过** `FLAT_BAND` 的照旧红 ——
## 豁免只吃「零」, 不吃「负」。
## ⚑ **2026-08-15:「起始金币 −3 → 0」已摘掉** —— 反向锁当场抓到,实测 **+0.02 段**
## 正好压在 `FLAT_BAND` 的边界上(判定是严格小于), 门要求删条目, 照办。
## ⚠ 行内那条断言**本身是 ✓**(3.61 → 3.63, 钱多了段数没变少)—— 红的只是这张记账表。
##
## **为什么现在才过期(假说, 有代码依据但未 A/B)**:同日第四轮补脸 1 → 4,
## 而 `closing` 的 `discard_actions: 1` 在 `core/phrase.gd::can_discard` 里被强制 ——
## **规则 bot 走 `Phrase` 打牌, 所以它对 bot 是 binding 的**(对求解器不是, 求解器不建模
## 弃牌次数)。bot 约 1/4 的局在 S4 撞上它 ⇒ S4 变难 ⇒ 边际金币的价值微微上升。
##
## ⚠⚠ **残留风险, 写在这里别让它消失**:摘掉之后这条断言只靠单调性判, 而它当初被声明成
## 「零效应」正是因为**效应恒为零时绿灯取决于四舍五入的符号**(08-12 `+0.00 ✓` /
## 08-13 `−0.00 ❌`, 同一个零)。**效应若漂回 0, 抛硬币就会回来。**
## 真正的修法不是把 `FLAT_BAND` 调宽(那是**为门绿改仪器**), 而是**把带宽从实测标准误推出来**
## —— 而下面那个 ±0.005 的噪声值是 **S10 之前**测的, 它自己也已经过期。
## ⚑ 2026-08-25:「起始金币 0 → +3」也摘掉了(表一度只剩它一条, 现在空表)——
## 08-24 新基线(删主角被动 + 探针世界有 boon)下实测 +0.02 段压到判定带上沿,
## 哨兵按自己的规则喊「不再是零效应」。S9 那句裁定的**世界已经变了**, 声明跟着世界走;
## 空表留着:结构和拼写保护都在, 下一条零效应声明照旧往里写。
const KNOWN_FLAT := {}
## 「零」的判定带:通关段数满分 4.00, 真效应实测 0.47~1.34 段, 噪声在 ±0.005 ——
## 0.02 段(0.5%)能干净地把两者分开, 且远小于任何真实效应。
const FLAT_BAND := 0.02

var _flat_seen: Dictionary = {}


func _mono(label: String, a: Array, b: Array, want_up: bool) -> void:
	var d: float = Stat.mean(b) - Stat.mean(a)
	# ⚑ 2026-08-26:带宽改从**实测标准误**推出 —— 正是上面「残留风险」段预告的真修法。
	# 起因:金币 −3→0 在 08-26 新基线量出 −0.01 段(±SE ≈ 0.03), 统计上就是零,
	# 但旧判定(d ≥ −0.0001)把噪声符号当方向 —— 抛硬币门第三次回来。
	# |Δ| < 2·SE_diff ⇒ 方向**不可判**, 打 ⚠ 平坦进 _warn, 不红也不假绿;
	# 方向反了且超出噪声带的照旧红。两臂共享 RNG 连续流、非配对, 用独立样本公式。
	# ⚠ 这不是调宽 FLAT_BAND(那是拍的常数, 已过期过一次)—— SE 跟着 n 与方差走。
	var se_d: float = sqrt(Stat.variance(a) / maxf(1.0, float(a.size()))
		+ Stat.variance(b) / maxf(1.0, float(b.size())))
	var ok: bool = d >= -0.0001 if want_up else d <= 0.0001
	var noise_flat: bool = (not ok) and absf(d) < 2.0 * se_d
	# 零效应 + 已声明 → ⚠ 而不是 ❌(行内就看得出来:一个印着 ❌ 却放行的读数
	# 会让下一个人整体不信这道门, 这条教训今天刚在 kit.gd 上付过一次)
	# ⚠ `_flat_seen` 记的是「这条 label **存在**」而不是「豁免生效了」——
	# 否则「声明了但效应变真」会同时触发反向锁和拼写保护, 两条报同一件事。
	if KNOWN_FLAT.has(label):
		_flat_seen[label] = true
	var flat: bool = absf(d) < FLAT_BAND and KNOWN_FLAT.has(label)
	print("    %-28s 通关段数 %.2f → %.2f  (%+.2f ±%.2f)  %s"
		% [label, Stat.mean(a), Stat.mean(b), d, se_d,
		("⚠ 已知零效应(已声明)" if flat
		else ("⚠ 平坦(|Δ|<2SE, 方向不可判)" if noise_flat
		else ("✓" if ok else "❌ 方向反了")))])
	if flat:
		_warn.append("%s: 实测 %+.2f 段 ≈ 0 —— %s" % [label, d, KNOWN_FLAT[label]])
		return
	if noise_flat:
		_warn.append("%s: 实测 %+.2f ±%.2f 段 —— 噪声带内, 方向不可判(想缩带加大 n)"
			% [label, d, se_d])
		return
	if not ok:
		_fail.append("单调性破了: %s 应该%s, 实际 %+.2f 段(±%.2f, 超出噪声带)"
			% [label, "变容易" if want_up else "变难", d, se_d])
	elif KNOWN_FLAT.has(label) and absf(d) >= FLAT_BAND:
		# 反向锁:声明了「零效应」却量出真效应 —— 说明那条裁定过期了(比如经济系统
		# 重做之后钱重新成为约束)。这是**好消息**, 但表必须跟着改, 否则下一次真的
		# 塌了没人拦得住。
		_fail.append("%s 实测 %+.2f 段(≥%.2f)—— 它不再是零效应, 把它从 KNOWN_FLAT 删掉"
			% [label, d, FLAT_BAND])


## --- ⑤ 生成器哨兵(docs/design/gates.md):目标分必须落在**录得到**的分数范围内。 ---
##
## 落在范围外 = 反解那一步在做分位数**外推**, 而外推出来的分位数没有意义。
## (另两条哨兵 —— 乱打必须过不了 / 最强必须过得了 —— `tools/sim.gd` 已经有了,
##  非零退出, 不在这里重复。)
## ⚠ 人群必须和 `curve.gd` 反解时用的**同一个**(混合人群 = 除 random/baseline 外等权),
## 否则拿单一队列的分数范围去判另一个人群的表, 结论不成立。
##
## ⚠ 第一版我拿**单一队列**(adaptive:twin)当人群, 报出「S1/S2 目标在录到范围之外」——
## **那是假警**: 表是混合人群反解的, 用单一队列的范围去判它结论不成立。换成同一人群后四段全绿。
## **和通路选错是同一条教训:选错仪器/人群, 哨兵会自信地报一个不存在的问题。**
##
## ⚠ **默认只警告, 不非零退出**(`SYNC5_GATE_STRICT=1` 打开)。理由:两张表按旧脸算,
## 重算排在「定价」那一步, 那之前这条随时可能红 —— 而**一道常红的门等于没有门**,
## 会把真正的覆盖失败淹掉。等目标分重算完就该打开 STRICT。
func _run_sentinel(_cfg: Dictionary, n: int) -> void:
	print("\n  ---- ⑤ 生成器哨兵(目标分在录到的范围内吗) ----")
	var strict := Probe.flag("SYNC5_GATE_STRICT")
	var table: Array = DB.sim().get("bot_targets", GameConfig.SECTION_TARGETS)
	var got := _section_scores(mini(n, 100))   # 100 = curve.gd 反解时的 N_RUNS, 对齐口径
	for s in range(GameConfig.SECTIONS_PER_RUN):
		var tgt := Run.section_target_for(table, s, "")
		var lo: float = got[s]["lo"]
		var hi: float = got[s]["hi"]
		var died: float = got[s]["died"]
		var inside: bool = float(tgt) >= lo and float(tgt) <= hi
		print("    S%d 目标 %-7d 录到 [%.0f, %.0f]  死亡率 %.0f%%   %s"
			% [s + 1, tgt, lo, hi, died * 100.0, "✓" if inside else "❌ 在录到的范围之外"])
		if not inside:
			var msg := "S%d 目标 %d 落在录到的分数范围 [%.0f, %.0f] 之外 —— 反解那一步在外推" \
				% [s + 1, tgt, lo, hi]
			if strict:
				_fail.append(msg)
			else:
				_warn.append(msg + "(表按旧脸算的, 重算排在定价那一步; SYNC5_GATE_STRICT=1 可让它变红)")


## 判据**两条**(2026-08-08 用户拍板 A 案):**显著** 且 **量级够**。
##
## 为什么必须两条 —— 这是本项目所有读数的通用纪律(`docs/design/gates.md`):
##   · **显著性(z)** 回答「这个读数信不信得过」;
##   · **量级(占基准的比例)** 回答「这个效应要不要管」。
## **蒙特卡洛的样本量是我们自己定的, 样本一大什么都会显著** —— 只看 z 等于让判据
## 跟着预算走。反过来只看量级又会把纯噪声当成大效应。
##
## ⚠ 两条判据把「量不到」拆成了**两种性质完全不同的失败**:
##   · 量级够但不显著 → **样本不足或效应不稳**, 这是真要去查的;
##   · 量级不够       → **效应真的小**, 那不是"模型看不见", 是"不值得管"。
## 后者允许豁免, 但**豁免必须是有意的**(照 `fixed_tiers` 的思路, 见 faces.json
## `weak_upper_bound`)—— 没声明的照样红。
##
## ⚑ **反向保护**:声明了豁免、实测却两条都过 → **报警**。
## 否则豁免会变成一块永久的遮羞布, 而机制/数值改动之后它早就不成立了。
## ⚑⚑ **按「族」分片, 不是按脸**(2026-09-03)。
##
## ⚠⚠ 这是写这个功能时差点踩进去的坑:`_reconcile_variants()` 是**臂内**比较 ——
## `norepeat` 和 `norepeat75` 一旦落到不同进程, 基础脸就不在 `_measured` 里,
## 和解当场失效, 变体重新变红。**并行化把一个刚修好的东西又弄坏, 而且不报错。**
## ⇒ 族 = `base` 字段(没有就是自己), 整族一起分给同一片。
## ⚠ 族大小不均 ⇒ 分片负载不均, 但正确性优先于均衡 —— 而且最大的族也只有 4 张。
func _shard_of(ids: Array, shard_i: int, shard_n: int) -> Array:
	var fams: Array = []             # 保持池序, 不用 Dictionary 的键序
	var by_fam := {}
	for fid in ids:
		var b := _variant_base(String(fid))
		var fam: String = String(fid) if b == "" else b
		if not by_fam.has(fam):
			by_fam[fam] = []
			fams.append(fam)
		by_fam[fam].append(fid)
	var out: Array = []
	for i in range(fams.size()):
		if i % shard_n == shard_i:
			out.append_array(by_fam[fams[i]])
	return out


## ⚑ 逐臂计时(2026-09-03)。
## 起因:门跑 6 小时, 而**它连「哪条臂吃掉了 4 小时」都答不出来** —— 我只能拿
## 文档里的「~0.37 秒/局」去推, 而那个标注偏了约 6 倍(CLAUDE.md 早写着别信它)。
## **这个项目的规矩是不猜去量, 而这道门自己从没被量过。**
func _timed(label: String, body: Callable, faces_n: int, runs: int) -> void:
	var t := Time.get_ticks_msec()
	body.call()
	var secs := float(Time.get_ticks_msec() - t) / 1000.0
	var total := faces_n * runs
	print("    \u001b[90m[计时] %s  %.0fs  (%d 单位 × %d 局 = %d 局, %.1f 局/秒)\u001b[0m"
		% [label, secs, faces_n, runs, total, float(total) / maxf(0.001, secs)])


## 这张脸在 `faces.json` 里**字面写了** `base` 吗(档位变体)。
## ⚠ 不走 `SectionMod.base_of()` —— 那个口对**复合脸**会回落到第一成分, 而复合脸的
## 量级不该由它的某一个成分来背书(复合的卖点恰恰是「合起来才难」)。
func _variant_base(fid: String) -> String:
	for e in DB.faces().get("faces", []):
		if String(e["id"]) == fid:
			return String(e.get("base", ""))
	return ""


## ⚑⚑ **档位变体的和解**(2026-09-02 立)。
##
## 病根:`MAG_MIN = 5%` 这条地板问的是「这个效应值不值得管」, 而**档位变体被设计出来
## 就是要比它的基础脸轻或重**。`norepeat`(`repeat_factor 0.5`, 砍一半)量到 **6.8%**,
## 它的轻档 `norepeat75`(`0.75`, 砍四分之一)量到 **3.2%** —— 比值 0.47 ≈ 参数比 0.50,
## **模型把这个参数看得清清楚楚**(z = −13.26, 全表最显著的几条之一), 却因为撞上一条
## 为基础脸设的地板被判红。⇒ 拿它去写 `weak_upper_bound` 是把仪器问题记成内容债。
##
## 判据(**没有魔法数**):变体只要 ① 显著(|z| ≥ Z_MIN)· ② 与基础脸**同号**
## · ③ **基础脸自己完整通过**(显著且量级够)—— 三条齐了, 量级由基础脸承担。
## ⚠ ③ 是防止这条变成后门的那一条:基础脸自己弱 ⇒ **整族红**, 变体不许借它的光。
##
## ⚑ 这一层**同时是新增的红**:变体与基础脸**符号相反**过去无人过问, 现在直接判红 ——
##   那意味着参数轴坏了(加大剂量反而变好), 比「量级小」严重得多。
## ⚠ 只在**同一条臂内**比较(`_measured` 每条臂开头清空)——
##   拿 score 臂的基础脸给 solver 臂的变体背书, 是拿两把尺量同一个东西。
func _reconcile_variants() -> void:
	for label in _measured.keys():
		var m: Dictionary = _measured[label]
		if not bool(m["sig"]):
			continue
		var b := _variant_base(String(label))
		if b == "" or b == label or not _measured.has(b):
			continue
		var mb: Dictionary = _measured[b]
		if signf(float(m["d"])) != signf(float(mb["d"])) and absf(float(mb["d"])) > 0.0:
			var bad := "%s: 与基础脸 %s **符号相反**(%+.1f vs %+.1f)—— 参数轴坏了, 加大剂量反而变好" \
				% [label, b, float(m["d"]), float(mb["d"])]
			print("    \u001b[31m✗ %s\u001b[0m" % bad)
			if not _fail.has(bad):
				_fail.append(bad)
			continue
		if bool(m["big"]):
			continue                     # 自己就过了, 不需要和解
		if not (bool(mb["sig"]) and bool(mb["big"])):
			continue                     # 基础脸自己没过 ⇒ 整族红, 不许借光
		if _fail_of.has(label):
			_fail.erase(_fail_of[label])
			_fail_of.erase(label)
		var note := "%s: 量级 %.1f%% < %.0f%%, 但它是 %s 的档位变体(同号 · z=%+.2f · 基础脸 %.1f%% 已过)—— 量级由基础脸承担" \
			% [label, float(m["mag"]) * 100.0, MAG_MIN * 100.0, b, float(m["z"]), float(mb["mag"]) * 100.0]
		print("    \u001b[36m↳ 变体和解:%s\u001b[0m" % note)
		_warn.append(note)


func _judge(label: String, a: Array, b: Array, base: float = 0.0,
		weak_declared: bool = false) -> float:
	var p := Stat.paired(a, b)
	var z: float = p["d"] / maxf(0.001, p["se"])
	var mag: float = absf(p["d"]) / maxf(1.0, absf(base)) if base != 0.0 else 1.0
	var sig: bool = absf(z) >= Z_MIN
	var big: bool = mag >= MAG_MIN
	var verdict := ""
	if sig and big:
		verdict = "✓ 量到了"
	elif not big and weak_declared:
		verdict = "⚠ 豁免(上界效应小, 已声明)"
	elif not big:
		verdict = "❌ 效应太小"
	else:
		verdict = "❌ 不稳(量级够但不显著)"
	_measured[label] = {"d": p["d"], "z": z, "sig": sig, "big": big, "mag": mag}
	var mag_txt := "" if base == 0.0 else "  %.1f%%" % (mag * 100.0)
	print("    %-28s %+9.1f  ±%.1f   z = %+.2f%s   %s"
		% [label, p["d"], p["se"], z, mag_txt, verdict])
	if sig and big:
		# ⚑ 声明过期:它已经量得到了, 那条豁免就是在遮一个不存在的问题。
		if weak_declared:
			_warn.append("%s: 已经量到了(z=%.2f, %.1f%%), 但仍挂在 weak_upper_bound 里 —— 声明过期, 摘掉它"
				% [label, z, mag * 100.0])
	elif not big and weak_declared:
		_warn.append("%s: 分差 %.1f (%.1f%% < %.0f%%) —— 上界效应小, 已声明豁免。**真人待定**"
			% [label, p["d"], mag * 100.0, MAG_MIN * 100.0])
	elif not big:
		var msg := "%s: 分差 %.1f ±%.1f (z=%.2f) 只占基准 %.1f%% < %.0f%% —— 效应太小。若确认「对完美玩家真的小」, 写进 faces.json 的 weak_upper_bound(必须显式声明)" \
			% [label, p["d"], p["se"], z, mag * 100.0, MAG_MIN * 100.0]
		_fail.append(msg)
		_fail_of[label] = msg
	else:
		_fail.append("%s: 分差 %.1f ±%.1f (z=%.2f) 量级够(%.1f%%)但不显著 —— 样本不足或效应不稳, 这条要查"
			% [label, p["d"], p["se"], z, mag * 100.0])
	if sig and p["d"] > 0.0 and not label.contains("上帝"):
		# 不是覆盖问题(它显然接上了), 但一张让玩家**打得更高**的 Boss 脸是设计事故。
		_warn.append("%s: 效果是 %+.1f —— 这张脸让分数**上升**了, 确认是有意的" % [label, p["d"]])
	return p["d"]


## 这张脸是否被显式声明为「上界效应小」(`faces.json` 的 `weak_upper_bound`)。
## ⚠ 只影响**量级**那一条判据, 不影响显著性 —— 声明改不了"这个读数信不信得过"。
## ⚠ belief / target 两条通路**不传 base**, 于是量级判据在那里恒真、行为与改动前完全一样:
## 信息值和通关段数各有各的尺度, 5% 这个数是按分数通路标定的, 不该硬套过去。
func _weak_declared(fid: String) -> bool:
	for w in DB.faces().get("weak_upper_bound", []):
		if String(w) == fid:
			return true
	return false


func _cohort() -> Dictionary:
	# 第一条真实人群队列就够 —— 这里量的是「脸有没有效果」, 不是流派强弱。
	for c in DB.sim()["cohorts"]:
		if String(c.get("bot", "")) == "random" or bool(c.get("no_jokers", false)):
			continue
		return c
	return {}


## 不死局打满 24 拍, 每段挂同一张脸, 返回每局总分。结构同 tools/sim.gd 的主循环
## (脸的接线点一个都不能少:mod 要在 start() **之前**赋值 —— 缓存容量在那里生效)。
##
## ⚠ 2026-08-08 迁到 `RunLoop`(一局的骨架只此一份)。st 记账口径同 addit/price:只手动记过
## n/score/disc, 没记过 mult/kinds —— 关掉 `tally_mult_kinds`, disc 照旧手动补。
func _play_score(cfg: Dictionary, mod: String, n: int) -> Array:
	var scores: Array = []
	var rep := Report.new(n, GameConfig.SECTIONS_PER_RUN)
	rep.reset()
	var bot := Bot.new(_rng, rep)
	var pcfg := cfg.duplicate()
	pcfg["bot"] = "adaptive"
	var faces := {}
	for w in GameConfig.WALL_SECTIONS:
		faces[w] = mod
	for r in range(n):
		# ⚠ 配对的全部意义在这一行:每条臂的第 r 局用完全相同的种子。
		_rng.seed = 620000 + r
		var st := {"n": 0.0, "disc": 0.0, "rep": 0.0, "late": 0.0, "early": 0.0,
			"zerod": 0.0, "faces": 0.0, "chord": 0.0, "tgt": 0.0,
			"score": 0.0, "mult": 0.0, "kinds": {}}
		var o := RunLoop.Opts.new()
		o.rng = _rng
		o.deck_seed = r * 17 + 5
		o.faces = faces
		o.player = "adaptive"
		o.cfg = pcfg
		o.shop = true
		o.mortal = false
		o.st = st
		o.tally_mult_kinds = false
		o.on_beat = func(_run: Run, p: Phrase, _outcome: Dictionary, _ctx: Dictionary) -> void:
			st["disc"] += float(p.discards_used)
		var res := RunLoop.play(o, bot)
		scores.append(res["total"])
	return scores


## 判生死臂:返回每局**通关了几段**(0..4)。用 0..4 而不是「通关了没有」是为了功效 ——
## 二值结果在 250 局里只够看巨大的效应, 段数是同样成本下更灵敏的统计量。
## 尺子 = `sim.json bot_targets`(机器人影子表)× `target_scale`, 脸的加码走
## `Run.section_target_for` —— **和 sim 判生死是同一份实现**, 否则这条臂会在
## sim 漏乘 target_mult 的时候照样绿(第一版就栽在这里)。
func _play_sections(cfg: Dictionary, mod: String, target_scale: float, coin_delta: int, n: int) -> Array:
	var out: Array = []
	for r in _play_runs(cfg, mod, coin_delta, n, true, target_scale):
		out.append(float(r["cleared"]))
	return out


## 不死局打满, 返回每段分数的 [最小, 最大] 和落在目标以下的比例。
## **人群 = curve.gd 反解 bot_targets 时用的那一个**(混合人群, 等权), 不是单一队列。
func _section_scores(n: int) -> Array:
	var table: Array = DB.sim().get("bot_targets", GameConfig.SECTION_TARGETS)
	var lo: Array = []
	var hi: Array = []
	var below: Array = []
	var tot: Array = []
	for s in range(GameConfig.SECTIONS_PER_RUN):
		lo.append(INF)
		hi.append(-INF)
		below.append(0.0)
		tot.append(0.0)
	for c in DB.sim()["cohorts"]:
		if String(c.get("bot", "")) == "random" or bool(c.get("no_jokers", false)):
			continue      # 和 curve.gd 同一条过滤: random 是回归基线, baseline 不买牌
		for r in _play_runs(c, "", 0, n, false, 1.0):
			var secs: Array = r["sec"]
			for s in range(secs.size()):
				lo[s] = minf(lo[s], float(secs[s]))
				hi[s] = maxf(hi[s], float(secs[s]))
				tot[s] += 1.0
				if float(secs[s]) < float(Run.section_target_for(table, s, "")):
					below[s] += 1.0
	var out: Array = []
	for s in range(GameConfig.SECTIONS_PER_RUN):
		out.append({"lo": lo[s], "hi": hi[s], "died": below[s] / maxf(1.0, tot[s])})
	return out


## 规则 bot + 商店的整局循环, 判不判生死由 `judge` 决定。结构同 tools/sim.gd::_one_run。
##
## ⚠ 2026-08-08 迁到 `RunLoop`(一局的骨架只此一份)。`RunLoop` 的 `mortal` 判生死没有
## `target_scale`(倍率)这个口子, 也不支持自定义起始金币以外的判生死表达式, 所以这里
## **不用 `o.mortal`**, 照旧不死局打满 24 拍(`o.mortal=false`), 拿到完整 4 段分数后
## **在外面按原逻辑逐段比对**。这样做结果不变的原因: 游戏本身不知道"死了", 死不死是
## 外部判的, 死亡点**之前**的每一分都是同一批 RNG 打出来的、不受"要不要在死亡点截断"
## 影响;死亡点之后的额外几拍只是多算了不用的数, 不影响 `cleared`/`sec`/`dead` 的取值。
## `coin_delta`(起始金币偏移)通过新加的 `Opts.coin_delta` 传入 —— 那个字段默认 0,
## 不影响其余 7 份既有调用。
func _play_runs(cfg: Dictionary, mod: String, coin_delta: int, n: int,
		judge: bool, target_scale: float) -> Array:
	var table: Array = DB.sim().get("bot_targets", GameConfig.SECTION_TARGETS)
	var out: Array = []
	var rep := Report.new(n, GameConfig.SECTIONS_PER_RUN)
	rep.reset()
	var bot := Bot.new(_rng, rep)
	var pcfg := cfg.duplicate()
	pcfg["bot"] = "adaptive"
	var faces := {}
	for w in GameConfig.WALL_SECTIONS:
		faces[w] = mod
	for r in range(n):
		_rng.seed = 620000 + r
		var st := {"n": 0.0, "disc": 0.0, "rep": 0.0, "late": 0.0, "early": 0.0,
			"zerod": 0.0, "faces": 0.0, "chord": 0.0, "tgt": 0.0,
			"score": 0.0, "mult": 0.0, "kinds": {}}
		var o := RunLoop.Opts.new()
		o.rng = _rng
		o.deck_seed = r * 17 + 5
		o.faces = faces
		o.player = "adaptive"
		o.cfg = pcfg
		o.shop = true
		o.mortal = false
		o.coin_delta = coin_delta
		o.st = st
		o.tally_mult_kinds = false
		o.on_beat = func(_run: Run, p: Phrase, _outcome: Dictionary, _ctx: Dictionary) -> void:
			st["disc"] += float(p.discards_used)
		var res := RunLoop.play(o, bot)
		var all_secs: Array = res["sec_scores"]
		var all_kinds: Array = res.get("sec_kinds", [])
		var cleared := 0
		var sec_scores: Array = []
		var dead := false
		for section in range(all_secs.size()):
			var section_score: int = int(all_secs[section])
			sec_scores.append(section_score)
			# ⚠⚠ 事后判生死也要乘曲目税(2026-08-21 评审 R5):这里是第三份判生死, 此前漏乘
			# `Run.variety_mult` ⇒ trilogy 的行为臂与基准臂逐位相同, 「实测 0.0」是结构性恒零,
			# 还被写进了 weak_upper_bound。种数由 RunLoop 按段带回(sec_kinds)。
			var kinds: int = int(all_kinds[section]) if section < all_kinds.size() else 0
			var target := int(round(float(Run.section_target_for(table, section, mod))
				* target_scale * Run.variety_mult(mod, kinds)))
			if judge and section_score < target:
				dead = true
				break
			cleared += 1
		out.append({"cleared": cleared, "sec": sec_scores, "dead": dead})
	return out


## belief / solver 臂:完美玩家(求解器), 无商店 —— 这里量的是**决策质量**, 商店只加方差。
##
## ⚠ 2026-08-08 迁到 `RunLoop`。没有商店/st, 是三份里最干净的一份。
func _play_perfect(cfg: Dictionary, mod: String, oracle: bool, n: int) -> Array:
	Solver.ORACLE = oracle
	var scores: Array = []
	var rep := Report.new(n, GameConfig.SECTIONS_PER_RUN)
	rep.reset()
	var bot := Bot.new(_rng, rep)
	var pcfg := cfg.duplicate()
	pcfg["bot"] = "perfect"
	var faces := {}
	for w in GameConfig.WALL_SECTIONS:
		faces[w] = mod
	for r in range(n):
		_rng.seed = 620000 + r
		var o := RunLoop.Opts.new()
		o.rng = _rng
		o.deck_seed = r * 17 + 5
		o.faces = faces
		o.player = "adaptive"
		o.cfg = pcfg
		o.shop = false
		o.mortal = false
		var res := RunLoop.play(o, bot)
		scores.append(res["total"])
	Solver.ORACLE = false                  # ⚠ 复位, 别把上帝视角漏给下一条臂
	return scores
