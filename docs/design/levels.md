# 关卡设计

> **这一篇管:一局是什么形状 —— 几段、几拍、几次商店、钱从哪来花到哪去。**
>
> 一局 = 巡演 = **4 场演出 × 1 盲注 = 4 Section,每盲注 6 个 Phrase**,单拍 8s,
> 每 3 拍一次商店(8 次)。**4 段全是 BOSS 墙**,不可跳过。
>
> **经济/商店归这一篇**(用户 2026-08-09 拍板)—— 商店节奏就是关卡节奏的一部分:
> 7 商店 : 4 槽 ≈ 1.75:1,后半程必须「买新替旧」,那才是构筑弧的发动机。
>
> 本篇 2026-08-09 由 `levels.md` + `levels.md` + `levels.md` + `levels.md` 合并而成 —— 见 [`README.md`](README.md) 的九篇结构。
> **验证方案在末尾**(每篇自带)。

---

## 结构:段与拍

> Rewritten 2026-08-05: **gig layer added** (关卡重构, user-approved).
> **Re-cut 2026-08-06 (pacing pass, docs/design/levels.md)**: shops are now **decoupled
> from blinds**. Run = 4 gigs × **1 blind** = **4 sections × 6 phrases**, with a
> shop every **3** phrases → still 7 shops (the finale section has no end-of-section shop), ≈ 4.9 min. Every section is a wall.
> Status: **shipped** — tests 314 green, `flow_probe` 0 violations.
> **Numbers are NOT re-sealed**: the bot calibration below predates the re-cut
> and the user has parked bot tuning ("算法的验证下一步等我来调").

### Structure

- **Phrase** = one 8s play window (**6 per section**).
- **Section = one blind (盲注)**: 6 phrases, one cumulative score target
  (`SECTION_TARGETS`). **Every section is a BOSS wall** — 小盲/大盲 are retired
  (用户 2026-08-06:「4 个阶段性的任务和规则要做, 也不做跳过, 就是必须做」).
- **Shop = every 3 phrases**, NOT every blind (`PHRASES_PER_SHOP`). The
  mid-section break opens the shop *inside* a running blind: score keeps
  accumulating, no clear/fail verdict. That is the point — you shop against a
  KNOWN deficit ("还差 14,100") instead of betting on an unseen blind. Balatro
  cannot do this; its shops sit strictly between blinds.
- **Gig (关卡 / 一场演出)** = **1 section**.
- **Run (巡演)** = 4 gigs = **4 sections**, **7 shops** (段中 4 + 段末 3 —— 末段没有段末商店,
  Tape 实测 37/37 局)。S4 = FINALE (谢幕).

#### Why 7 shops and not 4 (2026-08-06;原文写 8, 2026-08-09 实测末段无段末商店)

Shops outnumber joker slots **2:1** by design — 7 shops against 4 slots. The
4-slot cap is the *bottleneck*, not a collection target: the back half of the
run must trade up ("买新替旧", half-price recycle). Balatro runs 5 slots
against 24 shops (1:5). Cutting to 4 shops (1:1) would let a player fill the
board once and never trade, killing three shipped mechanics — half-price
recycle, Target 换旗 (`from_section: 3` would land on the last section), and
growth jokers. This is why the blind count could drop to 4 while the shop
count did not. Full derivation in `docs/design/levels.md`.

### Why the gig layer (2026-08 user call)

The old flow fired the full 演出成功 celebration (gold stars + confetti +
wage panel) after *every* section — a "you beat the game" screen every 60
seconds. Players read each section clear as 通关; the level layer existed
mechanically (three acts) but was invisible. Fix = Balatro's ante mapping:
small/big blind clears are quiet, only the boss clear gets the ritual.
Celebration is a scarce resource, saved for the gig boundary.

### Ceremony cadence

```text
phrase 3 of 6        -> MID-SECTION shop (blind still running; board shows
                        还差 N 分 · 还剩 N 拍) -> back to phrase 4
blind clear (S1..S3) -> light banner (target ✓, +3◆ wage), auto-slides away
                        ≤1s, no click -> shop -> next blind
S4 clear (FINALE)    -> 演出成功 screen -> 谢幕
any blind failed     -> 演出失败 screen -> 再来一次 (fresh run) | 返回主页
```

