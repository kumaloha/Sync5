# 关卡重构（Gig Restructure）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按 `design/08_Run_Section_System.md`（2026-08-05 已拍板）把 Run 从平铺 10 Section 改为 **4 场演出（gig）× 3 盲注（小盲/大盲/Boss 墙）= 12 Section**；庆祝权重归位（轻横幅 vs 演出成功屏），四墙四池，12 段目标重校准。

**Architecture:** `core/config.gd` 承载全部结构常量与钩子（gig 换算、墙判定、12 段目标、按场时长曲线）；`core/modifier.gd` 四墙四池；`view/phrase.gd` 在 `_advance()` 处分流（墙 → 全屏成功屏，非墙 → 新建 `BlindBanner` 轻横幅 + 直接进商店）；`view/run_end.gd` 成功屏挂「第 N 场」文案、终幕移到 S12；`tools/sim.gd` 改 12 段后重跑死亡分布校准。

**Tech Stack:** Godot 4.6.2 / GDScript。测试 = `tests/runner.gd`（当前基线 225 全绿）；视觉验证 = 截图探针（项目铁律：改了视觉就渲染出来自己看）。

**本项目不是 git 仓库**：所有「commit」检查点替换为「跑测试全绿 / 截图目检」。

**通用命令：**

```bash
godot --headless --path /Users/kuma/Projects/Sync5 --script res://tests/runner.gd
```

预期尾行 `=== RESULT: N passed, 0 failed ===`。新增 `class_name` 后必须先：

```bash
godot --headless --path /Users/kuma/Projects/Sync5 --import
```

---

### Task 1: config.gd 结构常量 + 12 段目标 + 时长曲线

**Files:**
- Modify: `core/config.gd`（42-52 行 Run structure 区、13-21 行 `phrase_duration`、66-68 行换旗注释）
- Test: `tests/runner.gd`

- [ ] **Step 1: 写失败测试**

在 `tests/runner.gd` 中 `_test_modifiers()` 函数定义之前加入：

```gdscript
# --- Run structure (2026-08 关卡重构: run = 4 gigs × 3 blinds) ---
func _test_run_structure() -> void:
	eq(GameConfig.SECTIONS_PER_GIG, 3, "3 blinds per gig")
	eq(GameConfig.GIGS_PER_RUN, 4, "4 gigs per run")
	eq(GameConfig.SECTIONS_PER_RUN, 12, "12 sections per run")
	eq(GameConfig.SECTION_TARGETS.size(), 12, "12 section targets")
	check(GameConfig.WALL_SECTIONS == [2, 5, 8, 11], "walls close every gig")
	for w in GameConfig.WALL_SECTIONS:
		check(GameConfig.is_wall(w), "S%d is a wall" % (w + 1))
	for v in [0, 1, 3, 4, 6, 7, 9, 10]:
		check(not GameConfig.is_wall(v), "S%d is a verse" % (v + 1))
	eq(GameConfig.gig_of(0), 0, "S1 in gig 1")
	eq(GameConfig.gig_of(5), 1, "S6 in gig 2")
	eq(GameConfig.gig_of(11), 3, "S12 in gig 4")
	eq(GameConfig.blind_name(0), "小盲", "first blind name")
	eq(GameConfig.blind_name(1), "大盲", "second blind name")
	eq(GameConfig.blind_name(2), "BOSS", "wall blind name")
	eq(GameConfig.phrase_duration(0), 13.0, "gig 1 teaching clock")
	eq(GameConfig.phrase_duration(3), 12.0, "gig 2 standard clock")
	eq(GameConfig.phrase_duration(8), 12.0, "gig 3 standard clock")
	eq(GameConfig.phrase_duration(11), 11.0, "gig 4 squeeze clock")
	for i in range(1, GameConfig.SECTION_TARGETS.size()):
		var prev: int = GameConfig.SECTION_TARGETS[i - 1]
		var cur: int = GameConfig.SECTION_TARGETS[i]
		if GameConfig.is_wall(i - 1) and not GameConfig.is_wall(i):
			continue  # post-wall breather may step back (faces carry the wall)
		check(cur > prev, "targets climb at S%d" % (i + 1))
```

