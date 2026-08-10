# 小丑牌候选图谱(批 3 · 60 张口径)

> **状态:候选池,等待人工删选;不是已批准内容,数值全部只是量级示意。**
>
> 用户拍板(2026-08-10):**roster 总数 60 张**。拆分建议:Target 8(现役 5 + 新 3)
> + Support 52(现役 18 + 新 34)。本图谱提供 Target 候选 6 + Support 候选 45,
> 超额约 1/3 供删选。现役 23 张是底座,本文不动它们。
>
> 分类口径(2026-08-10 三题决议):五维分类沿用(kind / rarity⇔通道 / proof / curve / 功能轴);
> **`curve` 升为数据必填**(配额表的记账单位,15→18 张时配额静默过期的教训);
> 功能轴留文档。**不设轮次门**——轮次身份由 `curve` 声明、由经济曲线执行
> (乘后平加早强晚衰、成长卡天然后期),货架不加门;唯一的轮次特例仍是首张 Target 免费。

---

## 0. 60 张口径下必须一起动的三个旋钮

**稀释数学**:一局 7 商店 × 3 货架位 ≈ 21 次曝光。稀有档权重 5%、池内均分:
稀有档 5 张时特定稀有卡一局出现率 ≈19%(镜面流五局一遇,手感正确);
稀有档扩到 ~10 张 → ≈10%,组合构筑从「可追」滑向「抽签」——
撞「随机不许决定有没有玩点」。对策三条,随批 3 一起做:

1. **自足卡为主、组合卡为辅**:新增卡中「单卡自足」(平贴/牌面/时机类)占比 ≥2/3,
   强依赖搭子的组合件(镜面类)不再增加——组合密度靠总量自然上升,不靠单卡绑定。
2. **曝光扩容走构筑侧**:联票(货架 4 选 2)与赞助(降价)本身就是搜索机制,
   优先级提到批 3 前排——60 张池子需要它们,25 张不需要。
3. **软旋钮备用不实施**:按段微调稀有度权重(70/25/5 → 后期 60/30/10),
   economy.json 一段一行,等真人 Tape 说后期货架全是死普通卡再开。

**配额表(60 张口径重写,curve 进 schema 后测试断言)**:

| 维度 | 配额(Support 52) |
|---|---|
| curve | burst ~22 · fixed ~10 · growth ~8 · floating ~6 · decay ≤2 |
| rarity(池内构成,非抽取权重) | 普通 ~24 · 罕见 ~18 · 稀有 ~10 |
| 功能轴下限 | 时机+序列 ≥14(身份轴) · 经济 ≥6 · 规则 6–8 · 缓存/交换 ≥6 |
| 原则上限(不随规模等比放大) | 复制 **1**(B4 槽序无意义,邻位复制无法定义) · 无条件甜品 ≤2 · 衰减 ≤2 且不入稀有(C5) |

**删选判据**(A1–A5 + C1 压缩版,逐张过):结算窗读牌 · 条件只挂四种计划级行为
(弃什么/换什么/多快/追哪型) · 成长只挂有代价或天然单次的动作 · 零挂机 ·
卡面 ≤7 词 · 它和谁成张力对 · 随机不决定玩点。

---

## 1. Target 候选(6 选 3)

现役 5 张全是「牌型族 × 行为」定义;新增走**行为流派**方向(时机/变化/经济),
不再切分牌型覆盖(族间按覆盖面定价的原则不变:新 Target 只需回答「覆盖多少拍,给几倍」)。

