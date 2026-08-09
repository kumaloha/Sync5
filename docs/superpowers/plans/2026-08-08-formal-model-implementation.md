# design/22 形式化建模 · 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `design/22` 里三条已经被实测支持的建模判断落地成代码 —— 决策噪声 `ε` 进玩家参数、L2 决策重放门、前瞻用真实跨拍转移。

**Architecture:** 三个任务互相独立,都不碰游戏内容(`data/*.json` 的卡与脸一个字不改)。任务 1 和 3 改 `tools/solver.gd` + `tools/bot.gd`,默认值下必须**逐位退化成现在的行为**;任务 2 只加一个新探针 `tools/replay.gd`,不改任何现有代码。

**Tech Stack:** Godot 4.6.2 / GDScript,headless 探针,`tests/runner.gd` 自建断言框架。

---

## ⚠ 这个仓库的三条硬约束(动手前必读)

1. **不是 git 库。** 计划里没有 `git commit` 步骤。每个任务的收尾是**跑回归**:
   ```bash
   godot --headless --path /Users/kuma/Projects/Sync5 --script res://tests/runner.gd
   ```
   基线 = **571 passed, 0 failed**。任务只允许让这个数字**变大**(新增断言),不允许出现 failed。
2. **对账手法**(任务 1/3 要用):把原版拷成 `tools/_base_solver.gd` 再改原版,两版各跑一次探针对拍,
   用完删掉。**不依赖 VCS,也不必在动手之前先跑一遍。**
3. **新增 `class_name` 后必须先** `godot --headless --path . --import`,否则报 `Identifier not declared`。

## ⚠ 两条会静默出错的纪律(这个项目栽过)

- **改了 RNG 消耗个数 = 所有历史读数不可比,而且不报错。** `Deck.peek_many` 改拒绝采样那次
  抽样语义没变、只是消耗数变了,探针输出从 +19.9 漂到 +23.3,**而它一点速度都没换来,已撤回**。
  → **任务 1 和 3 都有一条「默认值下不消耗任何额外随机数」的断言,那是本计划最重要的两条测试。**
- **比较任何两组东西必须共用随机数并报标准误。** 没有标准误的差值等于没有结论。

---

## 文件结构

| 文件 | 责任 | 本计划里的动作 |
|---|---|---|
| `tools/solver.gd` | 单拍枚举 + 求最优。**绝不重新实现计分** | 加 `ε` 噪声选择(任务1)、`cache_value` 走真实转移(任务3) |
| `tools/bot.gd` | 玩家策略。`_play_perfect` = 完美玩家 | 把 `eps` 从 cfg 穿到 `Solver`(任务1) |
| `tools/replay.gd` | **新建**。读 Tape JSONL,重放决策问题 | 全部(任务2) |
| `tools/formal.gd` | `design/22` 的主张验证探针 | 加 `eps` 扫描组(任务1) |
| `tests/runner.gd` | 单元测试 | 新增断言(任务1、3) |
| `design/22_Formal_Model.md` | 建模地基 | 回填实测(任务1、3) |

---

## Task 1: 决策噪声 `ε` 进玩家参数 `θ`

**为什么先做这个:** `design/22 §8.2` 实测 —— λ 全谱只解释 645 分,而规则 bot 与 λ=0 的完美玩家之间还差 **1894 分(z=+13.2)**。**能力谱上最大的一维现在没有任何形式表达。**

**形式:** `value' = value + ε · σ · N(0,1)`,`σ` = 这一拍全部候选值的标准差。
**ε 无量纲** —— 噪声与「切法之间的真实差异」同尺度,所以同一个 ε 在不同配置、不同分数量级下含义相同。`ε=0` → 精确 argmax;`ε→∞` → 随机挑。

**Files:**
- Modify: `tools/solver.gd`(`best_split` / `best_split_lookahead` 加参数 + 新增 `_noisy_argmax`)
- Modify: `tools/bot.gd:405`(`_play_perfect` 加 `eps` 参数)、`tools/bot.gd:357-359`(从 cfg 读)
- Modify: `tests/runner.gd`(`_test_solver` 内新增断言)
- Modify: `tools/formal.gd`(新增 `eps` 扫描组)

---

- [ ] **Step 1.1: 写失败的测试 —— `ε=0` 必须逐位等同且不消耗随机数**

在 `tests/runner.gd` 的 `_test_solver()` 函数末尾追加:

```gdscript
	# ── ε(决策噪声, design/22 §3)──────────────────────────────
	# ⚠ 这两条是本次改动最重要的断言。ε=0 时若消耗了随机数, 全部历史读数会
	# 整体漂移**而且不报错** —— `peek_many` 那次就是这个形状, 已撤回。
	var rng_e := RandomNumberGenerator.new()
	rng_e.seed = 12345
	var st_before := rng_e.state
	var s_eps0 = Solver.best_split(visible, slots, extra, {}, [], [], 0.0, rng_e)
	eq(rng_e.state, st_before, "eps=0 consumes no randomness (否则历史读数整体漂移且不报错)")
	var s_ref = Solver.best_split(visible, slots, extra)
	check(s_eps0 != null and s_ref != null, "both eps=0 and no-eps paths return a split")
	eq(s_eps0.score, s_ref.score, "eps=0 is bit-identical to the no-eps path")

	# ε 很大时必须真的偏离 argmax —— 否则它是个装饰品参数, 和「最多弃 2 张」
	# 同一个形状(一条写了等于没写的约束, 而那次骗了我们整整一轮)。
	# ⚠ 循环内计数, 循环外断言一次 —— 逐条 check 会把测试基线灌水。
	var mx_e := -1
	for s in all:
		mx_e = maxi(mx_e, s.score)
	var rng_e2 := RandomNumberGenerator.new()
	rng_e2.seed = 777
	var off_argmax := 0
	for _t in range(50):
		var pick = Solver.best_split(visible, slots, extra, {}, [], [], 3.0, rng_e2)
		if pick != null and pick.score < mx_e:
			off_argmax += 1
	check(off_argmax > 0, "eps>0 actually deviates from argmax (否则 ε 是装饰品参数)")
```

- [ ] **Step 1.2: 跑测试确认它失败**

```bash
godot --headless --path /Users/kuma/Projects/Sync5 --script res://tests/runner.gd
```
Expected: 报错 `Invalid argument count` 或 `Too many arguments` —— `best_split` 现在只有 6 个参数。

- [ ] **Step 1.3: 实现 `_noisy_argmax`**

在 `tools/solver.gd` 的 `best_split` 之前插入:

```gdscript
## 在候选值上加噪声再取 argmax —— **决策质量**这一维(design/22 §3)。
##
## ε 是**无量纲**的:噪声尺度 = ε × 这一拍候选值的标准差, 所以同一个 ε 在
## 不同配置、不同分数量级下含义相同 —— 这是它能跨配置比较的前提。
##   ε = 0    精确 argmax(完美玩家)
##   ε ≈ 1    噪声与切法之间的真实差异同量级
##   ε → ∞    随机挑
##
## ⚠⚠ **ε=0 时一个随机数都不许消耗。** 否则全部历史读数会整体漂移**而且不报错**
## —— `Deck.peek_many` 那次改的只是消耗个数, 探针输出就从 +19.9 漂到 +23.3,
## 而它一点速度都没换来, 已整条撤回。tests/runner.gd 里锁着这条。
##
## ⚠ 噪声必须来自**调用方传进来的** rng —— 配对实验靠两臂共用种子, 这里自己
## new 一个 RNG 就把配对破坏了, 而破坏得很安静。
static func _noisy_argmax(vals: Array, eps: float, rng: RandomNumberGenerator) -> int:
	var n := vals.size()
	if n == 0:
		return -1
	var bi := 0
	if eps <= 0.0 or rng == null:
		for i in range(1, n):
			if float(vals[i]) > float(vals[bi]):
				bi = i
		return bi
	var m := 0.0
	for v in vals:
		m += float(v)
	m /= float(n)
	var acc := 0.0
	for v in vals:
		acc += (float(v) - m) * (float(v) - m)
	var sd: float = sqrt(acc / float(maxi(1, n - 1)))
	var best := -1.0e30
	for i in range(n):
		var x: float = float(vals[i]) + eps * sd * rng.randfn(0.0, 1.0)
		if x > best:
			best = x
			bi = i
	return bi
```

- [ ] **Step 1.4: 给 `best_split` 加参数**

把 `tools/solver.gd:211` 的签名与函数体改成:

```gdscript
static func best_split(visible: Array, slots: Array, extra: Dictionary,
		rules: Dictionary = {}, hidden: Array = [], subs: Array = [],
		eps: float = 0.0, rng: RandomNumberGenerator = null) -> Split:
	var all := splits(visible, slots, extra, rules, hidden, subs)
	if all.is_empty():
		return null
	# ⚠ 一律按 belief 选(用信念选, 用真值记账) —— 混用会得到一个上帝视角的玩家。
	var vals: Array = []
	for s in all:
		vals.append(s.belief)
	var bi := _noisy_argmax(vals, eps, rng)
	return all[bi]
```

⚠ 保留原函数体里除 argmax 之外的任何逻辑;若原实现有额外分支,只替换取最大值那一段。

- [ ] **Step 1.5: 给 `best_split_lookahead` 加参数**

`tools/solver.gd:322` 的签名末尾追加 `eps: float = 0.0`(它**已经有** `rng` 参数,不要再加)。
函数体里两处取最大值改掉:

① `lam <= 0.0 or samples <= 0` 的早退分支:

```gdscript
	if lam <= 0.0 or samples <= 0:
		var vals0: Array = []
		for s2 in all:
			vals0.append(s2.belief)
		return all[_noisy_argmax(vals0, eps, rng)]
```

② 主循环的取最大值 —— 改成先把 TOP_K 内算过的候选收集起来,循环外做一次带噪声的挑选:

```gdscript
	var ub := _cache_ub(slots, extra, rules)
	var k: int = mini(TOP_K, all.size())
	var cand: Array = []          # 算过前瞻的候选
	var cand_v: Array = []
	var best_v := -1.0e30
	for i in range(k):
		var s3: Split = all[i]
		# ⚠ 早停判据仍然用**无噪声**的 best_v —— 它是精确剪枝(不改结果),
		# 拿噪声后的值去剪会把真正的好切法误剪掉, 那就从"加噪声"变成"算错了"。
		if not cand.is_empty() and s3.belief + lam * ub < best_v:
			break
		var v := s3.belief + lam * cache_value(s3.keep, slots, extra, futures, rules)
		cand.append(s3)
		cand_v.append(v)
		if v > best_v:
			best_v = v
	if cand.is_empty():
		return null
	return cand[_noisy_argmax(cand_v, eps, rng)]
```

- [ ] **Step 1.6: 跑测试确认通过**

```bash
godot --headless --path /Users/kuma/Projects/Sync5 --script res://tests/runner.gd
```
Expected: `=== RESULT: 575 passed, 0 failed ===`(571 + 新增 4 条)。
⚠ 若 passed 不是 575 或出现 failed,**停下来**,不要继续。

- [ ] **Step 1.7: 把 `eps` 从 cfg 穿到 `_play_perfect`**

`tools/bot.gd:405` 签名末尾追加参数:

```gdscript
func _play_perfect(p: Phrase, slots: Array, mod: String = "",
		lam: float = 0.0, lam_samples: int = 3, section: int = 0,
		eps: float = 0.0) -> void:
```

同一函数里两处调用改掉(其余不动):

```gdscript
				var b0 = Solver.best_split(vis0, slots, extra, p.deck.rules, hid0, subs0,
					eps, _rng)
```

```gdscript
	var best = Solver.best_split_lookahead(visible, slots, extra, p.deck,
		_rng, lam, lam_samples, p.deck.rules, hid, subs, eps)
```

`tools/bot.gd:357-359` 的调用点补一个 cfg 键:

```gdscript
				_play_perfect(p, slots, mod,
					float(cfg.get("lam", SOLVER["lam"])),
					int(cfg.get("lam_samples", SOLVER["lam_samples"])), section,
					float(cfg.get("eps", 0.0)))
```

- [ ] **Step 1.8: 回归 —— 默认路径必须逐位不变**

先把原版留一份做对拍:
```bash
cp /Users/kuma/Projects/Sync5/tools/formal.gd /Users/kuma/Projects/Sync5/tools/_base_formal.gd
```
跑改动后的 theta 组,和 `design/22 §8.2` 表里的数字逐个核对:
```bash
SYNC5_FORMAL_ONLY=theta godot --headless --path /Users/kuma/Projects/Sync5 --script res://tools/formal.gd
```
Expected(**必须一字不差**,`eps` 默认 0):
```
规则 bot(adaptive)   总分     4545
完美玩家 λ=0.00      总分     6438
完美玩家 λ=0.20      总分     6932
完美玩家 λ=0.40      总分     7083
```
⚠ **任何一个数不同 = ε 的默认路径改变了行为,回到 Step 1.3 查 `_noisy_argmax` 的早退分支。**
核完删掉备份:
```bash
rm /Users/kuma/Projects/Sync5/tools/_base_formal.gd
```

- [ ] **Step 1.9: 加 `eps` 扫描组,找出复现规则 bot 的 ε\***

在 `tools/formal.gd` 的 `_claim_theta()` 末尾追加(`LAMS` 之后新增一个常量 `const EPSS: Array[float] = [0.0, 0.5, 1.0, 2.0, 4.0]`):

```gdscript
	# ── ε 扫描:能不能用噪声把完美玩家降到规则 bot 的水平 ──
	# 判据不是"降下来了"就行 —— 分数对上只是**必要**条件。
	# 若某个 ε 把总分对上了, 那才有资格谈「真人落在能力谱的哪个点」。
	print("  ── ε 扫描(λ 固定 0.2)──")
	for e in EPSS:
		var arm_e := _play_eps(faces, N_THETA, 0.2, e, 7700)
		var pr_e := _paired(ref, arm_e)
		print("  λ=0.20 ε=%.1f       总分 %8.0f  vs bot 配对差 %+8.0f ±%.0f (z=%+.1f)"
			% [e, _mean(arm_e), pr_e["d"], pr_e["se"], pr_e["d"] / maxf(1e-9, pr_e["se"])])
```

并新增 `_play_eps`(照抄 `_play_many` 的循环,只把 `bot._play_perfect` 那一行换成带 eps 的版本):

```gdscript
## 完美玩家 + 决策噪声。与 _play_many 共用种子序列(配对)。
func _play_eps(faces: Dictionary, n: int, lam: float, eps: float,
		seed_base: int) -> Array:
	var bot := Bot.new(_rng, Report.new(n, GameConfig.SECTIONS_PER_RUN))
	var totals: Array = []
	for r in range(n):
		_rng.seed = seed_base + r
		var run := _fresh_run(r * 17 + 5, faces)
		var total := 0
		for sec in range(GameConfig.SECTIONS_PER_RUN):
			run.section_idx = sec
			run.section_score = 0
			run.first_kind = -99
			for pidx in range(GameConfig.PHRASES_PER_SECTION):
				run.phrase_in_section = pidx
				var p := Beat.begin(run)
				bot._play_perfect(p, run.joker_slots, String(faces.get(sec, "")),
					lam, int(DB.sim()["solver"]["lam_samples"]), sec, eps)
				var outcome := Beat.settle(run, p, {})
				total += int(outcome["score"])
				Beat.phrase_end(run, p, {})
		totals.append(float(total))
	return totals
```

