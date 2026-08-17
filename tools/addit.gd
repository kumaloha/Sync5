extends Probe

## 可加性检验 —— **脸的难度能不能相加?**
##   godot --headless --path . --script res://tools/addit.gd
##
## 规格 = `docs/design/gates.md`。这是**排布搜索的地基**, 而我预判它会破。
##
## ## 为什么这件事是地基
##
## 一局的脸是**每段从该段池子各掷一张**。池子大小 4/5/7/6 且有重叠, 所以真实排布是
## **4×5×7×6 = 840 种**(不是 C(12,3), 因为哪张脸能出现在哪一段是受限的, 而且同一张脸
## 可以跨段复现 —— 那正是 `faces.json` 的 `arc`)。840 条臂 ×几百局跑不完一整天,
## 所以整套定价压在一个**假设**上:
##
##   **量 12 张脸各自的价格, 一个排布的难度 = 各段之和。**
##
## 这个假设成立, 定价就是 12 个数;不成立, 就得引入**交互项**, 而且排布搜索必须
## **按对**而不是按单张来搜 —— 搜索空间的形状完全不同。**所以先验它。**
##
## ## 统计量:配对残差
##
## 四条臂共用种子(公共随机数), 逐局算
##
##   r_i = both_i + base_i − A_i − B_i
##
## 再对 r 求均值和标准误。**不能拿三个均值相减** —— 局间方差极大(一张补牌能让一手
## 从 231 分变 534), 非配对时真实交互会被整个淹掉。这是 λ 扫描那次用 250 局配对才把
## 标准误从 ≈5 压到 ±1.4 的同一条教训。
##
## r > 0 = **次可加**(两张脸一起没那么疼, 第二张的伤害被第一张吃掉了)
## r < 0 = **超可加**(一起更疼)
##
## ## ⚠ 通路必须选对, 否则量出来的是反号
##
## 2026-08-07 实测:用规则 bot 量 `freshsheet` 得 **+1584**(脸让玩家变强), 用完美玩家
## 得 **−790**。规则 bot 不跨拍养缓存, 洗掉缓存反而帮它。所以这里**按 `faces.json` 的
## `proof` 通路分组**:score 组用规则 bot(快, 样本大), solver 组用完美玩家(慢, 样本小)。
## 混着测等于把两把不同的尺子的读数相加。

const N_SCORE := 600       # 规则 bot ~50 局/秒
const N_SOLVER := 150      # 完美玩家 ~0.37 秒/局
const Z_MIN := 3.0         # 残差要显著
## ⚠ **光看 z 不够, 必须同时看量级。** 样本量一大, **任何**微小交互都会显著 ——
## N=1500 时 `cover@S1+setlist@S2` 拿到 z=+4.48, 而残差只占两张之和的 **2%**。
## 那不是「可加性破了」, 那是「样本足够多, 看见了一个可以忽略的东西」。
## 判据因此是**两条同时成立**:统计上显著 **且** 占两张之和 ≥ 这个比例。
## 5% 的取法:一个 4 脸排布有 C(4,2)=6 对, 就算 6 对全同号也才 ~一成半, 仍小于
## 目标分本身的不确定度;真要紧的交互不会只有这个量级。
const R_MIN := 0.05

## 每一对都必须带**假设**。乱配对只会得到一堆没法解释的数字, 而且样本量是有限的。
## `at` = {段号: 脸 id}。⚠ 只能填该段池子里真有的脸 —— 否则测的是一个游戏里不存在的局面。
const PAIRS := [
	{
		"name": "cover@S1 + cover@S3",
		"why": "两张都抽钱。预判**超可加**:κ 实测是一道阈值不是标量(拿走 36.3 分/金币, 给 0.3),\n"
			+ "         抽得越多越买不起, 第二张该比第一张更疼。",
		"ch": "score", "a": {0: "cover"}, "b": {2: "cover"},
	},
	{
		"name": "cover@S1 + setlist@S2",
		"why": "**替补的经济交互对**。原本的 cover@S1+cover@S3 是个哑弹:cover@S3 实测只有\n"
			+ "         −8.0 ±20.8(机器人后期金币过剩, κ 阈值以上一文不值), B 臂几乎没效应,\n"
			+ "         残差检验等于没做。这一对改成「早期抽钱 + 后面一张真有分量的脸」,\n"
			+ "         检验的是「穷 → 构筑弱 → 后面那张脸更疼」这条真正的携带通路。",
		"ch": "score", "a": {0: "cover"}, "b": {1: "setlist"},
	},
	{
		"name": "norepeat@S1 + rerun@S2",
		"why": "同一个参数的软硬两档(repeat_factor 0.5 / 0.0), 也是起承転結里「同一机制被发展」\n"
			+ "         的典型。预判**次可加**:第一张已经逼你换牌型, 第二张再逼一次收益递减。",
		"ch": "score", "a": {0: "norepeat"}, "b": {1: "rerun"},
	},
	{
		"name": "unplugged@S3 + setlist@S4",
		"why": "**阴性对照** —— 一个砍 Target 功率, 一个锁牌型, 机制正交且不同段。\n"
			+ "         这一对如果也破, 说明破的不是机制交互, 而是「跨段状态携带」本身。",
		"ch": "score", "a": {2: "unplugged"}, "b": {3: "setlist"},
	},
	{
		"name": "smallstage@S1 + freshsheet@S3",
		"why": "两张都打缓存(一张砍格子, 一张整个洗掉)。预判**次可加**:缓存的价值总共\n"
			+ "         只有 +10.4%(warm.gd), 第一张吃掉大半, 第二张没什么可吃的了。",
		"ch": "solver", "a": {0: "smallstage"}, "b": {2: "freshsheet"},
	},
	{
		"name": "smallstage@S1 + smallstage@S2",
		"why": "**同一张脸跨段复现** —— 正是 2026-08-07 声明为「有意」的那类(faces.json arc)。\n"
			+ "         教学弧要成立, 第二次出现就该比第一次容易应对(玩家学会了);而模型里\n"
			+ "         机器人不会学习, 所以这里量到的是**纯机制**的那一半。",
		"ch": "solver", "a": {0: "smallstage"}, "b": {1: "smallstage"},
	},
]

