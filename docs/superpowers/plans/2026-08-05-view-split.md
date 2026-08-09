# 大文件拆分（View Split）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按 `design/14_View_Split.md` 把 view/phrase.gd(1342 行)五刀拆到 ~400、tools/sim.gd(882 行)三拆，UI 布局/文案进 `data/ui.json`，行为零变更。

**Architecture:** 纯搬迁 + 接缝信号化。新文件一词命名：`view/widgets.gd`(Widgets.GradBar/SegPill/DJKey)、`view/hud.gd`(Hud)、`view/shop.gd`(Shop)、`view/hand.gd`(Hand)、`core/run.gd`(Run)、`tools/bot.gd`(Bot)、`tools/report.gd`(Report)。函数体**逐字搬**（源文件为权威），只有接缝（信号/vm 字典/ui.json 读数）按本计划的代码写。

**Tech Stack:** Godot 4.6.2 / GDScript。无 git，检查点 = 测试全绿 + 截图目检 + sim 逐字节 A/B。

**通用命令**：测试 `godot --headless --path /Users/kuma/Projects/Sync5 --script res://tests/runner.gd`（基线 283）；新增 class_name 后先 `--import`。

**铁则**：每刀做完立即测试 + 相关探针目检；发现行为漂移回滚本刀重来，不带病前进。JSON 数字读取处 `int()/float()` 归一。

---

### Task R0: 拆前基线

- [ ] 存 sim 基线：`godot --headless --path . --script res://tools/sim.gd > <scratchpad>/sim_presplit.txt 2>&1`（后台，~4.5 分钟；可与 R1-R2 并行）。
- [ ] 跑一遍全部截图探针存现状（shoot/banner/end/draft/card/crew/key），目检基准。

### Task R1: widgets.gd + data/ui.json 骨架 + DB.ui()

**Files:** Create `view/widgets.gd`, `data/ui.json`; Modify `core/db.gd`, `view/phrase.gd`, `tests/runner.gd`

- [ ] `tests/runner.gd` `_test_db` 加：`eq(DB.load_error(), "", ...)` 已覆盖 → 只需加 `check(DB.ui().has("stage"), "ui.json has stage")`。跑测试确认编译错（DB.ui 不存在）。
- [ ] `data/ui.json` 落 stage 节（数值 = phrase.gd 顶部 const 现值）：

```json
{"stage": {"margin": 26, "card_w": 114, "card_h": 170, "gap": 16,
           "resolve_hold": 1.6, "pill_w": 200, "hand_top": 672,
           "hand_card_y": 724, "cache_y": 1024,
           "lift_base": 16, "lift_scoring": 8, "lift_selected": -2}}
```

（hud/shop/hand/banner 节由 R2-R4 各自补入；`validate_ui` 只查「已知节名之外报错」+「stage 必在」，节内不逐键校验——布局键随实现走。）
- [ ] `core/db.gd`：加 `static func ui() -> Dictionary`（`_load("ui", validate_ui)`）、`validate_ui`（允许节：stage/hud/shop/hand/banner）、`load_error()` 接入。
- [ ] `view/widgets.gd`：`class_name Widgets extends RefCounted` + 把 phrase.gd 尾部 `class GradBar / class SegPill / class DJKey` 三个内部类**逐字搬入**为内部类。phrase.gd 删除三类，引用改 `Widgets.GradBar / Widgets.SegPill / Widgets.DJKey`（成员声明 `pbar/sort_key/discard_key/seg_pills` 的类型与 `new()` 处，共 ~8 处）。
- [ ] phrase.gd 顶部 const 改读 `DB.ui()["stage"]`（保持同名 static/成员变量，调用点不动；`HAND_X0` 仍由公式算出）。
- [ ] `--import` + 测试全绿；`shoot.gd` 重跑目检（信息区/两键/进度点应与基线无差）。

### Task R2: hud.gd（信息区组件）

**Files:** Create `view/hud.gd`; Modify `view/phrase.gd`, `data/ui.json`, `tools/shoot.gd`(如捅了内部)

