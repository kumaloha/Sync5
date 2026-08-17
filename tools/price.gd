extends Probe

## 脸的定价 —— **每个「(脸, 段)」值多少分, 用同一把尺子量。**
##   godot --headless --path . --script res://tools/price.gd
##   SYNC5_PRICE_N=<n>   改样本量(默认 150)
##   输出:表格 + 一份 JSON(**只打印**)
##
## ## ⚠ 这个文件头曾经指着两个不存在的东西(2026-08-14 清理)
##
## **① 「这是 `tools/pool.gd`(池子搜索)的输入」—— `tools/pool.gd` 从未存在。**
## 「池子搜索」是 `docs/design/gates.md §6` 的前瞻设计(生成器造一池子段 → Director 排序,
## 在留存代理下优化)。它的三个前提**现在去掉了两个**:`death_spec` 已由用户直接指定形状
## (2026-08-14, 设计常量不是待搜索参数)、Director 已拍板**不读 context** 是一张设计期的表;
## 第三个(留存代理数据)从来没有过。**所以这条指向不是"还没做", 是"不做了"。**
## ⚑ 这是本项目第 4 次「**注释承诺了一个不存在的机制**」——
## 前三次是 `core/beat.gd` 的「漏步 = 崩」· `core/db.gd` 的「直接红」·
## `view/shop.gd` 的「不许各写一份」(而 `_weighted_pick` 本来就是两份)。
##
## **② 「贴到 data/faces.json 的 `prices`」—— 贴不进去。**
## `core/db.gd` 的 `_FACE_ROOT_KEYS` 白名单只有 faces/families/fixed_tiers/weak_upper_bound,
## 多一个 `prices` 会**直接红**。这个输出目前就是给人读的, 没有下游。
##
## **那它现在还有什么用?** 它是**「(脸, 轮) 定价」的唯一仪器**, 而 2026-08-14 轮次从单值
## 放成集合(`tiers`, 见 core/modifier.gd)之后, 「这张脸能不能进第 N 轮」正是要靠它回答的。
## 消费者从"一个没写的搜索器"变成了"作者本人"。
##
## ## 两个非做不可的口径修正(2026-08-07, 都是量出来才知道的)
##
## **① 价格是「每个放置」一个数, 不是「每张脸」一个数。**
## `tools/addit.gd` 顺带量到:同一张脸放在不同段, 价格差一个量级 ——
##   · `cover@S1` **−374** vs `cover@S3` **−22**(差 17 倍)
##   · `smallstage@S1` −526 vs `@S2` −477
## cover 那个差距有明确机制:早期没钱, 一枚金币是命; 后期机器人金币过剩(段末余 16→31◆),
## κ 阈值以上一文不值。**所以定价表的大小是「合法放置数」= 4+5+7+6 = 22, 不是 12。**
## ⚠ 我一度说成「12 个单张的数」, 那是错的。可加性检验证明的是**没有成对交互项**,
## 它不保证同一张脸在各段等价 —— 这两件事不同。
##
## **② 必须一把尺子。** `gate.gd` 的两条通路各有各的基准:score 用规则 bot(基准 19402),
## solver 用完美玩家(基准 7038)。`cover −997` 和 `rush −909` 看着差不多, 其实一个是
## 基准的 5%、一个是 13%。**跨尺子的读数不能相加, 更不能拿来排序。**
## 这里统一用**完美玩家 + 开着商店**:
##   · 完美玩家是 docs/design/solver_roadmap.md 的锚(上界靠"解"不靠"学"), 而且**它是唯一能看见全部四类脸的**
##     —— 规则 bot 不跨拍养缓存、几乎用不满弃牌预算, 量缓存族和时间族会翻号(实测 freshsheet
##     规则 bot +1584 / 完美玩家 −790);
##   · 商店必须开着 —— `cover` 的伤害 98% 走商店(tools/coin.gd 实测), 关掉就量不到它。
##
## ## ③ 测「本段分数」还是「整局总分」—— 两个都要, 它们回答不同的问题
##
## 第一版只报整局总分, 结果 S1 的脸误差炸到 ±550~±1270, 根本量不准。根因是**测错了量**:
## S1 的脸只直接影响 S1, 后面三段的差异是**传播**(买牌变了、牌堆变了、缓存变了)——
## 那部分方差被算进了「这张脸的代价」, 而它其实不是。**脸放得越早, 传播得越远, 方差越大**
## (同一张 facedown: 放 S3 是 ±200, 放 S1 是 ±1270)。
##
##   · **本段分数**(sec)= 这张脸在**它当值那一段**的直接代价。方差小、可测。
##     **池子要的是这个** —— 「同一段里掷到哪张脸, 这一段的体验差不多吗」。
##   · **整局总分**(run)= 直接代价 + 传播。方差大, 但它才是**完整**代价
##     (S1 抽干你的钱, 疼的是 S3)。判生死看的是它。
##
## **两个都报, 不要只留一个。** 只留 sec 会漏掉经济类脸的真实杀伤(cover 的伤害 98%
## 走商店, 而商店在段末); 只留 run 就是第一版那个量不准的样子。
##
## ## raisedbar 不在这张表里
##
## 它不改分数, 改的是目标分(×1.5)。在"分数损失"这把尺子上它恒等于 0,
## 而它的难度是**除以 1.5**。定价时单独换算, 不要硬塞进同一列 —— 那是两种量纲。