| ID | 名称 | 卡面 | 流派 | 词汇成本 | 风险 |
|---|---|---|---|---|---|
| T-01 | 速弹 Shredder | Lock early: made hands ×4 | 时机(早锁)——身份之作,early_settle 钩子现成 | 零 | 与惯性/定格成套后可能过强 |
| T-02 | 万花筒 Kaleidoscope | Hand differs from last: ×4 | 变化——禁回/炒冷饭/曲目墙的构筑级答案 | 零(`diff_from_prev`) | 变化是自然发生的,倍率要按实测触发率压 |
| T-03 | 常青 Evergreen | Any made hand: ×2.5 | 通才保底,新手之家,低天花板 | 零 | 无聊风险;C3 说它该存在 |
| T-04 | 囤积 Hoarder | Holding 6+ coins: ×3.5 | 经济——独狼近亲,和利息/小费罐成套 | 零(`coins_gte`) | 与利息组成印钞回路,金币臂必测 |
| T-05 | 夜猫 Night Owl | Act late: made hands ×3.5 | 时机(压哨)——速弹的镜像 | 零(`acted_late`) | 与收线/封盘/赶场三堵墙正面相撞(这是卖点也是险点) |
| T-06 | 全场 Showman | Five-card hands: ×5 | 大牌通吃(顺/同花/葫芦跨族) | 小(`kind_in` 列表) | 跨族覆盖和族间定价原则的关系要先想清 |

---

## 2. Support 候选(45 选 ~34)

### 2.1 牌面族(记分牌过滤,普通,一个新操作码解锁全族)

`chip_per_card{filter}`:按参与成牌的牌逐张加 chips(吃全部倍率,早抽才值钱——B1 自动执行)。

| ID | 名称 | 卡面 | curve | 备注 |
|---|---|---|---|---|
| J-01 | 暖色 Warm Tone | Red scoring cards: +6 chips each | fixed | 红黑镜像对;两色 UI 直读 |
| J-02 | 冷色 Cool Tone | Black scoring cards: +6 chips each | fixed | 同上 |
| J-03 | 熟脸 Familiar Face | Scoring face cards: +12 chips each | fixed | 贵宾成套;蒙面/暗灯墙的赌点 |
| J-04 | 双数 Even Beat | Even cards: +5 chips each | fixed | 偶奇镜像对 |
| J-05 | 单数 Odd Groove | Odd cards: +5 chips each | fixed | 同上 |
| J-06 | 尖峰 Peak | Scoring Aces: +20 chips each | fixed | 高音的 chips 版;与独狼/低音墙联动 |

### 2.2 时机族(身份轴)

| ID | 名称 | 稀有度 | 卡面 | curve | 备注 |
|---|---|---|---|---|---|
| J-07 | 抢拍 Headstart | 普通 | First action within 2 seconds: +50 | burst | 尾声的镜像(早 vs 晚张力对) |
| J-08 | 谢幕 Curtain Call | 罕见 | Act in the final second: +60% | burst | 尾声的 % 大哥,窗口更窄更险 |
| J-09 | 定格 Freeze Frame | 罕见 | Early finish: next phrase +30% | burst | 时机×序列杂交;early_finish 事件现成 |
| J-10 | 双点 Two-Touch | 罕见 | Act early and late: +150 | burst | ⚠ 双窗口,阅读边缘,删选优先怀疑它 |
| J-11 | 半场 Halftime | 普通 | Phrases 3 and 4: +80 | burst | 段中商店相邻拍;`phrase_idx` 信号要加 |

### 2.3 序列族(身份轴)

| ID | 名称 | 稀有度 | 卡面 | curve | 备注 |
|---|---|---|---|---|---|
| J-12 | 复读 Reprise | 罕见 | Same hand as last: +50% | burst | 回响的 % 大哥;撞炒冷饭墙是自选的赌 |
| J-13 | 首演 Premiere | 罕见 | First time each hand type: +120 | burst | ⚠ A3 边缘:once-per-kind 旗标挂结算内容(无雷可踩,但要拍板) |
| J-14 | 回旋 Rondo | 罕见 | Alternate two hand types: +70 | burst | ⚠ 要两拍记忆窗(prev2),小词汇 |

(批 3 已含:变奏 J-B3 / 开场 J-B4,见 §2.9)

### 2.4 弃牌/牌流族

