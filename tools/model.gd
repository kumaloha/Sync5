extends Probe

## 能力模型 v2 —— 对抗校准框架的**生成侧 G**(2026-08-06 用户定调:
## 「有点像 GAN, 一个是生成, 一个是判断, 后面要互相对抗学习」)。
##
##   godot --headless --path . --script res://tools/model.gd
##
## 角色分工:
##   G(本工具)  = 能力模型:预测各队列每段的分数分布 → 通关率;
##                反解:给定「想要的死亡分布」→ 生成 bot 尺度 section_targets。
##   D(sim.gd)  = 判别器:bot 真打, 报实测死亡分布。
##   loss       = G 的预测 vs D 的实测之差。**两侧是独立程序, 对账在外面做**
##                (G 直接调 D 的代码就成第二个判别器了, 模型的意义在于快 + 可反解)。
##
## v1 的教训(2026-08-06 复核, 详见记忆):
##   · 拍级蒙特卡洛看不见跨拍增长引擎 —— 但 G 第一步只要**预测得准 D**,
##     D(bot)自己也不用成长牌复利, 所以 v2 先对齐 D, 真人上界是第 4 步的事;
##   · kit 的选择就是结论 —— v2 用 bot 实际买得起、抽得到的加法组合, 因为要预测的就是 bot;
##   · 无经济约束的弃牌预算是幻想 —— v2 用 bot 的真实上限(每拍 2 次)。
##
## v1 已知未建(loss 对账时按这个清单找差距):
##   × 经济记账(买不起就不装 —— v2 假设按固定日程装满)
##   × ~~主角被动~~(2026-08-24 主角系统删除, 这一项不复存在)
##   × 脸的行为影响(rotation 强制弃一张 / rush 压时钟 —— 只建了结算影响)
##   × 换旗/wolfpivot/anytarget/random 三类策略(涉及中途改道)
##   × 商店随机性(supports 固定为胜率组合, 实际是加权抽)

const TRIALS := 1200       # 每个原子格的蒙特卡洛数
const MIX := 20000         # 段分布重采样数
const D_BUDGET := 2        # bot 的弃牌上限(8s 拍只装得下两次付费动作)

## 预测队列, 与 sim cohorts 对齐(单 target 直线策略的六个)
const COHORTS := [
	{"name": "baseline", "target": "", "jokers": false},
	{"name": "twin", "target": "twin", "jokers": true},
	{"name": "stair", "target": "stair", "jokers": true},
	{"name": "mono", "target": "mono", "jokers": true},
	{"name": "triplet", "target": "triplet", "jokers": true},
	{"name": "lonewolf", "target": "lonewolf", "jokers": true},
]
## bot 真实会买的加法组合(sim 胜率组合; mirror 太贵太稀, bot 基本抽不到)
const SUPPORTS := ["neonsign", "encore", "finale"]
## 装配日程: [段, 槽位数] —— 「4 槽前 4 次商店填满」的窗口化:
## S1 前半 0 槽(开局无商店) / S1 后半 1(段中商店送免费 Target) /
## S2 前半 2 / S2 后半 3 / S3 起 4 槽拉满
const WINDOWS := [[0, 0], [0, 1], [1, 2], [1, 3], [2, 4], [3, 4]]

## 设计谱:每段「到达者中的死亡率」。红线来自 docs/design/levels.md —— 墙面健康区间
## 30-60%, 处决级(>85%)只允许终幕;基调 = 多数 run 会死。
## 0.10×0.30×0.45×0.60 → 全通率 ≈ 13.9%, 正落在基调上。
const DEATH_SPEC := [0.10, 0.30, 0.45, 0.60]

var _rng := RandomNumberGenerator.new()
var _bot: Bot
var _atoms := {}           # "cohort/window" -> Array[float] 单拍分数样本