再搜索 runner.gd 里 `_test_modifiers()` 的**调用处**（测试注册列表），在其旁边追加一行 `_test_run_structure()`。

- [ ] **Step 2: 跑测试确认失败**

Run: 测试命令（见顶部）。
Expected: 编译期报错 `Cannot find member "SECTIONS_PER_GIG" in base "GameConfig"`（GDScript 常量在加载期解析，报编译错即「测试失败」信号）。

- [ ] **Step 3: 实现 config.gd**

替换 `core/config.gd` 13-21 行的 `phrase_duration`：

```gdscript
static func phrase_duration(section_idx: int) -> float:
	# gig pacing: roomy teaching gig, standard middle, squeezed finale
	match gig_of(section_idx):
		0: return 13.0              # 第 1 场教学
		3: return 11.0              # 第 4 场挤压
		_: return PHRASE_DURATION   # 第 2、3 场正常演出
```

替换 42-52 行的 Run structure 区为：

```gdscript
# --- Run structure (2026-08 关卡重构: run = 4 gigs × 3 blinds) ---
const PHRASES_PER_SECTION := 5
const SECTIONS_PER_GIG := 3     # 小盲 → 大盲 → BOSS wall
const GIGS_PER_RUN := 4
const SECTIONS_PER_RUN := 12    # SECTIONS_PER_GIG * GIGS_PER_RUN
const WALL_SECTIONS := [2, 5, 8, 11]   # every gig's third blind carries a face
const BLIND_NAMES := ["小盲", "大盲", "BOSS"]

static func is_wall(section_idx: int) -> bool:
	return (section_idx + 1) % SECTIONS_PER_GIG == 0

static func gig_of(section_idx: int) -> int:
	@warning_ignore("integer_division")
	return section_idx / SECTIONS_PER_GIG

static func blind_name(section_idx: int) -> String:
	return BLIND_NAMES[section_idx % SECTIONS_PER_GIG]

# 12 段初稿（关卡重构后待 sim 重校准；口径不变：死亡聚集在墙上，
# 墙面死亡率 30-60%，处决级只许 S12 终幕）。墙带脸，面就是墙的一部分。
const SECTION_TARGETS := [140, 280, 550, 700, 1000, 1450, 1600, 1950, 2400, 2500, 2900, 3400]
# clear wage (Balatro's blind reward): the income backbone that funds the shop —
# pattern coins alone cannot carry both the discard cost and the draft prices
const SECTION_CLEAR_REWARD := 3
```

`TARGET_SWAP_FROM_SECTION := 3` **数值不动**（打完 S3 墙后的第一个商店 `section_idx == 3`，正好是第 2 场的第一个商店），只把 62-65 行注释改为：

```gdscript
# Target swap (2026-08 关卡重构): pivot window opens with gig 2's shops —
# the first shop after the S3 wall enters with section_idx == 3. Buying the
# shelf Target replaces yours outright (no refund; the first one was free).
```

- [ ] **Step 4: 跑测试确认全绿**

Run: 测试命令。
Expected: `0 failed`（passed 数比 225 涨，记下新数字）。

---

### Task 2: modifier.gd 四墙四池

**Files:**
- Modify: `core/modifier.gd:54-61`（`pool_for`）+ 文件头注释
- Test: `tests/runner.gd`（`_test_modifiers`，约 243-255 行）

- [ ] **Step 1: 改测试（先失败）**

`_test_modifiers()` 中，把

```gdscript
	for idx in [4, 7, 9]:
		for id in SectionMod.pool_for(idx):
			check(SectionMod.by_id(id) != null, "pool id %s exists" % id)
```

替换为：

```gdscript
	for idx in GameConfig.WALL_SECTIONS:
		check(not SectionMod.pool_for(idx).is_empty(), "wall S%d has a pool" % (idx + 1))
		for id in SectionMod.pool_for(idx):
			check(SectionMod.by_id(id) != null, "pool id %s exists" % id)
```

并把两行掷点断言

```gdscript
	check(SectionMod.roll(4, rng) in SectionMod.pool_for(4), "roll draws from the pool")
	eq(SectionMod.roll(2, rng), "", "no roll outside walls")
```