**演出成功 fires ONCE per run, at the finale** (2026-08-06 用户:「为什么中途要跳
那个通关成功的页面啊, 只有一整关通关才跳」). Tying the ritual to walls stopped
working the moment every section became a wall — it meant interrupting a
5-minute run with a full-screen celebration 4 times. Mid-run clears now take the
light banner (`BlindBanner`) straight into the shop. Failure still interrupts
with the full screen: a run ending is worth a stop, a run continuing is not.

- **Two shops per section** (mid + end). The joker pick is load-bearing and
  survives the restructure; decoupling it from the blind is what keeps the
  shop:slot ratio at 2:1 while the blind count drops to 4.
- Blind naming: BOSS only. The four tiers are told apart by **accent colour**
  (蓝 → 橙 → 红 → 粉) and index, not by name.

### The setlist (4 gigs)

| Gig | Sections | Phrase clock | Boss tier | Intent |
|---|---|---:|---|---|
| 1 教学场 | S1 | 8s | gentlest | **S1 is already a wall** — teaching space is gone, see below |
| 2 | S2 | 8s | mild | the shop starts to bite |
| 3 | S3 | 8s | mean | filters weak builds |
| 4 终演 | S4 | 8s | nasty | the squeeze; S4 = FINALE |

2026-08-06 用户拍板: 单拍统一 **8s** (「5 秒我玩不了,要 8 秒」), the gig curve
stays flat for now; `early_finish_time` = 3.5s. Budget: 4×6×(8+1) = 216s of
play + 7 shops ≈ **4.9 min**, inside the 5-minute ceiling (docs/design/levels.md).
The per-gig curve is gone for now but the `phrase_duration()` hook and the
per-gig data shape stay, so re-introducing a curve is a JSON edit.

- Phrase clock keyed **by gig** via the `phrase_duration()` hook — callers
  unchanged.
- **Calibration watch-point**: teaching space is **gone** — S1 is itself a
  wall and carries a boss face from phrase 1. Its pool must stay pinned to the
  gentlest tier (norepeat / cover; a test asserts this). This is the sharpest
  edge of the re-cut and the first thing to watch in a human pass. Mitigating
  factor: a section is 6 phrases long and has a shop in the middle, so a bad
  opening is recoverable in a way a 3-phrase section never was.

### Targets & calibration

- `SECTION_TARGETS`, **4 entries**, **HUMAN-anchored** (2026-08-05 真人试玩:
  casual play scored 万-level while bot-calibrated targets sat at 几百 —
  humans out-score the bots by roughly an order of magnitude, mainly via
  unlimited discard spending and deliberate cache curation):
  `[850, 2400, 6900, 19300]`
  Re-cut for 4 sections by resampling the previous curve at the same cumulative
  BEAT positions (total beats stay 24), so the shape is unchanged. Tables from
  other structures are NOT comparable section-by-section — only beat-for-beat.
  **Provisional — awaiting the user's feel pass.**
  The bot-scale table lives on as `sim.json bot_targets`, rebuilt to **4**
  entries the same way. ⚠ **Its length must equal `SECTIONS_PER_RUN`** — the sim
  iterates by section, so a longer table is silently truncated into a much
  easier board (this bit twice in one day; a test now locks the length).
  The sim measures RELATIVE archetype strength only, never absolute clear rates
  — and it is **not re-calibrated for this structure**: clear rates came back
  high across the board (random 35%, twin 99.5%) because 4 death checks with 6
  forgiving phrases each is simply a softer run than 8 checks of 3. The user has
  parked bot tuning ("算法的验证下一步等我来调").
- **盲注公示 = 舞台卡** (2026-08-05 真人试玩:「盲注呢?没看到」→「可以在选
  小丑牌的时候出」→「关卡就是盲注,局内样式要和首页那张玻璃卡一样」):
  the home screen's stage card and the in-game blind board are ONE object —
  `Widgets.StageCard` owns the look (glass slab, corner brackets, dotted
  grid, gradient rules, equaliser band), `Widgets.BlindBoard` is its
  in-game size. A blind IS a level, so they can never drift.
  The SHOP carries a blind board on top, in **two states** (2026-08-06):
  at a section end it previews 下一场 (第 N 场 · BOSS 墙 · target · face ⚠);
  at a MID-SECTION break it reports THIS blind instead — hero number = 还差 N 分,
  sub-line = 已得 X / 目标 Y, footer = 还剩 N 拍. The first keeps the
  preview-routing design; the second is what makes a mid-blind purchase a
  solvable problem rather than a bet. Shop-less entries (run start, retry) use the
  standalone centre card `view/intro.gd` instead: tap to skip /
  auto-dismiss (1.6s, walls 2.6s), phrase clock holds until it closes
  (`St.INTRO`).