| ID | 名称 | 稀有度 | 卡面 | curve | 备注 |
|---|---|---|---|---|---|
| J-15 | 快手 Quick Hands | 普通 | Three discards this phrase: +100 | burst | `discards_gte 3` 零词汇;周转的阈值版 |
| J-16 | 断舍离 Declutter | 罕见 | Discard five at once: +50% | burst | 整手重置的胆量奖;要「单批大小」ctx;与一口气墙同语言 |

### 2.5 缓存/交换族(现役仅和弦一张,重点补)

| ID | 名称 | 稀有度 | 卡面 | curve | 备注 |
|---|---|---|---|---|---|
| J-17 | 静物 Still Life | 普通 | Zero swaps this phrase: +60 | burst | 小费罐的交换镜像;和弦成套(稳缓存流) |
| J-18 | 高阁 Top Shelf | 普通 | Cache all ten or higher: +120 | burst | 和弦同形状新谓词;贵宾/独狼配件 |
| J-19 | 排练 Rehearsal | 罕见 | Cache forms a run: +150 | burst | 阶梯流缓存配件;`cache_run` 小词汇 |
| J-20 | 三重唱 Trio | 罕见 | Cache three same rank: +200 | burst | 三连音流缓存配件 |

(批 3 已含:串场/伴唱,见 §2.9)

### 2.6 经济族(金币玩点全归构筑侧的拍板落地处)

| ID | 名称 | 稀有度 | 卡面 | curve | 备注 |
|---|---|---|---|---|---|
| J-21 | 分成 Royalties | 罕见 | Hand coin rewards are doubled | floating | coin 通路;牌型金币线的放大器 |
| J-22 | 回收 Resale | 罕见 | Jokers sell for full price | fixed | shelf 键;鼓励换血实验,后期金币水槽的润滑剂 |
| J-23 | 打赏 Tip-Out | 普通 | Early finish: +1 coin | burst | 时机×经济;和速弹/惯性一家 |
| J-24 | 淘碟 Crate Digger | 罕见 | Each reroll: +12 forever | growth | 成长挂付费动作(A4✓);把刷新从纯消费变投资 |
| J-25 | 铁粉 Superfan | 罕见 | +5% per 2 coins held | floating | 利息的分数版;囤积 Target 的 support 表亲 |

(批 3 已含:联票/赞助,见 §2.9——60 张口径下这两张从「候选」升为「前置」)

### 2.7 规则族(稀有)

| ID | 名称 | 卡面 | 词汇成本 | 备注 |
|---|---|---|---|---|
| J-26 | 延长音 Fermata | Phrases last 1 second longer | `phrase_duration()` 钩子现成 | **时间是唯一压力货币,这是构筑侧最纯的力量**;赶场的镜像。⚠ 与第四轮 6s 的叠加语义要拍板(6+1=7?还是终演豁免?) |
| J-27 | 低音谱 Bass Clef | Low cards count as 10 | `additive_face_value` 族的变体操作码 | 贵宾的镜像(小牌翻身);与低音墙梦幻联动 |
| J-28 | 首尾 Wraparound | Aces wrap straights | ⚠ 判定手术:pattern.gd + 求解器 + pair.gd 整线 | 标远期,除非阶梯流实测还需要第四张救援 |

### 2.8 平贴族(追牌型救援,普通,故意平淡——C3 的 sleeper 之家)

| ID | 名称 | 卡面 | 备注 |
|---|---|---|---|
| J-29 | 台阶灯 Step Light | Straights: +150 | stair 外挂,零词汇 |
| J-30 | 调色 Palette | Flushes: +120 | mono 外挂 |
| J-31 | 三重 Triple Bill | Trips or better: +100 | triplet 外挂 |
| J-32 | 全员 Full Cast | Five-card hands: +150 | 大牌通用垫;与 T-06 同覆盖不同通道 |
| J-33 | 独奏 Solo | High Card hands: +90 | 未成牌缓冲;独狼配件;失败拍的安慰剂 |

