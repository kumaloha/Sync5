# 技术文档 · 项目结构

> **这一篇管:代码怎么分层,数据怎么配,规则为什么只准有一份。**
>
> **三条铁律**(展开在 [`../CLAUDE.md`](../../CLAUDE.md) 的「架构铁律」):
> ① `core/` = 纯逻辑,引擎无关、不含时钟、不 import view;
> ② 数值与内容全部在 `data/*.json`,`core/db.gd` 校验(**测试期门禁**,见下);
> ③ **规则只准有一份** —— 游戏与模型共用 `core/beat.gd`,探针共用 `tools/runloop.gd`。
>
> 本篇 2026-08-09 由 `tech.md` + `tech.md` + `tech.md` 合并而成 —— 见 [`README.md`](README.md) 的九篇结构。
> **验证方案在末尾**(每篇自带)。

---

## 数据配置(schema)

> ⚠⚠ **本章的示例块是 2026-08-05 配置化当天的快照,数值与部分键已过期(2026-08-21 评审标注)。
> schema 的权威 = `data/*.json` 本身 + `core/db.gd` 的 `validate_*`(测试期门禁,`t_db` 断言零违规)。**
> 已知过期处,读到时按下面这张表改:
> · `run.json` 示例写 12 段 / `blind_names` 小盲大盲 / 5 拍 / `gig_clocks 9.0` —— 现行 **4 段 × 6 拍 × 8s**,
>   `section_targets [420,1500,3100,5600]`,`blind_names` 只剩档位;
> · `economy.json` 示例写 `discard_cost: 1`、权重 70/25/5、含 `target_swap` —— 现行 **弃牌免费、35/30/25、无 target_swap、
>   多 `joker_upgrade`(5 级 / [4,7,11,16] / step 0.25)**;
> · `tutorial.json` 示例写 6 步 × 12s、键只有 `seconds/unlock/command/signal` —— 现行 **4 步 × 8s**,键是
>   `seconds/unlock/require/command/signal/focus`(**`require` 动作门与 `focus` 分区指向是现行核心键**,白名单在 `db.gd::validate_tutorial`);
> · 文件表只列 7 个文件 —— `data/` 现有 **15 个**:另有 `tickets`(券)/ `assets`(META 资产)/ `director`(B 轴剧本 + `context` 四开关)/
>   `ranking`(仪器输出,`rankgen.py` 重刷)/ `boons` / `ui`(含 blindcard·jokercard 交叉校验)/ `tape`(含 `upload` 回传节)/ `lingo`(中→英对照表)。
> ✅ 2026-08-21 晚:`run`/`economy`/`jokers`/`characters` 四块已改成「键名 + 指向校验函数」,`tutorial` 示例改成现行键;
> 其余示例块(DSL 片段 / faces / sim / ui)仍是当年快照,**别抄这里的数字**。


> 2026-08-05 配置化工程升级 (user-approved). Everything tunable moves out of
> code into `data/*.json`; behaviors become an effect DSL.
> Status: **shipped** — all six data files live, 283 tests green, sim A/B
> report byte-identical to the sealed round-3 baseline (pure move, proven).

### Why

- Balance edits should be data edits: 改一张牌 = 改一行 JSON,不碰代码。
- Kill the drift hazards: `tools/sim.gd::_target_mult` is a hand copy of the
  target tier tables in `core/joker.gd` — two homes for one number. After
  this, the bot derives it from the same `jokers.json` the game plays.
- The rosters were already half tables (`Joker.pool()`, `Character.roster()`
  one-liner constructors + a big `match id` dispatch); this finishes the move.

### File layout (`data/`)

| file | content | entries |
|---|---|---|
| `jokers.json` | 23 张小丑牌: identity + effect DSL | 23 |
| `characters.json` | 8 主角: identity + same DSL | 8 |
| `faces.json` | 6 Boss 脸: identity + numeric params + wall pools | 6 + 4 pools |
| `run.json` | 关卡结构: gigs × blinds, targets, clocks, timing windows | — |
| `economy.json` | coins, prices, wage, swap, reroll | — |
| `sim.json` | bot beliefs: cohorts, priors, EV params, chase shape | — |
| `tutorial.json` | 教学关脚本:每拍的拍长 / 首次解锁的部件 / 提示行 | 6 步 |

⚠ 上表的条目数是**当年的快照**,早就过期(小丑牌 61 张 / 脸 30 条)——
**现役数量看 [STATUS.md](../../STATUS.md),别信这一列。**

JSON has no comments — use `"_comment"` keys where a why is worth keeping;
the loader ignores them.

### tutorial.json — 教学关脚本(2026-08-14)

消费者只有 `core/tutorial.gd`(`Tutorial`),规格 = [`difficulty.md`](difficulty.md) §4。

```json
{ "components": ["hand", "discard", "cache", "multiselect", "shop"],
  "steps": [ {"seconds": …, "require": …, "unlock": …, "focus": …, "command": …, "signal": …} ] }   // 4 步 × 8.0s,键白名单在 db.gd::validate_tutorial
```

- `seconds` —— 这一拍多长。**拍长只收不放**,最后一拍必须等于正式局的 `phrase_duration`
  (过渡发生在教学关之内,不留 12 秒的错误肌肉记忆);
- `unlock` —— 这一拍**首次**亮出来的部件,**累积生效**(亮过就一直亮,后面不用重抄);
- `command` / `signal` —— 照 `ui.json` 的 `blindcard` 口径:中文一句 + 英文短标,
  英文守卡面那条 **≤7 词**。

`core/db.gd::validate_tutorial` 守四条结构契约:白名单外的部件 · 同一部件解锁两遍(死行)·
拍长 ≤0 · **有部件从没被解锁过**(教学关走完它仍是灰的 = 静默死锁)。
⚠ **只守结构,不守内容** —— 教哪几步、拍长多少是设计,用户直接改 JSON。