- Calibration lens unchanged: **death distribution** — deaths cluster on
  named walls, never attrition mush. Healthy wall deaths 30–60%;
  execution-grade (>85%) only on the S4 finale. Difficulty基调 unchanged:
  most runs die. Numbers stay bot-pessimistic; final trim belongs to human
  playtests.
- Economy: **4** wage points (`SECTION_CLEAR_REWARD` +3◆ per section clear) —
  down from 12, so per-shop purchasing power falls even though the shop count
  held at 8. Prices retuned only after the user's bot pass.

### Boss faces (`core/modifier.gd`)

Four walls per run — now **every** section (S1–S4), all rolled at run start,
**previewed one section ahead** (NEXT ⚠) on the preceding blind's card and on
the shop board. Pools keep their four escalating tiers, remapped to keys
`0/1/2/3` (S1 gentlest, S4 nasty). Bent-not-bricked rule unchanged.

### Target swap

Pivot window opens **from S2** (`from_section: 1`). ⚠ This had to move with the
re-cut: the old absolute `3` is the LAST section under a 4-section run, which
would have silently reduced the pivot to a two-shop window and killed the
"farm early economy, re-flag before the mean walls" arc. A test now asserts the
window opens by the halfway point. Still 8◆, no refund, 35% shelf chance.

### Failure

Any blind missed = 演出失败 → fresh run (roguelite正统, matches the
most-runs-die基调; keeps the death-distribution lens valid). No mid-gig
retry, no carry-over.

### HUD

- Top-left label: 「第 N 场 · 小盲/大盲/BOSS」 (was `SECTION 01`).
- Section progress dots: **4 groups × 3** (was 10 flat).
- Gig number is the narrative hook for future venue art
  (bar → club → theater → stadium); this pass ships numbering + copy only.

### Calibration (2026-08-05, 3 rounds, bots — pessimistic upper bound)

Round 1 (draft targets, rotation on S6): shape already clean (deaths cluster
on walls, no attrition mush; no-joker baseline dies 62-72% on the S3
teaching wall) but amplitude too hot: twin 6.3% (old anchor 15.8%), and
**S6 rotation bricked the wolf arc** — lonewolf 96%, even the
preview-pivoting wolfpivot bot 93%: the pivot window opens one shop before
S6, structurally too late to rebuild. Round 2: rotation moved out of the S6
pool (S9 keeps it — the old-world S8 timing); twin 8.4%, S6 healthy
(14-50%), anytarget 6.7% matching old greedy 6.6%. Round 3: S9 2400→2200→
**2100**, S10 2500→**2300**, S11 2900→**2600**, S12 3400→**3200**.

Final: twin **10.2%** / anytarget 8.4% / triplet 6.4% / mono 3.7% /
wolfpivot 3.1% / stair 0.8% / lonewolf 0.2% / random 0.0%. Twin death
distribution S6:14 / S9:38 / S12:20, verses ≈0. Wall faces in the 30-60%
band; rotation 64-91% only vs zero-discard styles (the designed nemesis —
re-flag on preview is the counterplay); execution-grade only on S12.
**Criterion change**: the old "random ≥1%" floor is structurally gone at 12
sections — the floor signal is now stair/wolfpivot > 0. Sealed vs bots;
final trim belongs to human playtests.

### Run end screens

`view/run_end.gd`, 1:1 from `docs/mockups/success.html` + `fail.html` (still
the design authority for the two full screens). Success screen gains
「第 N 场演出」 context; finale flag moves to S12. The light banner is a new
lightweight strip, not a run_end mode.

---

## 节奏定案

**状态:已定案(2026-08-06 用户拍板)。**
终值 = **4 场 × 1 盲注 = 4 盲注 × 6 拍 × 8 秒,每 3 拍一次商店**,一局约 4.9 分钟。
下面 §0 是定案与推导,§1–5 保留当时的约束/账本/候选,作为「为什么是这个数」的存档。

---

### 0. 定案(2026-08-06)