### 2.9 批 3 原案(8 张,并入本图谱重标)

| ID | 名称 | 稀有度 | 卡面 | curve | 状态 |
|---|---|---|---|---|---|
| J-B1 | 联票 Double Bill | 稀有 | Shops offer 4; buy up to 2 | fixed | **前置**(60 张池的搜索机制),用户点名 |
| J-B2 | 串场 Segue | 普通 | Swapped cards that score: +40 each | burst | 交换轴第一张 |
| J-B3 | 变奏 Variation | 普通 | Different hand than last phrase: +50 | burst | 零词汇;回响镜像 |
| J-B4 | 开场 Opener | 罕见 | First phrase of section: +80% | burst | 副歌镜像 |
| J-B5 | 高音 High Note | 普通 | An Ace in hand: +60 | burst | 零词汇 |
| J-B6 | 头条 Headliner | 罕见 | Hands with 200+ base: +50% | burst | 零词汇;追大牌放大器 |
| J-B7 | 伴唱 Backup | 普通 | Cache all face cards: +150 | burst | 贵宾成套 |
| J-B8 | 赞助 Sponsor | 罕见 | Shop cards cost 1 less | fixed | **前置**(同 J-B1) |

### 2.10 杂项/试验

| ID | 名称 | 稀有度 | 卡面 | curve | 备注 |
|---|---|---|---|---|---|
| J-34 | 空位 Empty Seats | 罕见 | +8% per empty support slot | floating | 反槽位经济:买卡自削——「要不要第三张卡」第一次成为问题 |
| J-35 | 烟花 Fireworks | 罕见 | ×2.5, leaves after this section | decay | ⚠ 第二张衰减(C5 上限 2);自毁机制要小钩子;「租一段的稀有力量」 |
| J-36 | 灯串 House Lights | 普通 | +50 and +1 coin | fixed | 第二张无条件甜品(C4 上限 2);双通道小甜水 |
| J-37 | 铜管 Brass | 罕见 | Made hands: +25% | fixed | 无条件 %,删选优先怀疑(荧光棒的无聊版) |
| J-38 | 收藏家 Collector | 罕见 | Each card bought: +15 forever | growth | 成长挂购买(有代价 A4✓) |

---

## 3. 新增词汇账单(实现前过 D1 门)

| 成本 | 内容 | 解锁 |
|---|---|---|
| 零 | `diff_from_prev` `base_gte` `top_rank_gte` `coins_gte` `kind/kind_in` `acted_late` `discards_gte` | T-02/04/05、J-B3/B5/B6、J-15、J-29~33 等 12+ 张 |
| 小(谓词/信号) | `first_phrase` `phrase_idx` `swaps 计数` `批量大小` `cache_min_rank` `cache_run` `cache_rank_trio` `cache_all_faces` `prev2` | 时机/缓存/序列三族 |
| 中(操作码) | `chip_per_card{filter}`(解锁整个牌面族 6 张) · `additive_low_value` · shelf 键扩展(联票/赞助/回收) · 自毁(烟花) | 牌面族、规则族、经济族 |
| 大(手术,标远期) | 判定层(首尾 J-28) | 单卡 |

## 4. 删选建议与回传格式

超额约 1/3。建议按族删:每族至少留一对张力(早 vs 晚、动 vs 稳、红 vs 黑),
单卡自足 ≥2/3,⚠ 标记的六张(J-10/13/14/28/35/37)优先怀疑。
删完后我按 60 口径重写 jokers.md 配额表、`curve` 进 schema、逐张入 json(数值留你调)。

```text
Target 保留:T-0x, T-0x, T-0x
Support 删除:J-xx, J-xx, ...
系统三旋钮:联票赞助前置 同意/否;按段权重软旋钮 留档/删;curve 进 schema 同意/否
需要拍板:延长音×第四轮语义 / 首演 A3 边缘 / 烟花 C5 第二席
```