- [ ] **Step 1.10: 跑扫描并回填文档**

```bash
SYNC5_FORMAL_ONLY=theta godot --headless --path /Users/kuma/Projects/Sync5 --script res://tools/formal.gd
```
把输出表填进 `design/22 §8.2`,并按结果二选一改主张 8 的状态:
- **某个 ε 让配对差落进 ±2σ** → 写「`⟨λ, ε⟩` 两维已能覆盖规则 bot 这个点,`τ` 仍待真人 Tape」;
- **没有任何 ε 能对上**(比如 ε 增大时分数掉过头或掉不下来)→ 写「两维仍不够,`θ` 需要第四维」,
  并在 `§8` 主张表里把主张 8 标成**部分证伪**。
⚠ **不许因为想要哪个结论就调 ε 的取值范围** —— 那是 `design/22 §11` 的铁律
「不要为了让度量工具好用而改变被度量的对象」的同一形状。

---

## Task 2: L2 决策重放门 `tools/replay.gd`

**为什么:** `design/22 §9` 的 L2 是这份建模**唯一能自动跑**的完备性判据 —— 给定文档 + 一局 Tape,能不能重放出每一个决策点。漏了一个状态维度,重放会当场撞墙。Tape 已经验了「能重放**局面**」,这条验「能重放**决策问题**」。

**Tape 事实格式**(实测自真实日志,不是猜的):
- `run {char, cn, coins, faces:{"0".."3"}, struct:{dur,pps,ppshop,sec}, targets:[...]}`
- `beat {i, p, dur, coins, hand:["4C","8H",...], cache:["3S","8S","9S"]}` ← **锚点**
- `disc {k, h, c, cost, coins, cards:[...], got:[...], at}`
- `swap {h, c, at}` · `sort {at}` · `pick {z, i, on, at}`
- `settle {kind, chips, base, mult, bonus, score, coin, cards:[...], fired, mod, ...}`
- `sec {i, target, face, wall, coins}` · `sec_end {i, score, target, ok, beats, coins}` · `close {...}`

牌的编码 = `Card.label()`,形如 `"4C"` / `"QH"` / `"10D"`。

**Files:**
- Create: `tools/replay.gd`
- Test: 用 `tools/flow_probe.gd` 现成产出的日志跑(它每次运行都会写一批到 `user://tape/`)

---

- [ ] **Step 2.1: 建 `tools/replay.gd` 的骨架 + 定位最新日志**

```gdscript
extends SceneTree

## **L2 完备性门**(design/22 §9)—— 给定形式化描述 + 一局 Tape,
## 能不能重放出**每一个决策点**?
##   godot --headless --path . --script res://tools/replay.gd
##   SYNC5_REPLAY_INJECT=1   注入一个假事件, 用来 A/B 验证这道门本身没坏
##
## **和 tapeprobe 的分工**:`tapeprobe` 验「日志能不能重放出**局面**」(采集侧完整性);
## 本探针验「文档能不能重放出**决策问题**」(建模侧完整性)。
## 判据:每个决策点必须能唯一确定 `s` / `A(s)` / `o(s)`。
## 漏一个状态维度 → 撞上「这个动作不在 A(s) 里」或「两个不同局面映射到同一个 s」。
##
## ⚠ **非零退出**。一道不会红的门等于没有门。
## ⚠ **这道门自己必须做 A/B** —— 注入假 bug 确认它真的报警。写过一条**假的**守卫:
## 注入误判照样全绿(测试卡是成长牌、计数器为 0, 根本没走到那条路径)。

var _fail: Array = []
var _checked := 0


func _initialize() -> void:
	var dir := "user://tape"
	var files := _newest_logs(dir, 5)
	if files.is_empty():
		push_error("[replay] %s 下没有日志 —— 先跑一次 tools/flow_probe.gd" % dir)
		quit(1)
		return
	var inject := OS.get_environment("SYNC5_REPLAY_INJECT") == "1"
	for f in files:
		_replay_one(f, inject)
	print("=== L2 决策重放:%d 个决策点,%d 处违规 ===" % [_checked, _fail.size()])
	for m in _fail:
		print("  x ", m)
	quit(1 if _fail.size() > 0 else 0)


## 取最近改动的 n 个日志。⚠ 只取最近的 —— 老日志的结构参数可能和当前不同
## (`run` 事件里记了 struct 就是为了这个), 拿它们验今天的建模会假红。
func _newest_logs(dir: String, n: int) -> Array:
	var d := DirAccess.open(dir)
	if d == null:
		return []
	var out: Array = []
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.ends_with(".jsonl"):
			out.append(dir + "/" + name)
		name = d.get_next()
	d.list_dir_end()
	out.sort()
	if out.size() > n:
		out = out.slice(out.size() - n, out.size())
	return out
```