| 参数 | 终值 | 前一版(8 盲注) | 更早(实验值) |
|---|---|---|---|
| `phrases_per_section` | **6** | 3 | 2 |
| `phrases_per_shop` | **3**(新键) | —(= 段长) | — |
| `sections_per_gig` | **1** | 2 | 3 |
| `gigs_per_run` | 4 | 4 | 4 |
| 盲注总数 | **4** | 8 | 12 |
| 商店总数 | **8**(段中 + 段末各一) | 8 | 12 |
| 墙位 | **全部 4 段** | S2/S4/S6/S8 | S3/S6/S9/S12 |

时长不变:`4 × 6 × 9s = 216s` 出牌 + 7 次商店 ≈ **4.9 min**(单拍 8s + 1s `resolve_hold`)。

#### 关键结构决定:商店与盲注**解耦**

前一版把商店频次绑在盲注上(照 Balatro 抄的 1:1),所以「压时长」只能砍盲注数。
用户提出的方案把这两件事拆开:**盲注 4 个,但商店每 3 拍开一次,所以还是 8 次**。
总拍数(24)、商店数(8)、槽位压力(4 槽)三项与前一版**完全相同**,唯一的实质差异是
**生死判定点从 8 个降到 4 个**,以及**商店可以开在一个盲注的中途**。

段中商店是这套设计的价值所在,也是原作没有的:

- Balatro 的商店严格卡在盲注**之间**,你为一个还没看清的盲注买牌,本质是**赌**;
- 段中商店开在你已经打完半个盲注之后 —— 分数、缺口、构筑转没转起来全都已知,
  买牌变成**解题**(「还差 14,100,我需要一个乘法」)。

代价要记住:**能中途救场,意味着前半段打崩不再是死刑**。挫败感下降,一次打对的压力也下降。

#### 为什么是 4 盲注 7 商店而不是 4 商店 —— 槽位是瓶颈,不是容量目标

用户曾问「4 个槽位是不是就该配 4 个盲注」,**反过来才对**:

- Balatro 是 **5 槽 : 24 商店 ≈ 1:5** —— 构筑的乐趣在**换掉**(顶掉旧牌、看 Boss 预告转流派),不在集齐;
- 现在是 **4 槽 : 7 商店**,前 4 次填满、后 3 次必须做替换决策;
- 若商店也砍到 4 次(1:1),三个已实装机制会直接失活:**买新替旧·折半回收**(刚填满就结束)、
  **Target 换旗**(`from_section: 3` 会落在最后一段)、**成长牌**(没有后期)。

用户 2026-08-06 确认:「为了控制只有 4 个小丑牌,所以设计了只有 4 个槽位,要上新的就要替代掉以前老的」。

#### 连带改动

- `blind_names` → 1 项 `["BOSS"]`。**小盲/大盲的概念作废**(用户:「就是异常下来有 4 个阶段性的
  任务和规则要做,也不做跳过,就是必须做」),4 段全是 BOSS 墙,递进感由档位色 + 序号承担。
- `accent_for()` 改**四档递进**:蓝 → 橙 → 红 → 粉(前三档是用户拍板的红蓝橙,第四档取调色板
  里的粉,是「红再往上」的终局色)。`tier_stars()` 相应变成 1..4。
- `data/faces.json pools` 键 → `0/1/2/3`,四档递进(最温和 → 最狠)逐档照搬。
  ⚠ **教学空间归零**:第一段就带 Boss 规则,S1 的池必须留在最温和档(测试里有断言)。
- 首页赛程 12 点 → **4 点**;`BLIND TIER ×N` 改读总段数(否则 `SECTIONS_PER_GIG` 恒 1,永远显示 ×1)。
- **商店盲注板两态**:段末仍是「下一场」预告;段中改讲**这一段的进度** ——
  大字 = 还差多少分(决策依据), 副行 = 已得 X / 目标 Y, 页脚 = 还剩 N 拍。
- **满槽替换流程补完**(见 §0.2)。

#### 0.1 目标分:按累计拍数重采样,**未校准**

总拍数始终是 24,所以两张表都按「旧曲线在同一累计拍位上的几何插值」重采样,形状不变:

```
section_targets (人锚) = [850, 2400, 6900, 19300]
sim.json bot_targets   = [215, 540, 895, 1345]
```

**都只是起点。** 用户 2026-08-06 明确:「机器人模拟算法还比较蠢,不着急过。我们先把节奏定下来,
代码写好 QA 做好,算法的验证下一步等我来调」。所以本轮**只定结构 + 保证代码/QA 正确,没有追封盘轮廓**。