替换为（S3 现在是墙，改用 S4 当「非墙」样本）：

```gdscript
	check(SectionMod.roll(2, rng) in SectionMod.pool_for(2), "roll draws from the pool")
	eq(SectionMod.roll(3, rng), "", "no roll outside walls")
```

- [ ] **Step 2: 跑测试确认失败**

Expected: `wall S3 has a pool` 一类断言 FAIL（pool_for(2) 目前为空）。

- [ ] **Step 3: 实现 pool_for**

替换 `core/modifier.gd:54-61`：

```gdscript
## Wall pools, one per gig (2026-08 关卡重构): S3 teaches "rules can change"
## with the gentlest pair, S6 stays mild, S9 gets mean, S12 nasty.
static func pool_for(section_idx: int) -> Array:
	match section_idx:
		2: return ["norepeat", "cover"]
		5: return ["norepeat", "rotation", "cover"]
		8: return ["unplugged", "static", "rotation", "norepeat"]
		11: return ["unplugged", "rush"]
	return []
```

同时把文件头注释里的 `(S5 / S8 / S10)` 改为 `(every gig's third blind: S3 / S6 / S9 / S12)`。

- [ ] **Step 4: 跑测试确认全绿**

---

### Task 3: sim.gd 改 12 段

**Files:**
- Modify: `tools/sim.gd:19`（`SECTIONS`）、`tools/sim.gd:104-106`（墙面掷点）

- [ ] **Step 1: 改常量**

`const SECTIONS := 10` → `const SECTIONS := GameConfig.SECTIONS_PER_RUN`
（若跨类常量初始化报错，退回字面量 `12` 并加注释 `# = GameConfig.SECTIONS_PER_RUN`。）

- [ ] **Step 2: 改墙面掷点**

`_one_run()` 中：

```gdscript
	var faces := {}
	for w in [4, 7, 9]:
		faces[w] = SectionMod.roll(w, _rng)
```

改为：

```gdscript
	var faces := {}
	for w in GameConfig.WALL_SECTIONS:
		faces[w] = SectionMod.roll(w, _rng)
```

- [ ] **Step 3: 验证解析**

跑一次测试命令确认无编译错（sim 的完整跑放在 Task 7）。

---

### Task 4: BlindBanner 轻横幅 + 截图探针

**Files:**
- Create: `view/blind_banner.gd`
- Create: `tools/banner_sheet.gd`

- [ ] **Step 1: 写 view/blind_banner.gd**

```gdscript
class_name BlindBanner
extends Control

## Light strip for non-boss blind clears (design/08 关卡重构): the full
## 演出成功 celebration is reserved for gig walls — small/big blinds get a
## sub-second banner (target ✓ + wage) that never blocks input; the shop
## opens beneath it while it slides away.

const W := 470.0
const H := 58.0
const SHOW_Y := 196.0

var _score := 0
var _target := 0
var _wage := 0
var _tw: Tween


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(W, H)
	position = Vector2((720.0 - W) * 0.5, SHOW_Y)


func pop(score: int, target: int, wage: int) -> void:
	_score = score
	_target = target
	_wage = wage
	move_to_front()
	visible = true
	modulate.a = 0.0
	position.y = SHOW_Y - 26.0
	queue_redraw()
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	_tw.set_parallel(true)
	_tw.tween_property(self, "position:y", SHOW_Y, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(self, "modulate:a", 1.0, 0.14)
	_tw.set_parallel(false)
	_tw.tween_interval(0.55)
	_tw.tween_property(self, "modulate:a", 0.0, 0.20)
	_tw.parallel().tween_property(self, "position:y", SHOW_Y - 18.0, 0.20)
	_tw.tween_callback(func() -> void: visible = false)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(StageTheme.box(
		Color(0.043, 0.055, 0.13, 0.88),
		Color(StageTheme.CYAN.r, StageTheme.CYAN.g, StageTheme.CYAN.b, 0.55), 2, 14,
		Color(StageTheme.CYAN.r, StageTheme.CYAN.g, StageTheme.CYAN.b, 0.30), 14), r)
	var zh := StageTheme.zh()
	var num := StageTheme.num("Bold")
	var seg_a := "目标达成 ✓  "
	var seg_n := "%d / %d" % [_score, _target]
	var seg_b := "   工资 +%d ◆" % _wage
	var wa: float = zh.get_string_size(seg_a, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var wn: float = num.get_string_size(seg_n, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	var wb: float = zh.get_string_size(seg_b, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var x := (W - (wa + wn + wb)) * 0.5
	var base_y := H * 0.5 + 8.0
	draw_string(zh, Vector2(x, base_y), seg_a, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("dffcf9"))
	draw_string(num, Vector2(x + wa, base_y + 1.0), seg_n, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, StageTheme.GOLD)
	draw_string(zh, Vector2(x + wa + wn, base_y), seg_b, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("ffd9a0"))
```

