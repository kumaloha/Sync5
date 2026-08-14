# 小丑牌与主角设计

> **两者归一篇**:它们是同一类东西 —— 构筑侧的数值内容,
> 各自的平衡数值在一张表里(`data/jokers.json` 与 `core/character.gd::roster()`),
> **改平衡只动那里,别散到代码各处**。

> **Revised 2026-08** after the Balatro deep-dive (`research_balatro_jokers.md`).
> Supersedes the previous version of this file: the candidate-draw era support
> list (Test Draw / Preview / Refund / Thin Ice / old Turnover) is gone, and the
> six support categories are replaced by the axis system below.

## Definition

Joker rewrites local optimum and pressure.

It turns repeated gambling into a learning loop:

```text
Old rule becomes familiar
→ new Joker enters
→ pressure rises
→ player experiments
→ rule is understood
→ rule is mastered
→ release becomes larger
```

## Two layers (unchanged)

| Layer | Count | Question |
|---|---:|---|
| Target Joker | 1 | What is a good answer? |
| Support Joker | max 3 | How do I reach it? |

Target defines **WHAT** (pattern-family multipliers; the first is free after
Section 1, and from the shop after S3 a Target may appear at the swap price —
buying it replaces yours outright: the pivot arc). Support defines **HOW**.

## Locked decisions (2026-08)

- **All passive.** Effects trigger on the settle chain or on acquire. No
  clickable abilities in v0.1 — the 12s clock owns the player's attention.
- **Rarity system: Common / Uncommon / Rare.** Draft choices are drawn by
  rarity weight (placeholder 70/25/5). Rarity replaces the old
  upgrade-once system; full slots → replace one or skip.
- **Roster size: Target 5 + Support 18** (batch 2 added three rule rescues).
- Targets carry no rarity — one per run, drafted equally.
- **⚑ 2026-08-10 用户拍板:roster 目标总数 60**(Target 8 + Support 52)。终选名单、
  配额 60 口径、稀释数学与实施状态全在 [`jokers_atlas.md`](jokers_atlas.md) §0/§5,
  本文的 roster/quota 节保留为批 2 时代的历史口径。批 3 分波入池,每张过
  `SYNC5_KIT_ID=<id>` 单卡门;`curve`(burst/fixed/growth/floating/decay)自此为
  support 的**数据必填项**(`core/db.gd` 校验)—— 配额表的记账单位,忘填直接红。
- ⚑ 同日新增判据:**有用但无感 = 没用**(杀延长音的理由:「谁差这一秒」)——
  卡的价值必须能被感受,不只是被测量;与「测出近零不许改内容」互为两个方向的镜像。

## Scoring formula and channels

```
score = (pattern base + Σ base-mods) × target mult × (1 + Σ percent) + Σ bonus
coins = pattern coins + Σ coin bonus
```

Base-mods (VIP, Vinyl) ride the multiplier — they must be drafted early to
matter (user rule). Flat bonuses land AFTER the multiplier: huge in S1,
pocket change by S10 — the mechanism that kills universal filler cards.

Three support channels, hard-bound to rarity (climbing rarity swaps the
currency, never just inflates the number):

| Rarity | Allowed channels | Feel |
|---|---|---|
| Common | flat `bonus` (post-mult), small coins; Vinyl alone rides the mult | strong early, expires late |
| Uncommon | strong conditional `+%`, growth, light rules | build commitment |
| Rare | `×mult`, copy, rule change | run-defining, scarce |

## Design principles

### A. Time-compression constraints (where we diverge from Balatro)

- **A1 — Settle is the only reading window.** All effects fire in the settle
  chain and get a beat in the settle show. Mid-phrase, jokers are silent rule
  reminders.
- **A2 — Conditions must be plan-level or muscle-memory behaviors.** The only
  levers a player consciously controls in 12s: what to discard, what to swap
  with cache, how fast to act, which pattern to chase. Every condition lands on
  one of these four. No mid-phrase reading tasks.
- **A3 — Growth and resets hang on explicit actions only, never on settled
  pattern content.** Settle auto-picks the best hand; avoidance-style
  conditions (Ride the Bus / Obelisk) would let the system step on the
  player's landmine. Legal growth drivers: discards, timing behaviors, draft
  decisions.
- **A4 — Zero idle growth.** Real-time makes per-phrase counters a passive
  drip. Balatro ships 150 jokers with zero idle scaling; so do we. Free
  actions (cache swaps cost nothing) may not feed counters either — growth
  drivers must cost something (coins) or be once-per-phrase by nature.
- **A5 — Timing and sequence cards are our identity.** Balatro has no clock
  and no phrase memory. Timing + sequence together ≥ 5 of the 15 supports.

### B. Numeric structure