跑出来的通关率整体偏高(random 35% / twin 99.5%),原因是结构本身而不是表长:
**生死判定点从 8 个降到 4 个,且每段 6 拍容错高、段中还能补强**。真要收敛需要用户先调机器人。

> ⚠ **`bot_targets` 的表长必须等于 `SECTIONS_PER_RUN`。** 这个坑同一天踩过两次:
> sim 按段数迭代,表比段数长就被**静默截断**成一个放水盘(random 通关率一度从 0.8% 飙到 42%)。
> 现在 `tests/runner.gd` 里有断言锁住长度,别再靠注释。

#### 0.2 满槽替换:入口原本是残的

用户指出「选第 5 个小丑牌要去替换一个,这个操作还没做」。核实后:入口在
(满槽时点货架上的卡 → 槽位挂「替换」角标 → 点槽完成),但**流程缺信息**:
`_on_shop_replace()` 会 `shop.close()`,**把玩家正要买的那张牌一起关掉** ——
而替换决策的本质就是新旧对比,当时只能凭记忆选。价格也随货架一起消失了。

新结构把这个洞放大:4 槽在前 4 次商店就填满,**后 3 次商店 100% 是替换场景**,
「前期吃经济、后期转流派」那条弧全靠这个界面承载。已修:

- **新卡钉住**:待装入的卡以「第 5 个槽位」的形态留在小丑牌行下方,新旧同屏上下对照;
- **拖拽替换**:把新卡拖到要换掉的槽位上。手势与缓存区一致 ——
  CLAUDE.md 定的是「不存在存入空位,**拖拽 = 两张对调**」,换小丑牌本来就是一次对调
  (新卡进、旧卡折半回收),玩家不必学第二套操作。点击路径保留作降级;
- Target 槽**拒绝**接放(它是取消位,不该悄悄吞掉一次拖拽);
- 提示条补上**买入价**,并收窄避开左边的盲注卡与右边的唱片。

仍未做(用户拍板留到真人试玩后再定):槽位上显示「这张牌本局贡献了多少分」——
连着做 4 次替换决策却没有任何数值依据,可能是下一个痛点。

---

### 1. 用户已拍板的硬约束

> **【存档】以下 §1–5 记录的是 2026-08-05 定案之前的状态,已被 §0 取代。**
> 保留是为了「为什么是这个数」可追溯 —— 里面的「当前配置」「12 个盲注」等说法**都不是现状**。

| 约束 | 原话 | 含义 |
|---|---|---|
| 单拍不能低于 8 秒 | 「5 秒我玩不了,要 8 秒」 | `gig_clocks` 下限 = 8.0(末轮压缩另议,见 §4) |
| 一局 3 分钟为目标,5 分钟是上限 | 「我目标是三分钟一局」「手游节奏肯定更快的。5 分钟极限了」 | 总时长预算 **180s 目标 / 300s 硬上限** |
| 盲注不可跳过 | 已是铁律(docs/design/levels.md) | 不能靠 skip 压缩时长,只能压**单拍秒数 × 拍数** |
| 12 个盲注 | 四场 × 三盲(docs/design/levels.md) | 比原作(Balatro 8 底注 × 3 = 24)少一半,是有意为之 |

**注意这四条互相冲突**,这正是这件事需要专门一个 session 的原因 —— 见 §3 的账。

---

### 2.【存档】2026-08-05 当时的配置是实验值

`data/run.json` 现在停在:

```json
"phrases_per_section": 2,
"gig_clocks": [8.0, 8.0, 8.0, 8.0],
"section_targets": [175, 350, 770, 1230, 2000, 3000, 4400, 6000, 8000, 10700, 14400, 19300]
```

三点必须知道:

1. **`phrases_per_section` 从 5 降到 2 是为了凑时长,没有做过任何平衡验证。** 一段只有 2 拍
   意味着玩家只有两次出牌机会去够 target,弃牌/养缓存的空间被砍掉大半 —— 这对
   「早抽改基牌」「成长牌」这类需要时间铺开的小丑牌是结构性削弱。
2. **`section_targets` 这一版是按 2 拍重新拍的脑袋,没跑过 sim,也没有真人数据。**
   上一版经过校准的人锚表是 `[500 … 60000]`(12 段,5 拍/段),两者**不可直接比较**,
   因为每段的出牌次数不同。要回退就整组一起回退。
3. `gig_clocks` 四场全平(8/8/8/8),**场曲线还没做** —— 原本设计里它是难度弧的一部分。