const N_DEFAULT := 150
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var n := Probe.env_int("SYNC5_PRICE_N", N_DEFAULT)
	var cfg := _cohort()

	# 只测这几个放置(逗号分隔的 `脸@段号`, 0 起)。给「只有一两个悬着、要加样本」的场景用 ——
	# 全表跑一次 30 分钟, 为了两条臂陪跑十条是浪费。
	var only: Array = []
	var only_env := Probe.env_str("SYNC5_PRICE_ONLY")
	if only_env != "":
		only = only_env.split(",")

	# 合法放置 = 池子里真有的 (段, 脸)。不测池子外的组合 —— 那是游戏里不存在的局面。
	var placements: Array = []
	for s in range(GameConfig.SECTIONS_PER_RUN):
		for fid in SectionMod.pool_for(s):
			if SectionMod.proof(fid) == "target":
				continue      # raisedbar: 另一种量纲, 见文件头
			if not only.is_empty() and not only.has("%s@%d" % [fid, s]):
				continue
			placements.append({"s": s, "f": String(fid)})

	print("\n=== 脸的定价 · 每个放置一个数 (%d 局/臂, 队列 %s) ===" % [n, cfg.get("name", "?")])
	print("  尺子 = **完美玩家 + 开着商店**(唯一能看见全部四类脸的那把)")
	print("  合法放置 %d 个 = 各段池子大小之和;raisedbar 不在表里(它改目标分不改分数)" % placements.size())

	var base := _play(cfg, {}, n)
	var b := Stat.mean(base["run"])
	print("  基准总分 %.0f;各段 %s\n" % [b, _sec_means(base["sec"])])
	print("  %-13s %-4s | %10s %8s %6s | %10s %8s   %s"
		% ["脸", "段", "本段分差", "±", "z", "整局分差", "±", "判据(本段)"])

	var table := {}
	var weak: Array = []
	for pl in placements:
		var sidx: int = int(pl["s"])
		var faces := {sidx: String(pl["f"])}
		var arm := _play(cfg, faces, n)
		# 本段:只比这张脸当值的那一段, 把下游传播的方差挡在外面
		var ps := Stat.paired(_col(base["sec"], sidx), _col(arm["sec"], sidx))
		var pr := Stat.paired(base["run"], arm["run"])
		var zs: float = ps["d"] / maxf(0.001, ps["se"])
		var ok := absf(zs) >= 3.0
		if not ok:
			weak.append("%s@S%d" % [pl["f"], sidx + 1])
		print("  %-13s S%-3d | %+10.1f %8.1f %+6.2f | %+10.1f %8.1f   %s"
			% [pl["f"], sidx + 1, ps["d"], ps["se"], zs, pr["d"], pr["se"],
				"✓" if ok else "⚠ 量不到"])
		table["%s@%d" % [pl["f"], sidx]] = {
			"sec": round(ps["d"] * 10.0) / 10.0, "sec_se": round(ps["se"] * 10.0) / 10.0,
			"run": round(pr["d"] * 10.0) / 10.0, "run_se": round(pr["se"] * 10.0) / 10.0}

	print("\n  ---- 贴进 data/faces.json 的 `prices`(键 = 脸@段号, 0 起) ----")
	print("  " + JSON.stringify(table))

	if not weak.is_empty():
		print("\n  ⚠ 下面这些放置在这把尺子上**量不到**(|z| < 3):")
		print("      %s" % ", ".join(weak))
		print("    两种可能, 别混:")
		print("      ① 它在那一段确实几乎没有代价(比如 cover 放在机器人金币过剩的后段)")
		print("         —— 那是**真实的设计信息**, 说明这个放置不该指望它撑难度;")
		print("      ② 样本不够 —— 加大 SYNC5_PRICE_N 再看估计值稳不稳。")
		print("    判别法:加样本后**估计值稳住、z 上升**是真效应;")
		print("            **估计值减半、z 不升反降**是噪声(2026-08-07 栽过一次)。")
	print("\n[price] %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)


func _cohort() -> Dictionary:
	for c in DB.sim()["cohorts"]:
		if String(c.get("bot", "")) == "random" or bool(c.get("no_jokers", false)):
			continue
		return c
	return {}


## 不死局打满 24 拍, 按 `faces` 放脸。完美玩家 + 商店。
## ⚑ 短, 是因为编排归了 `core/beat.gd`(docs/design/tech.md)—— 按段放不同的脸是免费的。
##
## ⚠ 2026-08-08 迁到 `RunLoop`(一局的骨架只此一份)。st 记账口径同 `addit.gd`:原实现
## 只手动记过 n/score/disc, 没记过 mult/kinds —— 关掉 `tally_mult_kinds`, disc 照旧手动补。
func _play(cfg: Dictionary, faces: Dictionary, n: int) -> Dictionary:
	var scores: Array = []
	var secs: Array = []      # 每局一个 [S1..S4] 的分数数组
	var rep := Report.new(n, GameConfig.SECTIONS_PER_RUN)
	rep.reset()
	var bot := Bot.new(_rng, rep)
	var pcfg := cfg.duplicate()
	pcfg["bot"] = "perfect"
	for r in range(n):
		# ⚠ 配对:每条臂的第 r 局种子完全相同; 选主角消耗一个随机数, 顺序不许动。
		_rng.seed = 620000 + r
		var st := {"n": 0.0, "disc": 0.0, "rep": 0.0, "late": 0.0, "early": 0.0,
			"zerod": 0.0, "faces": 0.0, "chord": 0.0, "tgt": 0.0,
			"score": 0.0, "mult": 0.0, "kinds": {}}
		var per_sec: Array = []
		var o := RunLoop.Opts.new()
		o.rng = _rng
		o.deck_seed = r * 17 + 5
		o.faces = faces
		o.player = "adaptive"        # cfg["bot"]="perfect" 走 cfg 分派到完美玩家
		o.cfg = pcfg
		o.shop = true
		o.mortal = false
		o.st = st
		o.tally_mult_kinds = false
		o.on_beat = func(_run: Run, p: Phrase, _outcome: Dictionary, _ctx: Dictionary) -> void:
			st["disc"] += float(p.discards_used)
		o.on_section = func(_run: Run, _section: int, sec_score: int, _coins: int) -> void:
			per_sec.append(float(sec_score))
		var res := RunLoop.play(o, bot)
		scores.append(res["total"])
		secs.append(per_sec)
	return {"run": scores, "sec": secs}


## 取每局第 s 段的分数, 摊成一列。
func _col(secs: Array, s: int) -> Array:
	var out: Array = []
	for row in secs:
		out.append(float(row[s]))
	return out


func _sec_means(secs: Array) -> String:
	var parts: Array = []
	for s in range(GameConfig.SECTIONS_PER_RUN):
		parts.append("S%d %.0f" % [s + 1, Stat.mean(_col(secs, s))])
	return " / ".join(parts)