func _initialize() -> void:
	_bot = Bot.new(_rng, Report.new(1, GameConfig.SECTIONS_PER_RUN))
	var t0 := Time.get_ticks_msec()
	print("=== 能力模型 v2(生成侧 G) ===")
	print("结构 %d 段 × %d 拍 · 弃牌预算 %d/拍 · 原子 %d 试次/格\n"
		% [GameConfig.SECTIONS_PER_RUN, GameConfig.PHRASES_PER_SECTION, D_BUDGET, TRIALS])
	_sample_atoms()
	_predict()
	_generate()
	print("\n[model] %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)


# ============================ 原子采样 ============================

func _sample_atoms() -> void:
	print("--- 原子格(单拍期望分 · 段位脸池已采样进去) ---")
	var head := "%-10s" % "队列"
	for w in WINDOWS:
		head += "%12s" % ("S%d·%d槽" % [int(w[0]) + 1, int(w[1])])
	print(head)
	for c in COHORTS:
		var line := "%-10s" % String(c["name"])
		for wi in range(WINDOWS.size()):
			var key := "%s/%d" % [String(c["name"]), wi]
			var xs: Array = []
			for t in range(TRIALS):
				_rng.seed = 7000000 + wi * 100000 + t
				xs.append(_phrase_score(c, WINDOWS[wi]))
			_atoms[key] = xs
			line += "%12.0f" % Stat.mean(xs)
		print(line)


## 一拍的最终得分:真实 Deck/Phrase/Pattern/Settle, 段位脸从该段的池里抽。
func _phrase_score(c: Dictionary, w: Array) -> float:
	var tid := String(c["target"])
	var slots := _slots_for(c, int(w[1]))
	var section := int(w[0])
	var budget := 0 if tid == "lonewolf" else D_BUDGET
	# 该段的脸(结算影响; 行为影响未建, 见头部清单)
	var pool: Array = SectionMod.pool_for(section)
	var mod := "" if pool.is_empty() else String(pool[_rng.randi_range(0, pool.size() - 1)])

	var deck := Deck.new(_rng.randi())
	var cache: Array = []
	# 热身拍:20/24 张牌是条件触发(prev_kind / 跨拍缓存), 冷启动会让它们哑火
	var wp := Phrase.new(deck, cache, 999)
	wp.start()
	_curate(wp, tid, budget)
	var prev_kind := int(wp.lock_and_settle().get("kind", -99))
	wp.cleanup()

	var p := Phrase.new(deck, cache, 999)
	p.start()
	var used := _curate(p, tid, budget)
	var res := p.lock_and_settle()
	# ⚠⚠ `section_target` 必须传, 否则按「本段每拍目标的 x%」定额的卡在这里静默算 0。
	# 本探针是**单段尺度**的, 所以取第 0 段 —— 显式写出来, 别让它是个默认值的副作用。
	var out := Settle.run(res, slots, {"prev_kind": prev_kind, "acted_late": true,
		"discards": used, "coins": 20, "cache_cards": p.cache, "mod": mod,
		"section_idx": 0, "section_target": GameConfig.section_target(0)})
	return float(out["score"])


func _slots_for(c: Dictionary, n: int) -> Array:
	var slots: Array = [null, null, null, null]
	if not bool(c["jokers"]) or n <= 0:
		return slots
	slots[0] = Joker.by_id(String(c["target"]))
	for i in range(mini(n - 1, SUPPORTS.size())):
		slots[i + 1] = Joker.by_id(SUPPORTS[i])
	return slots


## 免费换缓存 + 弃牌(bot 同款贪心计划, 上限 = budget)
func _curate(p: Phrase, tid: String, budget: int) -> int:
	var rules: Dictionary = p.deck.rules
	for ci in range(p.cache.size()):
		for hi in range(p.hand.size()):
			var before: float = float(_bot._best_plan(p.hand, tid, 3, rules)["ev"])
			# probe 口径与 tools/bot.gd::_play_adaptive 同步(2026-08-13):
			# 试探不是玩家动作, 否则「本拍零交换」类条件在模型里永不成立。
			if not p.swap_with_cache(hi, ci, true):
				continue
			var after: float = float(_bot._best_plan(p.hand, tid, 3, rules)["ev"])
			if after <= before:
				p.swap_with_cache(hi, ci, true)
			else:
				p.commit_probe_swap()
	var used := 0
	while used < budget:
		var plan: Dictionary = _bot._best_plan(p.hand, tid, budget - used, rules)
		if bool(plan.get("keep_all", false)):
			break
		var keep: Array = plan["keep"]
		var idx: Array = []
		for i in range(p.hand.size()):
			if not keep.has(i) and idx.size() < budget - used:
				idx.append(i)
		if idx.is_empty() or not p.discard_selected(idx, []):
			break
		used += idx.size()
	return used


# ============================ 段分布与预测 ============================

## 段 s 的窗口构成:S1 = 前半窗 + 后半窗 各 3 拍;S2 同;S3/S4 = 单窗 6 拍
func _section_windows(s: int) -> Array:
	match s:
		0: return [[0, 3], [1, 3]]
		1: return [[2, 3], [3, 3]]
		2: return [[4, 6]]
		_: return [[5, 6]]


## 队列 c 在段 s 的总分样本(MIX 个)
func _section_samples(cname: String, s: int) -> Array:
	var parts := _section_windows(s)
	var out: Array = []
	out.resize(MIX)
	for i in range(MIX):
		var total := 0.0
		for pt in parts:
			var xs: Array = _atoms["%s/%d" % [cname, int(pt[0])]]
			for k in range(int(pt[1])):
				total += float(xs[_rng.randi_range(0, xs.size() - 1)])
		out[i] = total
	return out


func _predict() -> void:
	print("\n--- 预测:各队列通关率(打在当前 bot_targets 上) ---")
	print("bot_targets = %s" % str(DB.sim()["bot_targets"]))
	print("对账方法:跑一遍 sim, 把下表和它的 reach%%/full clear 并排看 —— 差距 = loss。\n")
	var head := "%-10s" % "队列"
	for s in range(GameConfig.SECTIONS_PER_RUN):
		head += "%9s" % ("过S%d" % (s + 1))
	head += "%9s" % "全通"
	print(head)
	_rng.seed = 424242
	for c in COHORTS:
		var cname := String(c["name"])
		var line := "%-10s" % cname
		var alive := 1.0
		for s in range(GameConfig.SECTIONS_PER_RUN):
			var t := float(int(DB.sim()["bot_targets"][s]))
			var xs := _section_samples(cname, s)
			var pass_n := 0
			for v in xs:
				if float(v) >= t:
					pass_n += 1
			var pc := float(pass_n) / float(xs.size())
			alive *= pc
			line += "%8.0f%%" % (pc * 100.0)
		line += "%8.1f%%" % (alive * 100.0)
		print(line)


# ============================ 反解生成 ============================

func _generate() -> void:
	print("\n--- 生成:给定死亡谱, 反解 bot 尺度 section_targets ---")
	print("设计谱(到达者死亡率): %s" % str(DEATH_SPEC))
	print("参照人群 = 六队列等权混合(v1 简化:未按段淘汰重加权)。\n")
	_rng.seed = 434343
	var gen: Array = []
	for s in range(GameConfig.SECTIONS_PER_RUN):
		var mixture: Array = []
		for c in COHORTS:
			mixture.append_array(_section_samples(String(c["name"]), s))
		mixture.sort()
		var q := clampf(float(DEATH_SPEC[s]), 0.0, 1.0)
		var idx: int = clampi(int(round(q * float(mixture.size() - 1))), 0, mixture.size() - 1)
		gen.append(int(round(float(mixture[idx]))))
	print("生成的 bot_targets = %s" % str(gen))
	print("验证方法:把它填进 data/sim.json bot_targets 跑 sim, 比对实测死亡分布")
	print("与设计谱的差距(记得改回)。差距大的段 = 模型缺的机制在那一段最重。")