> 一句话:**任何拿现在的通关率/分数说事的结论都是无效的。** 新 session 第一件事应该是
> 决定 §4 的结构,然后**重新校准 targets**,而不是在现有数字上微调。

---

### 3. 时长的账(把公式写下来,别再手算)

单局总时长 ≈

```
Σ(每段) [ phrases_per_section × (gig_clock + RESOLVE_HOLD) ]  +  商店停留 × 12  +  结算屏
```

其中 `RESOLVE_HOLD` 是结算三段式的停顿(`data/ui.json stage.resolve_hold`),
商店 12 次(每 Section 结算后一次,Balatro 频次 1:1)。

几个候选结构的**纯出牌时间**(不含商店/结算屏):

| 结构 | 每段 | ×12 段 | 纯出牌 |
|---|---|---|---|
| 2 拍 × 8s(**现值**) | 16s | 192s | 3.2 min |
| 3 拍 × 8s | 24s | 288s | 4.8 min |
| 3 拍 × 8/8/7/6 场曲线 | 24/24/21/18s | 261s | 4.35 min |

**商店是被低估的那一块**:12 次商店,哪怕每次只停 10 秒也是 120s = 2 分钟,
足以把「3.2 分钟出牌」推到 5 分钟以上。**压时长的第一刀应该考虑砍在商店频次上,
而不是继续砍拍数** —— 但商店频次 = 盲注频次是照 Balatro 抄的,砍它要用户拍板。

---

### 4.【存档】当时提过但未定案的方案

用户自己提过一版:

> 「12 盲注 3 拍,但是最后一轮我们固定盲注(我们比原作多一个盲注)是压缩时间到 6 秒,这样就差不多了?」

这一版**和「不低于 8 秒」的约束表面冲突**,但用户的意思应该是:8s 是**常规**下限,
**末场作为终幕专门提速到 6s** 是设计意图(赶场感),不是违背手感底线。需要新 session 跟用户确认这一点。

我当时给的建议是 **3 拍 × 8/8/7/6 场曲线**(≈4.35 min 纯出牌),理由是:
- 3 拍保住构筑空间(2 拍太少,见 §2.1);
- 提速放在场与场之间而不是段与段之间,玩家能感知到「越来越赶」这条弧;
- 8→6 的降幅温和,不会在末场突然失手。

**这只是建议,未经用户确认,也未经任何平衡验证。**

另注:`gig_clocks` 已经是**按场**的数组,上面任何方案都不需要改代码,改 JSON 即可
(时长一律走 `GameConfig.phrase_duration()` 钩子)。

---

### 5.【存档】当时给新 session 的建议顺序

1. 跟用户敲定结构(拍数 / 场曲线 / 末场是否破 8s 下限 / 商店频次是否动);
2. 改 `data/run.json` 的 `phrases_per_section` + `gig_clocks`;
3. **重新校准 `section_targets`** —— 跑 `tools/sim.gd`,但只看**流派相对强弱**和死亡分布,
   绝对通关率不对应真人(机器人是悲观下界,差一个数量级,见 CLAUDE.md);
4. 真人试玩,按体感修目标曲线;
5. 回归:`tests/runner.gd` 全绿 + `tools/flow_probe.gd` 0 违规。

---

## 经济与商店

> Rewritten 2026-08 for the shipped single-pool economy. The escalating
> draw-cost table died with the candidate mechanic.

### Definition

Coins are **future choice capacity** - the run's only spendable resource
(Balatro splits hands / discards / money into three pools; we deliberately
run one). Coins persist through the run and reset after it.

### Income

| Source | Amount |
|---|---:|
| Pattern reward at settle | 0-15 by pattern (`Pattern.BASE_COINS`) |
| Section clear wage | +3 |
| Skipping a shop | +2 |
| Sell-back on replace | half price, rounded down |
| Jokers (Interest, Tip Jar) and character effects | varies |

Starting coins: **6**.

### Sinks

| Sink | Cost |
|---|---:|
| Discard | 1 per card |
| Support joker | common 4 / uncommon 6 / rare 9 (Mirror 11) |
| Shop reroll | 3, +1 per further reroll |
| Target swap (S4+ shops) | 8 |
| Cover Charge boss face | 1 per phrase |

All numbers live in `core/config.gd` and `core/economy.gd`.

### Zero coins

Paid discards disable; swaps and settlement continue normally.

### Structural notes (sim-verified)