### Effect DSL (jokers + characters share it)

An entity carries `effects: [{when, do}, ...]`; effects are evaluated in
order at settle time against the settle ctx (`core/settle.gd`). `when` is a
dict of predicates, AND-combined; empty/absent = always. `do` is one channel
write.

#### Predicates (`when`)

| key | value | meaning |
|---|---|---|
| `kind` | `"PAIR"` | ctx.kind == Pattern.Kind[name] |
| `kind_in` | `["STRAIGHT_FLUSH", "ROYAL_FLUSH"]` | membership |
| `same_as_prev` | `true` | prev_kind == kind |
| `diff_from_prev` | `true` | prev_kind != -99 and != kind |
| `acted_late` | `true` | ctx.acted_late |
| `discards_eq` / `discards_gte` | int | this-phrase discards |
| `coins_gte` | int | held coins |
| `base_gte` | int | ctx.base_score |
| `last_phrase` | `true` | phrase_idx == phrases_per_section - 1 |
| `cache_mono_suit` | `true` | non-wild cache cards all one suit, cache non-empty |
| `top_rank_gte` | int | max rank over scoring_cards |
| `counter_gte` | `["n", 1]` | state counter ≥ x |

#### Channels & modifiers (`do`)

```json
{"<channel>": <amount>, "per": ..., "step": ..., "cap": ...}
```

| channel | semantics | popup |
|---|---|---|
| `mult` | ctx.mult ×= amount | `×3` |
| `mult_add` | ctx.mult ×= (1 + amount × count) | `×1.25` |
| `additive` | 改基牌, rides the multiplier | `+12` |
| `bonus` | 奖励分, lands after the multiplier | `+80` |
| `bonus_pct` | ctx.bonus_pct += | `+75%` |
| `coins` | ctx.coins_bonus += | `+2◆` |

- `amount` is a number, or `{"counter": "pct"}` to read a state counter.
- `per` multiplies amount by a count source: `"discard"` | `"counter:<name>"`
  | `"coins:<k>"` (floor(held/k)). `step` divides the count (bassline 每 12);
  `cap` clamps the computed contribution. Contribution 0 ⇒ no popup.
- Popup text is generated from channel + value (matching current formats);
  no per-card popup strings.

#### Counters (`counters`) — growth/decay state, fed by hook events

```json
"counters": {"n": {"on_discard": "sum"},
             "stacks": {"on_early_finish": 1},
             "pct": {"init": 0.60, "decay_per_phrase": 0.06, "floor": 0.0}}
```

`on_discard: "sum"` adds n per paid discard; `on_early_finish: k` adds k at
phrase end when early_finish; `decay_per_phrase` subtracts at phrase end,
clamped at `floor`. This replaces the hand-written `on_discard` /
`on_phrase_end` hooks — the generic hooks read the spec.

#### Acquire (`acquire`) — install-time rule changes

`{"deck_rule": "shortcut"}` sets `Deck.rules[x] = true`;
`{"wilds": 2}` calls `Deck.enable_wilds()`.

#### Escape-hatch opcodes (the irreducible two, as `do` keys)

- `mult_from_target_factor: 0.5` — mirror: ×(1 + (target_factor − 1) × 0.5)
- `additive_face_value: 15` — vip: per scoring face card add (15 − rank)

Adding a third opcode requires the same bar as a new hook (docs/design/jokers.md).

### jokers.json

**权威 = 文件本身 + `core/db.gd::validate_jokers`**。08-05 那份「full v1 content — numbers as shipped & sealed」
(90 行 18 张卡的旧数值)已于 2026-08-21 整块删除:它封印的是配置化当天的数,此后卡池扩到 63 张、倍率表三版演进,
**读者抄这里的数字比不抄更糟**。现行卡的键集:`acquire` · `cn` · `counters` · `curve` · `effects` · `fx` · `hold` · `id` · `kind` · `name` · `proof` · `rarity` · `shelf`;
kind 分布:support 55 · target 8。
数值演进与定价在 [`jokers.md`](jokers.md) / [`jokers_history.md`](jokers_history.md),升级放大规则在 CLAUDE.md「升级的三条原则」。

### characters.json

**权威 = 文件本身 + `core/db.gd::validate_characters`**(与 jokers 共用 `_validate_effects`)。
08-05 的「full v1 content」块已删(2026-08-21):主角被动走同一套 Effect DSL,键 `idx/cn/title/fx/effects`,
`core/character.gd::roster()` 只保留名字与立绘指向。

### faces.json — metadata + params in data, 生效逻辑留在结算链

The six twists are structural (unplugged inside the target step, norepeat /
rotation on the final score, static on the bonus channel, rush on the view
clock, cover on the phrase toll). DSL-izing six deeply-coupled faces is
over-design; instead **all their numbers** load from `params` and the
apply sites (`Settle.run`, `view/phrase.gd`) read accessors on `SectionMod`.

```json
{"faces": [
 {"id": "unplugged", "name": "Unplugged", "cn": "拔电",
  "fx": "Your Target works at half power", "params": {"target_power": 0.5}},
 {"id": "static", "name": "Static", "cn": "杂讯",
  "fx": "Score bonuses are disabled", "params": {"bonus_disabled": true}},
 {"id": "norepeat", "name": "No Repeats", "cn": "禁回",
  "fx": "Repeating last hand scores half", "params": {"repeat_factor": 0.5}},
 {"id": "rotation", "name": "Forced Rotation", "cn": "强制换血",
  "fx": "Zero discards: score halved", "params": {"zero_discard_factor": 0.5}},
 {"id": "rush", "name": "Rush Hour", "cn": "赶场",
  "fx": "Phrases are 2 seconds shorter", "params": {"time_penalty": 2.0}},
 {"id": "cover", "name": "Cover Charge", "cn": "入场费",
  "fx": "Pay 1 coin each phrase", "params": {"phrase_toll": 1}}
],
"pools": {"2": ["norepeat", "cover"], "5": ["norepeat", "cover"],
          "8": ["unplugged", "static", "rotation", "norepeat"],
          "11": ["unplugged", "rush"]}}
```