- [ ] **Step 2: 注册 class_name**

Run: import 命令（见顶部）。新增 `class_name` 不 import 会报 `Identifier not declared`。

- [ ] **Step 3: 写探针 tools/banner_sheet.gd**

```gdscript
extends SceneTree

## Screenshot probe for the blind-clear banner. Run NON-headless:
##   godot --path . --script res://tools/banner_sheet.gd
## Captures _shot_banner.png mid-hold, when the strip is fully lit.

var _banner: BlindBanner
var _frames := 0

func _initialize() -> void:
	get_root().set_content_scale_size(Vector2i(720, 1280))
	var bg := ColorRect.new()
	bg.color = Color("070a1a")
	bg.size = Vector2(720, 1280)
	get_root().add_child(bg)
	_banner = BlindBanner.new()
	get_root().add_child(_banner)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 6:
		_banner.pop(286, 260, 3)
	elif _frames == 6 + 30:
		var img := get_root().get_texture().get_image()
		img.save_png("res://_shot_banner.png")
		print("saved _shot_banner.png")
		quit()
	return false
```

- [ ] **Step 4: 截图目检**

Run: `godot --path /Users/kuma/Projects/Sync5 --script res://tools/banner_sheet.gd`
然后 Read `_shot_banner.png`：暗玻璃底 + 青描边 + 金色数字，文字居中、无溢出、无白块（渐变贴图首帧白块是已知坑，本横幅只用 StyleBox 不该出现）。

---

### Task 5: run_end.gd 成功屏挂「第 N 场」+ 终幕文案

**Files:**
- Modify: `view/run_end.gd:23-33`（成员）、`88-98`（`show_success`）、`78`（按钮文案）、`346-353`（`_title`）
- Modify: `tools/end_sheet.gd:19`

- [ ] **Step 1: 加场次参数**

成员区（`var _finale := false` 之后）加：

```gdscript
var _gig := 1             # which gig just cleared (1-based, shown on success)
```

`show_success` 改签名并存参（带默认值，兼容旧调用不炸编译）：

```gdscript
func show_success(score: int, target: int, wage: int, finale: bool, gig_no: int = 1) -> void:
	_mode = "success"
	_score = score
	_target = maxi(1, target)
	_wage = wage
	_finale = finale
	_gig = gig_no
	_rng.randomize()
	_make_confetti()
	_make_sticks()
	_open()
```

- [ ] **Step 2: 按钮 + 副标题文案**

78 行改为（「下一关」→「下一场演出」）：

```gdscript
	_btn_b.text = ("谢幕 ▸" if _finale else "下一场演出 ▸") if _mode == "success" else "再来一次 ↻"
```

`_title()` 成功分支的副标题改为：

```gdscript
		_sub("第 %d 场演出 · 全场沸腾" % _gig, 448.0, Color("5fd8d0"))
```

- [ ] **Step 3: 更新探针调用**

`tools/end_sheet.gd:19`：

```gdscript
		_scene.show_success(186, 150, 3, false, 2)   # after _ready — buttons exist
```

- [ ] **Step 4: 截图目检**

Run: `godot --path /Users/kuma/Projects/Sync5 --script res://tools/end_sheet.gd`
Read `_shot_end_success.png` / `_shot_end_fail.png`：成功屏副标题显示「第 2 场演出 · 全场沸腾」，主按钮「下一场演出 ▸」；失败屏不变（含雨幕——设计稿钦定，勿动）。

---

### Task 6: phrase.gd 流程接线 + HUD