- The clear wage is the income backbone: pattern coins alone cannot fund
  both discards and the shop (discard-heavy builds starved at 2-3 coins
  before it existed).
- Zero-discard builds (Lone Wolf + Tip Jar) are the hoarders the priced
  shop and the target swap exist for.
- Debt / credit cards are future design space (cut from v0.1).

### Acceptance (unchanged)

- Coins must create real hesitation.
- Spending improves opportunity, not certainty; saving must have a future.

---

## Director(前瞻,未实施)

> ### ⚠⚠ 2026-08-14:下面三节**已作废**,规格转 [`difficulty.md`](difficulty.md) §3
>
> 用户拍板:「**这里不是千人千面的不用读 context。真正千人千面的只有随机出来的小丑牌
> (控制难度的)。**」
>
> ⇒ **`Inputs`(每拍 9 个信号)· `Recent behavior model`(20–30 拍滚动窗 + 6 种玩家倾向)·
> `Joker learning states`(Tried / Understood / Mastered 判定)—— 这三节全是读 context 的,
> 全部作废。**
>
> Director 从「自适应 AI 系统」降级成**一张设计期写死的表**:实现成本从「建行为模型 +
> 在线推断」掉到「读一张 JSON」。⚑ 这大概也是它一直没实现的真正原因 —— **它被设计得太重了。**
>
> **`Sequence states`(七状态)· `Offer logic` · `Fairness` 三节仍然有效** ——
> 用户举的例子(前三关教学 → 难一关 → 简单两关 → 难一关)与七状态序列**逐项对得上**。
>
> ⚠ `Fairness` 那节的边界要按 [`difficulty.md`](difficulty.md) §3 末尾精确化:
> 禁的是 **DDA / 橡皮筋**(读表现偷偷改数),**不禁**按局数索引、对所有人相同的设计常量表。
> 判据 = **同一个玩家在同一个位置永远拿到同一个数**。

### Definition

Director controls learning and emotional pacing.

It does not directly decide victory.

### ~~Inputs~~(作废,见上)

Per Phrase:

- Initial Best / Final Best
- draw count and spend
- last action time
- Cache usage
- pattern distribution
- near miss
- character trigger
- Target/Support trigger
- Section completion rate

### ~~Recent behavior model~~(作废,见本节开头)

Use a rolling window of 20–30 Phrases.

| Tendency | Signal |
|---|---|
| Conservative | few draws, early inactivity |
| Balanced | moderate draws, preserves coins |
| Chaser | high draw count, frequent coin depletion |
| Planner | high Cache usage and future conversion |
| Fixed | repeats same pattern strategy |
| Improviser | frequently changes pattern and route |

These are temporary states, not permanent labels.

### Sequence states

| State | Purpose | Typical system action |
|---|---|---|
| Establish | build habit | clear normal hands |
| Pressure | raise tension | weaker starts or tighter economy |
| Introduce | add new rule | Joker draft |
| Experiment | encourage use | visible opportunities for the Joker |
| Mastery | test learning | normal randomness |
| Payoff | amplify release | more high-value structures |
| Recovery | reduce fatigue | stronger start or cheaper first draw |

Typical Section:

```text
Establish
→ Pressure
→ Introduce
→ Experiment
→ Payoff
```

### ~~Joker learning states~~(作废,见本节开头)

```text
Unseen
→ Owned
→ Tried
→ Understood
→ Mastered
```

Default interpretation:

- Tried: triggered once
- Understood: triggered twice in three Phrases
- Mastered: player altered behavior around it in three of five Phrases

Each Joker can override these thresholds.

### Offer logic

Three choices:

- A: reinforce mastered behavior
- B: adjacent new decision
- C: high-risk alternate route

Do not introduce two high-load rules in consecutive drafts.

### Fairness

Director may:

- choose between pre-generated legal hand templates
- adjust unseen deck order between Phrases
- raise the frequency of real opportunities

Director may not:

- change revealed cards
- create illegal cards
- alter results after player action
- fake a near miss

The player must believe:

> Randomness gives the problem; choice determines the answer.

---

## 附:从 `CLAUDE.md` 迁来的推导与实测(2026-08-09)

> 逐字迁移,未压缩。与 §0 有重叠处以本节为准(§0 那张表里的「商店总数 8」是旧读数)。