### run.json

**权威 = 文件本身 + `core/db.gd::validate_run`**(2026-08-21:原示例块写 12 段/小盲大盲/5 拍,整块删除)。
现行顶层键:`phrases_per_section` · `phrases_per_shop` · `sections_per_gig` · `gigs_per_run` · `blind_names` · `gig_names` · `section_targets` · `gig_clocks` · `warning_offset` · `lock_offset` · `late_act_window` · `final_act_window` · `early_finish_time` · `early_discard_window` · `early_lock_min` · `hand_size` · `cache_cap` · `beat_budget` · `death_spec`。
结构常量(4 段 × 6 拍 × 8s,`phrases_per_shop: 3` ⇒ 7 次商店)的推导在 [`levels.md`](levels.md);
⚠ 所有按段索引的表长度必须 = 段数(`t_run` 锁着,表短会被静默截断成放水盘)。

### economy.json

**权威 = 文件本身 + `core/db.gd::validate_economy`**(2026-08-21:原 08-05 示例块写 `discard_cost: 1`(现为 0,弃牌免费)并含已删的 `target_swap`,整块删除)。
现行顶层键:`starting_coins` · `discard_cost` · `section_clear_reward` · `draft_rarity_weights` · `joker_prices` · `joker_price_overrides` · `reroll` · `joker_upgrade`。
规则(去掉数字仍成立的部分):弃牌免费 · 标价不保底 · 刷新递增 · `joker_upgrade.costs` 长度 = `max_level − 1` ·
`prices`/`weights` 键集必须相等(校验锁着)。数字与推导见 [`levels.md`](levels.md) §经济。

### sim.json — 机器人信念表 (user call: bot tunables are config too)

```json
{"runs": 1000,
 "cohorts": [
  {"name": "baseline(no jokers, adaptive)", "bot": "adaptive", "target": "", "no_jokers": true},
  {"name": "adaptive:twin", "bot": "adaptive", "target": "twin"},
  {"name": "adaptive:stair", "bot": "adaptive", "target": "stair"},
  {"name": "adaptive:mono", "bot": "adaptive", "target": "mono"},
  {"name": "adaptive:triplet", "bot": "adaptive", "target": "triplet"},
  {"name": "adaptive:lonewolf", "bot": "adaptive", "target": "lonewolf"},
  {"name": "adaptive:wolfpivot", "bot": "adaptive", "target": "lonewolf", "pivot": true},
  {"name": "adaptive:anytarget", "bot": "adaptive", "target": "", "pivot": true},
  {"name": "random", "bot": "random", "target": ""}],
 "kind_prior": {"0": 0.35, "1": 0.20, "2": 0.14, "3": 0.04, "4": 0.05,
                "5": 0.15, "6": 0.06, "7": 0.01},
 "target_tf": {"twin": 3.5, "stair": 8.0, "mono": 6.0, "triplet": 5.0, "lonewolf": 4.0},
 "counterfactual_tv": {"twin": 2.2, "stair": 0.9, "mono": 0.95, "triplet": 1.1, "lonewolf": 1.7},
 "lonewolf_value": {"high_prior": 0.35, "mult": 3.0, "vow_discount": 0.5},
 "ev": {"blend_w": 6.0, "mult_prior": 1.6, "score_prior": 120.0, "coin_score_ratio": 0.10,
        "growth_horizon": 0.5, "glowstick_horizon": 10.0,
        "cards": {
         "encore":      {"rate": "rep",   "prior": 0.30},
         "finale":      {"rate": "late",  "prior": 0.25},
         "turnover":    {"rate": "disc",  "prior": 1.00},
         "tipjar":      {"rate": "zerod", "prior": 0.30},
         "chord":       {"rate": "chord", "prior": 0.08},
         "neonsign":    {},
         "vinyl":       {"rate": "disc",  "prior": 0.20},
         "chorus":      {"fixed_rate": 0.20},
         "interest":    {"coin_mult": 1.2},
         "momentum":    {"rate": "early", "prior": 0.25},
         "vip":         {"rate": "faces", "prior": 0.70, "boost": 3.0},
         "glowstick":   {},
         "bassline":    {"rate": "disc",  "prior": 0.20},
         "mirror":      {"rate": "tgt",   "prior": 0.30},
         "shortcut":    {"on_target": ["stair", 0.12, 7.0], "off_target": 0.02},
         "fourfingers": {"on_target": ["stair", 0.30, 7.0], "off_target": 0.03},
         "twotone":     {"on_target": ["mono", 0.35, 5.0],  "off_target": 0.03},
         "wildcard":    {"base": 0.10, "target_bonus": [["stair", "triplet"], 0.10]}}},
 "chase": {"gain": 2.2, "cap": 0.92, "floor": 0.02}}
```