- [ ] ui.json 补 `hud` 节：`_build_info_bar` 里的全部坐标（panel pos/size、section_label、pills{x0,pitch,gap,y,w,h}、coin、score、target_x_base、phrase、mod、pbar）。
- [ ] `view/hud.gd`：`class_name Hud extends Control`。搬 `_build_info_bar` 全部（构造即搭建，读 ui.json）+ `_refresh` 的信息区片段。对外：

```gdscript
## vm keys: section_idx:int, coins:int, score:int, target:int,
##          phrase_no:int, fraction:float
func refresh(vm: Dictionary) -> void
func set_mod_text(t: String) -> void      # NEXT ⚠ / 生效脸一行
func coin_anchor() -> Vector2             # 飘字定位（coin_label 全局坐标）
```

- [ ] phrase.gd：删被搬代码；`_build_ui` 建 `hud = Hud.new()`；`_refresh` 头部与 `_start_phrase` 的 mod_label 写点改走 hud API；`coin_label.get_global_position()` 两处飘字改 `hud.coin_anchor()`。
- [ ] `--import` + 测试 + shoot.gd 目检。

### Task R3: shop.gd（商店组件）

**Files:** Create `view/shop.gd`; Modify `view/phrase.gd`, `data/ui.json`, `tools/draft_sheet.gd`(探针改用 Shop)

- [ ] ui.json 补 `shop` 节（文案 + 布局，值 = 现代码字面量：title/target_line/support_line/reroll_text/skip_text/free_text/insufficient/replace_prompt + title_y/kind_y/card_w/card_gap/cards_y/price_dy/btn_y）。
- [ ] `view/shop.gd`：`class_name Shop extends Control`。搬 `_build_draft/_draft_button/_deal_draft/_weighted_pick/_candidate_price/_draft_affordable/_on_draft_pick/_on_draft_reroll/_on_draft_skip` + replace_prompt 与 `draft_*` 成员。接缝：

```gdscript
signal bought(j, price: int)            # 判定可负担后发出；扣币装槽在编排器
signal replace_requested(j)             # 满槽：编排器进入替换模式
signal skipped()                        # 已含 +skip 奖励的金币委托
signal reroll_paid(cost: int)           # 编排器扣币
func open(slots: Array, coins: int) -> void     # 进店（重置 reroll 计数）
func redeal(slots: Array, coins: int) -> void   # reroll 后重发
func close() -> void
func section_idx: int                   # 编排器每段更新（换旗窗口判定用）
```

内部只做展示与可负担判定；`randf/randi_range/shuffle` 调用点与顺序**原样保留**。
- [ ] phrase.gd：`_open_draft` 变薄（`state=DRAFT; shop.open(...)`）；接四个信号：bought→扣币/装槽/on_acquire/`_start_phrase`，replace_requested→现 `replace_pick` 流程（`_on_slot_tapped/_end_replace` 留编排器，槽行是它的），skipped→加币飘字 `_start_phrase`，reroll_paid→扣币后 `shop.redeal(...)`。
- [ ] draft_sheet.gd 探针改经 Shop 入口摆拍。`--import` + 测试 + draft_sheet 两态目检。

### Task R4: hand.gd（手牌/缓存/两键组件）

**Files:** Create `view/hand.gd`; Modify `view/phrase.gd`, `data/ui.json`

- [ ] ui.json 补 `hand` 节（hand_tab/cache_tab/sort_label/discard_label + 区标签坐标）。
- [ ] `view/hand.gd`：`class_name Hand extends Control`。搬 `_build_orbit` 的 5 张卡格（frame/orbit/区标签一并）、`_build_cache_row` 全部、INPUT 区 `_on_hand_tap/_on_cache_card_tap/_on_hand_drop/_on_cache_drop/_on_discard_drop` 的**选中态维护半边**、`_refresh` 的手牌/缓存/按键片段、`_flip_reveal/_ghost_fly`。选中态 `sel_hand/sel_cache/_last_hand/_last_cache/_deal_flip` 内聚于 Hand。接缝：

