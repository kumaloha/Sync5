# 牌与牌型

> **这一篇管:一张牌怎么流动,五张牌值多少分。**
> 数值在 `data/` 之外 —— 牌型表在 `core/pattern.gd::BASE_MULT`,那是权威。
>
> 本篇 2026-08-09 由 `cards.md` + `cards.md` 合并而成 —— 见 [`README.md`](README.md) 的九篇结构。
> **验证方案在末尾**(每篇自带,这是文档约定之一)。

---

## 牌流

> Rewritten 2026-08. The candidate-draw mechanic is dead; this documents the
> shipped discard-refill rules.

### Zones

| Zone | Function | Size | Persists |
|---|---|---:|---:|
| Draw Pile | random input | 52 (+2 wilds if unlocked) | run |
| Hand | solve the current Phrase | exactly 5 | phrase |
| Cache | prepare future Phrases | exactly 3, always full | run |
| Discard | spent cards | - | until reshuffle |

The player still answers: **now, future, or abandon?**

### Core loop: discard-refill

- Select hand and/or cache cards -> 弃牌 -> pay **1 coin per card** -> every
  discarded slot refills in place immediately.
- Hand <-> Cache drag = **swap** (always an exchange - the cache has no
  holes), free; time is the cost. Free actions never feed joker counters
  (05 principle A4).
- Drag onto the discard key = single-card discard.
- 理牌 sorts the hand by rank.

### Deck

- Standard 52. Reshuffles discard when empty; Hand and Cache are excluded.
- 大小王 join only via the Wildcard joker (`Deck.enable_wilds`); patterns
  resolve wilds by brute-force substitution (at most 2 wilds).
- Rule-change jokers write flags to `Deck.rules` (shortcut / fourfingers /
  twotone), read by `Pattern` - a fresh run resets them for free.

### Lock edge cases

- Card mid-drag at lock: returns to its origin zone.
- Discard cost is never refunded.

---

## ⚑⚑ 牌型倍率 v3 方法论(2026-08-27 用户两洞见,⑥ 数值批首位)

> 用户实测:顺子一个 section 只凑出 1-2 次。两个论点,都改定价公式:
> ① **先验概率没考虑金币约束** —— P(≥k) 是弃牌免费口径;经济 v2(1◆/张)后
> 真实可达概率是**钱包的函数**。⇒ prior 层加第二列:`P(≥k | 弃牌预算 b)`,
> b ∈ {0, 2, 4, ∞} 扫表(零数据可算,守「组合口径」拍板)。
> ② **概率有两个含义:难度 + 波动率**(用户三次强调后的最终表述:「倍率和概率确实是
> 正比,但倍率不止奖励概率,还奖励波动性——否则期望一样的情况下谁不玩好凑的?」
> 已升格 CLAUDE.md Target 原则 ④)—— 追型策略凑不成时手是烂的,而段目标是
> 硬生死线,方差本身是成本;风险中性 1/p 定价 = 期望持平但更容易死。
> ⇒ 波动率溢价:`mult(k) = base(P≥k|b) × (1 + λ·CV(k))`,CV = 追该型策略
> 得分的变异系数(先验层可算);**λ = 风险厌恶系数,归用户试玩手感标定**
> (它本质是「玩家多讨厌死」,仪器量不了)。
> 连带:弃牌条件卡(拆迁弃6等)的条件成本随经济 v2 剧变(6 张 = 6◆ ≈ 三拍收入),
> 处置三案(数额抬 / **触发返还弃牌费**[推荐,「拆迁公司出拆迁费」] / 条件降)待用户拍。

## 牌型

### Settlement

At Phrase end:

1. read all Hand cards
2. find the highest-scoring five-card combination
3. identify poker pattern
4. apply base score
5. apply character
6. apply Target Joker
7. apply Support Jokers
8. award score and coins

### Base patterns

| Rank | Pattern | Base chips | Mult | Balatro L1 | Base coins |
|---:|---|---:|---:|---|---:|
| 1 | High Card | 5 | ×1 | 5 ×1 | 0 |
| 2 | Pair | 10 | ×2 | 10 ×2 | 1 |
| 3 | Two Pair | 20 | ×3 | 20 ×2 ← **偏离** | 2 |
| 4 | Three of a Kind | 30 | ×3 | 30 ×3 | 3 |
| 5 | Straight | 30 | ×4 | 30 ×4 | 4 |
| 6 | Flush | 35 | ×5 | 35 ×4 ← **偏离** | 4 |
| 7 | Full House | 40 | ×6 | 40 ×4 ← **偏离** | 6 |
| 8 | Four of a Kind | 60 | ×7 | 60 ×7 | 8 |
| 9 | Straight Flush | 100 | ×8 | 100 ×8 | 12 |
| 10 | Royal Flush | 140 | ×8 | **100** ×8 ← **偏离** | 15 |