**Derived, not stored**: `_target_mult` (bot's model of target payouts) is
computed from `jokers.json` effects (kind→mult tiers) — the drift hazard
this upgrade exists to kill. Card amounts already in `jokers.json`
(80/70/20/120/…) are likewise read from the DB inside `_card_ev`, not
duplicated in `sim.json`. `sim.json` holds only what the game data cannot
know: 先验概率、混合权重、horizon、target 档位估值。Bot ALGORITHM (EV 公式、
plan search) stays code — it is the bot's brain, the numbers are its beliefs.

### Loader: `core/db.gd`

- `class_name DB`, static. Loads all six files once (lazy, first access);
  `res://data/…` works headless and in-editor.
- **Hard validation, fail loudly** (push_error + quit in tests): duplicate
  ids; unknown predicate / channel / counter / acquire keys (typo net);
  `kind` names must resolve via `Pattern.Kind`; pool face ids must exist;
  size cross-checks (targets vs structure, characters dense 0..7);
  `joker_price_overrides` and `sim.ev.cards` ids must exist in jokers.
  `_comment` keys are skipped everywhere.
- API stability: `Joker.pool()/by_id()`, `Character.roster()`,
  `SectionMod.roster()/by_id()/pool_for()/roll()/time_penalty()/phrase_toll()`,
  `GameConfig.*` (incl. `phrase_duration()` etc.), `Economy.*` keep their
  signatures — **callers in view/tools/tests stay untouched**. `Joker` /
  `Character` become data shells + one generic interpreter each
  (`apply(ctx)` walks effects; generic hooks feed counters from spec).
  Note: `const X := GameConfig.Y` initializers in callers must become
  plain reads (consts can't init from loaded vars).

### Verification (the contract of "纯搬家")

1. Existing **266 tests stay green** — they assert per-card behaviors, so
   they are the DSL's regression net. New tests: DB loads + validation
   catches a planted bad file (unknown key, dup id, bad kind name).
2. **Sim A/B byte-diff**: full `sim.gd` run before vs after must produce an
   identical report (the sim is fully seeded — proven by two identical runs
   during the gig re-calibration). Any diff = behavior changed = bug.
3. Screenshot probes unchanged (`card_sheet` / `crew_sheet` / `draft_sheet`
   render from the same fields).

### Non-goals

- No face-effect DSL (params only; apply sites stay in Settle/Pattern/view).
- No bot-algorithm DSL (only beliefs/tunables move).
- No new cards/characters in this pass — content identical, homes change.
- View layer untouched.

---

## view 组件化拆分

> 2026-08-05 大文件拆分 (user-approved). view/phrase.gd 五刀,tools/sim.gd
> 三拆,UI 布局与文案进 data/ui.json。
> Status: **shipped** — phrase.gd 1342→726(编排+结算演出),widgets 180/
> hud 117/shop 266/hand 284/run 66;sim.gd 882→146 + bot 573 + report 200。
> 301 tests green(Run 状态机 +17 条直测);七探针逐张目检一致;
> sim 报告与拆前基线零内容差异(纯搬家已证明)。

### User calls (constraints)

- **命名一词化,无下划线**:新文件 `widgets.gd / hud.gd / shop.gd / hand.gd /
  run.gd / bot.gd / report.gd`。存量文件名这次不动。
- **UI 实体内容配置化**:坐标、尺寸、界面文案全部进 `data/ui.json`,走 DB
  加载+硬校验;组件构造时读自己那节。标签/按钮创建尽量数据驱动(循环吃表)。
- 行为零变更:283 测试全绿、六个截图探针逐张目检一致、sim 报告与拆前
  逐字节一致(除计时行)。

### data/ui.json

```json
{"stage": {"margin": 26, "card_w": 114, "card_h": 170, "gap": 16,
           "resolve_hold": 1.6, "pill_w": 200, "hand_top": 672,
           "hand_card_y": 724, "cache_y": 1024,
           "lift_base": 16, "lift_scoring": 8, "lift_selected": -2},
 "hud":   {"pos": [26, 26], "size": [668, 150], "...每个标签/进度点的坐标..."},
 "shop":  {"title": "选择小丑牌", "target_line": "TARGET · 定义什么是好答案 · 免费",
           "support_line": "SUPPORT · 定义怎么到达答案 · ◆ %d",
           "reroll_text": "刷新 · %d ◆", "skip_text": "继续 ▸",
           "free_text": "免费", "insufficient": "◆ 不足",
           "replace_prompt": "点一个 SUPPORT 槽替换 · 旧卡折半回收 · 点 TARGET 取消",
           "...布局参数..."},
 "hand":  {"hand_tab": "手 牌 区", "cache_tab": "缓 存 区",
           "sort_label": "理牌", "discard_label": "弃牌", "...布局参数..."},
 "banner": {"w": 470, "h": 58, "show_y": 196, "done_text": "目标达成 ✓  ",
            "wage_text": "   工资 +%d ◆"}}
```

具体键以实现为准(实现=权威),DB.validate_ui 检查节存在 + 未知节报错。
数值经 `int()/float()` 归一(JSON 数字全是 float)。

### phrase.gd 五刀

phrase.gd 瘦身后只剩:St 状态机 + `_process` 时钟、`_start_phrase/_settle/
_advance/_next_section` 编排、run_end/banner/picker 接线、settle 演出
(popup 定位/震屏/JUICE 小工具)。目标 ~400 行。

| 新文件 | class | 搬走的内容 | 接口 |
|---|---|---|---|
| `view/widgets.gd` | `Widgets`(容器) + 内部类 `GradBar/SegPill/DJKey` | 尾部三个内部类原样搬 | 引用改 `Widgets.GradBar` 等,行为零变 |
| `view/hud.gd` | `Hud extends Control` | `_build_info_bar` 全部 + `_refresh` 的信息区片段(场次标签/12点/金币/分数/目标/PHRASE/预告行/进度条) | `refresh(vm: Dictionary)`(键:section_idx/coins/score/target/phrase_no/mod_text/fraction);`set_mod_text(t)`;`coin_anchor() -> Vector2` 供飘字 |
| `view/shop.gd` | `Shop extends Control` | `_build_draft/_draft_button/_open_draft/_deal_draft/_weighted_pick/_candidate_price/_draft_affordable/_on_draft_pick(判定部分)/_on_draft_reroll/_on_draft_skip` + replace_prompt | 编排器调 `open(slots, coins)`;信号 `bought(joker, price)` / `replace_requested(joker)` / `skipped()`;**扣币、装槽、on_acquire、_start_phrase 全留编排器**。reroll/跳过内部处理但金币变动走 `coins_changed(delta)` 信号(或回调查询——实现选一,保持行为同) |
| `view/hand.gd` | `Hand extends Control` | 手牌 5 格+缓存 3 格+理牌/弃牌键+两个区标签的搭建;选中态 sel_hand/sel_cache;tap/drag/drop 处理;`_refresh` 的手牌/缓存/按键片段;`_flip_reveal/_ghost_fly` | 信号 `sort_pressed` / `discard_pressed(sel_h, sel_c)` / `swap_requested(hand_i, cache_i)` / `acted`(喂 _action_feedback);编排器校验并改 Phrase 后调 `refresh(vm)`(键:hand/cache/scoring_set/decide/can_discard/fee) |
| `core/run.gd` | `Run extends RefCounted` | 推进状态:deck/cache/section_idx/phrase_in_section/section_score/phrase_index/joker_slots/prev_kind/run_faces/character + `reset()/roll_faces()/advance() -> {section_done, cleared, is_wall, finale}/next_section()/install_joker(slot,j)` | **引擎无关、可直测**;phrase.gd 持有一个 Run,读判定、指挥组件。新增 runner.gd 直测(推进/过墙/终幕/重置) |

### sim.gd 三拆

- `tools/bot.gd`(`Bot extends RefCounted`):`_rate/_amt/_glow_avg/_mirror_power/
  _card_ev/_target_value/_pick_target_ev/_draft/_weighted_pick/_play_phrase/
  _play_random/_play_adaptive/_best_plan/_p_chase/_target_mult` + 信念表成员
  (SIM/KIND_PRIOR/TARGET_TF/COUNTERFACTUAL_TV/EV/CHASE/_tmult)。
  构造时注入 **同一个 RNG 实例**;方法签名与调用顺序不变。
- `tools/report.gd`(`Report extends RefCounted`):全部累计器(died_at/wall_mod/
  phrase_score_*/coins_at_*/kind_count/discards_*/presence/trigger/run_records)
  + `_reset_stats/_record_run/_track_triggers/_report/_report_playbooks`。
- `tools/sim.gd` 只剩:SceneTree 入口、cohort 循环、`_one_run` 编排(建
  deck/phrase、调 bot 出牌选购、喂 report)。

**决定性契约**:RNG 同实例、消耗顺序不变 ⇒ 拆分后 sim 报告与拆前逐字节
一致(除计时行)。拆前先存一份基线报告,拆完对拍。

### Verification

1. 每刀之后:`--import`(新 class_name)+ 283 测试全绿。
2. R5 新增 Run 状态机直测(现在测不到的裸区)。
3. 视觉:shoot / banner / end / draft / card / crew / key 探针全部重跑逐张
   目检;shoot.gd 直捅的 `_scene.run_faces/section_idx` 等内部引用同步改。
4. sim A/B 逐字节(除计时行)。

### 后续入册 (2026-08-05)

- `view/home.gd`(`HomeScreen`)= 首页,规格 `docs/mockups/home.html`。整屏自绘,
  只发两个意图信号(`start_pressed` / `character_pressed`),不碰 run 状态。
- `Widgets.StageCard` = 首页大玻璃卡与局内盲注板**共用的外观定义**(玻璃板/
  角标/点阵/渐变分隔/均衡器带/档位配色/难度星),`Widgets.BlindBoard` 是它的
  局内尺寸。用户拍板「关卡就是盲注」,所以两者必须是同一个对象。
- meta 数值(等级/经验/双货币)是 `HomeScreen.PROFILE` 一处占位,docs/design/ui_meta.md 未做。

### Non-goals

- 不改任何行为、数值、布局、文案内容(只换存放位置)。
- 存量文件不改名;run_end/paper_card 等不重构。
- view 其余文件(stage_bg/joker_slot/…)不动。

---

## 一套规则:游戏与模型不分家

> 起因(2026-08-07 用户):「有没有办法实际游戏和数学建模用一套规则。」
> 回答:能,而且这正是**五次「规则在游戏里、不在模型里」**的共同根。

---

### 0. 一页纸

**已经共用的是「计分」,没共用的是「编排」。**
`Pattern` + `Settle` 只有一份(`agree.gd` 退役时刻意消灭了第二份),
但**「一拍怎么走完」被写了 12 遍** —— 每加一条规则就要在 12 个地方各写一次,
漏一个就静默分叉,而分叉不报错、只让所有下游数值悄悄偏掉。

**做法**:把编排上提进 `core/`,做成**分步状态机** `core/beat.gd`。
游戏从时钟回调里按顺序调,探针连着调。**关键不是「提供共用函数」,
而是「漏调会崩」** —— 光提供函数,忘了用仍然是静默分叉(`sim.gd` 那次就是
`Run.target()` 摆在那儿而它自己读了表)。

**验收**:不是读代码,是**跑出一模一样的数** —— `gate.sh` 全绿 + `pair.gd` 逐手相同 +
sim 报告与重构前**逐字节一致**。这个项目已经用这条判据验过两次纯搬家(配置化、大文件拆分)。

---

### 1. 现状:哪些是一份,哪些是十二份

| 东西 | 实现份数 | 位置 |
|---|---|---|
| 计分(`Pattern` + `Settle`) | **1** | `core/` ← 有意做到的 |
| 段目标 × 脸的加码 | **1**(2026-08-07 刚合的) | `Run.section_target_for` |
| **一拍的编排**(调 `Settle.run` 的地方) | **12 个文件、16 处** | view ×1 + tools ×15 |
| 入场费扣钱 | 5 | `view/phrase.gd:409` · `sim.gd:121` · `curve.gd:94` · `gate.gd` ×2 |
| 商店节奏 `% PHRASES_PER_SHOP` | 6 | view ×2 · sim · curve · coin · gate ×2 |
| 一拍时长 `phrase_duration − time_penalty` | 3 | `view/phrase.gd:418` · `bot.gd:417` · `bot.gd:526` |

**注意「16 处」里有一半是合理的**:`pair.gd` / `warm.gd` / `lam.gd` 是**单拍探针**,
它们只想要「这一手值多少分」,不需要整局编排。真正重复的是**整局编排**那 6 份:
`view/phrase.gd` · `sim.gd` · `curve.gd` · `coin.gd` · `blind.gd` · `gate.gd`。

---

### 2. 五次事故按成因分类(这决定了方案能治好几次)

| 次 | 规则 | 成因 | 统一编排能不能治 |
|---|---|---|---|
| 1 | 赶场 −2s | 时长表达式两份,模型那份当时不含时间维度 | ✅ 能 |
| 2 | cover 入场费 | 扣钱五份,我在求解器里找不到通路就下了结论 | ✅ 能 |
| 3 | 盖牌族 | **模型比游戏弱**(完全信息求解器) | ❌ 不能 |
| 4 | 「最多弃 2 张」 | 语义错位(注释"次数"、代码"张数") | ⚠ 部分 |
| 5 | raisedbar | 段目标两份,`sim.gd` 漏乘 `target_mult` | ✅ 能 |

**3/5 直接治好,1/5 部分**(共用常数至少让语义只需定义一次),
**1/5 治不了** —— 那类是能力缺口,只有 `gate.gd` 的 belief/ORACLE 对照臂抓得到。
**所以门和统一编排是互补的,不是二选一:门是探测器,统一是修复。**

---

### 3. 障碍(必须先说清楚,否则方案是空中楼阁)

**游戏是实时异步的,探针是同步的。** 游戏的一拍横跨 8 秒钟、若干 tween 和玩家输入,
中间要 `await`;探针的一拍是一个函数调用。**所以不可能共用一个 `for` 循环。**

但可以共用**转移**。`core/run.gd::advance()` 今天已经是这个形状(游戏调它拿裁决),
只是它只管计数器,不管扣钱、不管结算、不管商店。**方案就是把它长大。**

---

### 4. 方案:`core/beat.gd` —— 一拍的分步状态机

```gdscript
class_name Beat
### 引擎无关, 不含时钟, 不 import view(core/ 铁律)。
### 一拍 = 三次转移, 游戏和模型都必须走完这三步, 顺序固定。

static func begin(run: Run, opt: Opts) -> Phrase
    # 解析本段的脸(必须在 start() 之前 —— 缓存容量在那里生效)
    # → Phrase.new → p.mod = face → start() → 扣入场费 → 推进 phrase_index
    # 返回一个「可以开始做决定」的 Phrase

static func settle(run: Run, p: Phrase, flags: Dictionary) -> Dictionary
    # lock_and_settle → 组装 Settle 的 ctx(prev_kind / first_kind / acted_late /
    # discards / coins / phrase_idx / cache_cards / mod / character)
    # → Settle.run → 金币入账 → joker.on_phrase_end → p.cleanup()(缓存驱逐在这)
    # 返回 outcome

static func after(run: Run, opt: Opts) -> Verdict
    # 推进 phrase_in_section → 商店节奏(shop_break)→ 段末: 段目标(含 target_mult)
    # → 判生死 → 通关工资。返回 {shop, section_done, cleared, dead}
```

#### 4.1 漏步必须崩,否则等于没做

`run.stage` 记当前走到哪一步。`settle` 前没 `begin`、`after` 前没 `settle`,
直接 `push_error` + 测试断言。**这一条是方案的核心** ——
「提供一个共用函数」拦不住任何人自己再写一遍,而 `sim.gd` 漏乘 `target_mult` 那次,
`Run.target()` 就摆在旁边。

#### 4.2 探针的变体收进一个 `Opts`

今天六份编排各自发明开关,合并后是**一个**结构:

| 开关 | 谁在用 | 今天的形态 |
|---|---|---|
| `shop: bool` | coin(无商店对照臂) | 各写各的 if |
| `judge: bool` | curve/gate(不死局) | 有的有有的没有 |
| `target_table` | sim 用影子表 / 游戏用真人表 | 两处硬编码 |
| `target_scale: float` | gate 的单调性臂 | gate 独有 |
| `coin_delta: int` | coin 的 ±1/拍 | coin 独有 |
| `faces: Dictionary` | 全部(强制某张脸 / 掷点) | 各写各的 |

**副产品:这张表本身就是「模型能表达哪些反事实」的清单**,现在它散在六个文件里,
没人能一眼看全。

#### 4.3 view 侧怎么接

`view/phrase.gd` 的 `_start_phrase()` 现在是**规则 + 表现混在一起**
(第 401-412、418 行是规则;orbit / deal_flip / Tape / _refresh 是表现)。
迁移后:

```gdscript
func _start_phrase() -> void:
    phrase = Beat.begin(run, _opts())      # ← 规则全在这一行里
    cur_duration = run.phrase_duration()   # ← 时长也归 core 算
    ...剩下全是表现:orbit / hand.deal_flip / Tape / _refresh
```

**`Tape` 打点留在编排器**(铁律:只在 `view/phrase.gd` 打),但它读的是 `Beat` 的返回值。

---

### 5. 迁移顺序(每步都要能单独验)

| # | 事项 | 验收 |
|---|---|---|
| ✅ 1 | `Beat.settle` + `Beat.phrase_end`,`sim.gd` 换成持有真的 `Run` | **已做**,见下 |
| ✅ 2 | 六份编排逐个换成调 `Beat`(view 最后) | **已做**,每份都做了读数对账,见下 |
| ✅ 3 | stage 断言(漏步即崩)+ 注入 A/B | **已做**,跳步当场 push_error |
| ✅ 4 | `Beat.begin` —— 脸解析 / 发牌 / 扣入场费 / 计数器,时长归 `Run.phrase_duration_for` | **已做**,见下 |
| ✅ 5 | `Beat.after` —— 商店节奏 + 判生死 + 通关工资 | **已做,但落在 `tools/runloop.gd` 而不是 `Beat`**,见下 |
| ✅ 6 | 六份的 `Opts`(§4.2)合并,消掉剩下的循环骨架重复 | **已做**,见下 |

#### 第 5-6 步的实测(2026-08-08)

⚠ **先纠正一个数**:本文当时写的是「六份编排」,那只数了**一拍**这一层。
**一局**那一层实测是 **14 份** —— sim · curve · coin · blind · addit · price 各 1、
**gate 3**、**formal 6**。formal 那 6 份是 2026-08-08 当天加的,而那个文件顶部
就写着「别在这里重写规则」。**光有共用函数拦不住再抄一遍,这是第二次证明。**

**落点不是 `Beat` 而是新的 `tools/runloop.gd`(`class_name RunLoop`)**,理由是分层:

| | 共用什么 | 谁用 |
|---|---|---|
| `core/beat.gd` | **一拍的转移** | 游戏(异步,从时钟回调里调)+ 全部探针 |
| `tools/runloop.gd` | **一局的循环** | **只有探针** —— 游戏是实时异步的,共用不了 `for`(§6) |

把判生死放进 `Beat.after` 会让 `core/` 依赖一个游戏侧根本不会那样调用的形状;
放进 `RunLoop` 则让**判生死只有一份**(走 `Run.section_target_for`),而那正是
`raisedbar` 事故的形状。

**战果**:14 份 → **1 份**,11 个调用点。差异全部收敛到 5 个键:
**谁在打 / 有没有商店 / 判不判生死 / 脸从哪来 / 录什么**。

**⚠ 迁移中抓到四个会静默出错的地方**(每个都不报错,只是数悄悄偏):

1. **RNG 消耗顺序** —— 多数探针是「先抽主角、后掷脸」,而 `RunLoop` 内部也抽主角。
   不把主角提前抽好传进 `Opts.character`,顺序就反了,**全部读数整体漂移**。
2. **钩子时机** —— 方差分解那类测量必须挂在**玩家动手之前**(`on_begin`);
   挂到 `on_beat` 上量的是打完之后的局面,**结果依然是个合理的数**。
3. **`prev_kind` 必须在 `Beat.settle` 之前抓** —— 它在里面就被更新了。
   `sim.gd` 统计「重复成手」靠的是这个差,读晚一步统计会静默变成恒真。
4. **各份的 `st` 记账口径本来就不同** —— `coin.gd` 只记 `n`(score/mult/kinds 恒为 0),
   `addit`/`price`/`gate` 只记 `n`+`score`+`disc`。这些是 `bot._draft` 给卡定价的输入,
   **"顺手补全"就等于改了买牌行为**。所以 `Opts` 加了 `tally_score` / `tally_mult_kinds`
   两个开关,让每份按自己原来的口径接线。**默认值维持原行为。**

⚠ 还有一个 GDScript 的坑:**lambda 按值捕获局部变量** —— int 计数器在闭包里 `+=` 不传出来,
而 Dictionary/Array 是引用类型所以正常。**一半状态正常、一半静默丢失**,输出还是合理的数字。

#### 第 4 步的实测(2026-08-07,同日)

`Beat.begin(run)` 一句话吃掉「解析这一段的脸 → 发牌(缓存容量在 `start()` 生效)→ 收入场费 →
推进计数器」;一拍时长归 `Run.phrase_duration_for(section, mod)`。

**这一步的实质战果 —— 重复被清零:**

| | 之前 | 现在 |
|---|---|---|
| 入场费扣钱 | **5 份** | **1 份**(`Beat.begin`) |
| 一拍时长 `phrase_duration − time_penalty` | **3 份**(view + `bot.gd` ×2) | **1 份**(`Run.phrase_duration_for`) |

正好堵上五次事故里的**第 1 次(赶场:时长两份)与第 2 次(cover:扣钱五份)**的形状。
`grep` 全仓复核:除 `core/beat.gd` / `core/run.gd` 外再无第二处。

**验收(全部逐字节一致,连耗时行都过滤掉了)**:
coin 30 行 · curve 72 行 · sim 137 行 · blind 20 行 · gate 48 行;
view 走 `flow_probe` 0 bugs + `tapeprobe` 0 bugs;测试 559 全绿。

#### 第 2-3 步的实测(2026-08-07,同日)

六份编排**全部**换成调 `Beat`,逐份对账(判据:除耗时那一行外逐字节一致):

| 探针 | 结果 |
|---|---|
| `sim.gd` | ✅ 135 行只差耗时(113.4s → 107.0s) |
| `gate.gd`(三个循环) | ✅ 46 行只差耗时(353.0s → 390.7s,被并行任务抢了 CPU) |
| `coin.gd` | ✅ 30 行逐字节一致 |
| `curve.gd` | ✅ 72 行逐字节一致 |
| `blind.gd` | ✅ 20 行逐字节一致 |
| `view/phrase.gd` | ✅ `flow_probe` 0 bugs(2501 帧 / 27 结算屏 / 112 次段中商店)+ `tapeprobe` 0 bugs |

对照臂的做法:把原版拷成 `tools/_base_X.gd` 再改原版,两个版本**同一进程外**各跑一次对拍 ——
这样不必在动手之前先跑一遍,也不依赖 VCS(这个仓库不是 git 库)。

**⚠ 搬 view 时抓到一个会静默算错的地方**:`Tape` 的 `settle.total` 原本写
`run.section_score + gained_score`(那时入账发生在打点**之后**),而 `Beat.settle` 已经入过账,
照抄旧写法会把这一拍**算两遍**,而日志不报错。已改成 `run.section_score`。
**这正是「搬家最容易丢的是顺序」的实例**,也说明对账要连打点一起对(`tapeprobe` 抓的就是它)。

#### 第 1 步的实测(2026-08-07)

- `core/beat.gd` = `settle` + `phrase_end`,`core/run.gd` 加了 `coins` 与 `Stage` 状态机。
- `tools/sim.gd` 从「自己写一遍」改成持有一个真的 `Run`、调 `Beat`。
- **验收:sim 报告 135 行里只有耗时那一行不同(113.4s → 107.0s),其余 134 行逐字节一致。**
- 测试 **559 全绿**(新增 9 条锁 `Beat` 的顺序契约,其中最重要的一条是
  **`first_kind` 只能被本段第一拍写**——先更新就把 setlist 的锁套在了它自己头上)。
- **漏步守卫已 A/B**:正常顺序静默,跳过 `settle` 直接 `phrase_end` 当场
  `ERROR: [Beat] phrase_end() 在 stage=0 时被调用, 期望 1 —— 有一步被跳过了`。

⚠ **一次只换一份,每换一份都跑一次读数对比。** 这个项目的两次成功纯搬家
(配置化、大文件拆分)都是这么做的,而且都做到了**零差异**。
⚠ **view 放最后**:它是唯一有时钟和动画的,风险最高,而且前四步做完之后
它的迁移已经有充分参照。

---

### 6. 共用不了的三样(别指望,也别假装)

1. **求解器的能力**(事故 3)—— 盖牌不是代码分叉,是模型比游戏弱。共用再多代码
   也不会让完全信息求解器看见盖着的牌。**这类只能靠 `gate.gd` 的 belief/ORACLE 对照臂。**
2. **真人 8 秒 vs 机器人 `beat_budget`** —— 这是**近似**,不是重复。
   `beat_budget{discards:2, swaps:5}` 是拿动作次数近似时间压力,永远会有缝。
   **要等真人 Tape 数据才能校准**,而且校准的是参数,不是代码。
3. **视图的时钟与动画顺序**(掐 tween、翻牌 reveal 之类)—— 本来就该只在 view。

---

### 7. 风险与退路

**主风险:`Opts` 变成配置怪物。** 六份编排合并时,每个探针都想再加一个开关,
最后变成一个谁都读不懂的分支树。
**闸门**:`Opts` 的字段数超过 §4.2 那张表就要停下来问「这个变体是不是该用别的方式表达」。

**次风险:view 迁移把实时行为改坏。** 那一层有 `state != St.END` 早退、
翻牌 tween 掐断这类**用事故换来的**细节,搬家时最容易丢。
**闸门**:`flow_probe`(连点两次)+ `tapeprobe` 必须 0 违规,而且要先注入假 bug 确认它们还在报警。

**退路**:第 1-3 步各自独立有价值。即使 view 那步最终不做,
**六份探针编排合成一份**已经消掉了模型内部的分叉,只剩「游戏 vs 模型」一条缝,
而那条缝现在有 `gate.sh` 守着。

---

### 8. 和其他待办的关系

- **`docs/design/gates.md` 第 2 项(可加性检验)不依赖本文档**,可以并行。
- **定价那一步依赖本文档** —— 目标分是拿模型算的,模型和游戏不是一套规则的话,
  算出来的目标分就是给另一个游戏定的。
- 用户已拍板的「**重构分模块**」:本文档是它的第一块,也是我核出来「漏了三样」里
  最重要的那样(计分核心 + 它的编排)。

---

## 验证方案

| 验什么 | 怎么验 | 失败长什么样 |
|---|---|---|
| **schema 正确** | `core/db.gd` 校验 | 未知键/坏引用**在测试里直接红**,不静默。⚠ **测试期门禁,运行时不拒绝启动**(代价不对称:漏网坏数据只影响一次构建,开不了机影响每个玩家)—— 理由与改法见 `core/db.gd` 文件头 |
| **规则只有一份** | `tools/pair.gd` 三关递进 | 求解器与游戏分差 ≠ 0 |
| **全量回归** | `tests/runner.gd`(589 条) | — |
| **加了内容** | `./tools/gate.sh`(~8 分钟) | 覆盖自证 / 单调性 / 哨兵 / 流程 / 打点 / 重放 / 尺子 |
| **只验一张新脸** | `./tools/gate.sh <face_id>`(十几秒) | **这才是常用路径** |

### 三条跑探针的纪律(全部踩过)

1. **跑完必须确认退出码** —— GDScript 运行时错误**不会终止** `SceneTree` 脚本,进程会空转
2. **读退出码别隔着管道**
3. **计时必须在无竞争时做**

### ⚠ GDScript 的一个静默坑

**lambda 按值捕获局部变量** —— int 计数器在闭包里 `+=` 不传出来,
而 Dictionary/Array 是引用类型所以正常。
**一半状态正常、一半静默丢失,输出仍是合理的数字。**

### ⚠ 新增 `class_name` 后必须先跑

```bash
godot --headless --path . --import
```