```gdscript
signal sort_pressed()
signal discard_pressed(sel_hand: Array, sel_cache: Array)      # 多选弃
signal single_discard(zone: String, idx: int)                  # 拖到弃牌键
signal swap_requested(hand_i: int, cache_i: int)               # 点选或拖拽对调
signal acted()                                                  # 喂 _action_feedback
func refresh(vm: Dictionary) -> void
## vm keys: hand:Array[Card], cache:Array[Card], scoring:Dictionary,
##          decide:bool, can_discard_sel:bool, fee:int, can_drop:bool
func clear_selection() -> void
func deal_flip() -> void            # phrase 开始时整手翻入
func selection() -> Array           # [sel_hand, sel_cache] 只读
```

- [ ] phrase.gd：编排器保留 `_on_sort/_on_discard` 的**业务半边**（校验 can_discard、改 Phrase、`_notify_discard`、vinyl.spin_boost、`_action_feedback`），由信号触发；`_refresh` 相应片段改为组装 vm 调 `hand.refresh(vm)`。orbit（走圈）与 hand 同帧几何，orbit 仍由编排器持有（结算 popup 定位用）——只搬卡格不搬 orbit 亦可，实施时取耦合更小者，**保证视觉零变**。
- [ ] `--import` + 测试 + shoot.gd 三段式目检（翻牌/选中抬升/拖拽 payload 都在此验证）。

### Task R5: core/run.gd（推进状态机，唯一新增测试面）

**Files:** Create `core/run.gd`; Modify `view/phrase.gd`; Test `tests/runner.gd`

- [ ] 先写失败测试 `_test_run_machine()`（注册在 `_test_run_structure` 旁）：

```gdscript
func _test_run_machine() -> void:
	var r := Run.new()
	r.reset(7)                                   # 种子掷脸,决定性
	eq(r.section_idx, 0, "run starts at S1")
	for w in GameConfig.WALL_SECTIONS:
		check(r.run_faces.has(w), "face rolled for wall S%d" % (w + 1))
	r.section_score = 999999
	var out := r.advance()                        # 5 个 phrase 后过段
	for i in range(GameConfig.PHRASES_PER_SECTION - 1):
		check(not bool(out["section_done"]), "mid-section keeps going")
		out = r.advance()
	check(bool(out["section_done"]), "section closes after 5 phrases")
	check(bool(out["cleared"]), "score over target clears")
	check(not bool(out["is_wall"]), "S1 is not a wall")
	r.next_section()
	eq(r.section_idx, 1, "advance to S2")
	eq(r.section_score, 0, "score resets")
	r.section_idx = 2
	r.phrase_in_section = GameConfig.PHRASES_PER_SECTION - 1
	r.section_score = 0
	out = r.advance()
	check(bool(out["section_done"]) and not bool(out["cleared"]), "miss = fail")
	check(bool(out["is_wall"]), "S3 is a wall")
```

- [ ] `core/run.gd` 实现（**引擎无关**，字段与 phrase.gd 现成员同名同义）：

```gdscript
class_name Run
extends RefCounted

## Run progression state machine (design/14): everything about WHERE the
## run is lives here, engine-free and directly testable. view/phrase.gd
## keeps only presentation and input orchestration.

var deck: Deck
var cache: Array = []
var section_idx := 0
var phrase_in_section := 0
var section_score := 0
var phrase_index := 0
var joker_slots: Array = [null, null, null, null]
var prev_kind := -99
var run_faces: Dictionary = {}
var character: Character = null


func reset(face_seed: int = -1) -> void:
	deck = Deck.new()
	cache.clear()
	section_idx = 0
	phrase_in_section = 0
	section_score = 0
	phrase_index = 0
	joker_slots = [null, null, null, null]
	prev_kind = -99
	roll_faces(face_seed)


func roll_faces(seed_v: int = -1) -> void:
	var rng := RandomNumberGenerator.new()
	if seed_v >= 0:
		rng.seed = seed_v
	else:
		rng.randomize()
	run_faces = {}
	for w in GameConfig.WALL_SECTIONS:
		run_faces[w] = SectionMod.roll(w, rng)


func target() -> int:
	return GameConfig.SECTION_TARGETS[mini(section_idx, GameConfig.SECTION_TARGETS.size() - 1)]


## One phrase ended; step the counters and report where we stand.
func advance() -> Dictionary:
	phrase_in_section += 1
	var done := phrase_in_section >= GameConfig.PHRASES_PER_SECTION
	return {"section_done": done,
		"cleared": done and section_score >= target(),
		"is_wall": GameConfig.is_wall(section_idx),
		"finale": section_idx >= GameConfig.SECTIONS_PER_RUN - 1}


func next_section() -> void:
	section_idx = mini(section_idx + 1, GameConfig.SECTIONS_PER_RUN - 1)
	phrase_in_section = 0
	section_score = 0
```

