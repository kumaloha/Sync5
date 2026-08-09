extends Probe

## 覆盖自证的门 —— **每张进池子的脸都要证明「它在模型里真的生效」**。
##   godot --headless --path . --script res://tools/gate.gd
##   SYNC5_GATE_FACE=<id>   只验一张脸(加了一张新脸时用这个, 十几秒)
##   SYNC5_GATE_N=<n>       改样本量(默认 score 250 / belief 60)
##
## 规格 = `design/gates.md`。一句话:**一条规则如果进不了模型, 它就不该进池子。**
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
## 那个字段是必填的(`DB.validate_faces` 锁着), 含义见 design/blinds.md §4。
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
var _warn: Array = []


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	_only = Probe.env_str("SYNC5_GATE_FACE")
	var n_score := Probe.env_int("SYNC5_GATE_N", N_SCORE)
	var n_solver := Probe.env_int("SYNC5_GATE_N", N_SOLVER)
	var n_belief := Probe.env_int("SYNC5_GATE_N", N_BELIEF)

	var cfg := _cohort()
	var ids := SectionMod.pooled_ids()
	if _only != "":
		if not ids.has(_only):
			print("[gate] '%s' 不在任何池子里 —— 没有池子就不需要自证" % _only)
			quit(1)
			return
		ids = [_only]

	print("\n=== 覆盖自证的门 (design/gates.md) ===")
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

	if not by_channel["score"].is_empty():
		_run_score(cfg, by_channel["score"], n_score)
	if not by_channel["solver"].is_empty():
		_run_solver(cfg, by_channel["solver"], n_solver)
	if not by_channel["belief"].is_empty():
		_run_belief(cfg, by_channel["belief"], n_belief)
	if not by_channel["target"].is_empty():
		_run_target(cfg, by_channel["target"], n_score)
	if _only == "":
		_run_monotonic(cfg, n_score)
		_run_sentinel(cfg, n_score)

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
	var base := _play_score(cfg, "", n)
	print("    基准总分 %.0f" % Stat.mean(base))
	for fid in ids:
		var arm := _play_score(cfg, fid, n)
		_judge(fid, base, arm, Stat.mean(base), _weak_declared(fid))


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
	var base := _play_perfect(cfg, "", false, n)
	print("    基准总分 %.0f" % Stat.mean(base))
	for fid in ids:
		var arm := _play_perfect(cfg, fid, false, n)
		_judge(fid, base, arm, Stat.mean(base), _weak_declared(fid))


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
	var base := _play_sections(cfg, "", 1.0, 0, n)
	for fid in ids:
		var arm := _play_sections(cfg, fid, 1.0, 0, n)
		_judge("%s: 通关段数(判生死)" % fid, base, arm)


## --- ④ 结构单调性(design/gates.md):无论数值怎么调都必须成立的方向。 ---
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


func _mono(label: String, a: Array, b: Array, want_up: bool) -> void:
	var d: float = Stat.mean(b) - Stat.mean(a)
	var ok: bool = d >= -0.0001 if want_up else d <= 0.0001
	print("    %-28s 通关段数 %.2f → %.2f  (%+.2f)  %s"
		% [label, Stat.mean(a), Stat.mean(b), d, "✓" if ok else "❌ 方向反了"])
	if not ok:
		_fail.append("单调性破了: %s 应该%s, 实际 %+.2f 段"
			% [label, "变容易" if want_up else "变难", d])


## --- ⑤ 生成器哨兵(design/gates.md):目标分必须落在**录得到**的分数范围内。 ---
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
## 为什么必须两条 —— 这是本项目所有读数的通用纪律(`design/gates.md`):
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
		_fail.append("%s: 分差 %.1f ±%.1f (z=%.2f) 只占基准 %.1f%% < %.0f%% —— 效应太小。若确认「对完美玩家真的小」, 写进 faces.json 的 weak_upper_bound(必须显式声明)"
			% [label, p["d"], p["se"], z, mag * 100.0, MAG_MIN * 100.0])
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
		var cleared := 0
		var sec_scores: Array = []
		var dead := false
		for section in range(all_secs.size()):
			var section_score: int = int(all_secs[section])
			sec_scores.append(section_score)
			var target := int(round(float(Run.section_target_for(table, section, mod)) * target_scale))
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