- [ ] **Step 2.2: 跑一次确认它能找到日志(此时还没有断言)**

```bash
godot --headless --path /Users/kuma/Projects/Sync5 --script res://tools/flow_probe.gd
godot --headless --path /Users/kuma/Projects/Sync5 --script res://tools/replay.gd
echo "EXIT=$?"
```
Expected: `=== L2 决策重放:0 个决策点,0 处违规 ===` 且 `EXIT=0`。
⚠ **读退出码别隔着管道** —— `godot ... | tail` 之后的 `$?` 是 tail 的,不是 godot 的。

- [ ] **Step 2.3: 实现重放主体**

在 `tools/replay.gd` 追加:

```gdscript
## 重放一局。核心状态只需要三样就能验完 L2:hand / cache / 这一拍是否已锁定。
## 其余状态维度(k_prev / k_first / joker.state)由 settle 事件的 mod+kind 间接覆盖。
func _replay_one(path: String, inject: bool) -> void:
	var fh := FileAccess.open(path, FileAccess.READ)
	if fh == null:
		_fail.append("%s 打不开" % path)
		return
	var hand: Array = []
	var cache: Array = []
	var have_beat := false
	var n_line := 0
	while not fh.eof_reached():
		var line := fh.get_line()
		if line.strip_edges() == "":
			continue
		var d = JSON.parse_string(line)
		if typeof(d) != TYPE_DICTIONARY:
			_fail.append("%s:%d 不是合法 JSON" % [path, n_line])
			continue
		n_line += 1
		var e := String(d.get("e", ""))
		match e:
			"beat":
				# 锚点:一拍开始时的真实局面。
				hand = _arr(d.get("hand", []))
				cache = _arr(d.get("cache", []))
				have_beat = true
				# A(s) 的规模在这里就该是确定的 —— 手牌 5 + 缓存 cap。
				# 缓存容量随脸变(smallstage 3→2), 所以只断言"非空且 ≤3"。
				if hand.size() != GameConfig.HAND_SIZE:
					_fail.append("%s beat#%d 手牌 %d 张, 形式化说恒 %d"
						% [path, int(d.get("i", -1)), hand.size(), GameConfig.HAND_SIZE])
				if cache.is_empty() or cache.size() > GameConfig.CACHE_CAP:
					_fail.append("%s beat#%d 缓存 %d 张, 越界"
						% [path, int(d.get("i", -1)), cache.size()])
			"disc":
				if not have_beat:
					continue
				var cards := _arr(d.get("cards", []))
				var got := _arr(d.get("got", []))
				_checked += 1
				# ① 动作必须在 A(s) 里:弃掉的每张都得当时真的在手上或缓存里。
				for c in cards:
					if not (hand.has(c) or cache.has(c)):
						_fail.append("%s disc 弃了 %s, 而它不在 A(s) 里(hand=%s cache=%s)"
							% [path, c, str(hand), str(cache)])
				# ② 补牌张数必须等于弃牌张数 —— 手牌恒 5、缓存恒满是形式化的硬约束。
				if got.size() != cards.size():
					_fail.append("%s disc 弃 %d 补 %d, 破坏「手牌恒 5 缓存恒满」"
						% [path, cards.size(), got.size()])
				# ③ 原位替换:推进状态。
				var gi := 0
				for c in cards:
					var at := hand.find(c)
					if at >= 0:
						hand[at] = got[gi] if gi < got.size() else ""
					else:
						at = cache.find(c)
						if at >= 0:
							cache[at] = got[gi] if gi < got.size() else ""
					gi += 1
			"swap":
				if not have_beat:
					continue
				_checked += 1
				var h := int(d.get("h", -1))
				var c2 := int(d.get("c", -1))
				if h < 0 or h >= hand.size() or c2 < 0 or c2 >= cache.size():
					_fail.append("%s swap(%d,%d) 下标越界(hand=%d cache=%d)"
						% [path, h, c2, hand.size(), cache.size()])
				else:
					var t = hand[h]
					hand[h] = cache[c2]
					cache[c2] = t
			"sort":
				# 理牌 = 确定性重排, 不改集合。重放不跟踪顺序, 但它必须不改变**集合**,
				# 所以这里只计一个决策点 —— 真正的检查在下一条 settle 上。
				_checked += 1
			"settle":
				if not have_beat:
					continue
				_checked += 1
				# ⚑ **这是 L2 最硬的一条**:若状态模型完备, 我们推导出的 hand
				# 必须和实际计分的 5 张**逐张相同**(集合意义)。
				# 对不上 = 形式化漏了一条会改手牌的转移。
				var played := _arr(d.get("cards", []))
				if not _same_multiset(played, hand):
					_fail.append("%s settle 打的是 %s, 而重放推出的手牌是 %s —— 状态模型漏了一条转移"
						% [path, str(played), str(hand)])
				have_beat = false
	fh.close()
	if inject:
		# A/B:注入一个不可能的决策点, 这道门必须报警。
		_checked += 1
		_fail.append("%s [INJECTED] 人为违规 —— 看到这一条说明门是活的" % path)


func _arr(v) -> Array:
	var out: Array = []
	if typeof(v) == TYPE_ARRAY:
		for x in v:
			out.append(String(x))
	return out


## 多重集相等(同一张牌可能出现两次? 不会 —— 但用多重集比较更保守)。
func _same_multiset(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var x := a.duplicate()
	var y := b.duplicate()
	x.sort()
	y.sort()
	return x == y
```

