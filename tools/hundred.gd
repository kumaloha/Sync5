extends SceneTree

## 100 关生成验证(2026-08-19 用户:「要生成 100 关, 请确认关卡都是最新的逻辑生成」)。
##   godot --headless --path . --script res://tools/hundred.gd
##
## 走**真实生成路径**(Director.roll_run + data/ranking.json + min_run 解锁 + 局内去重),
## 把第 1~100 局全部掷出来, 逐局断言四条硬规则, 再给分布摘要。
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
	for r in range(1, RUNS + 1):
		var st := Director.state_for(r)
		by_state[st] = int(by_state.get(st, 0)) + 1
		var faces := Director.roll_run(r, rng, ranking)
		var used := {}
		for sec in faces:
			var f := String(faces[sec])
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
	if bugs == 0:
		print("  ✅ 100 关 × 4 墙 = 400 个放置, 全部通过四条硬规则(最新逻辑)")
	else:
		print("  ❌ %d 处违规" % bugs)
	quit(0 if bugs == 0 else 1)