**Files:**
- Modify: `view/phrase.gd`（`_ready` 156-161 后、成员 90 附近、`_advance` 615-628、`_on_end_next` 631-642、`_roll_run_faces` 677-682、`_build_info_bar` 204-213、`_refresh` 1010/1016-1022）

- [ ] **Step 1: 挂 banner 节点**

成员区 `var run_end: RunEndScreen`（90 行）后加：

```gdscript
var banner: BlindBanner
```

`_ready` 中 `add_child(run_end)`（161 行）后加：

```gdscript
	# blind-clear strip: non-boss sections skip the full success screen
	banner = BlindBanner.new()
	add_child(banner)
```

- [ ] **Step 2: _advance 分流（墙 vs 非墙）**

替换 615-628 行整个 `_advance()`：

```gdscript
func _advance() -> void:
	phrase.cleanup()
	_phrase_end_hooks()
	phrase_in_section += 1
	if phrase_in_section >= GameConfig.PHRASES_PER_SECTION:
		var target: int = GameConfig.SECTION_TARGETS[mini(section_idx, GameConfig.SECTION_TARGETS.size() - 1)]
		state = St.END
		if section_score < target:
			run_end.show_fail(section_score, target)
			return
		phrase.coins += GameConfig.SECTION_CLEAR_REWARD    # clear wage, shown as the panel chip
		if GameConfig.is_wall(section_idx):
			# gig cleared — the full 演出成功 ritual lives on the wall now
			run_end.show_success(section_score, target, GameConfig.SECTION_CLEAR_REWARD,
				section_idx >= GameConfig.SECTIONS_PER_RUN - 1, GameConfig.gig_of(section_idx) + 1)
		else:
			# small/big blind — light banner only, straight into the shop
			banner.pop(section_score, target, GameConfig.SECTION_CLEAR_REWARD)
			_next_section()
		return
	_start_phrase()
```

- [ ] **Step 3: 抽出 _next_section，改 _on_end_next**

替换 631-642 行：

```gdscript
## advance to the next blind and open the shop — every section boundary is a
## shop visit; with full slots it becomes the buy-new-replace-old flow
func _next_section() -> void:
	section_idx = mini(section_idx + 1, GameConfig.SECTIONS_PER_RUN - 1)
	phrase_in_section = 0
	section_score = 0
	_open_draft()


## success screen: 下一场演出 (or 谢幕 on the finale)
func _on_end_next() -> void:
	run_end.close()
	if section_idx >= GameConfig.SECTIONS_PER_RUN - 1:
		_on_end_home()          # 谢幕: the run is complete, take a bow
		return
	_next_section()
```

- [ ] **Step 4: 四墙掷点**

`_roll_run_faces()` 中 `for w in [4, 7, 9]:` → `for w in GameConfig.WALL_SECTIONS:`

- [ ] **Step 5: HUD——场次标签 + 12 点分组进度**

`_build_info_bar` 204-206 行，标签换中文字体与文案：

```gdscript
	section_label = StageTheme.label("第 1 场 · 小盲", StageTheme.zh(), 19, StageTheme.rim(0.75))
```

208-213 行的 10 连点改为 12 点、每场之间加 6px 组间隙、点距收窄（右边不许压到 `coin_label` 区，x 上限 ≈486）：

```gdscript
	for i in range(GameConfig.SECTIONS_PER_RUN):
		var pill := SegPill.new()
		pill.position = Vector2(244 + i * 19 + GameConfig.gig_of(i) * 6, 25)
		pill.size = Vector2(14, 7)
		inner.add_child(pill)
		seg_pills.append(pill)
```

`_refresh` 1010 行：

```gdscript
	section_label.text = "第 %d 场 · %s" % [GameConfig.gig_of(section_idx) + 1, GameConfig.blind_name(section_idx)]
```

（1020-1022 行的点亮循环 `i <= section_idx` 对 12 点依然成立，不改。）

- [ ] **Step 6: 跑测试 + 截图目检**

Run: 测试命令 → `0 failed`。
Run: `godot --path /Users/kuma/Projects/Sync5 --script res://tools/shoot.gd`
Read `_shot_idle.png`：信息区左上显示「第 1 场 · 小盲」（中文无豆腐块），12 点分 4 组、组间隙可辨、右侧不撞金币数字；预告条（NEXT ⚠）逻辑未动。