### 演出成功屏为什么全程只发 1 次

  **演出成功屏全程只发 1 次 —— 打完 S4 那一下**(2026-08-06 用户:「为什么中途要跳那个通关成功的
  页面啊,只有一整关通关才跳」)。旧规则是「成功屏挂在 Boss 墙上」,4 段全变成墙之后它等于每段都发,
  5 分钟一局被全屏打断 4 次。中途过关改走 `BlindBanner` 轻横幅(≤1s 自动滑走)直接进商店。

### 商店是 **7 次不是 8 次**

  ⚠ **不是 8 次**:末段没有段末商店 —— `view/phrase.gd` 在 `finale` 那一支直接走结算屏,
  而那一刻剩余拍 = 0,买什么都不可能再产生分数。2026-08-09 用 Tape 的 `shop` 事件实测
  **37/37 完整局都是 4+3**。⚠ 曾经**只有 `tools/runloop.gd` 无条件开末段商店**,
  于是模型比游戏多一次(买入率实测 0%,几乎不改读数,但那是「规则在游戏/模型里不一致」
  的反方向一例)—— 已修。旧文档里的「8 次」一律按 7 读。

### 段中商店为什么值得做

  编排器只 `_open_draft()` 不推进 section。为什么值得这么做:Balatro 的商店严格卡在盲注之间,
  你为一个没看清的盲注买牌本质是**赌**;段中商店时玩家已经打完半个盲注,分数/缺口/构筑转没转
  全都已知,买牌变成**解题**。代价是前半段打崩不再是死刑(挫败感和压力同时下降)。

### 为什么商店是 7 次不是 4 次 —— 槽位是瓶颈不是容量目标

  **为什么商店是 7 次不是 4 次**:槽位(4)是**瓶颈**不是容量目标——7 商店 : 4 槽 ≈ 1.75:1,
  后半程必须「买新替旧」,那才是构筑弧的发动机(Balatro 是 5 槽 : 24 商店 = 1:5)。
  ⚠ 实测(`tools/wallet.gd`, 200 局):**满槽稳定发生在第 5 次商店**(0-based 第 4 次),
  200/200 局无一例外 —— 所以**后 3 次商店 100% 是替换场景**。
  砍到 4 次会让折半回收/Target 换旗/成长牌三个已实装机制全部失活,推导见 `docs/design/levels.md`。

### ⚠ 改段数要顺手核对的三张按段索引的表

  ⚠ **改段数要顺手核对三张按段索引的表/参数**:`section_targets`、`sim.json bot_targets`
  (表长必须 == 段数,长了会被**静默截断**成放水盘)、`target_swap.from_section`
  (绝对值会漂到末段,换旗弧静默失效)——三条现在都有测试锁着。

### 目标分表的来历

  目标分见 `SECTION_TARGETS`(4 段 = [850,2400,6900,19300],按累计拍位从旧曲线重采样,
  总拍数始终 24;**待真人收敛**。不同结构的表只能按拍位比,不能逐段比)。

---

## 验证方案

### 1. 三张按段索引的表 —— **改段数必查**

`section_targets` · `sim.json bot_targets` · ~~`target_swap.from_section`~~(已删)

⚠ **`bot_targets` 表长必须 == 段数**,长了会被**静默截断**成放水盘。
三条现在都有测试锁着 —— 这是踩过才加的。

### 2. 目标分的闭环重放(`19_Generator_Validation §4.1`)

生成器说「这个配置下第 3 段死亡率 45%」→ 拿它自己的输出**真打一遍**,实测是不是 45%。

```
loss = | 预测通过率 − 实测通过率 |
```

⚠ **目标分那一维是恒等式**(查分位数),按定义不会错;
**真正会错的是分数分布本身** —— 所以闭环重放实际验的是求解器,不是生成器。

### 3. 商店流程 —— `flow_probe`(已并进 `gate.sh`)

守**段中商店不结算、不清分、不判生死**这条(`Run.advance()` 返回 `shop_break`)。
上一轮回归:112 次段中商店,**0 违规**。

### 4. 判生死只有一份

走 `Run.section_target_for`。⚠ 这条是 `raisedbar` 事故的形状 ——
一局的循环曾被抄了 14 份,每份自己判生死。现在 14 → 1(`tools/runloop.gd`)。

### 5. ⚠⚠ 目标分表当前是**占位**

`run.json section_targets` 与 `sim.json bot_targets` **不是定稿**,
整套要跟着新目标函数(留存最大化)重新设计。**别把它们当待修的 bug。**