- [ ] **Step 2.4: 跑门,期望全绿**

```bash
godot --headless --path /Users/kuma/Projects/Sync5 --script res://tools/flow_probe.gd
godot --headless --path /Users/kuma/Projects/Sync5 --script res://tools/replay.gd
echo "EXIT=$?"
```
Expected: `0 处违规`,`EXIT=0`,且**决策点数明显 > 0**(flow_probe 每局 24 拍 × 至少 settle 一次 → ≥100)。
⚠ 若决策点数是 0,说明日志里没有 `beat`/`settle` —— 门是空转的,那和没有门一样。**停下来查。**

- [ ] **Step 2.5: A/B 验证这道门本身没坏**

```bash
SYNC5_REPLAY_INJECT=1 godot --headless --path /Users/kuma/Projects/Sync5 --script res://tools/replay.gd
echo "EXIT=$?"
```
Expected: 打印 `[INJECTED] 人为违规`,`EXIT=1`。
⚠ **若 EXIT 仍是 0,这道门是假的** —— 这个项目写过一条注入误判照样全绿的守卫。

- [ ] **Step 2.6: 真实注入 —— 改一条日志确认能抓到**

手工造一个坏日志(把某条 `disc` 的 `cards` 换成一张不在手里的牌):
```bash
cd ~/Library/Application\ Support/Godot/app_userdata/Sync5*/tape/ && \
  ls -t *.jsonl | head -1 | xargs -I{} python3 -c "
import json,sys
p='{}'
out=[]
hit=False
for l in open(p):
    d=json.loads(l)
    if d['e']=='disc' and not hit and d.get('cards'):
        d['cards']=['AS'] * len(d['cards']); hit=True
    out.append(json.dumps(d))
open(p,'w').write('\n'.join(out)+'\n')
print('injected:', hit)
"
```
再跑门:
```bash
godot --headless --path /Users/kuma/Projects/Sync5 --script res://tools/replay.gd
echo "EXIT=$?"
```
Expected: 报 `弃了 AS, 而它不在 A(s) 里`,`EXIT=1`。
之后重新生成干净日志:
```bash
godot --headless --path /Users/kuma/Projects/Sync5 --script res://tools/flow_probe.gd
```
⚠ 这一步和 Step 2.5 不同:2.5 验的是**报警通道**通不通,这一步验的是**判据本身**抓不抓得到真错。两条都要。

- [ ] **Step 2.7: 接进 `tools/gate.sh`**

在 `tools/gate.sh` 里 `tapeprobe` 那一段之后追加同样形状的一段(照抄它的错误处理与非零退出写法),
命令为:
```bash
godot --headless --path "$ROOT" --script res://tools/replay.gd
```
⚠ 必须放在 `flow_probe` **之后** —— 它依赖 flow_probe 刚写出来的日志。
跑一次全量门确认没变红:
```bash
./tools/gate.sh
```
Expected: 全部通过,耗时仍在 ~8-10 分钟预算内。

---

## Task 3: 缺口② —— 前瞻用真实跨拍转移

**为什么:** `design/21 §3` 的缺口 2,也是 2026-08-07 那场误判的根。现在 `Solver.cache_value(keep, ...)` **假设留下的 3 张会原样留到下一拍**,而 `Beat.phrase_end` → `Phrase.cleanup()` 会按 `SectionMod.cache_evict(mod)` 随机弃掉 n 张(丢谱 1 张 / 翻篇 3 张),下一拍开局再补满。

**修法:** 前瞻里跑**真实**的驱逐,而不是想象一个不变的缓存。

**⚠ 这个改动会移动带 `cache_evict` 脸的全部读数。** 无脸时必须**逐位不变** —— 那是验收判据。

**Files:**
- Modify: `tools/solver.gd:290`(`cache_value` **签名不变**,只改主体;新增 `_survivor_sets`)
- Modify: `tests/runner.gd`(`_test_solver` 内新增 5 条断言)
- Modify: `design/22 §8` 主张 15 的状态、`design/21 §3 缺口 2`

---

- [ ] **Step 3.1: 写失败的测试 —— 无脸时逐位不变,有 `cache_evict` 时必须变**

在 `tests/runner.gd` 的 `_test_solver()` 末尾追加:

```gdscript
	# ── 前瞻的真实跨拍转移(design/22 §8 主张 15 / design/21 缺口 2)──
	# 现在的 cache_value 假设留下的 3 张会原样留到下一拍, 而 cache_evict 族
	# 正好拿走它们。判据两条, 缺一不可:
	#   ① 无脸(evict=0)时**逐位不变** —— 否则历史读数全部漂移;
	#   ② 有脸(evict>0)时**必须变** —— 否则这条修复是空气(和「最多弃 2 张」同形状)。
	var deck_cv := Deck.new(4242)
	var rng_cv := RandomNumberGenerator.new()
	rng_cv.seed = 99
	var futures_cv: Array = []
	for _i in range(3):
		futures_cv.append(deck_cv.peek_many(rng_cv, GameConfig.HAND_SIZE))
	var keep_cv: Array = [visible[0], visible[1], visible[2]]

	var extra_none := extra.duplicate()
	extra_none["mod"] = ""
	var v_none := Solver.cache_value(keep_cv, slots, extra_none, futures_cv, {})
	var v_none2 := Solver.cache_value(keep_cv, slots, extra_none, futures_cv, {})
	eq(v_none, v_none2, "cache_value is deterministic given shared futures")

	# 驱逐越多 → 缓存潜力越低。用**单调性**做判据而不是"两个数不相等":
	# ⚠ 「不相等」在原理上可能偶然相等(若那 5 张补牌恰好就是 56 选 1 的最优),
	# 而单调性是**结构上恒成立**的 —— 牌少了, 可选的手就是原来的子集。
	# 这条同时抓住"根本没读 mod"(三个数会全等)和"读错方向"。
	var extra_lost := extra.duplicate()
	extra_lost["mod"] = "lostpage"      # cache_evict 1
	var extra_fresh := extra.duplicate()
	extra_fresh["mod"] = "freshsheet"   # cache_evict 3 —— 缓存整个换掉
	var v_lost := Solver.cache_value(keep_cv, slots, extra_lost, futures_cv, {})
	var v_fresh := Solver.cache_value(keep_cv, slots, extra_fresh, futures_cv, {})
	check(v_none >= v_lost and v_lost >= v_fresh,
		"cache_value 随 cache_evict 单调不增 (%.1f >= %.1f >= %.1f)" % [v_none, v_lost, v_fresh])
	check(v_none > v_fresh,
		"cache_value 在 evict=3 下必须严格低于无脸 (否则缺口2 的修复是空气)")
	eq(int(SectionMod.cache_evict("freshsheet")), 3,
		"freshsheet 的 cache_evict 仍是 3 (这条测试的前提)")
	eq(int(SectionMod.cache_evict("lostpage")), 1,
		"lostpage 的 cache_evict 仍是 1 (这条测试的前提)")
```

- [ ] **Step 3.2: 跑测试确认它失败**

```bash
godot --headless --path /Users/kuma/Projects/Sync5 --script res://tests/runner.gd
```
Expected: `x FAIL: cache_value 在 cache_evict 脸下必须不同于无脸` —— 现在 `cache_value` 根本不读 `mod`。

- [ ] **Step 3.3: 改 `cache_value` 走真实驱逐**

`tools/solver.gd:290` 的函数体改成:

```gdscript
static func cache_value(keep: Array, slots: Array, extra: Dictionary,
		futures: Array, rules: Dictionary = {}) -> float:
	if futures.is_empty():
		return 0.0
	# ⚑ **真实跨拍转移**(design/22 §8 主张 15):留下的 3 张**不一定**留到下一拍 ——
	# `Beat.phrase_end` → `Phrase.cleanup()` 会按 cache_evict 随机弃掉 n 张,
	# 下一拍开局补满。前瞻假设它们原样留着, 就会在缓存驱逐族下**高估缓存**,
	# 而那正是 2026-08-07 把「丢谱测出正分」误读成「这张脸没用」的根。
	#
	# ⚠⚠ **不许"取前 n 张"** —— 驱逐在游戏里是**均匀随机**的, 而 `keep` 的顺序来自
	# 切法枚举顺序。按位置删会让 cache_value 依赖枚举顺序, 于是某些切法纯因排在前面
	# 而显得好 —— 那是一个**不报错的排序偏置**。
	# 缓存只有 3 张, 所以**精确枚举全部 C(3,n) 种驱逐结果取期望**就行:
	#   evict 0→1 种(与原实现完全相同) · 1→3 种 · 2→3 种 · 3→1 种。
	# 精确期望既没有采样噪声, 也不消耗任何随机数。
	var evict: int = SectionMod.cache_evict(String(extra.get("mod", "")))
	var survivor_sets := _survivor_sets(keep, evict)
	var acc := 0.0
	var n := 0
	for f in futures:
		for sv in survivor_sets:
			var trial: Array = (sv as Array).duplicate()
			trial.append_array(f)
			if trial.size() < GameConfig.HAND_SIZE:
				continue
			acc += best_score(trial, slots, extra, rules)   # 只要数字, 不建 56 个对象
			n += 1
	return acc / float(maxi(1, n))


## 从 keep 里随机弃掉 evict 张之后, **全部可能的幸存集合**。
## 缓存 ≤3 张所以直接位掩码枚举, 最多 8 次循环。
## evict=0 → 恰好一种(= keep 本身), 所以老路径逐位不变。
static func _survivor_sets(keep: Array, evict: int) -> Array:
	var n := keep.size()
	if evict <= 0:
		return [keep.duplicate()]
	if evict >= n:
		return [[]]
	var want := n - evict
	var out: Array = []
	for mask in range(1 << n):
		var cnt := 0
		for b in range(n):
			if (mask >> b) & 1:
				cnt += 1
		if cnt != want:
			continue
		var sub: Array = []
		for b in range(n):
			if (mask >> b) & 1:
				sub.append(keep[b])
		out.append(sub)
	return out
```