---

### Task 7: sim 重校准（死亡分布）

**Files:**
- Modify: `core/config.gd`（仅 `SECTION_TARGETS` 数值，可能微调 `core/modifier.gd` 池子）
- Modify: `design/08_Run_Section_System.md`（记录校准结论）

- [ ] **Step 1: 跑基线**

Run（后台，12 段比原来慢 ~20%，约 1-2 分钟）：

```bash
godot --headless --path /Users/kuma/Projects/Sync5 --script res://tools/sim.gd
```

- [ ] **Step 2: 按口径判读**

判据（全部沿用封盘时的口径）：
- 死亡聚集在 S3/S6/S9/S12 四堵墙上，不许出现「非墙段成片阴死」；
- 墙面死亡率（reachers 口径）30-60%；S3 允许贴下限（教学空间只剩 2 段，宁松勿紧）；处决级（>85%）只许 S12；
- 通关率量级参照旧盘：twin 队列 ~10-18%、greedy ~5-8%、random ≥1%；
- 若某张脸在非终幕墙上单独 >85%，调池子（把它挪去更晚的墙）而不是调倍率——小丑数值已封盘，**本任务只许动 `SECTION_TARGETS` 和墙池**。

- [ ] **Step 3: 迭代到健康**

改 `SECTION_TARGETS` → 重跑 → 复判，预计 2-4 轮收敛。每轮结论一行记在临时笔记，最终把「墙面死亡率表 + 通关率 + 改动理由」写进 `design/08` 新增的 Calibration 小节，并把 status 行从 "implementation pending" 改为 "shipped"。

- [ ] **Step 4: 校准后全量测试**

Run: 测试命令 → `0 failed`（结构测试只断言段数/爬升，不锁具体数值，改目标分不该红）。

---

### Task 8: 全量验证 + 文档同步

**Files:**
- Modify: `CLAUDE.md`（测试基线数、规则区、进度区、截图工具清单）

- [ ] **Step 1: 全量测试并记录新基线**

Run: 测试命令。记下 `N passed`（旧基线 225，Task 1/2 加了断言后会变）。

- [ ] **Step 2: 三处截图全部重跑并目检**

```bash
godot --path /Users/kuma/Projects/Sync5 --script res://tools/shoot.gd
```

```bash
godot --path /Users/kuma/Projects/Sync5 --script res://tools/banner_sheet.gd
```

```bash
godot --path /Users/kuma/Projects/Sync5 --script res://tools/end_sheet.gd
```

逐张 Read 目检（HUD / 横幅 / 结算两屏）。

- [ ] **Step 3: 同步 CLAUDE.md**

- 「测试基线 225 passed」→ 新数字；
- 规则区「Phrase 固定 12s。5 个 Phrase 一个 Section…」补充为四场三盲结构（一行带走：Run=4 场 ×3 盲注=12 Section，墙在每场第三盲，轻横幅/成功屏分层，时长曲线 13/12/12/11 按场）；
- 截图工具清单加 `banner_sheet.gd` → `_shot_banner.png`；
- 进度区加一行：关卡重构已实装（design/08 为准），下一站仍是真人试玩。

- [ ] **Step 4: 终检**

跑一遍测试命令收尾确认 `0 failed`，对照 `design/08` 逐节核对无遗漏（结构/节奏/池子/换旗/失败/HUD 六项）。

---

## Self-Review 结论

- **Spec 覆盖**：结构常量(T1)、四池(T2)、sim(T3/T7)、轻横幅(T4)、成功屏场次+终幕(T5)、流程与 HUD(T6)、校准(T7)、文档(T8)——design/08 各节均有对应任务；换旗窗口经核对**数值无需改动**（仅注释），已在 T1 说明。
- **类型一致**：`show_success(..., gig_no: int = 1)` 与 T6 调用一致；`GameConfig.is_wall/gig_of/blind_name/WALL_SECTIONS/SECTIONS_PER_RUN` 各处引用同名。
- **无占位**：所有代码块给全文；校准数值本质是迭代产物，判据已写死。
