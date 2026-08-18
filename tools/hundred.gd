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
	for r in range(1, RUNS + 1):
		var st := Director.state_for(r)
		by_state[st] = int(by_state.get(st, 0)) + 1
		var faces := Director.roll_run(r, rng, ranking)
		var used := {}
		for sec in faces:
			var f := String(faces[sec])
			# ① 每段必须有脸
			if f == "":
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