- [ ] phrase.gd：成员 `deck/cache/section_idx/phrase_in_section/section_score/phrase_index/joker_slots/prev_kind/run_faces/character` 全部改为 `var run := Run.new()` 的字段访问（机械替换 `section_idx`→`run.section_idx` 等，~90 处）；`_advance/_reset_run/_roll_run_faces/_next_section` 改薄为调 Run；行为判定用 `advance()` 返回字典。**逐字段替换后全文 grep 校核无漏网旧名**。
- [ ] `--import` + 测试全绿（283 + Run 新增）+ shoot/end/banner 探针目检。

### Task R6: sim 三拆（bot.gd / report.gd）

**Files:** Create `tools/bot.gd`, `tools/report.gd`; Modify `tools/sim.gd`

- [ ] `tools/bot.gd`：`class_name Bot extends RefCounted`。搬函数（逐字）：`_rate/_amt/_glow_avg/_mirror_power/_card_ev/_target_value/_pick_target_ev/_draft/_weighted_pick/_play_phrase/_notify_discard/_play_random/_play_adaptive/_best_plan/_p_chase/_target_mult` + 成员 `SIM/KIND_PRIOR/TARGET_TF/COUNTERFACTUAL_TV/EV/CHASE/_tmult/_int_keys`。构造：

```gdscript
var _rng: RandomNumberGenerator
func _init(rng: RandomNumberGenerator) -> void:
	_rng = rng
	SIM = DB.sim()
	...   # 信念表初始化照搬
```

- [ ] `tools/report.gd`：`class_name Report extends RefCounted`。搬全部累计器成员 + `reset()`(原 `_reset_stats`)/`record_run`/`track_triggers`/`report`/`report_playbooks`（去前导下划线为公开方法，sim.gd 调用点同步）。
- [ ] `tools/sim.gd` 剩：`_initialize`（建 `_rng`、`Bot.new(_rng)`、`Report.new()`、cohort 循环）+ `_one_run`（编排，出牌/选购调 bot.*，统计喂 report.*）。**RNG 消耗顺序逐行核对不变**。
- [ ] `--import` + 测试全绿 + `--check-only` sim。
- [ ] **A/B 对拍**：重跑 sim，与 R0 的 `sim_presplit.txt` diff（滤 Godot 头/计时行），**必须零差异**。

### Task R7: 终检 + 文档 + 记忆

- [ ] 全量测试记新基线（283 + Run 条数）；`wc -l` 报告 phrase.gd/sim.gd 落点（目标 ~400 / ~250）。
- [ ] 七个探针全部重跑逐张目检。
- [ ] `design/14` status → shipped（记两个落点行数）；CLAUDE.md：基线数、架构铁律区补一行（view 组件化 + ui.json）、进度区一行。
- [ ] 记忆：项目状态补拆分基线；**新增 feedback 记忆**：用户命名偏好（文件名一词化无下划线）+ 配置优先方针（实体内容一律 JSON）。

---

## Self-Review 结论

- Spec 覆盖：五刀=R1-R5、sim 三拆=R6、ui.json=R1-R4 分节落、验证契约=R0/R6/R7。
- 类型一致：`Hud.refresh(vm)/coin_anchor`、`Shop.open/redeal/close` 与 R2/R3 接线同名；`Run` 字段与 phrase.gd 现成员同名（机械替换可行）。
- 无占位：纯搬函数以源文件为权威（函数名清单即内容指针），接缝代码全文在案。