var _rng := RandomNumberGenerator.new()
var _broke: Array = []


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var cfg := _cohort()
	# ⚠ 冒烟用:SceneTree 探针一旦在 _initialize 里报错就**永远不退**(GDScript 的运行时
	# 错误不终止脚本, quit() 那行永远跑不到)。所以先用极小样本跑通一遍再上真样本。
	var n_score := Probe.env_int("SYNC5_ADDIT_N", N_SCORE)
	var n_solver := Probe.env_int("SYNC5_ADDIT_N", N_SOLVER)
	# solver 臂是完美玩家(0.37 秒/局), 给 score 通路加样本时不该陪跑。0 = 整条通路跳过。
	n_solver = Probe.env_int("SYNC5_ADDIT_NSOLVER", n_solver)
	print("\n=== 可加性检验 (docs/design/gates.md) ===")
	print("  队列 %s · score %d 局/臂 · solver %d 局/臂 · 判据 |z| >= %.1f"
		% [cfg.get("name", "?"), n_score, n_solver, Z_MIN])
	print("  问题:**12 张脸的价格能不能相加成 840 种排布的难度?**")
	print("  统计量 = 配对残差 r = (两张一起) + (都没有) − (只有A) − (只有B)")
	print("           r > 0 次可加(没那么疼) · r < 0 超可加(更疼)")

	var cache := {}      # faces 字典的 key -> 每局总分, 免得同一条臂跑两遍
	for ch in ["score", "solver"]:
		var pairs: Array = PAIRS.filter(func(p): return String(p["ch"]) == ch)
		if pairs.is_empty():
			continue
		var n: int = n_score if ch == "score" else n_solver
		if n <= 0:
			print("\n  ════ %s 通路:样本量 0, 跳过 ════" % ch)
			continue
		print("\n  ════ %s 通路(%s) ════"
			% [ch, "规则 bot" if ch == "score" else "完美玩家"])
		var base := _arm(cache, cfg, {}, ch, n)
		print("    基准总分 %.0f" % Stat.mean(base))
		for p in pairs:
			_check(cache, cfg, p, base, ch, n)

	print("\n=== 判据 ===")
	if _broke.is_empty():
		# ⚠ 措辞要准:可能**有**显著的对, 只是量级可以忽略。写成「都不显著」
		# 会让将来读日志的人以为一个交互都没测到, 而事实是测到了、决定不管它。
		print("  ✅ 没有一对的交互同时满足「显著 且 ≥%.0f%%」 —— **加法够用**:" % (100.0 * R_MIN))
		print("     定价 = 12 个单张的数, 排布搜索可以按段独立地挑脸。")
	else:
		print("  ⚠ 以下几对的可加性**破了**:")
		for b in _broke:
			print("      · %s" % b)
		print("\n  这不是 bug, 是设计事实。后果有两条, 都要跟进:")
		print("    ① **定价不能只给单张** —— 至少这几对要带交互项(或者直接量这几对的联合价格);")
		print("    ② **排布搜索必须按对搜** —— 按段独立挑脸会系统性地估错整局难度。")
		print("  ⚠ 但也别过度反应:先看**残差占两张之和的比例**, 小于一成的交互")
		print("     在 840 种排布上的累计影响可能仍在噪声里。")
	print("\n[addit] %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)                       # 破了不算失败 —— 这是测量, 不是回归门


func _check(cache: Dictionary, cfg: Dictionary, p: Dictionary, base: Array,
		ch: String, n: int) -> void:
	var fa: Dictionary = p["a"]
	var fb: Dictionary = p["b"]
	var both := fa.duplicate()
	for k in fb:
		# 同段两张脸在规则里不可能同时存在 —— 配对时就该避开, 撞上直接喊出来。
		if both.has(k):
			push_error("[addit] %s: 两张脸落在同一段 S%d, 这个局面在游戏里不存在" % [p["name"], int(k) + 1])
			return
		both[k] = fb[k]
	var a := _arm(cache, cfg, fa, ch, n)
	var b := _arm(cache, cfg, fb, ch, n)
	var ab := _arm(cache, cfg, both, ch, n)

	var da := Stat.paired(base, a)
	var db := Stat.paired(base, b)
	var dab := Stat.paired(base, ab)
	# 逐局残差 —— 四条臂共用种子, 所以可以逐局作差, 局间方差在这里抵消掉
	var res: Array = []
	for i in range(n):
		res.append(float(ab[i]) + float(base[i]) - float(a[i]) - float(b[i]))
	var rm := Stat.mean(res)
	var rse: float = sqrt(Stat.variance(res) / maxf(1.0, float(n)))
	var z: float = rm / maxf(0.001, rse)
	var summed: float = da["d"] + db["d"]

	print("\n    ---- %s ----" % p["name"])
	print("      %s" % p["why"])
	print("      只有A  %+9.1f ±%.1f" % [da["d"], da["se"]])
	print("      只有B  %+9.1f ±%.1f" % [db["d"], db["se"]])
	print("      两张   %+9.1f ±%.1f   (相加预测 %+.1f)" % [dab["d"], dab["se"], summed])
	var share: float = absf(rm) / maxf(1.0, absf(summed))
	var tag := "可加"
	if absf(z) >= Z_MIN and share >= R_MIN:
		tag = "**次可加**" if rm > 0.0 else "**超可加**"
		_broke.append("%s — 残差 %+.1f ±%.1f (z=%+.2f), 占两张之和的 %.0f%%"
			% [p["name"], rm, rse, z, 100.0 * share])
	elif absf(z) >= Z_MIN:
		tag = "显著但可忽略(<%.0f%%)" % (100.0 * R_MIN)
	elif share >= R_MIN:
		tag = "量级不小但不显著 —— 加样本"
	print("      残差   %+9.1f ±%.1f   z = %+.2f   %s   (占之和 %.0f%%)"
		% [rm, rse, z, tag, 100.0 * share])


## 同一组 faces 只跑一次 —— 单张的臂会被多对复用(smallstage@S1 出现在两对里)。
func _arm(cache: Dictionary, cfg: Dictionary, faces: Dictionary, ch: String, n: int) -> Array:
	var key := "%s|%s" % [ch, _key(faces)]
	if cache.has(key):
		return cache[key]
	var out: Array = _play(cfg, faces, ch == "solver", n)
	cache[key] = out
	return out


func _key(faces: Dictionary) -> String:
	var parts: Array = []
	for s in range(GameConfig.SECTIONS_PER_RUN):
		parts.append(String(faces.get(s, "-")))
	return ",".join(parts)


func _cohort() -> Dictionary:
	for c in DB.sim()["cohorts"]:
		if String(c.get("bot", "")) == "random" or bool(c.get("no_jokers", false)):
			continue
		return c
	return {}


## 不死局打满 24 拍, 每段挂 `faces` 里指定的脸(没指定 = 无脸)。返回每局总分。
##
## ⚑ 2026-08-08 迁到 `RunLoop`(一局的骨架只此一份)。**st 的记账口径必须原样保留**:
## 原实现手动记过 `n`/`score`/`disc`, 但从没记过 `mult`/`kinds` —— `bot._draft` 靠这些
## 字段给卡定价, 多记会让抽卡决策偏出去, 所以只关掉 `tally_mult_kinds`, `disc` 照旧
## 用 on_beat 手动补(`RunLoop._tally` 不管这个字段)。
func _play(cfg: Dictionary, faces: Dictionary, perfect: bool, n: int) -> Array:
	var scores: Array = []
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
		var o := RunLoop.Opts.new()
		o.rng = _rng
		o.deck_seed = r * 17 + 5
		o.faces = faces
		# o.character 留空:这几份都不掷脸(`faces` 是外面传进来的固定字典), 选主角是
		# 唯一消耗随机数的一步, 顺序天然对齐 RunLoop 内部的建局顺序。
		o.player = "adaptive"        # cfg["bot"] 已经带着 perfect/adaptive, 走 cfg 分派
		o.cfg = pcfg
		# ⚠ 商店必须开着:cover 的伤害 98% 走商店(tools/coin.gd 实测),
		# 关掉商店就等于把这一对里最重要的那条通路掐了。
		o.shop = not perfect
		o.mortal = false
		o.st = st
		o.tally_mult_kinds = false
		o.on_beat = func(_run: Run, p: Phrase, _outcome: Dictionary, _ctx: Dictionary) -> void:
			st["disc"] += float(p.discards_used)
		var res := RunLoop.play(o, bot)
		scores.append(res["total"])
	return scores
