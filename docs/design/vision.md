# 初衷与玩法逻辑

> **这一篇管:为什么做这个游戏,它凭什么好玩。**
> 它是判断的**依据**,不是可自动验证的对象 —— 见末尾。
>
> 本篇 2026-08-09 由 `vision.md` + `vision.md` + `vision.md` 合并而成 —— 见 [`README.md`](README.md) 的九篇结构。
> **验证方案在末尾**(每篇自带,这是文档约定之一)。

---

## 系统总览

### System goal

The game delivers three values through three loops:

| Time scale | Player value | Main systems |
|---|---|---|
| Phrase | Release | draw, choose, auto-settle |
| Section / Run | Skill growth | Joker, coins, Cache, build |
| Day / Month | Asset growth | characters, temporary Jokers, cosmetics |

### Core loop

```text
Initial local optimum
→ spend coins to keep drawing
→ preserve, cache, replace, or discard
→ forced settlement on the beat
→ release or near miss
→ next Phrase
```

### System map

```text
Character
→ Phrase Engine
→ Card Flow + Economy
→ Pattern Evaluation
→ Target Joker
→ Support Jokers
→ Score / Coins
→ Section Progress
→ Director
→ Next Sequence
```

### System boundaries

| System | Main question |
|---|---|
| Phrase | When does an experience begin and end? |
| Card Flow | Where does each card go? |
| Pattern | What is the submitted answer? |
| Economy | How much future choice can the player buy? |
| Target Joker | What is a good answer in this Run? |
| Support Joker | How does the player reach that answer? |
| Character | What pressure model governs the Run? |
| Director | What should the player experience or learn next? |
| Meta | What remains after the Run? |

### Default hierarchy

```text
Meta
→ Run
→ Section
→ Phrase
```

- Phrase: complete emotional unit
- Section: learning unit
- Run: build unit
- Meta: ownership unit

---

## 乐句系统

> Synced 2026-08 to the shipped implementation (the 5s draft era is over).

### Definition

Phrase is the smallest complete experience unit.

Baseline: **12 seconds**, bent per section by the setlist curve (see 08):
13s on the teaching acts, 12s through the show, 11.5s / 11s in the finale
squeeze. Every duration flows through `GameConfig.phrase_duration(section)`.

### Lifecycle (12s phrase)

| Time | State | System | Player |
|---:|---|---|---|
| 0.00-0.25s | Deal | deal/refill hand, top up cache | observe |
| 0.25-11.0s | Decision | discard-refill / swap / sort | choose |
| 11.0-11.75s | Warning | countdown feedback strengthens | final decision |
| 11.75s | Lock | input stops | none |
| 11.75s+ | Resolve | settle chain + show (FLY/MERGE/BURST) | watch the number grow |
| +1.6s | Next | hand to discard, cache persists | continue |

`early_settle()` exists as a hook: finishing early is a timing behavior
(Momentum reads it) and a future pacing lever.

### Settle chain

```text
LOCK
-> PATTERN (best five, automatic)
-> TARGET JOKER (x mult)
-> SUPPORT JOKERS (base mods / percents / flat bonus / coins)
-> CHARACTER PASSIVE (popup slot -1)
-> SCORE = (base + base mods) x mult x (1 + %) + flat bonus
-> COINS -> CLEANUP -> NEXT
```

### Base rules

- Hand clears at Phrase end; Cache persists.
- Phrase cannot be paused or extended.
- Settlement is automatic - no submit button.
- Boss faces (08) may bend rules for a whole section, announced up front.

### Phrase Sequence (Director concept, phase 5 - unchanged)

Establish -> Pressure -> Disturb -> Learn -> Payoff -> Recover

### Tunable parameters

All in `core/config.gd`: PHRASE_DURATION 12.0, warning = duration - 1.0,
lock = duration - 0.25, RESOLVE_FEEDBACK 0.25, LATE_ACT_WINDOW 2.0,
EARLY_FINISH_TIME 6.0.

### Acceptance (unchanged)

- Pressure rises before settlement.
- Settlement feels immediate, and the show explains the number.
- The next Phrase begins without menu interruption.

---

## 早期路线图

> # ⚠ 已被 `STATUS.md` 取代
>
> 这份是早期的状态账本。**当前状态看 repo 根的 `STATUS.md`**,待办看 `TODO.md`。
> 保留本文只为留住早期的阶段划分。

## vision.md

> Status ledger, 2026-08. Execution merged the original phases 2-3 and
> pulled parts of phase 5 (pacing) forward.

### Done (225 tests green)

- Phrase - 12s clock with the setlist curve, discard-refill, best-five,
  automatic settle, FLY/MERGE/BURST show.
- Cache & economy - 3 always-full cache slots, free swaps, single-pool
  coins, priced shop, clear wage.
- Joker - Target 5 + Support 18 (incl. the rescue-rule batch), draft shop
  with target swap, 16 design principles (05), 20 sim calibration rounds.
- Run/Section - three-act setlist, S5/S8/S10 boss faces with preview,
  run-end screens from the docs/mockups/ mocks.
- Balance methodology - adaptive bots, EV drafting, routine harvester
  (`tools/sim.gd`).

### Remaining

- **Human playtests** - numbers are locked against bots; the final trim
  needs real players.
- **User art** - joker illustrations (`assets/jokers/joker_<id>.png`
  hot-loads), card back, protagonist art; the S10 finale screen.
- Character (old phase 4) - 8 passives are first-draft numbers in
  `core/character.gd roster()`.
- Director (old phase 5) - designed in 07, not built; its telemetry inputs
  double as the playtest data pipeline.
- Meta (old phase 6) - designed in 09, not built.

---

## 验证方案

⚠⚠ **这一篇没有自动验证,而且不该有。**

「好不好玩」最终是留存,而**留存零数据**(见 [`../STATUS.md`](../../STATUS.md))。
任何声称能给「好玩」打分的做法,都是在把一个未知数偷偷写成常数 ——
这正是 [`generating.md §5`](generating.md) 反复警告的事。

**能做的只有三件,按硬度排:**

1. **测量形状,不评价**(`generating.md §5.2`)—— 五项难度分解 + 缺口分布按段打出来,
   让设计者看见自己的设计产生了什么形状。判断留给人。
2. **检测明显坏**(`generating.md §5.3`)—— 通过率 ≈0/≈100%、技巧空间 ≈0、
   缺口双峰。**「检测坏」比「评价好」容易得多,而且不需要留存数据。**
3. **等真人 Tape** —— 采集侧已实装(`telemetry.md`),分析侧一行没有。

⚠ **本篇的三份源文档都有过期内容**(`00` 尤甚:它写于候选牌机制作废之前)。
读的时候以 [`../CLAUDE.md`](../../CLAUDE.md) 的「已拍板的规则」为准 ——
那里是**现行**规则,这里是**当初为什么这么想**。