#### The table is Balatro's (2026-08-06 用户拍板)

「你看看原作, 牌型的倍率。基本可以抄他的」。Values verified against
[balatrowiki.org/w/Poker_Hands](https://balatrowiki.org/w/Poker_Hands) — the
level-1 baseline. Balatro also has three secret hands we do not implement
(Five of a Kind 120×12, Flush House 140×14, Flush Five 160×16); they need
duplicate ranks, which our 大小王 wilds could in principle reach.

**Balatro deliberately lets hands share a mult** (2,2 / 3 / 4,4,4 / 7 / 8,8) and
carries the value difference on **chips alone**. Mult is the scarce resource
reserved for jokers: spend it early on the mid hands and there is no headroom
left at the top.

We deviate from Balatro L1 in four places (终版表 `1/2/3/3/4/5/6/7/8/8`):

> ⚑ **第 1 条经历了一次「推翻的推翻」,账要记全**:
> ×3 是 2026-08-06 白天用户的拍板;当晚按 `P(≥牌型)` **实测**累计重定价时被覆盖回 ×2
> (算出 2.47);**2026-08-17 恢复 ×3** —— 因为 08-14 用户已把定价口径换成**组合**,
> 同一套 0.75 幂压缩在组合累计上 = 2 × (92.88/53.22)^0.75 ≈ **3.04**,
> 与用户当初的拍板相符。覆盖它的那把尺子已经被换掉了,拍板回到原位。
> (Flush ×5 / Full ×6 是 08-06 晚那次重定价的**存活**部分,一并列为偏离。)

1. **Two Pair ×2 → ×3.** The user's own catch (「two pair 和 pair 怎么是一个倍率」).
   Balatro puts Two Pair's entire premium into doubled chips (10→20), paying
   ~25% more for a hand that is **8.9× rarer**. Balatro can afford that — it is
   turn-based and you have time to push toward a better hand. An 8-second live
   phrase does not: Two Pair is frequently the best you can actually assemble.
   Poker order still holds: (20+30)×3 = 150 < (30+30)×3 = 180.
2. **Royal Flush keeps 140 chips.** Balatro scores Royal and Straight Flush
   *identically* (both 100×8) — no premium at all for the royal. We model it as
   its own hand, so it keeps a chips edge; the mult copies Balatro's 8.

Difficulty compensation still lives entirely in the Target layer, never here.

> ⚠ Do NOT price off the hand frequencies our own sim reports. Discard-refill
> makes chasing suits/runs cheap, so Flush and Straight appear **more** often
> than Three of a Kind in practice — the reverse of natural odds. Poker order is
> what the player's intuition reads, and it is a settled rule.

### Rank value

```text
chips = pattern base chips + sum of best five card ranks
pattern score = chips × pattern mult
(Settle stacks jokers onto the mult chain: × target × (1 + Σ%), + bonus after)
```

J/Q/K/A = 11/12/13/14.

### Local optimum

- **Initial Best**: strongest pattern in the initial five cards
- **Final Best**: final submitted pattern

These values measure whether the player:

- preserved the initial optimum
- improved it
- destroyed it without recovery
- spent resources efficiently

### Near miss

Near miss is analytical and feedback data, not a hidden score bonus.

Examples:

| Current structure | Near target |
|---|---|
| four consecutive ranks | Straight |
| four cards of one suit | Flush |
| Two Pair | Full House |
| Three of a Kind | Four of a Kind |
| four-card straight-flush structure | Straight Flush |

The system cannot modify already revealed cards to manufacture a near miss.

---

## 附:从 `CLAUDE.md` 迁来的推导(2026-08-09)

> 逐字迁移,未压缩。`CLAUDE.md` 现在只留原则,数值与推导在这里。

### 弃牌免费的连带五处(2026-08-06 用户拍板,推翻「1 金币/张」)

⚠ **上面「Core loop: discard-refill」里的 `pay 1 coin per card` 已被这条推翻**,按本节读。

  **唯一的闸门是 8 秒钟**,金币只剩买牌一个出口。连带五处:
  ① **「赶场」-2s 从对模型无效变成最狠的一张脸** —— 时间成了唯一约束,砍 2 秒就是砍掉一次弃牌
  (改前它是空气:求解器不弃牌、交换预算又永远不 binding,S4 池子里那半局等于没有 Boss 规则);
  ② **「强制换血」(零弃牌减半)随手弃一张就免疫**,几乎失效;
  ③ 周转 / 黑胶 / 贝斯线三张吃弃牌的卡明显变强(后两张是永久成长,增速翻倍以上);
  ④ **独狼的零弃牌起誓代价变大**(放弃的从「省钱」变成「放弃无限重抽」),而它本来就垫底;
  ⑤ **手速预算(`run.json beat_budget`)从一个近似升级成唯一的平衡杠杆**,必须用 Tape 真人数据量准。
  模型侧的好处:**金币影子价 κ 整个消失**,求解器少一个要扫的参数(弃牌不花钱,只受时间限制)。
  ⚠ **牌型频率会因此整体上移**(追牌变便宜),照旧频率调的倍率表要重测。

### 牌型倍率表:三版演进,以及我两次用错指标

  **倍率表 = 抄 Balatro 的 level-1 表**(2026-08-06 用户拍板:「你看看原作,牌型的倍率。
  基本可以抄他的」,数值核对自 balatrowiki.org/w/Poker_Hands):
  `1/2/3/3/4/4/4/7/8/8`。
  **⚑ 2026-08-06 晚按本作实测频率修正两处 → `1/2/2/3/4/4/5/7/8/8`**
  (用户:「概率和之前瞎想的不同,按照概率设置牌型倍率吧」)。
  数据来自 `tools/attrib.gd` 中性基准(完美玩家/八选五/不装 Target/不弃牌)——
  **这是本作的真实分布,不是自然扑克分布**:
  高牌 **6.1%** · 对子 27.2% · **两对 33.5%(最常见)** · 三条 5.5% · 顺子 11.0% ·
  同花 10.7% · 葫芦 5.1% · 四条 0.7%。
  ⚠ **不能直接照频率定价**(会给出荒谬结果:高牌 6.1% 比同花 10.7% 还稀有,
  照价它该更贵)——**八选五让「稀有」不再等于「难」**,高牌稀有是因为你很难打得那么烂,
  频率把「难做到」和「难避免」混成了一个数。规则因此是:**保住扑克序,
  只用实测频率调序内间距,且只往下调不往上抬**(往上抬 = 普涨 = 构筑价值塌,见下面 log₂ 的教训)。
  ⚠⚠ **上面那版依据(出现频率)是错的,我连错两次,终版见下。**
  出现频率 P(恰好是这个牌型)有**中转站伪影**:高牌 1.6% 稀有不是因为难,是因为八选五 +
  自由弃牌几乎总能成手;三条 5.6% 稀有是因为它是**路过**(有三条就顺手去葫芦)。
  **「路过」≠「到达」**,照它定价会得出「高牌该排第二贵」。
  ✅ **正确的量是 `P(≥ 这个牌型)`(累计)**——消掉中转站伪影,**且天生与扑克序单调一致**,
  所以「保扑克序」和「按概率定价」根本不冲突,之前所有拧巴都是我用错指标造出来的。
  实测(弃牌免费后):对子 98.4% · 两对 74.2% · 三条 51.6% · 顺子 46.0% · 同花 33.2% ·
  葫芦 20.7% · 四条以上 <1.6%。映射 = **0.75 次幂压缩、锚在对子=2**(用户选「中等」基调)。
  **终版 `1/2/2/3/4/5/6/7/8/8`**(同花 4→5、葫芦 5→6;顶端三档无数据,保持手拍值不动)。
  ⚠ **葫芦看着常见(出现 19.1%)其实是天花板**:P(≥葫芦)=20.7%,因为四条以上几乎不存在。
  我曾据「出现频率高」要给它降价,那是第二次用错指标。

### Target 层不再区分顺子/同花之后,`jokers.json` 的配套改动与两处偏离

  配套改 `jokers.json`:**阶梯 ×8 与单色 ×6 是纯倒挂**(实测等频 11.0% vs 10.7%),
  拉平为**各 ×7 / 同花顺各 ×14**。
  **教训:测试里的 Target 倍率断言当时还在手抄数字,这一改一次红 10 条;
  而牌型倍率那批早已改成从 `Pattern.BASE_MULT` 推导,一条没红。已全部改成从 jokers.json 推导
  (`tests/runner.gd::_tmult`)——平衡数值要反复调,手抄断言等于给每次调参加一道返工。**
  **原作有意让多个牌型共享同一个 mult**(2,2 / 4,4,4 / 8,8),
  价值差全靠 chips 拉开——mult 是留给小丑牌的稀缺资源,中段发完顶端就没梯度了。
  **我们偏离四处**(Two Pair ×3 · Flush ×5 · Full ×6 · Royal chips 140):
  ① **Two Pair 2→3** ⚑ **经历了一次「推翻的推翻」**
  (08-06 白天拍板 ×3 → 当晚按实测累计覆盖回 ×2 → **2026-08-17 恢复 ×3**:
  08-14 口径换成组合后,同一套压缩算出 ≈3.04,当年覆盖它的尺子已被换掉)。原始理由 ——
  (用户提的:「two pair 和 pair 怎么是一个倍率」——
  原作把它的溢价全放在 chips 翻倍上,实算只高 25% 而它稀有 8.9 倍;原作是回合制有时间往
  高牌型走,我们 8 秒实时里 Two Pair 常常就是能拿到的最好结果。仍低于 Three Kind,扑克序不倒挂);
  ② **Royal 保留 140 chips**(原作 Royal 与 Straight Flush **完全同分** 100×8,不给皇家任何溢价;
  我们把它做成独立牌型,靠 chips 区分,mult 照抄 8)。
  原作还有三个我们没做的隐藏牌型:Five of a Kind 120×12 / Flush House 140×14 / Flush Five 160×16。
  ⚠ **别拿 sim 的牌型频率当定价依据**:弃牌重抽让追花色/追顺子很便宜,实测 Flush/Straight 比
  Three Kind **更常见**(与自然概率相反);扑克序是已拍板的,玩家直觉读的就是它。

---

## 验证方案

| 验什么 | 怎么验 |
|---|---|
| **牌型判定正确** | `tests/runner.gd` 逐牌型断言(含万能牌暴力代入、`Deck.rules` 三张救援规则牌的全链路) |
| **倍率表没被手抄** | ⚑ 断言一律**从 `Pattern.BASE_MULT` 推导**,不写死数字。这条踩过两次:牌型倍率改成推导后一条没红,而 Target 倍率当时还在手抄,一改红 10 条 |
| **实测频率** | `tools/attrib.gd` 中性基准(完美玩家/八选五/不装 Target/不弃牌)|
| **求解器与游戏同分** | `tools/pair.gd` 三关递进,逐手比对 |

⚠ **定价用 `P(≥ 牌型)` 不用 `P(= 牌型)`** —— 出现频率有「中转站伪影」
(有三条就顺手去葫芦,所以三条的出现频率低不代表它难)。这个指标我用错过两次,
详见 [`../CLAUDE.md`](../../CLAUDE.md) 结算公式那节。

⚠ **别拿 sim 的牌型频率当定价依据**:弃牌重抽让追花色/追顺子很便宜,
实测 Flush/Straight 比 Three Kind **更常见**(与自然概率相反)。

## ⚑⚑ 倍率 v4 终表(2026-08-29 落地)

**牌型层** `BASE_MULT`(`core/pattern.gd`):
`1 / 2 / 3 / 5 / 6 / 7 / 9 / 16 / 21 / 26`(高牌→皇家)。
口径 = `tools/vol.gd` 现口径(手牌 5 张 + 缓存 1 次交换 + 弃 ≤2),公式 `(1/P)^0.75` 归一到对子 ×2;
**同花从算出的 6 手抬到 7**,保住「同花 > 顺子」这条玩家直觉。

**Target 层**:`twin 1.4 · triplet 2.0 · stair 4.8 · mono 5.6`。
推导在 [`numbers.md` §2.51](numbers.md)(落空损失补偿),**终值可以偏离公式** ——
公式对齐期望,而段目标是硬生死线,方差大的更容易死(同花 CV 1.087 全场最高)。
实测通关率:换旗 44.3% · 任意 44.7% · 顺子 39.2% · 三条 36.7% · 同花 29.6% · 对子 23.6%。

⚠⚠ **`BASE_CHIPS` 不参与这次改动, 它保持 `5/10/20/30/30/35/40/60/100/140`。**
2026-08-29 我改 `BASE_MULT` 时把同一批值**也写进了 `BASE_CHIPS`**(缩了 5 倍),
而 `rank_sum`(≈30~60)没跟着缩 ⇒ **点数和的权重压过牌型本身, 牌型差异被压平**。
在那个污染表下量了一整天:对子路线读出 3.6%(实为 23.6%)、四张 Target 的落空分全部偏低、
关卡分据此反解成 420/650/1150/1930(**已作废**)。抓住它的是单测一条万能牌断言。
⇒ **改这两张表一律按「表名 + 键」双重定位, 不许全文件 `re.sub`**(见 LESSONS)。

---
