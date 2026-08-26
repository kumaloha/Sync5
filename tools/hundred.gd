extends SceneTree

## 100 关生成验证(2026-08-19 用户:「要生成 100 关, 请确认关卡都是最新的逻辑生成」)。
##   godot --headless --path . --script res://tools/hundred.gd
##
## 走**真实生成路径**(Director.roll_run + data/ranking.json + min_run 解锁 + 局内去重),
## 把第 1~100 局全部掷出来, 逐局断言四条硬规则, 再给分布摘要。
## 2026-08-26 起追加周期课程(difficulty.md §2.5)两条:⑤ 考试局(pos 5/10)四墙
## 至少一张加码族;⑥ 学习局主题轴命中率显著(2σ)高于基线。
## ⚠ 种子固定 —— 本探针验的是「逻辑」, 不是某个玩家会拿到的具体序列
## (真实游戏的 RNG 每局不同, 但走的是同一条代码路径)。

const RUNS := 100


func _initialize() -> void:
	var ranking: Dictionary = DB.ranking_tiers()
	assert(not ranking.is_empty(), "ranking.json 没喂 —— Director 是 1.0 必须")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260819
	var bugs := 0
	var seen_per_face := {}          # face -> [首次出现的局号, 次数]
	var by_state := {}               # 状态名 -> 局数
	var s1_easy := 0                 # 解锁后首墙掷成纯分数关的局数(概率放水)
	# 周期课程(difficulty.md §2.5)的账本:主题轴命中 vs 基线(同一轴在非主题局)
	var axes: Array = SectionMod.axis_ids()
	var th_hits := {}                # 轴 -> 主题局里命中该轴的墙数
	var th_slots := {}               # 轴 -> 主题局里的实墙总数
	var bg_hits := {}                # 轴 -> 非主题局里命中该轴的墙数(基线)
	var bg_slots := {}
	var exam_runs := 0
	for r in range(1, RUNS + 1):
		var st := Director.state_for(r)
		by_state[st] = int(by_state.get(st, 0)) + 1
		var caxis := Director.cycle_axis(r)
		var faces := Director.roll_run(r, rng, ranking)
		var used := {}
		var fam := false
		for sec in faces:
			var f := String(faces[sec])
			# 周期账本(空墙不算槽位 —— 没掷点就没有课程可谈)
			if f != "":
				var fa: Array = SectionMod.attack_axes(f)
				for a in axes:
					var akey := String(a)
					var hit := 1 if fa.has(akey) else 0
					if akey == caxis:
						th_hits[akey] = int(th_hits.get(akey, 0)) + hit
						th_slots[akey] = int(th_slots.get(akey, 0)) + 1
					else:
						bg_hits[akey] = int(bg_hits.get(akey, 0)) + hit
						bg_slots[akey] = int(bg_slots.get(akey, 0)) + 1
				if Director.exam_family(f):
					fam = true
			# ① 每段必须有脸 —— **除了首墙**(2026-08-24 两层放水):
			#    新手期(r < s1_face_min_run)首墙**必须**空;解锁后允许按 s1_easy_chance 空。
			if int(sec) == 0 and not SectionMod.wall_face_unlocked(0, r):
				if f != "":
					print("❌ 局 %d 首墙未到解锁局却有脸 %s" % [r, f]); bugs += 1
				continue
			if f == "":
				if int(sec) == 0:
					s1_easy += 1
					continue
				print("❌ 局 %d 段 %d 空脸" % [r, sec]); bugs += 1
				continue
			# ② 局内不重复
			if used.has(f):
				print("❌ 局 %d 重复脸 %s" % [r, f]); bugs += 1
			used[f] = true
			# ③ tier 合法(这张脸允许出现在这一段)
			if not SectionMod.pool_for(int(sec)).has(f):
				print("❌ 局 %d 段 %d 掷出池外脸 %s" % [r, sec, f]); bugs += 1
			# ④ min_run 解锁(禁回只许第 10 局起)—— 走和游戏同一个判定口
			if not SectionMod.unlocked_at(f, r):
				print("❌ 局 %d 掷出未解锁脸 %s" % [r, f]); bugs += 1
			if not seen_per_face.has(f):
				seen_per_face[f] = [r, 0]
			seen_per_face[f][1] += 1
		# ⑤ 考试局(周期课程 §2.5):四墙至少一张加码族。保证是 zero-RNG 的
		#    (Director.ensure_exam_wall), 所以这里红 = 接线断了, 不是运气差。
		if Director.cycle_exam(r) != "":
			exam_runs += 1
			if not fam:
				print("❌ 局 %d 是考试位却没有加码族" % r); bugs += 1
	print("\n=== 100 关生成验证 ===")
	print("  状态分布: %s" % str(by_state))
	# 概率放水的走带自检:解锁后 ~97 局 × p, 偏出 3 个标准误就喊(p=0 时必须恰 0)
	var p := GameConfig.S1_EASY_CHANCE
	var n_unlocked := RUNS - (GameConfig.S1_FACE_MIN_RUN - 1)
	var expect := p * float(n_unlocked)
	var se3 := 3.0 * sqrt(maxf(0.0001, p * (1.0 - p) * float(n_unlocked)))
	print("  首墙简单关: %d / %d 局(期望 %.1f ± %.1f)" % [s1_easy, n_unlocked, expect, se3])
	if absf(float(s1_easy) - expect) > se3:
		print("❌ 简单关频率偏出 3σ —— s1_easy_chance 的掷点可能接错了"); bugs += 1
	print("  出场脸种数: %d;首次出现最晚的:" % seen_per_face.size())
	var rows: Array = []
	for f in seen_per_face:
		rows.append([seen_per_face[f][0], f, seen_per_face[f][1]])
	rows.sort()
	for i in range(maxi(0, rows.size() - 5), rows.size()):
		print("    局 %d 首见 %s(共 %d 次)" % [rows[i][0], rows[i][1], rows[i][2]])
	# ⑥ 周期课程:学习局的主题轴命中率显著高于基线(同一轴在非主题局的命中率)。
	#    期望/方差按逐轴基线合成(每轴的主题槽数 × 该轴基线率), 2σ 门槛 ——
	#    固定 seed 下这是确定读数, 红 = 偏置没接上或 bias_mult 拧太小, 不是抽样噪声。
	var actual := 0
	var expect_hits := 0.0
	var var_sum := 0.0
	print("  周期课程(bias_mult=%.1f):" % Director.cycle_mult())
	for a in axes:
		var akey := String(a)
		var ts := int(th_slots.get(akey, 0))
		if ts == 0:
			continue          # 这条轴没占过学习位(如 time:第四轮全员时间族, 不占学习位)
		var p0 := float(bg_hits.get(akey, 0)) / maxf(1.0, float(bg_slots.get(akey, 0)))
		var th := int(th_hits.get(akey, 0))
		actual += th
		expect_hits += float(ts) * p0
		var_sum += float(ts) * p0 * (1.0 - p0)
		print("    轴 %-8s 主题局 %2d/%2d = %.2f | 基线 %.2f" \
			% [akey, th, ts, float(th) / float(ts), p0])
	var sigma := sqrt(maxf(var_sum, 0.0001))
	print("  主题命中合计 %d(无课程期望 %.1f, 2σ 门槛 %.1f)" \
		% [actual, expect_hits, expect_hits + 2.0 * sigma])
	if float(actual) <= expect_hits + 2.0 * sigma:
		print("❌ 学习局主题轴命中率不显著高于基线 —— 课程没接上或 bias_mult 太小"); bugs += 1
	print("  考试局: %d 局(pos 5/10), 逐局加码族保证见 ⑤" % exam_runs)
	if exam_runs == 0:
		print("❌ 100 局里一个考试位都没有 —— 周期表没接上"); bugs += 1
	if bugs == 0:
		print("  ✅ 100 关 × 4 墙 = 400 个放置, 全部通过四条硬规则(最新逻辑)")
	else:
		print("  ❌ %d 处违规" % bugs)
	quit(0 if bugs == 0 else 1)