- **B1 — True dual currency.** The `+base_score` additive channel exists so
  additive cards decay in relative value across a run while `×` cards grow —
  the time-curve axis comes free (Balatro principle #1/#2).
- **B2 — Channel × rarity binding** as in the table above (census: +Mult is
  79% Common, ×Mult penetration 3% → 28% → 60%).
- **B3 — The late-run curve must have a source.** SECTION_TARGETS spans ×20;
  three support slots fill by mid-run. ≥3 permanent-growth cards (stateful
  counters) carry the back half. Additive growth may be Common; multiplicative
  growth is Rare-only.
- **B4 — Slot order is meaningless, by design.** Channels are segregated and
  merged at the end of the chain. No placement metagame in a 12s game.

### C. Experience and build principles

- **C1 — Every card passes six questions:** Which choice changes? Which local
  optimum or pressure changes? What does the player learn? Tradeoff or mere
  complexity? Does mastery release more? **Which chain link is it, and with
  whom does it chain?**
- **C2 — At least two mutually exclusive pairs** (discard vs. hold, fast vs.
  late). Cheapest decision manufacturing there is.
- **C3 — No pure trap cards; sleepers must have a home.** Cut only what
  cannibalizes neighbors or what nobody picks. Keep 2–3 "looks mid, finds its
  family later" cards.
- **C4 — Fun-overpowered is allowed.** One unconditional Common treat
  (the Cavendish slot). Only exclusionary overpower gets cut.
- **C5 — One decay card, overpriced on its face.** The clock is already
  ticking; decay reads unambiguously in real time. "Rented early-game power."
  Never at Rare.
- **C6 — One copy card, Rare.** With 4 slots it is a fifth virtual slot and
  scales with the build, so it can't be independently broken. No
  ally-destroying or pure-placeholder cards in v0.1 (25% slot tax is brutal).

### D. Engineering and readability

- **D1 — Few events, many cards.** The public hook set is fixed:
  `on_settle / on_acquire / on_discard / on_swap / on_phrase_end /
  on_section_end` plus the ctx signal list. New cards use existing hooks;
  opening a new one needs a hard justification.
- **D2 — Card text: English, ≤7 words, no subclauses, readable in 1.5s.**
  ("Flush hands ×4" is the canonical length.) A design that can't fit goes
  back to the drawing board.
- **D3 — The settle show gives every triggered joker a beat.** Scoring is a
  watchable Rube Goldberg machine; FLY/MERGE/BURST must show how the number
  snowballed.

## Support quota table (batch-2 时代的 15 张口径,历史保留)

> ⚑ **60 张口径的配额表在 [`jokers_atlas.md`](jokers_atlas.md) §0**(2026-08-10 起生效):
> burst ~22 · fixed ~10 · growth ~8 · floating ~6 · decay ≤2;普 ~24 / 罕 ~18 / 稀 8(稀释保护);
> 原则上限不随规模放大:复制 1 · 甜品 ≤2 · 衰减 ≤2 且不入稀有。

| Axis | Quota |
|---|---|
| Time curve | burst 6 · fixed 3 · permanent growth 3 · floating 2 · decay 1 |
| Rarity | Common 7 · Uncommon 5 · Rare 3 |
| Function floors | timing+sequence ≥5 · economy ≥2 · rule change 5 (batch 2: the stair/mono rescue rules live on `Deck.rules`, read by `Pattern`) · copy 1 |

## Engine interface (design-time contract)

Existing ctx signals: `kind, base_score, mult, bonus_pct, coins_bonus,
prev_kind, acted_late, discards, coins`.

To add for the v0.1 roster: `additive` (B1 channel), `last_action_time`,
`phrase_idx_in_section`, cache contents at settle, per-joker state counters.
Economy hook: discard cost must consult installed jokers.

⚑ 2026-08-10 批 3 扩容后的现役 ctx 追加:`phrase_idx` `cache_cards` `scoring_cards`
`early_finish` `section_idx`;谓词扩到 21 个、操作码新增 `additive_low_value` 与
`chips_per_card{card_filter}`(一个操作码解锁整个牌面族)。完整词汇账单见
[`jokers_atlas.md`](jokers_atlas.md) §3。

## Draft shop (decided + implemented 2026-08)

Every Section clear is a shop visit:

- **Targets**: free three-choice draft (the build direction must not die to
  coin variance). One per run.
- **Supports**: three rarity-weighted choices, each **priced** (Common 4 /
  Uncommon 6 / Rare 9). Unaffordable cards still show, dimmed — envy funds
  the saving motivation (straight from Balatro's shop).
- **Reroll** the board for 3 ◆, +1 per further reroll (resets each visit).
- **Skip** pays +2 ◆.
- **Full slots** → buy-new-replace-old: pick a candidate, then tap the
  support slot to swap out; the old card sells back for half price. This is
  the late-game coin sink.
- Income backbone: **Section clear wage +3 ◆** (the blind-reward analog) +
  pattern coins. Pattern coins alone cannot carry both the discard cost and
  the shop (sim round 5 proved it — discard-heavy builds starved at 2-3 ◆).

## Roster v0.1 (approved 2026-08, implemented in `core/joker.gd`)

All +N / % / × numbers are relative scales pending the simulation balance pass.

### Targets (5, no rarity)

Multipliers are priced against 5-card-hand achievability (sim-calibrated;
see the calibration note below).

| Card | 中文 | Text | Notes |
|---|---|---|---|
| Twin | 双子 | Pair ×3, Two Pair ×5 | tiers inverse to chase rate (user rule) |
| Stairway | 阶梯 | Straight ×8, Straight Flush ×16 | rarest chase (~7-12%), the jackpot ladder |
| Monochrome | 单色 | Flush ×6, Straight Flush ×12 | ~18-25% chase |
| Triplet | 三连音 | Trips ×4, Full House ×8, Quads ×12 | tiered per pattern, not one flat family |
| Lone Wolf | 独狼 | Ace/King high, no discards: ×4 | J/Q-high does NOT count; chase the top card with free swaps; locks out the discard economy |

### Supports (15)

| Card | 中文 | Rarity | Curve | Class | Text |
|---|---|---|---|---|---|
| Encore | 回响 | Common | burst | sequence | Same hand as last phrase: +80 |
| Finale | 尾声 | Common | burst | timing | Act in final 2 seconds: +70 |
| Turnover | 周转 | Common | burst | card flow | +20 per discard this phrase |
| Tip Jar | 小费罐 | Common | burst | economy | Zero discards this phrase: +2 coins |
| Chord | 和弦 | Common | burst | card flow | Cache all one suit: +120 |
| Neon Sign | 灯牌 | Common | fixed | — | +80 |
| Vinyl | 黑胶 | Common | growth | card flow | Every discard: +3 forever |
| Chorus | 副歌 | Uncommon | burst | sequence | Last phrase of section: +75% |
| Interest | 利息 | Uncommon | floating | economy | +1 coin per 4 held |
| Momentum | 惯性 | Uncommon | growth | timing | Each early finish: +10% forever |
| VIP | 贵宾 | Uncommon | fixed | rule | Face cards count as 15 |
| Glow Stick | 荧光棒 | Uncommon | decay | timing | +60%, fades 6% each phrase |
| Bassline | 贝斯线 | Rare | growth | card flow | Every 12 discards: ×0.25 forever |
| Shortcut | 近道 | Uncommon | fixed | rule | Straights may skip one rank |
| Four Fingers | 四指 | Rare | fixed | rule | Four-card straights count |
| Two-Tone | 双色调 | Rare | fixed | rule | Flushes need only matching colors |
| Mirror | 镜面 | Rare | floating | copy | Copies your Target at half power |
| Wildcard | 百搭 | Rare | fixed | rule | Two wild cards join your deck |

Built-in tensions: Turnover vs Tip Jar (discard or not), Finale vs Momentum
(late or early), Vinyl vs Tip Jar (long discard investment vs cash flow),
Lone Wolf vs the whole discard package (it teams with Tip Jar instead).
Sleepers: Vinyl, Bassline, Chord. Unconditional treat: Neon Sign.
"Early finish" = at least one action, and none after the 6s mark
(`GameConfig.EARLY_FINISH_TIME`) — an untouched phrase never counts.

## Boss faces (core/modifier.gd, implemented 2026-08)

Six faces, pooled per wall (S5 mild / S8 mean / S10 nasty), all rolled at run
start and **previewed one section ahead** ("NEXT ⚠ ..." in the info bar) —
Balatro's visible-boss mechanism. The preview is what turns a face from an
execution into a routing decision: a Lone Wolf that sees No Repeats or
Forced Rotation coming pivots its Target in the shop window before the wall.

| Face | Rule | Taxes |
|---|---|---|
| Unplugged 拔电 | Your Target works at half power | Mirror+Target cores (full silence bricked: 100% deaths in r16) |
| Static 杂讯 | Score bonuses are disabled | flat-bonus kits |
| No Repeats 禁回 | Repeating last hand scores half (High Card exempt) | Encore repeat routines; the exemption un-bricked Lone Wolf (68%→16% wall deaths) |
| Forced Rotation 强制换血 | Zero discards: score halved | the zero-discard vow |
| Rush Hour 赶场 | Phrases are 2 seconds shorter | timing play, universal |
| Cover Charge 入场费 | Pay 1 coin each phrase | coin hoarders (regressive: hits poor builds — keep in mild pool only) |

Bent-not-bricked verdicts (round 18, deaths among wall reachers): healthy
range 30-60%; Unplugged remains the heaviest (54-87%) and near-execution
levels are tolerated only on the S10 finale.

## Universal-routine toolkit (user framework, 2026-08)

Three medicines for three diseases: **direct nerf** (prefer mechanism over
numbers) when a card is top in every build and stage — scarcity would just
make it a lottery; **probability control** when the card's power is the
fantasy and scales with the build — reliability, not strength, is the
disease; **pricing** when the card's value differs per build — price asks
"worth it to YOU?", but is only a toll on universally-good cards and is
regressive when incomes differ. Fourth tool: **boss-face rotation tax** for
combos whose parts are individually healthy. Applied: Neon Sign -> mechanism
nerf (post-mult channel), Mirror -> price 11 + pool dilution, Encore core ->
the No-Repeats modifier (08).

## Calibration (tools/sim.gd, 2026-08, 8×1000 runs/round)

Chips×mult round (2026-08-05, 用户拍板 second pass on the same feedback):
score = (chips + Σchip-mods) × 牌型mult × target mult × (1+Σ%) + Σbonus —
each hand is now (chips, mult) Balatro-style (table in design/cards.md), the
pattern mult seeds the chain and targets stack onto it, so rare hands scale
WITH jokers. Phrase clock flattened to 9s (bot squeeze: 2 paid discards per
phrase everywhere). SECTION_TARGETS recalibrated in 4 rounds — old targets
left mid-game toothless (twin 25.2%, only faces killed), round-2 overshoot
crushed the floors (stair 0.2%, pure wolf S2-S6 bleed-out), converged at
[160,280,600,850,1200,1600,2000,2400,2800,3200,3600,4200]: twin 9.7% /
triplet 9.0% / anytarget 8.3% / mono 3.1% / wolfpivot 3.3% (50% pivot) /
stair 0.7% / random 0% — the sealed 12-section difficulty profile
reproduced under the new formula, with the pattern archetype (triplet)
keeping its playtest buff (6.4→9.0). Walls stay 30-60%; execution-grade
only S12-unplugged-vs-twin (85%) and S9-rotation-vs-vow-wolf (88%, pivot
escape 69%). Beliefs updated: score_prior 180, counterfactual_tv
twin 2.6 / triplet 2.2 / mono 1.55 / stair 1.5 / lonewolf 1.7.

Human-playtest round (2026-08-05, first live feedback): "凑到 full house 不如独狼"
— confirmed by arithmetic: FH off-target 160+57=217 < lonewolf junk 56×4=224.
Root cause was the BASE_SCORE slope, not the target mults: rank_sum flattened
the ladder so patterns only ever paid THROUGH a matching target. Fix: steepen
trips-and-above (70/100/120/160/220 → 110/170/200/320/550, SF 900, RF 1400;
two pair 45→50, bottom held so the already-strong pair family gains ~nothing).
Bot beliefs now DERIVE plan values from Pattern.BASE_SCORE (`Bot._pat_val`, no
more hand-copied 160/140/195); counterfactual_tv rescaled to the new outputs
(stair 1.35 / mono 1.4 / triplet 1.8). One round converged, SECTION_TARGETS
untouched: twin 10.2→14.7% (at the ~15% intent ceiling), triplet 6.4→10.9%,
mono 3.7→7.4%, stair 0.8→1.6%, lonewolf 0.2→0.7% with pivot usage 32→52%
(the re-flag arc strengthened — pattern targets are now worth flying to),
anytarget 8.4→11.6%, random 0%. Deaths still cluster on walls (twin S9 30% /
S12 25%); execution-grade faces only hit the vow-keeping pure wolf on S12
(98% unplugged — wolfpivot escapes at 81%). Archetype spread compressed from
51× (0.2–10.2) to ~9× (1.6–14.7): assembling a rare hand now beats junk
archetypes even off-target, which was the entire complaint.

Difficulty intent (user-locked): most runs die, clearing is an achievement —
build bot ~15% full clear, greedy <5%, random ≈0%. Round-4 state (tiered
target pricing + Lone Wolf A/K gate): baseline(no jokers) dies by S4 with 0%
clear; twin 15.8%, lonewolf 6.7%, mono 4.4%, triplet 0.8%, stair 0.0%;
greedy 6.6%, random 1.3%.
`SECTION_TARGETS` steepened to [150,280,450,680,950,1300,1750,2300,3000,3900].

Rescue batch rounds (19-20): Shortcut / Four Fingers / Two-Tone joined the
pool and found their homes unprompted (stair's winning kits carry
fourfingers+shortcut, mono's top kit is mirror+neonsign+twotone). Teaching
act re-softened (chase archetypes were dying at S2 before the first support
shop even opened). Round-20 state: twin 7.9%, anytarget 5.7%, mono 4.3%,
triplet 5.0%, stair 1.3%, wolfpivot 2.3%. Numeric tuning STOPS here by
decision: bots cannot re-shelf supports against a previewed face (humans
will), so wall deaths are a pessimistic bound — the final trim belongs to
human playtests, not another bot round.

Boss-face rounds (16-18): faces went live on the walls. Round 16 verdicts:
Unplugged-as-silence and norepeat-vs-wolf were executions, not taxes; walls
were double-charging (hot base target + face). Surgery: Unplugged -> half
power, No Repeats exempts High Card, wall base targets stepped back (the
face IS the wall), and the run's three faces are rolled up front and
previewed one section ahead. Round 18: twin 7.4%, wolfpivot 2.0% (26% pivot
usage), wolf S5-norepeat deaths 68%->16%. Overall level intentionally tight —
the next Support batch (Shortcut-type rescues) adds player power, so the
final level pass waits for it.

Post-mult formula + pivot arc (rounds 13-15): the flat empire collapsed on
contact (twin 48.4% -> ~9%), pure Lone Wolf hit 0% — it is now genuinely an
early-economy archetype that must re-flag (pivot usage 25% in the wolfpivot
cohort once the window opened after S3 and pivot valuation switched to
counterfactual chase-rate tables). Teaching act softened after S2 briefly
became a hidden wall for chase archetypes. Known remaining distortions:
S8 over-lethal for twin, mono/stair bots over-chase from S2 (fidelity), wolf
pivot timing tight. Final leveling deliberately deferred to the boss-modifier
pass — modifiers take the last cut at the walls.

Setlist pacing + routine harvest (rounds 11-12): SECTION_TARGETS reshaped to
the three-act setlist (walls at S5/S8/S10, breather S6), phrase_duration()
curve live (13s teaching -> 12s -> 11s squeeze), and the sim now reports
死亡分布 (deaths-per-section) as the primary calibration lens plus a
**routine harvester** (winning kits + per-support clear lift). Round-12
pre-modifier state: twin 48.4% (deaths 50% at S9/S10 — walls work),
lonewolf 22.5%, triplet 17.5%, mono 8.3%, stair 2.8% (uniform-attrition
anti-pattern), anytarget 30.8%. Version answer harvested: **Mirror +
Neon Sign core in every winning kit** (twin+encore+mirror+neonsign ×190).
Top-build rates deliberately left high: the S5/S8/S10 rule modifiers (08)
are designed against exactly these routines and will take the final cut —
last calibration pass happens with modifiers + playbook bots. Lift numbers
are correlational, not causal (weak runs buy cheap fillers).

Player-model upgrades (rounds 9-10): the bots were rebuilt twice on user
direction — (9) adaptive play: chase whichever big hand is closest, weighted
by the target's payoff; (10) EV drafting: no taste tables, every candidate is
priced by the run's own measured behavior (discard rate, repeat rate, target
trigger rate, phrases left) as score-per-coin. Each upgrade lifted clear
rates dramatically (twin 13.9% -> 25.3% -> 44.4%; triplet resurrected
0.6% -> 15.3%; lonewolf's EV-drafted kit — Encore + Tip Jar + Mirror —
reached 19.4%). Calibration conclusions expire with bot fidelity: rerun the
whole suite after every player-model change. Anchor redefinition pending
user decision.

Economy calibration (rounds 5-8): pricing alone broke the poor builds
(twin 15.8% → 2.4% — build bots live at 2-3 ◆ and could never buy); adding a
+4 clear wage overshot (twin 25%) because the replace flow keeps builds
improving S5-S10; wage 3 + steeper late targets
([...,1350,1900,2600,3500,4600]) converged: twin 13.9%, greedy 4.9%,
random 0.5%, mono 3.6%, lonewolf 3.4%, triplet 0.6%, stair 0.0%.

Structural findings:
- A fixed 5-card hand makes pattern families wildly unequal to chase
  (pair 55% / flush ~18% / trips ~12% / straight ~7%). Target multipliers are
  priced against that, but stair/triplet cannot be fixed by numbers alone —
  they need card-flow help (wilds already help; a Shortcut-style rule support
  is the designed fix, candidate for the next support batch).
- Lone Wolf's original "made hands ×1" had no tension here (auto-best +
  discard-refill made High Card 91% reproducible). The zero-discard condition
  restores the tradeoff and turns it into the economy-hoarding build.
- Economy has no sink besides discards (greedy bots bank 80+ coins) —
  draft pricing is the 04 agenda item.
- Caveat: chase rates are bot-policy-dependent; re-validate against human
  telemetry once playtests exist.


---

## 主角

### Definition

A character is a Run-long global rule extracted from a Balatro-style defining Joker.

Character:

- is selected before Run
- stays active for the entire Run
- changes the pressure model or Phrase rhythm
- does not define the target poker pattern
- is a permanent account asset

### Hierarchy

```text
Character
defines how pressure is experienced
→ Target Joker
defines what answer is valuable
→ Support Jokers
define how to reach the answer
```

### Initial characters

#### Punk

**Rule**

> After 2 seconds, the player may lock early. Each unused second gives +20% score.

**Rhythm**

decisive, off-beat, active release

**Skill**

knowing when the current result is already enough

---

#### Lo-fi Producer

**Rule**

> If Final Best is not worse than Initial Best, Flow +1. Each stack gives +12%, max 5. Regression resets Flow.

**Rhythm**

stable, continuous, low volatility

**Skill**

maintaining consistency instead of chasing every extreme

---

#### Gambler

**Rule**

> Each paid draw gives +15% this Phrase. If Final Best does not improve, all bonus is lost.

**Rhythm**

high risk, escalating pressure

**Skill**

distinguishing useful pursuit from sunk-cost pursuit

---

#### Sampler

**Rule**

> At Phrase end, choose one rank from the best five. Next Phrase initial hand guarantees one card of that rank.

**Rhythm**

repetition, variation, cross-Phrase memory

**Skill**

building around a recurring motif

### Candidate characters

#### Conductor

> Every four Phrases form a group; 20% of the first three scores is released on the fourth.

#### Minimalist

> Hand capacity is exactly five; all score ×1.5.

#### Collector

> Cache +2; all paid draws cost +1.

### Character design rules

- one sentence must explain the rule
- must change how pressure is experienced
- must support several Target Jokers
- cannot be a direct permanent power advantage
- should remain competitive without becoming mandatory

---

## 附:从 `CLAUDE.md` 迁来的推导与实测(2026-08-09)

> 逐字迁移,未压缩。

### Target 倍率两层原则的数字(2026-08-07 用户批 A 案,已实装)

  牌型倍率已经按 `P(≥牌型)` 定过价, Target 再按稀有度分层就是**同一件事收两次费**:
  葫芦在牌型层拿 6(它是 P(≥)=20.7% 的天花板)、三连音层再拿 ×8 = **48 倍**,
  一拍 4080 分, 三连音因此独走到 4.09×(次名 2.93×)。

**② 族间按覆盖面标定**(接 `../CLAUDE.md` 那一行「因为**牌型层管「达到某牌型多难」,」):

  管不了「这个流派的射程覆盖多少拍」**:双子覆盖对子+两对 = **96%** 的拍,
  阶梯覆盖顺子+同花顺 = **20%**。所以按各自「超出中性基准的部分」反推倍率。
  终值 **双子 ×6 / 三连音 ×5 / 单色 ×7 / 阶梯 ×10**(独狼另论, 见下)。
  实测极差 **1.90× → 1.13×**(阶梯 731 / 双子 730 / 单色 724 / 三连音 820, 中性基准 262)。

  **⚑ 2026-08-12 重锚:覆盖面必须拿真人量,bot 量出来的等值是假的。**
  用户试玩后点名「加分条件的难度没有对应到倍率」。三重证据闭合:
  ① 真人 Tape(11 局有效):双子触发 71% / 单色 16.7% / 三连音 8.3% / 阶梯≈0
  —— 真人牌型分布里顺子只有 **1.9%**(bot 20%),同花 7.4%,对子+两对 64%。
  bot 会追牌,人追不动 = 校准手册那条「流派强弱跟着玩家水平变」。
  ② bot 仿真在当前 meta(39 支援/24 脸/4 段墙)下也已崩:通关率
  双子 27.0% / 单色 8.7% / 三连音 8.0% / 阶梯 4.8%,A 案的 1.13× 极差成了 5.6×。
  ③ 两条独立的真人等值推算(单色、三连音各自反推)都收敛在 ×9.7。
  **新终值:双子 ×6(锚,不动)/ 单色 ×10 / 三连音 ×10 / 阶梯 ×13**。
  锚定双子 = 难度不受扰(用户:「难度控的蛮好」,而双子是当前主流选择)。
  阶梯按真人覆盖面(1.9%)等值算出来是天文数字 —— **数字治不了低频答案**,
  它的成立注定依赖近道/四指那套救援规则牌,×13 是可读性上限内的诚实补偿,
  **待用户实战回评**。万花筒 ×4(真人拍均 702 vs 双子 762,已然齐平)、
  速弹 ×4(真人 0 局持有,无数据)、独狼(经济轴)均不动,列入观察。

  ⚠ 又一次栽在硬抄:这一改让 5 条抄死旧倍率的断言变红, 已全部改成从 jokers.json 推导
  (`tests/runner.gd::_tmult`)。**平衡要反复调, 断言抄死等于给每次调参加一道返工。**

### ⚑⚑ 第三次重锚(2026-08-14):标定输入换成**组合命中率**,顺子/同花翻转

**用户拍板**(先验层落地当天):定价用的「难」= **命中 Target 条件的组合概率**,
不是实测频率(理由三条,已写进 `../CLAUDE.md` Target 两层原则的 ③)。

`tools/prior.gd` 实测(N=20 万,8 张 iid、零策略、8 选 5 取最优;
**与牌型分布逐项吻合** —— 双子 = 对子 39.66 + 两对 25.98 = 65.64,是一条自检):

| Target | 覆盖 | **组合命中率** | 旧值(真人锚) | **新值** |
|---|---|---:|---:|---:|
| 双子 | 对子+两对 | 65.64% | ×6 | **×6**(锚,不动) |
| 三连音 | 三条+葫芦+四条 | 11.46% | ×10 | **×10**(正好落回现值) |
| **阶梯** | 顺子+同花顺 | **8.99%** | ×13 | **×11** ↓ |
| **单色** | 同花+同花顺 | **6.88%** | ×10 | **×12** ↑ |

压缩幂次 **0.3**,依据 = 「保住双子 ×6 这个锚,且三连音落回现值」——
所以四个数里**只有两个真的动了**,而动的那两个**互换了高低**。

**⚑ 为什么翻转,以及为什么这比数字本身重要:**

| | 顺子 | 同花 | 谁更难 |
|---|---:|---:|---|
| 牌堆给不给(组合) | 8.89% | 6.79% | **同花难** |
| 真人打出来(11 局 Tape) | **1.9%** | 7.4% | 顺子难 4 倍 |

同花两个口径几乎一样(6.8 → 7.4%),**顺子却从 8.9% 掉到 1.9%** ——
**真人连"白给的顺子"都没打出来**。所以那 7 个百分点的落差**不是难度**,
是**没认出来 / 来不及凑**。

⇒ **旧的 ×13 补的不是「顺子难」,是「玩家看不见顺子」。**
而上一节自己就写下过怀疑(「数字治不了低频答案」「×13 是**可读性上限内的诚实补偿,
待用户实战回评**」)—— **现在有第二把尺子,那句怀疑被证实了。**

⚠ **对症的药也在先验层那张表上**:近道把顺子从 8.89% 抬到 **27.5%**(+18.57pp)、
四指抬到 26.5%。**概率放大器治得了低频,倍率治不了** —— 与 numbers.md §2 那条一致。
⚠ 而且旧值有一个**会自己长大的**毛病:装了近道之后顺子 27.5% 还拿 ×13,那才是真超模。

**同日连带**:**双色调 uncommon → rare**。先验实测它把同花从 6.79% 抬到 **66.3%(9.8×)**,
而同价位的近道/四指只有 3.1× / 3.0× —— **同一稀有度,效力差三倍以上**。
不削效果(按颜色算同花没有"削一半"的形状,能调的只有稀有度与价钱),
改稀有度自动带来两件事:价格 6◆ → 9◆、货架权重 25 → 5。
⚠ 真正的理由不是数值超标是**机制超标**:同花的 ×5 是按"它稀有"定的,
而这张卡让同花不再稀有,**倍率却还在**。

⚠ **两个没量过的结构事实,一并记下**(同一批数据):
**挤出** —— 双色调的 Δ顺子族是 **−6.10pp**(同花 mult 5 吃掉了本来打顺子 mult 4 的拍),
**规则牌不是纯加法**;**超可加** —— 近道+四指叠加 +48.64pp > 各自之和 36.18pp(**多 34%**),
**规则牌之间有协同,不能各自独立定价**。

#### 过门读数(SOP 第 5 步)· **三态分解**,1000 局/队列 · 共用随机数

单跑一次 before/after 只能看到净效果,而净效果里混着两个改动。所以拆成三态:
**A** = 改动前 · **C** = 只改倍率(twotone 仍 uncommon)· **B** = 最终。

| 队列 | A | C | B | **倍率效应 C−A** | **双色调稀有度效应 B−C** |
|---|---:|---:|---:|---:|---:|
| twin | 47.3% | 47.3% | 45.1% | +0.0 | **−2.2** |
| stair | 16.3% | 12.5% | 12.3% | **−3.8** | −0.2 |
| mono | 31.6% | 33.3% | 31.0% | **+1.7** | **−2.3** |
| triplet | 38.3% | 38.3% | 38.2% | +0.0 | −0.1 |
| wolfpivot | 19.6% | 19.6% | 17.2% | +0.0 | **−2.4** |
| anytarget | 37.5% | 38.3% | 38.3% | +0.8 | +0.0 |
| baseline / lonewolf | 0.0% | 0.0% | 0.0% | +0.0 | +0.0 |
| random | 1.1% | 1.1% | 0.7% | +0.0 | −0.4 |

**倍率那一列零外溢** —— 该动的动了(stair −3.8 / mono +1.7),其余六个队列**逐位不变**。
`|漂移| > 3pt` 的只有 stair,**而那就是改动本身**(×13→×11 降 15%)。

⚑⚑ **真正的发现在最后一列:双色调升 rare 让三个互不相干的队列各掉 2.2–2.4pt** ——
而 `twin`(对子流派)和 `wolfpivot` **根本不吃同花**。
⇒ **它不是同花流派的卡,它是所有流派的通用首选**(同花 mult 5 远高于对子 mult 2,
任何构筑打出同花都赚)。**这比 9.8× 那个数更强地证明了它不配 uncommon。**

⚠ **连带解释了单色的反常**:mono 倍率升 20% 却净 −0.6pt ——
**+1.7(倍率)被 −2.3(买不到双色调)吃掉了**。
按铁律「不许为了让模型好看而改内容」,**不补偿** —— 净 −0.6 在噪声内,
而两个改动各自都是独立正确的。
⚠ 且这是 **bot 读数**,而 bot 选切法约等于随机(`solving.md §8.2b`);真人未必同此形状。

### roster 现状与批 2(救援规则牌)

- **小丑牌 roster 已实装**(Target 5 + Support 18,普通7/罕见6/稀有5,全被动;批 2 = 近道/四指/双色调
  三张救援规则牌,规则挂 `Deck.rules`、`Pattern` 全链路读取):

### Target 回池:起因、三条代价、实装结果

  起因:用户问「为什么要单独给这张卡概率」——旧设计让同一件事(这张牌多久出现)
  有**两套平行机制**:货架走 `draft_rarity_weights` 推导,换旗走一个凭空的 `chance`。
  三条代价:① `from_section` 是**绝对段号**,正是「改段数会静默破坏三处表」里的一条地雷,
  回池后这个键直接消失;② 违反「规则只准出现在动作空间」——卡类专属掷点是嵌进内容系统的规则;
  ③ **不随新卡扩展**(后面有大量新卡,每个卡类都配一个 `chance` 就失控了)。
  回池后出现率变成**池子组成的推论**:5 张 Target 若入「稀有」档, 单货架位 ≈2.9%、
  一个商店(3 位)≈8.5%、一局 6 个合格商店期望 ≈0.5 次 —— 比旧的 35%/商店
  (真机一局期望 **2.1-2.5 次**,用户点名「太高了」)低一个量级,且**是算出来的不是拍的**。
  **实装结果**:5 张 Target 已填 `rarity: "rare"`;`target_swap{price,chance,from_section}`
  连同 `GameConfig.TARGET_SWAP_*` 三个常量、bot/shop 的两段特判分支**整体删除**;
  价格走同一张价目表(首张仍免费, 之后 = 稀有档 **9◆**, 原专属价是 8◆)。

**回归**(接 bot 侧那条门:`cfg.target` 强制的队列不许换旗,除非 `cfg.pivot`):

  让 bot 自己换掉就没了。回归:测试 367 全绿 + flow_probe 0 违规(112 次段中商店)。

  ⚠ 踩坑记档:`Economy.joker_price(j)` **少传 `has_target` 会把 Target 算成免费**——
  Target 进了同一个货架池之后, support 的比价循环必须显式跳过它, 否则白送。
  这也顺手让「Target 之间该不该有稀有度差异」第一次成为可表达的设计维度。

---

## 验证方案

| 验什么 | 怎么验 | 状态 |
|---|---|---|
| **卡面 ≤7 词** | `tests/runner.gd` 断言(1.5 秒读懂) | ✅ |
| **钩子契约** | `apply/on_acquire/on_discard/on_swap/on_phrase_end/on_section_end` 逐个测 | ✅ |
| **Target 族内一致** | 同一张 Target 对它覆盖的全部牌型给**同一个**倍率 —— 结构契约,测试锁着 | ✅ |
| **倍率不手抄** | 断言从 `jokers.json` 推导(`tests/runner.gd::_tmult`) | ✅ |
| **零挂机成长** | 成长/重置只挂显式动作(弃牌/时机),**绝不挂结算牌型内容** | ✅ 铁律 |
| **每张牌声明 `proof` 通路** | `jokers.json` 必填 + `db.gd` 值受限 + 逐张断言 | ✅ 2026-08-09 |
| **求解器看得见它** | 配对 A/B:装它 vs 不装它,分差必须显著(`tools/kit.gd`) | 🔨 建设中 |

### ⚠⚠ 缺的那道门是最重要的一道

脸有覆盖自证(`gate.sh <face_id>`),**小丑牌没有**。
一张新小丑牌同样可能「在游戏里生效、在模型里是空气」——
比如它的触发条件 `Settle` 根本不读。

而**小丑牌是分数的大头**:`tools/coin.gd` 实测整个构筑值 **4.2 倍**
(有商店 18654 / 无商店 4410)。**这个门比脸的门更重要。**

见 [`capability.md §5`](capability.md) 与 [`../TODO.md`](../TODO.md)。

### `proof` 通路(2026-08-09 定,`jokers.json` 必填)

⚑ **通路是按「用什么仪器证明」分的,不是按机制分的** —— 和脸的 `proof` 同一条原则。

| 通路 | 仪器 | 谁走 | 为什么必须单独一条 |
|---|---|---|---|
| `score` | 规则 bot 配对 A/B,**关商店** | 16 张 | 效果直接改分,便宜的证明用便宜的方法 |
| `solver` | **完美玩家**配对 A/B | `shortcut` `fourfingers` `twotone` `wildcard` | 它们改 `Deck.rules` 或牌堆组成,而**规则 bot 未必会去用新规则** —— 脸那边 `freshsheet` 两种 bot 量出的**符号是反的**(见 `tools/gate.gd::_run_solver`) |
| `coin` | 金币臂 + **行为臂** | `lonewolf` `tipjar` `interest` | 只给钱不给分,**在分数臂里按定义恒等于 0**;拿分数验只会得出「没接上」,与 `raisedbar` 同形。行为臂证明钱真的变成了购买力 —— **证明要落在做决定的那条路径上,不是它的定义上** |

⚠ **商店必须关掉**:开着商店两臂会买到不同的牌,差值里混进抽卡运气,配对就白配了。
卡要**直接装进槽位**并调 `Joker.on_acquire(deck)` —— `deck_rule` 与 `wilds` **全在那里生效**,
漏调等于那四张卡的效果根本不存在,而门会报「没接上」(那是门自己的 bug)。

⚠ **基准臂 = 它需要的前置装好、但它自己不装。** 现役里 `mirror` 是唯一有前置的:
它复制 Target 的一半,没有 Target 时恒等于 0,基准臂必须也装一张 Target。

⚠ **量不到有三种可能,门必须报触发率来分辨**:
① 没接进模型 · ② 接上了但**条件没发生**(`discards_eq: 0` / `same_as_prev` / `last_phrase`
这类依赖玩家行为的谓词,规则 bot 的打法可能让它几乎不触发)· ③ 接上了但效果本来就微不足道。
⚠ `report.gd::track_triggers` 数的是「结算弹了 popup 的次数」,
**对 `solver` 通路那四张恒为 0**(它们没有 `effects`)—— 那是仪器的盲区,不是卡没触发。

### 加一张新牌时按顺序问三个问题

1. **它改的是七类规则里的哪一类?**(答不上来 = 可能属于第 7 类「改结构」,**停下来讨论**)
2. **现有词汇表达得了吗?** 表达不了 → 加 param / DSL 操作码,走 `_FACE_PARAMS` 那道强制门
3. **求解器看得见吗?** 1/2/3/5 类自动看见;**4/6 类要先确认缺口修没修**

⚠ 第 3 问答错的代价是**静默**的:模型给出一个自洽但错误的价格,目标分照着它算。
**这个项目已经因此栽过五次。**

### ⚑ bonus 族重定价:条件概率 × 数额(2026-08-12,用户点名「现在最大的问题」)

**病灶**:bonus 族(乘后落地)里,无条件的灯牌(+80,触发 100%)是全族每拍期望的
**天花板**,所有条件卡的期望都被压死 —— 回响 80×11% ≈ 9、全员 150×0%、排练 150×0%。
条件概率从未参与定价:无条件卡严格优于一切条件卡,「加分条件的难度没有对应到数额」。

**仪器**(两台互证,咬合良好):真人 Tape 11 局的持有期 fired 率 × bot 仿真
support trigger%(尾声 54/70、变奏 71/65、彩虹 25/23、死卡两边同 0-5%)。

**定价原则**:族内把「打得好时的每拍期望(触发% × 数额)」对齐到 **40-50 带**,
无条件卡降为**保底**而不是天花板。灯牌 80→60,其余按各自触发率反推:

| 卡 | 触发(人/bot%) | 旧 | 新 | 新期望 |
|---|---|---|---|---|
| 灯牌 | 100 | 80 | **60** | 60(保底) |
| 尾声 | 54/70 | 70 | **80** | ~46 |
| 变奏 | 71/65 | 50 | **65** | ~45 |
| 回响 | 11/39 | 80 | **160** | ~40(与禁回/炒冷饭脸的冲突已计价) |
| 彩虹 | 25/23 | 150 | **180** | ~43 |
| 清流 | —/33 | 60 | **130** | ~43 |
| 周转 | 73/64(×弃牌数) | 20/张 | **25/张** | ~35-45 |
| 和弦 | —/9(build-around) | 120 | **140** | 建成后 140/拍持续 |
| 全员 | 0/10 | 150 | **240** | 彩票位 ~24 |
| 伴唱 | 0/1 | 150 | **200** | ⚠ 复审名单 |
| 排练 | 0/5 | 150 | **200** | ⚠ 复审名单 |

**⚠ 结构复审名单(数字治不了,待用户裁决)**——行为答案三死法里的「低频/负答案」:
- **快闪**:kit 里活得很好(开局装 = S1 六拍 25% 触发 +1200),但**真实商店最早
  S1 过半才能买**,买到手最多吃 3 拍 → bot 2685 局实测触发 0%。窗口 × 商店时机
  的结构错位,加数额是假修。候选方向:改「前 N 拍」滚动窗口 / 首店必见 / 删。
- **伴唱**(缓存三张全人头,bot 1%/人 0%)、**排练**(缓存三连号,5%/0%):
  建缓存的机会成本吃掉了收益,没人为它们建。候选方向:条件放宽(两张即触发、
  数额减半)/ 改成长型 / 删。
- 本轮**未动**:bonus_pct 族(12-30% 期望带内相对均衡)、chips/additive 族
  (build-around,吃倍率,curve 字段已表达前后期定位)、coins 族(经济轴)。
- 测试侧:9 条手抄数额的断言全部改为 `_bonus()` 推导(同 `_tmult` 的教训,
  这是第二次踩「断言抄死」——以后新支援牌的断言一律走推导)。

### ⚑ 流派批第一波(2026-08-12,archetypes.md 落地;经过记档)

起因 = 用户定向:「常见卡牌要凑多个加成方案才有机会破关,稀有卡牌要凑增加概率的」
→ 流派图谱([archetypes.md](archetypes.md))→ 用户拍板「研究完了就开始做」。
本波只做轻手术件(门都现成),重手术全部延期挂 TODO。

**增 8**(定价按 numbers.md 三轴代公式,锚写在卡旁;kit 读数 = bot 尺度下界):

| 卡 | 稀有/curve | 定价推导 | kit(Δ/局, z, 触发) |
|---|---|---|---|
| 对唱 duo +10c | 普/burst | 含对 p̂≈0.72,10c×链 ≈ 地板 50 | +337, 35.5, 47% |
| 二重唱 duet +25% | 罕/burst | 可控式 E=87.6 → 25.3% 取整 | +493, 31.6, 47% |
| 三和弦 triad +25c | 普/burst | 本线 p̂≈0.35 → ~65,故意 sleeper(C3) | +368, 16.8, 11% |
| 三重 triplebill +60% | 罕/burst | p̂=0.35 代式 → 62% 取 60 | +620, 16.3, 11% |
| 后台 backer +1c/2◆ | 普/floating | 持币 17.7◆ → ~59,带边;⚠ 观察铁粉同形 | +1115, 35.3, 100% |
| 替补 bench 顶牌计c | 罕/floating | 自然 9.6 → ~71,建成(囤 K/A)~100 | +762, 55.9, 100% |
| 包厢 boxseats ×1.2/人头 | 稀/floating | build-around 税式:1.47 脸打平 141 | +597, 20.2, 54% |
| 修剪 trim 规则 | 稀/fixed | 概率放大器,Δp 两态封锁不定价(宪法 §1) | solver 臂 |

**contains 语义零词汇**:顺/同花五张点数互异 → `kind_in[PAIR..FOUR_KIND]` 就是「含对子」,
葫芦双吃对子件+三条件(原作 Duo+Trio 的直译),结构契约进了测试。

**删 2**:快闪(结构死卡,复审两轮)、伴唱(包厢上位替代 —— 同读缓存人头,
per-face 缩放替代 all-or-nothing)。素材与 manifest 按 wrecker 先例保留,只撤出 json。
**排练保留**:trio 回池前它是阶梯线唯一缓存件,删了概率线更瘸。

**改 2**:四指/双色调 rare→uncommon(概率线曝光,shortcut 的「轻规则」先例;
规则牌 12 局零购买的三措施之一,另两条 = trim 实装 ✓ + 点唱机复活【延期】)。

**新词汇入账**(D1 门):操作码 `additive_cache_top`(替补)· 计数源 `per: "cache_face"`
(包厢)· acquire 键 `trim_low`(修剪,Deck 减牌手术,enable_wilds 的镜像)。
⚠ 顺手把 acquire 内键 / deck_rule 值 / per 值三张白名单补进 db.gd ——
之前不校验,拼错 = 规则牌静默不生效,「栽过五次」的形状。

### ⚑ 流派批第二波:shelf 三件套 + 商店仪器臂(2026-08-12 深夜)

**增 3(货架结构卡,新 proof 通路 `shop`)**:

| 卡 | 稀有 | shelf 键 | kit 证物(零基线) |
|---|---|---|---|
| 联票 doublebill 9◆ | 稀/fixed | shelf_slots 4 + buy_limit 2 | 双购店 +1.2/局, z=25.5 |
| 赞助 sponsor 6◆ | 罕/fixed | price_delta −1(地板 1◆,回收不吃折扣) | 实收折扣 +3.4◆/局, z=24.4 |
| 点唱机 jukebox 9◆ | 稀/fixed | rule_guaranteed(规则牌=带 acquire 键) | 含规则牌店率 18%→98%, z=61.8 |

概率线曝光三措施至此**全部落地**(降稀有度 ✓ 修剪 ✓ 点唱机 ✓)。
点唱机从 atlas 落选复活的理由 = 流派层视角(archetypes.md §3.8:它是 Oops! All 6s
的 Sync5 形态 —— 放大的是「买得到 Δp」的概率)。

**机制**:货架 API 收口在 `Joker.slots_*` 五个静态口(shelf_size/buy_limit/price_delta/
rule_guaranteed + 既有 target 两口),**游戏侧与 bot 侧消费同一个口**;折扣价收口
`Economy.shelf_price`(展示=成交,replace 流同源)。联票的续买 = 同一货架摘牌重估,
不重掷(重掷就成了免费刷新);bot 侧同构,换旗不占续买额度。

**⚠ 仪器教训(第一版证物双双阵亡,记档)**:联票用「每局成交数↑」、赞助用「均价↓」
—— 都被**钉槽混杂**吃掉(kit 实验臂钉死一个槽 → 少装一张卡,效应同量级:联票
buys 差恰好 +0.0;赞助花费 −5.9◆ z=−15 证明折扣活着,均价却只动 0.2)。
换成**零基线机械读数**(双购店数/实收折扣,无卡在手时≈0)一次过。
**判据:货架证物必须选「没这张卡就几乎不可能发生」的量,行为量会被槽位效应淹掉**
—— 与 coin 行为臂 2026-08-09「总分→花费」的换尺是同一课的两次上课。

**顺手结案**:外部审查 V2(shelf 内键无校验)—— `_SHELF_KEYS` 白名单入 db.gd;
`draft_sheet` 新增 `_shot_draft_four` 联票四卡位验收态(card_w_4=156 窄版布局,
data/ui.json 两个新键)。

### ⚑ 引擎波次·子波 1(2026-08-13):动作内容信号 8 张

用户「开始」后的第一批。选这 8 张的判据 = **只碰结算侧信号,不碰时钟与商店管线**
(那两块分别是子波 2/3),所以门全是现成的。

| 卡 | 稀有/curve | 效果 | 新信号 |
|---|---|---|---|
| 定格 freeze | 罕/burst | 早锁 → **下一拍** +30% | `pulse_on_early_finish` 脉冲计数器 |
| 静物 stilllife | 普/burst | 本拍零交换 +60 | `swaps_eq` |
| 串场 segue | 普/burst | 换入且成牌 +40/张 | `per: swapped_scoring` |
| ~~断舍离 declutter~~ | 罕/burst | 一次弃五张 +50% | `discard_batch_gte` |
| 让位 stageexit | 普/burst | 每弃人头 +30 | `per: face_discard` |
| ~~打包 doggybag~~ | 普/burst | 段分达两倍 +3◆ | `section_doubled` |
| 分成 royalty | 罕/floating | 牌型金币 ×2 | 操作码 `coins_factor` |
| 穷开心 skint | 稀/fixed | 金币上限 5,常驻 ×1.3 | **`hold` 新键族** `coin_cap` |

**入池 6 张,2 张挂仪器债**(❌ 撤出 json,机制与谓词保留 —— wrecker/trio 先例):
- **断舍离**:bot 一拍最多弃 `beat_discards()` 2-3 张,「一次弃五张」**结构上不可能**
  (kit 触发 0%)。欠的是 bot 侧的弃牌流策略块 —— 与 wrecker 同一笔债。
- **打包**:条件「段分达目标两倍」依赖**整套构筑的输出**,而 kit 是**单卡臂**
  (基准只装前置不装构筑),段分天生打不到 2×目标;加 PREREQ 试过,触发仍 0%。
  欠的是一条「构筑臂」。⚠ 这两张**不是设计有问题,是仪器量不到** ——
  按铁律「不许为了让门变绿去改卡」,卡撤出、债记下。

**kit 读数(入池 6 张)**:静物 +303 z=28.6(触发 21%)· 串场 +1050 z=83.4(79%)·
定格 +301 z=22.5(25%)· 让位 +187 z=31.8(4.1% 走量级豁免)· 分成 +44.5◆ z=57.0(100%)·
穷开心 +1265 z=34.6(100%)。

**三条设计取舍(都会被将来的人问,先写下来)**:

1. **串场的「换入」= 经交换进手 且 不是开拍原牌**。只判前一半会被 bot 的
   试探性换回刷出幻影(它换过去再换回来),两个条件一起才是真换入 —— 契约在 t_phrase。
2. **打包用悲观口径**:读的是**结算开始时**的段分,本拍自己的分还在链上(循环依赖)。
   于是它奖励的是「超标后继续打」而不是「一击超标」,翻倍后的每拍持续付。
3. **穷开心的金币上限有两个口,缺一不可**:`Economy.grant` 卡住收入(四个入账点
   全部改走它)+ `Economy.cap_held` 在**装卡后**修剪存量。少了后者,卡面「上限 5」
   对一个已有 30◆ 的玩家就是假的 —— **D2 管的不只是词数,还有卡面不许说谎**。
   ⚠ 修剪必须在 `on_acquire` 之后:装之前读的是旧槽位,新卡的上限不在里面
   (替换流那一处我第一版就写错了位置,当场自查出来)。

**⚑ 顺带修好一个模型盲区(这批最有价值的副产品)**:
新信号 `swaps` / `discard_batch_max` / `faces_discarded` **求解器本来就算得出来**
(`splits()` 早就有 `need_swaps`,`best_discard` 手里就是被弃的那几张),只是从没写进 ctx
—— 于是静物/让位在求解器眼里恒等于「零交换、零人头」。接上后两张当场量到。
**判据升级:「求解器算得出来的量必须进 ctx」** —— 这是 jokers.md 第 3 问
(「求解器看得见吗」)的可执行版本。

**⚑ 判据从魔法数换成具名豁免表**:`t_draft` 那条「多数卡非零」原本是
`nonzero >= 总数 − 5`,而这一批一次就吃掉 4 格余量 —— **数字余量会被新卡悄悄吃光**。
改成 `SOLVER_BLIND` 具名表(逐张带理由,且反向锁「声明了却其实量得到」),
照的是脸那边 `weak_upper_bound` 的先例:**豁免必须是有意的,不能是漏掉的**。
现役 6 张,三类结构盲区:时间族 4(模型无时钟)· 前置族 1(mirror)·
动作空间族 1(declutter:求解器一拍只弃 ≤3 张未握牌,游戏允许整手 5 张 —— 归 S5)。

**校验层同批加锁**:`counters` 内键 / `hold` 内键两张白名单(接着 acquire/shelf/per
那四张)—— 计数器键拼错会让成长/衰减/脉冲**静默不走**,同一条纪律。

**⚑ 仪器侧的三个副产品(这批最值钱的部分,判据全部进了 LESSONS)**:

1. **bot 的试探性交换在污染动作计数** —— 每拍 15 次试探全都真调 `swap_with_cache`,
   于是「本拍零交换」在模型里永不成立(静物触发 0%)。修法 = `probe` 参数 +
   `commit_probe_swap()` 显式补记。**连带**:`swap_actions_used`/`action_count`/
   `action_track` 正是**单换/岔轨/限流**三张脸的判据 —— 那三张脸的实测强度里
   一直混着「bot 被自己的试探拖累」,是方向性高估。同款试探在 `tools/model.gd`
   也有一份,同批修(口径不许分叉)。
2. **求解器算得出来的量必须写进 ctx** —— `need_swaps` 与被弃的那几张,
   `tools/solver.gd` 本来就有,只是没交给结算。接上后静物/让位在 `Draft.card_value`
   里当场从 0 变成有值,**没改卡一个字**。
3. **两处判据从魔法数换成具名豁免表** —— `t_draft` 的 `SOLVER_BLIND`(求解盲区,
   6 张三类)与 `tools/kit.gd` 的 `WEAK_MAGNITUDE`(量级豁免,让位 1 张),
   都带反向锁。理由:这一批一次吃掉 4 格数字余量而门还是绿的。

**⚑ 第四个副产品:穷开心的估值臂漏了代价那一半(2026-08-13)**

它的 bot 估值臂第一版只写了「×1.3 的好处」,漏了「金币上限的代价」——
bot 因此 **100% 买它**(sim 实测持有率 100%),买完经济锁死在 5◆。
修法 = 代价按**没收的购买力**折算((会攒到的持币 − cap) × 折分率 × horizon 折现);
修完 bot 不买了,而卡照旧在池里给真人用。
**判据入册(LESSONS)**:新卡带代价时先问「代价落在哪个系统里」——
落在估值臂算不到的系统里,就必须显式折算进来,否则 bot 变成无脑吃亏的玩家,
而所有以 bot 为尺子的读数一起歪。

⚠⚠ **但我一度把 `gate.sh` 金币单调性哨兵的红灯归因给它 —— 那条因果链是错的。**
修完哨兵照旧红,翻出穷开心入池**之前**的读数一看:昨天 `+0.00 ✓`、今天 `−0.00 ❌`,
**效应量级两次都是零**,绿灯只取决于四舍五入的符号。哨兵在量一个 S9 早已裁定的
游戏事实(「钱从来不是约束」),不是在守护不变量。完整推导与两条新判据
(「修完必须验症状真的消失」/「一个符号随噪声翻转的判据不是判据」)在 LESSONS。

### ⚑ 引擎波次·子波 2(2026-08-13):计时族 3 张 + bot 时间信念数据化

| 卡 | 稀有/curve | 效果 | 新信号 | kit |
|---|---|---|---|---|
| 谢幕 curtain | 罕/burst | 最后 1 秒行动 +60% | 谓词 `acted_final` | +1147 z=31.8 触发 44% |
| 秒表 stopwatch | 罕/burst | 结算每剩 1 秒 +8% | `per: second_left`(连续量) | +644 z=42.5 触发 65% |
| 早弃 earlyout | 普/burst | 弃牌都在前 4 秒 +80 | 谓词 `early_discards` | +1338 z=79.3 触发 70% |

**时钟观测走 flags,不进 core**:`core/` 不含时钟是铁律,所以三个量与 late/early
同一条路 —— view 侧算好装进 `Beat.settle(flags)`,core 只是把读数放进 ctx。
弃牌时刻记在 `_notify_discard`(**所有成功弃牌的共同出口**,三条路径一处覆盖)。

**两条口径拍板**:
1. **谢幕与尾声是包含关系,不是互斥** —— 压到最后一秒同时点亮两张(窄窗口的溢价
   叠在宽窗口上)。测试锁了这条(pct 乘在链上、bonus 在乘法后加,顺序错了会红)。
2. **秒表的「剩余秒数」在没动过手的一拍记 0** —— 否则「整拍不操作」拿满额剩余,
   秒表就成了「什么都不做最赚」的挂机卡(A4)。同理早弃要求**弃过牌**才算。

**⚑ bot 时间旗数据化(本子波的重构点)**。旧版三宗罪,每条都咬过人:
① 概率写死在 `.gd` 里(违「数值在 data/」);② **只认 `finale`/`momentum` 两个卡名**
—— 每加一张时机卡就要改一次代码,而**忘了改不报错**,那张卡在模型里就是
「玩家从不为它调整打法」;③ `elif` 是**隐式优先级** —— 同时持有压哨卡与早锁卡时
只有前者生效,这条规则从没人写下来、也没人验证过它是不是想要的。
现在偏置表在 `sim.json ev.timing`,**多张取最大值、早/晚两轴独立**。
⚠ 这是**行为改动**:finale/momentum 的既有读数会移动(与 probe 修正同批解释)。
⚠ 表里是 **bot 的打法先验,不是真人** —— 真人早锁率实测 8%(bot 78%),
定价一律锚 Tape(numbers.md §1「p_bot ≫ p_人 → 定价锚真人」)。

**顺手修了一处卡面说谎**:`ui.json` 写「前 4 秒」而实现复用了早锁线(3.5s)。
给早弃配了**自己的旋钮** `early_discard_window: 4.0` —— 早锁问「你是不是不动了」、
早弃问「你的弃牌是不是都做完了」,概念不同,调一条不该连带另一条。
英文卡面也改成写实的 "All discards in first 4 seconds"(改这个值要连卡面一起改,
同数额章的纪律)。

**`SOLVER_BLIND` 第一次证明它的价值**:三张新卡全被它当场抓住(求解器没有时钟,
剩余秒数在推演里恒 0),逼我逐张声明理由。换作旧的「−5 魔法数」,
它们会**悄悄吃掉余量而门照旧绿** —— 这正是 08-13 立那张表时预言的场景。

### ⚑ 引擎波次·子波 3(2026-08-13):商店成长族 3 张 + 第七个钩子

| 卡 | 稀有/curve | 效果 | 计数器 | kit(计数器终值) |
|---|---|---|---|---|
| 淘碟 digger | 罕/growth | 每次刷新 +12 永久 | `on_reroll` | +0.8 z=12.7 |
| 收藏家 collector | 罕/growth | 每买一张 +15 永久 | `on_buy` | +4.5 z=55.5 |
| 转型 rebrand | 罕/growth | 每次换旗 +40% 永久 | `on_target_swap` | +1.1 z=54.5 |

**roster 到 60 张 —— 正是用户 2026-08-10 拍板的目标数。**

**开第七个钩子 `on_shop_event`(过 D1 门的理由)**:A4 要求成长只挂**有代价的动作**,
而商店动作(刷新付钱 / 买卡付钱 / 换旗丢掉旧旗)是**唯一一整片没有钩子覆盖的动作空间**
—— 既有六个钩子全在对局内。三张已定稿的卡都要它,且代价天然真实(钱),
不用另造一个人造成本。
**收口**:所有商店事件走 `Joker.notify_shop(slots, kind)` 一个静态口 ——
调用点天然分散(游戏侧编排器 3 处 + bot 侧 3 处,铁律「经济动作只发生在编排器」
决定了收不成一处),那就退一步**让形式统一到一行**,`grep notify_shop` 一眼数清两侧。
⚠ 两侧计数:reroll 1/1 · target_swap 1/1 · buy 游戏 2 / bot 3 ——
差异是结构性的(游戏侧一个调用点覆盖了 target/support 两条分支)。

**一条口径**:事件在**装卡之前**发 —— 否则刚买的这张会给自己记一次,
「每买 1 张 +15」凭空多出第一次(换旗同理,新旗不该给自己记)。测试锁了这条。

**⚠⚠ 三个仪器教训(这批我错了两次,都记下来)**:

1. **我把它们声明成 `score` 通路,并断言「开商店的臂量得到」—— 错的**。
   score 通路**关商店**(kit 文件头明写:开着商店两臂会买到不同的牌,抽卡运气混进配对),
   所以那条臂里根本没有商店事件,实测三张全部触发 0%。
   **判据:引用一条纪律之前先确认它说的是什么** —— 我引用的是自己读过的文件。
2. **正解 = 零基线机械证物**(与昨天 shelf 三件套同一条判据):证物 =
   **一局末那张卡的计数器终值**。没有这张卡就没有这个计数器 → 基准恒 0,混杂无处藏身。
   现有四条通路一条都量不到它们(score 关商店 / coin 量钱不量分 / shop 原有三种证物
   都是货架读数),所以给 `SHOP_WITNESS` 加了第四种 `counter`。
3. **`COHORT_PATCH`:`PREREQ` 的推广 —— 有些卡需要的不是前置「卡」,而是前置「环境」**。
   转型的成长挂在换旗上,而默认队列 `cfg.target` 强制固定 Target(bot 侧那条门:
   实验者的随机分配是整条 pipeline 唯一干净的因果通道),换旗**物理上不发生**。
   ⚠ 而我第一版补丁只加了 `pivot: true` —— **仍然不换**:默认队列的 Target 是 twin,
   它的 `counterfactual_tv = 2.6` 是全表最高,换任何旗都是负收益。
   补丁必须打到**换旗真的会发生**的那个形状上(独狼 1.7 起手 + pivot = wolfpivot),
   之后 z=54.5 一次过。**「打开开关」不等于「那件事会发生」。**
   ⚠ 不是放水:两臂用**同一个**改造队列(基准跟着重跑),配对性完全保留 ——
   改的是「实验在什么环境里做」,不是判据。

⚠ **定价按美术冻结值落,不是按公式**:三张的整卡图**已预渲染**(数额印在图上),
所以 +12/+15/+40% 动不了。我的估算:收藏家按 bot 一局 5 次购买算,到达值
≈500 分/拍,**超 uncommon 地板(75)6 倍** —— 但购买次数的真人分布未知
(bot 每店最多一次付费刷新,真人可能刷很多),所以现在算不准。
**列为观察点等 Tape**,与「发挥系数不许拍初值」同一条纪律:缺数据时不假装能算准。

### ⚑ 仪器债第一批(2026-08-13):还债时挖出手速预算是个没量过的占位值

**债的清单**:wrecker + declutter ← bot 弃牌策略;trio ← 判据/样本量;doggybag ← kit 构筑臂。
⚠ **后续(2026-08-13 还债批)**:wrecker **已回池**(+1286 z=12.1);
**trio 的债被重新定性** —— 手速预算校准后重量得 **z=1.81 / 量级 4.1%**,
而量级与样本量无关,**这是「效应不够」不是「量不到」**(详见本文末的还债批记录)。
本轮只动弃牌线那两笔。

**没有直接给 bot 加策略,先去查了真人 Tape**(12 局、81 个弃牌拍):
一拍弃牌张数 **均值 2.30 / 最大 4**(1 张 22% · 2 张 35% · 3 张 35% · 4 张 9%),
而 `beat_budget.discards = 2` —— **模型让 44% 的真实行为不可达**。
⚠ 顺带口径发现:**弃牌动作次数 81/81 全是 1** —— 真人从不在一拍里弃两次,
永远「多选一批、按一次」, 所以这个参数的语义是**张数**。
校准到 **4**(覆盖实测极值), 完整教训见 LESSONS。

**结果**:
| 卡 | 结果 |
|---|---|
| 拆迁 wrecker | ✅ **回池** +1286(z=12.1, 触发 19%)。`beat_budget` 校准让「弃 3 张」可达, `ev.discard_bias` 给了动机 —— **能力 ≠ 动机, 两个都要** |
| 断舍离 declutter | ❌ 仍欠, 但**债的内容变了**:不再是「模型不允许」(4 张现在允许了), 而是「bot 的 `_best_plan` 保守、很少大批量弃牌」。真人侧 9% 可达(爆发档下沿, 合格) |

**⚠ 我为断舍离调了三次 bot, 第三次调回来了** —— 再调就是为门绿而改仪器(判据入 LESSONS)。

**三个连带**(每个都比原债值钱):
1. **`pair.gd` 把弃牌预算抄成了字面量 `2`** —— 配对差一夜变 −16(z=−8),
   看起来像求解器与游戏分叉, 真相是探针没跟着配置走。改读配置后回 +0.0。
2. **回响/复读在 `t_draft` 里从「测得到」变成 0** —— 而**旧的「测得到」才是噪声**:
   预算小时求解器被迫重复牌型, 偶然触发了 `same_as_prev`。完美玩家每拍追最优,
   牌型天然多变 —— 新增 `SOLVER_BLIND` 第 ⑤ 类「完美玩家打法族」。
   kit 侧(规则 bot)照旧 +1242 触发 22%, 卡是活的。
3. **赶场 rush 进 `weak_upper_bound`** —— 它的效应 −966→+72(1.0%), 因为
   `beat_discards` 的 floor 离散化在预算 2 时把 −25% 放大成了 −50%。
   **旧读数才是失真的那个**。详见 blinds.md。

**漂移**(基线 = 还债前):twin 43.7→47.3 · triplet 31.6→**38.3**(追三条最依赖换牌)·
random 1.0→1.1 · **baseline 与 lonewolf 零变化**(不装卡 / 起誓零弃牌 —— 逻辑自洽的验证)。
⚠ 由此反推:此前所有以 bot 为尺子的读数都**系统性偏保守**, 目标分跟着偏松 ——
这条要带进「重算目标分」那一项。

**这批还掉的债 / 没还掉的债**:

| 卡 | 债的内容 | 结果 |
|---|---|---|
| 拆迁 wrecker | bot 不弃满 3 张 | ✅ **回池**(+1286,z=12.1,触发 19%)—— 加 `DISCARD_BIAS` |
| 三重唱 trio | 记作「判据/样本量」 | ⚠ **定性改了**,见下 |
| 断舍离 declutter | bot 的**大批量弃牌**策略 | ❌ 仍欠(真人 9% 做得到,bot 的 `_best_plan` 保守不做) |
| 打包 doggybag | kit **构筑臂** | ❌ 本轮未动 |

**⚑ 三重唱:一笔「债」在校准之后被证明根本不是债。**
旧读数 **+376 / 5.3% / z=2.36** —— 量级过线、显著性差一口气,所以记作样本量不足。
手速预算校准后重量:**+300.6 / 4.1% / z=1.81**,**两条都不达标**。

- 为什么变差:**基准被抬高了**。弃牌预算从 2 涨到 4,bot 更容易直接摸到好牌型,
  于是 (a) 总分涨 → 量级(效应/基准)被摊薄,(b) 对「缓存三张同点数」这种织构的依赖下降。
- 为什么加样本没用:**量级与 n 无关**。我一度按 power analysis 算出 n=80 并给 kit 加了
  `ARM_BOOST`,算完才发现判据的另一半根本不吃样本量(全过程留在 `tools/kit.gd` 的注释里,
  连同一个「`_arm_n` 只作用于实验臂、`Stat.paired` 取 `mini(a,b)`,所以加量压根不生效」
  的实现坑)。
- **裁决:这是「效应不够」的设计结论,不是覆盖缺陷。** 它留在池外,债的条目撤销。
  回池只有两条路 —— 换个更强的效果,或**等真人 Tape** 证明真人的缓存织构率远高于 bot
  (早锁 8% vs 78% 就是先例)。⚠ **不许为了让它过门而调高数额。**

**⚑⚑ 一条要带进重算的通则:校准仪器会重新裁决已经量过的卡,而且两个方向都可能。**
同一次手速预算校准:让回响/复读的「非零」变成噪声(它们本来看着是活的),
让三重唱从「差一口气」变成「够不着」。**基线一动,所有以它为分母的量级都得重读** ——
`WEAK_MAGNITUDE` 和 `weak_upper_bound` 两张豁免表尤其要重扫,它们锁的正是量级。

---

### ⚑ 杂项两张的裁决分析(2026-08-13,**建议,待用户拍板**)

这两张在 atlas 里各挂着一个 ⚠ 挂了很久。把算术做完之后,**两个 ⚠ 的内容都不对**。

#### 渐强 crescendo:atlas 担心的问题不成立,真正的问题是另一个

atlas 记的是「⚠ 轻微藏分动机」(J-60,`Beat last phrase's score: +60`)。

**先看藏分的算术 —— 它不成立**:

| | 数 |
|---|---|
| 藏分成本(故意打低一拍) | 真人拍均分 **502** → 随便打个对子约 150,**成本 ~350** |
| 藏分收益(下一拍必触发) | 按 common/burst 的期望锚定价 = **100~135**(见下) |

**成本是收益的 2.6 倍,藏分严格不划算。** ⚠ 注意这条结论**依赖数额** ——
数额超过 ~350 时藏分才划算,所以这张卡真做的话,**350 是它的定价硬上限**。
(顺带:atlas 写的 60 是**没走定价公式**的估值。同为 common/burst 的锚:
霓虹灯牌 +50 无条件 · 变奏 +85@高触发 · 回响 +240@22% —— 期望都落在 50~68/拍,
而渐强的触发率约 50%,反推数额 **100~135**。)

**真正的问题:它的条件与玩家的任何决策都不相关。**
「这一拍比上一拍高」在随机序列里就是**上升沿**,约占 50%,而且**与玩家水平无关**
(打得好整条线抬高,锯齿性不变)。玩家做不了任何事去提高它 —— 打高分永远是最优解,
持不持有渐强都一样。**它是一张伪装成条件卡的无条件卡。**

于是它在决策层**等价于霓虹灯牌**,但读起来更复杂、体感更差(「我为什么没触发」)。
⚠ 而霓虹灯牌的零决策是**诚实的**(它明说无条件,作用是地板);渐强的零决策
藏在一个看起来有讲究的条件后面 —— 加的是**零信息的随机**。

**⚑ 这张卡的设计空间没有安全地带**:
- 条件保持「与上一拍比」→ **零决策**(无害但冗余,严格劣于霓虹灯牌);
- 条件改成玩家能主动追求的(如「本段逐拍递增」,要规划弃牌节奏)→ **决策密度上来了,
  但藏分动机这次是真的**(第一拍故意打低,后面一路递增)。

**建议:不做。** 若要做,只有第二种形状值得,且必须先解决藏分 ——
而 8 秒的压力让藏分几乎免费(玩家本来就常打不出好牌),那个解法我现在没有。

#### 透牌 xray:不是「仪器未建」,是**认错了通路**

atlas/TODO 记的是「⚠ belief 通路仪器未建,量不到就是空气」。
但透牌(`弃牌前先看到将补的牌`)**没有 `effects`** —— 它不加分,它改的是**决策的信息集**。
那正是 `shortcut`/`fourfingers`/`twotone`/`trim` 那一族的形状:**solver 通路**,
证物用 `*score`(分差就是它的全部效应,和修剪同一个判据)。

所以它欠的不是一件新仪器,是**求解器弃牌枚举里的一个分支**:
现在的弃牌决策基于补牌的**分布期望**,透牌要求它用**实际的那张牌**。
⚠ 这会让求解器在持有透牌时严格变强 —— **而那正是这张卡的效果**,不是仪器作弊。

**建议:可以做,归到 S5(扩求解器动作空间)那一批** —— 它和「求解器一拍只弃 ≤3 张」
(`t_draft.gd` 第 ③ 类结构盲区)是同一个引擎的两处扩张,一起做比分两次便宜。

---

### ⚑⚑ 直接从 Tape 量三张欠债卡的**真人反事实率**(2026-08-13)

起因是想回答「打包的债该不该还」——`kit` 的单卡臂打不到 2× 目标是事实,
但**如果真人也打不到,那它和三重唱一样是设计问题,建仪器纯属浪费**。
于是没等 probbook 重刷,直接扫合格 Tape 算反事实率(「假如持有这张卡,会不会触发」)。

**方法**:`_qualified` 的三道筛(局时长 >60s · 有 `intro` · 玩家操作 ≥5)
把 2376 个 Tape 文件筛到 **12 局 / 168 拍** —— 与记档的真人样本量一致,
筛选工作正常(⚠ 我一度怀疑探针污染了 Tape:全量扫出「2174 局打满 24 拍、
段分是目标的 343 倍」。那些是 `tools/tapeprobe.gd` 的不死局,**恰好被时长那道筛拦住**。
写 Tape 的只有编排器 / t_tape / tapeprobe / replace 四处,sim/kit/gate **不写**)。

| 卡 | 真人反事实率 | 裁决 |
|---|---|---|
| 打包 doggybag | **25.0%**(7/28 段达到 2× 目标;段分/目标中位 **1.32**,最大 4.97) | ✅ **债值得还** —— 每 4 段触发 1 次,是张活卡 |
| 断舍离 declutter | **8.6%**(7/81 个有弃牌的拍一次弃了 4 张) | ✅ **债值得还** —— 与记档的 9% 吻合 |
| 三重唱 trio | **0.0%**(0/168 拍;缓存满 3 张的拍有 **150** 个,一次三同点都没有) | ❌ **坐实留在池外** |

**⚑ 三重唱这一条比 bot 侧的 4.1% 有力得多**:那只说明「对这个 bot 效应小」,
而 0/168 说明**这件事在真人手里根本不发生**。算术也支持:随机三张同点数
≈ `52/C(52,3)` = **0.24%**,玩家就算主动凑也要拿三格缓存去赌一个 13 选 1。
⚠ **它和「量级 4.1%」是两个独立的死因** —— 任何一个单独成立都足够,
所以这张卡不需要再复查了(与 `WEAK_MAGNITUDE` 里那些「真人待定」的卡不同)。

**⚠ 顺带修一个会被误读的口径**:记档里的「真人一拍弃**均值 2.30**」是**条件均值**
(只算有弃牌的 81 拍);**无条件均值是 1.11**(168 拍里有 87 拍一张都不弃)。
两个数都对,但**校准 `beat_budget.discards` 用的是分布的上界(最大 4)**,
和这两个均值都无关 —— 写清楚免得下一个人拿 1.11 去质疑那次校准。
分布:`{0:87, 1:18, 2:28, 3:28, 4:7}`。

**⚑ 方法本身值得留**:probbook 算的是「已持有的卡触发了几次」,
这里算的是「**假如持有会不会触发**」—— 后者才是**新卡该不该做**的输入,
而且不需要那张卡先进池、先被真人买到。⚠ 前提是那张卡的条件**能从 Tape 的事实字段
重建**(缓存内容 / 段分 / 弃牌批量都可以;而「早锁率」这种依赖动作时刻的
就要看 `act` 字段在不在)—— 这正是 telemetry.md 那条「事实完整性 = 能重放任意时刻」的兑现。

### ⚑ 观察点 ①④ 结案:两个「真人读数」在 10 倍样本下都回落成噪声(2026-08-13)

STATUS 的观察点 ① 回响 **33%@n15** 和 ④ 彩虹 **40%@n15** 都挂着「样本仍薄,继续攒」。
用反事实率把样本从 **n=15 撑到 n=156/168**(不再只算持有那张卡的拍),两个都下修:

| | 旧(probbook,持有态) | 新(反事实,全部拍) | 差 | 判定 |
|---|---|---|---|---|
| 回响 same_as_prev | 33% @ n=15 (se **12.1pt**) | **25.0%** @ n=156 | −8.0pt = **0.66 se** | 不显著 |
| 彩虹 all_suits | 40% @ n=15 (se **12.6pt**) | **29.8%** @ n=168 | −10.2pt = **0.81 se** | 不显著 |

**结论:旧读数就是小样本噪声,而且「持有 vs 不持有」之间看不到激励效应** ——
玩家没有为了触发回响而去重复牌型(至少这 12 局里没有)。
⚠ **这两个观察点可以摘掉了**:它们等的是「n≥30 坐实」,现在 n 是它的 5 倍。

**顺带用可靠触发率复核了这一族的定价**(common/burst 期望锚 **50~68/拍**):

| 卡 | 数额 × 真人 p | 期望 | |
|---|---|---|---|
| 回响 | 240 × 25.0% | **60.0** | ✓ |
| 变奏 | 85 × 75.0% | **63.8** | ✓ |
| 彩虹 | 180 × 29.8% | **53.6** | ✓(C8 的「留彩票」裁定不受影响) |
| **无对 nopair** | 190 × 20.2% | **38.4** | ⚠ **比锚低 23%** |

**无对是这一族唯一偏离的**:五张点数互异在真人手里只有 20.2%(比直觉低 ——
玩家追牌型,而大多数牌型都含对子)。按锚复价 = **250~300**(现 190)。
⚠ **待走 numbers.md 六步 SOP 再动**,这里只记读数与偏离幅度。
⚠ 依据是**用户自己的 Tape**,符合「发挥系数不许拍初值」那条 —— 但 12 局仍是小样本,
`n=168 拍` 撑起的是**拍级**统计量(触发率),撑不起局级的(通关率、构筑成型率)。

### ⚑ 观察点 ⑤⑦ 也一起答了:一个红灯 + 三条族两张卡只值半价(2026-08-13)

**真人牌型分布(12 局 / 168 拍)** —— 这是族内件定价的分母,以前只有 bot 侧的:

| 牌型 | 拍数 | 占比 | | 牌型 | 拍数 | 占比 |
|---|---|---|---|---|---|---|
| 对子 | 76 | **45.2%** | | 同花 | 12 | 7.1% |
| 两对 | 32 | 19.0% | | 葫芦 | 6 | 3.6% |
| 高牌 | 19 | 11.3% | | 顺子 | 3 | 1.8% |
| 三条 | 17 | 10.1% | | 四条 | 3 | 1.8% |

→ **含对子族 79.8%** · **三条或更好 15.5%**

**⑦ 族内件复价(地板线 12.5 分/拍·◆;倍率链均值 6.70 / 拍均乘法部 481)**:

| 卡 | 通道 | 期望/拍 | 地板 | |
|---|---|---|---|---|
| 对唱 duo | +10 chips × 79.8% | **53.5** | 50 | ✓ |
| 二重唱 duet | +25% × 79.8% | **96.0** | 75 | ⚠ 偏高 28%(到地板 = 20%) |
| **三和弦 triad** | +25 chips × 15.5% | **26.0** | 50 | ⚠⚠ **只值半价**(到地板 = 48) |
| **三重 triplebill** | +60% × 15.5% | **44.7** | 75 | ⚠⚠ **偏低 40%**(到地板 = 101%) |

**⚑ 三条族两张同时偏低约一半 —— 这不是定价失手,是分母错了。**
它们定价时用的是 bot 侧的三条率,而真人只有 **15.5%**(bot 追三条追得比人狠得多:
sim 的 triplet 队列通关率 38.3%,人做不到)。**对子族没这个问题**(79.8% 高到
bot 和人都摸得着,所以 duo 一次就定准了)。
⚠ **判据:族内件的定价分母必须用真人牌型分布** —— bot 与人的差距在**难牌型上被放大**,
而族内件恰好是按牌型难度分档的。

⚠ **一处不确定性**:这 168 拍是**没装这些卡**时的分布。装了三和弦之后玩家会主动追三条,
真实触发率会高于 15.5%。但同一批数据里**回响/彩虹都看不到激励效应**(见上一节),
所以保守假设是"激励有限"。⚠ 追三条比"重复上一拍牌型"更可执行,这条不能直接套用 ——
**复价前先用装了卡的 Tape 复测一次三条率**,这是 SOP 该走的一步。

**⑤ 规则牌购买 = 0 张(红灯,但样本几乎全在措施之前)**:
合格局共 **35 次购买**,规则牌(近道/四指/双色调/百搭/修剪)**一张都没有**。
⚠ 但 12 局的日期是 **08-06 / 08-11 / 08-12**,而 §3.8 曝光三措施
(四指·双色调降罕见 + 修剪 + 点唱机)是 **08-12 夜**落地的 —— **这批数据基本测不到措施**。
观察点 ⑤ **保留**,判据不变:措施之后的局里规则牌购买数是否 >0。
