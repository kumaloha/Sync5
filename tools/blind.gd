extends Probe

## 信息隐藏族探针 —— **盖牌到底值多少分?**
##   godot --headless --path . --script res://tools/blind.gd
##
## 这个探针要回答两个不同的问题, 第二个比第一个重要:
##   ① 盖牌脸让分数掉多少?(它的难度价格)
##   ② **求解器是真的被蒙住了, 还是只是画面上盖了一下?**
##
## ② 用 `Solver.ORACLE` 做 A/B:同一局、同一批随机数、同一张脸, 唯一的区别是
## 求解器看不看得见那几张牌。**两条臂的差 = 这几张牌的信息值。**
## 差 ≈ 0 就说明信念机制根本没接上 —— 而「规则只改了画面没进模型」正是这个项目
## 栽过三次的坑(赶场 → 入场费误判 → 这一次)。**新机制必须自带这种证明。**
##
## 口径:配对(逐局作差)、报标准误和 z、不死局打满 24 拍。同 tools/coin.gd。

const N_RUNS := 150

## `oracle` = 求解器开上帝视角(看得见盖着的牌)。它**不是**一张脸, 是 A/B 的对照臂。
const ARMS := [
	{"name": "base(无脸)", "mod": "", "oracle": false},
	{"name": "blindspot 暗补", "mod": "blindspot", "oracle": false},
	{"name": "blindspot · 上帝视角", "mod": "blindspot", "oracle": true, "vs": "blindspot 暗补"},
	{"name": "facedown 蒙面", "mod": "facedown", "oracle": false},
	{"name": "facedown · 上帝视角", "mod": "facedown", "oracle": true, "vs": "facedown 蒙面"},
]

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var cohorts: Array = DB.sim()["cohorts"]
	var cfg := {}
	for c in cohorts:
		if String(c.get("bot", "")) == "random" or bool(c.get("no_jokers", false)):
			continue
		cfg = c
		break

	print("\n=== 信息隐藏族 · 配对实验 (%d 局/臂, 队列 %s, blind_samples=%d) ==="
		% [N_RUNS, cfg.get("name", "?"), GameConfig.BLIND_SAMPLES])

	var res := {}
	for arm in ARMS:
		res[arm["name"]] = _play(cfg, String(arm["mod"]), bool(arm["oracle"]))

	var base: Array = res["base(无脸)"]
	print("\n  基准总分 %.0f" % Stat.mean(base))

	print("\n  ---- ① 脸的效果(vs 无脸) ----")
	for arm in ARMS:
		if String(arm["mod"]) == "" or bool(arm["oracle"]):
			continue
		_line(arm["name"], base, res[arm["name"]])

	print("\n  ---- ② 信息值 = 蒙住 vs 上帝视角(同脸同种子) ----")
	print("  ⚠ 这一栏是**机制的 A/B**。≈0 就说明求解器根本没被蒙住,")
	print("     那这一族的脸只是画面效果, 而目标分会照着一个没发生的难度算。")
	var ok := true
	for arm in ARMS:
		if not bool(arm["oracle"]):
			continue
		# ⚠ 配对的臂名**显式写在 ARMS 里**, 不靠字符串裁剪拼 —— 第一版靠 replace()
		# 拼, 拼出来的键不存在, 整个 ② 段当场崩了(而 ① 已经跑了 8 分钟)。
		var blind_name := String(arm["vs"])
		var d := _line(blind_name + ": 上帝 − 蒙住", res[blind_name], res[arm["name"]])
		if d <= 0.0:
			ok = false
			print("    ❌ 上帝视角**没有**打得更高 —— 信念机制没接上或被噪声淹没")

	print("\n=== 判据 ===")
	if ok:
		print("  ✅ 每一张盖牌脸的上帝视角都打得更高 —— 求解器确实被蒙住了")
	else:
		print("  ❌ 至少一张脸的信息值不为正, 见上")
	print("\n[blind] %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0 if ok else 1)


func _line(label: String, a: Array, b: Array) -> float:
	var p := Stat.paired(a, b)
	var z: float = p["d"] / maxf(0.001, p["se"])
	print("    %-28s %+9.1f  ±%.1f   z = %+.2f   %s"
		% [label, p["d"], p["se"], z, "显著" if absf(z) > 2.0 else "不显著"])
	return p["d"]


## 打 N 局不死局, 每段挂同一张脸。返回每局总分。
##
## ⚠ 2026-08-08 迁到 `RunLoop`(一局的骨架只此一份)。这份原本就不开商店, 没有 st/买牌的
## 记账口径要保, 是这批 6 份里最干净的一份迁移。
func _play(cfg: Dictionary, mod: String, oracle: bool) -> Array:
	Solver.ORACLE = oracle
	var scores: Array = []
	var rep := Report.new(N_RUNS, GameConfig.SECTIONS_PER_RUN)
	rep.reset()
	var bot := Bot.new(_rng, rep)
	var pcfg := cfg.duplicate()
	pcfg["bot"] = "perfect"          # 这里量的是**求解器**看不看得见, 必须用完美玩家
	var faces := {}
	for w in GameConfig.WALL_SECTIONS:
		faces[w] = mod
	for r in range(N_RUNS):
		_rng.seed = 620000 + r       # ⚠ 配对:每条臂的第 r 局种子完全相同
		var o := RunLoop.Opts.new()
		o.rng = _rng
		o.deck_seed = r * 17 + 5
		o.faces = faces
		o.player = "adaptive"        # cfg["bot"]="perfect" 才是真正派到完美玩家, 见 Opts 注释
		o.cfg = pcfg
		o.shop = false
		o.mortal = false
		var res := RunLoop.play(o, bot)
		scores.append(res["total"])
	Solver.ORACLE = false            # ⚠ 复位, 别把上帝视角漏给下一条臂
	return scores