⚠ **`evict == 0` 时与原实现逐条等价**:`_survivor_sets` 返回恰好一个集合(= `keep` 本身),
外层循环退化成原来的单层循环,**且不消耗任何随机数** —— 那是 Step 3.5 要验的。
⚠ **成本**:`evict=1` 或 `2` 时 `best_score` 的调用数 ×3。只有带 `cache_evict` 的脸付这个钱
(无脸路径 ×1 不变)。`cache_value` 是全场最贵的一步,所以 Step 3.7 要留意 `gate.sh` 的耗时
是否仍在 ~10 分钟预算内;超了就在 `design/22` 里记一笔,**但不许为提速改回按位置删** ——
那是拿正确性换速度。

- [ ] **Step 3.4: 跑测试确认通过**

```bash
godot --headless --path /Users/kuma/Projects/Sync5 --script res://tests/runner.gd
```
Expected: `=== RESULT: 580 passed, 0 failed ===`(575 + 新增 5 条)。

- [ ] **Step 3.5: 对拍 —— 无脸路径必须逐位不变**

```bash
SYNC5_FORMAL_ONLY=theta godot --headless --path /Users/kuma/Projects/Sync5 --script res://tools/formal.gd
```
Expected(**必须一字不差**,这一组全程无脸):
```
规则 bot(adaptive)   总分     4545
完美玩家 λ=0.00      总分     6438
完美玩家 λ=0.20      总分     6932
完美玩家 λ=0.40      总分     7083
```
⚠ 任何一个数变了 = `evict=0` 的路径不是恒等变换,回到 Step 3.3。

- [ ] **Step 3.6: 量修复的效应 —— 缓存驱逐族的价格会移动多少**

```bash
./tools/gate.sh lostpage
./tools/gate.sh freshsheet
```
把两张脸修复前后的配对分差记下来,填进 `design/21 §3 缺口 2` 和 `design/22 §8` 主张 15。
判据按项目铁律**两条同时成立**:`|z| ≥ 3` **且** 量级 ≥5%。
⚠ **无论数字往哪边动,都不许去改这两张脸的机制** —— `design/22 §11` 的铁律:
模型测出近零只有两条路(修模型 / 标注「上界不动,真人待定」),
**第三条「改内容直到数字变负」是错的**,2026-08-07 已经栽过一次并全部还原。

- [ ] **Step 3.7: 全量回归**

```bash
godot --headless --path /Users/kuma/Projects/Sync5 --script res://tests/runner.gd
./tools/gate.sh
godot --headless --path /Users/kuma/Projects/Sync5 --script res://tools/pair.gd
```
⚠ **`pair.gd` 必须跑** —— 它守「求解器 = 游戏代码」,而本任务改的正是 `tools/solver.gd`,
`gate.sh` 不包含它(`design/19 §5.1` 注)。
Expected: tests 578 passed / gate 全过 / pair 第一关逐手相同。

---

## ⚠ 本计划**不覆盖**的 spec 内容(自检结果,显式列出而不是悄悄漏掉)

`design/22` 里还有四块没有对应任务。它们不是遗忘,是**当前做不了或用户没批**:

| spec 位置 | 为什么不在本计划里 |
|---|---|
| §2.7 **时间建成代价**(`Σ τ(a) ≤ T`) | 需要 `τ` 的真人取值,而**真人局为零**(磁盘 1067 局全是探针)。§8.3 已经证明它 binding 且向后兼容,**实现时机 = 拿到真人 Tape 之后** |
| §3 `θ` 的 `τ` 与 `d` 两维 | 同上;`d`(前瞻深度 >1 拍)没有实测支持要不要做,**别在没有证据时加维度** |
| §4 把 `P` 作为**生成器的产物**输出 | 本计划只让 `formal.gd` **算**这四个分量,没有把它接成生成器的输出。那一步依赖池子搜索(`design/19 §9` 第 5 项) |
| §5 `U` 的敏感性分析 | `U` 零数据。做法已写死(扫权重看 top-k 排序稳不稳),但排在池子搜索之后 |
| §9 **L1**(独立参考实现逐位对账) | 工作量与本计划三项相当,且必须由**没读过 `core/`** 的通路来写,否则是自证。单独排 |

⚠ **不要因为"顺手"就把这几项加进来** —— 尤其是 `τ`:在没有真人数据时给它拍一个值,
正是 `design/22 §11` 那张近似表要防的事(方向未知的近似 = 不能用来做决定的读数)。

---

## 完成后要回填的文档

- `design/22 §8` 主张表:主张 8(ε)、主张 15(前瞻转移)的状态;新增 L2 门的状态
- `design/22 §8bis`:ε 扫描的实测表
- `design/21 §3 缺口 2`:标注已修 + 实测效应
- `design/22 §9 L2`:从「判据」改成「已实装 = `tools/replay.gd`,已进 `gate.sh`」
- `CLAUDE.md` 工具链一节:新增 `replay.gd` 一行
