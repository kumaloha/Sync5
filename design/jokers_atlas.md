# 小丑牌候选图谱(批 3 · 60 张口径)

> **状态:候选池,等待人工删选;不是已批准内容,数值全部只是量级示意。**
>
> 用户拍板(2026-08-10):**roster 总数 60 张;候选出到 100 再做减法**(与盲注图谱同方法:
> 先覆盖空间,再由人判断趣味、重复、成本与平衡——候选池里有大量不好的,那是覆盖的成本不是事故)。
> 拆分建议:Target 8(现役 5 + 新 3)+ Support 52(现役 18 + 新 34)。
> 本图谱提供 **Target 候选 9 + Support 候选 92 = 101 张**,约 2.7 倍超额。
> 现役 23 张是底座,本文不动它们。
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
| J-10 | 双点 Two-Touch | 普通 | Act early and late: +150 | burst | ⚠ 双窗口,阅读边缘,删选优先怀疑它 |
| J-11 | 半场 Halftime | 普通 | Phrases 3 and 4: +80 | burst | 段中商店相邻拍;`phrase_idx` 信号要加 |

### 2.3 序列族(身份轴)

| ID | 名称 | 稀有度 | 卡面 | curve | 备注 |
|---|---|---|---|---|---|
| J-12 | 复读 Reprise | 罕见 | Same hand as last: +50% | burst | 回响的 % 大哥;撞炒冷饭墙是自选的赌 |
| J-13 | 首演 Premiere | 普通 | First time each hand type: +120 | burst | ⚠ A3 边缘:once-per-kind 旗标挂结算内容(无雷可踩,但要拍板) |
| J-14 | 回旋 Rondo | 普通 | Alternate two hand types: +70 | burst | ⚠ 要两拍记忆窗(prev2),小词汇 |

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
| J-19 | 排练 Rehearsal | 普通 | Cache forms a run: +150 | burst | 阶梯流缓存配件;`cache_run` 小词汇 |
| J-20 | 三重唱 Trio | 普通 | Cache three same rank: +200 | burst | 三连音流缓存配件 |

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
| ~~J-37~~ | ~~铜管 Brass~~ | — | ~~Made hands: +25%~~ | — | ❌ **自查出局(B2)**:无条件 % 不是任何档位的合法货币——荧光棒的无条件 % 是拿衰减付的税,这张什么都没付 |
| J-38 | 收藏家 Collector | 罕见 | Each card bought: +15 forever | growth | 成长挂购买(有代价 A4✓) |

### 2.11 牌面族续(花色与点数结构)

| ID | 名称 | 稀有度 | 卡面 | curve | 备注 |
|---|---|---|---|---|---|
| J-39 | 彩虹 Rainbow | 普通 | All four suits in hand: +150 | burst | 反同花纹理;与单色流互斥的张力对 |
| J-40 | 同色 One Color | 普通 | All cards one color: +100 | burst | 双色调的 burst 小弟;两色 UI 直读 |
| J-41 | 清唱 A Cappella | 普通 | No face cards: +90 | burst | 反贵宾路线;与低音谱/低声部成套 |
| J-42 | 双 A Pocket Aces | 普通 | A pair of Aces: +150 | burst | ⚠ 彩票感;高音/尖峰家族的尖子 |
| J-43 | 高声部 Treble | 普通 | Tens and up: +7 chips each | fixed | chip_per_card 家族;与高阁成套 |
| J-44 | 低声部 Bass Section | 普通 | Fives and under: +9 chips each | fixed | 小牌流的 chips 底座 |
| J-45 | 中音 Midrange | 普通 | Sixes through nines: +8 chips each | fixed | ⚠ 纯填充嫌疑,删选优先怀疑 |
| J-46 | 清流 No Pair | 普通 | No pair in hand: +60 | burst | 反对子纹理;顺/同花/独狼三路的垫 |

### 2.12 弃牌内容族(弃「什么」——A2 四行为里最没被开发的半格)

| ID | 名称 | 稀有度 | 卡面 | curve | 备注 |
|---|---|---|---|---|---|
| J-47 | 让位 Stage Exit | 普通 | Each face card discarded: +30 | burst | 反贵宾路线的燃料;蒙面墙下变盲赌 |
| J-48 | 拆台 Breakup | 普通 | Discard a pair: +100 | burst | 牺牲机制:拆掉现成对子换分,twin 的对家 |
| J-49 | 舍身 Sacrifice | 普通 | Discard your highest card: +80 | burst | ⚠ 「最高」要标记,阅读边缘 |
| J-50 | 拾荒 Scavenger | 普通 | Each discard: +1 coin | burst | ⚠ A4 张力:弃牌免费,仅时间限流;金币臂必测 |
| J-51 | 早弃 Early Purge | 普通 | All discards before 4 seconds: +80 | burst | 收线墙的训练卡;时机×弃牌 |
| J-52 | 组合拳 Combo | 普通 | Swap and discard this phrase: +80 | burst | 双动词教学(走台候选的奖励侧转世) |

### 2.13 缓存/交换族续

| ID | 名称 | 稀有度 | 卡面 | curve | 备注 |
|---|---|---|---|---|---|
| J-53 | 暖房 Greenhouse | 普通 | Cache all one color: +100 | burst | 和弦的宽松版;条件易读 |
| J-54 | 候场 Understudies | 普通 | Cache holds a pair: +80 | burst | 三重唱的小弟 |
| J-55 | 保险柜 Vault | 罕见 | Untouched cache all section: +150% | burst | ⚠ 段级状态管道;与丢谱/翻篇/墨迹墙对赌,大赌卡 |
| J-56 | 原班 Original Cast | 普通 | Settle the dealt hand: +120 | burst | 零弃+零换的胆量封顶;小费罐/静物一家 |
| ~~J-57~~ | ~~走位 Footwork~~ | — | ~~+30 per swap this phrase~~ | — | ❌ **自查出局(A4)**:交换免费且次数无上限,按次付钱 = 来回换牌刷分机。我起初写的「自然封顶」是错的——串场(J-B2)要求参与成牌才有上限,这张没有 |

### 2.14 时机/序列族续(身份轴加厚)

| ID | 名称 | 稀有度 | 卡面 | curve | 备注 |
|---|---|---|---|---|---|
| J-58 | 换手 Opening Swap | 普通 | First action a swap: +60 | burst | 动词顺序条件;岔轨墙联动 |
| J-59 | 休止符 Rest Note | 普通 | Untouched phrase: +120 | burst | ⚠ 反决策密度边缘:玩点=「这拍歇不歇」,乐理上很美,删选时想清楚 |
| J-60 | 渐强 Crescendo | 普通 | Beat last phrase's score: +60 | burst | 自链棘轮;⚠ 轻微藏分动机 |
| J-61 | 秒表 Stopwatch | 罕见 | +8% per second left at settle | burst | 速弹 Target 的最佳拍档;时间→分数的字面翻译 |
| J-62 | 压轴 Grand Finale | 罕见 | Final section: +100% | burst | S4 特化;和 6s+返场共舞 |
| J-63 | 快闪 Pop-Up | 普通 | Section one only: +200 | decay | ⚠ 衰减席位(≤2):悬崖式,glowstick 是坡式 |
| J-64 | 热场 Warm-Up Act | 普通 | +100, fades 10 each phrase | decay | ⚠ 同上,线性版;四张衰减候选选二 |

### 2.15 经济族续(金币玩点的主战场)

| ID | 名称 | 稀有度 | 卡面 | curve | 备注 |
|---|---|---|---|---|---|
| J-65 | 全下 All-In | 罕见 | Spend every coin: +30% | burst | ⚠ 跨商店→拍状态管道;反利息的张力对 |
| J-66 | 穷开心 Broke & Happy | 稀有 | Coins cap at 5; +35% | fixed | 自断经济换常驻力量;与利息/囤积互斥 |
| J-67 | 常客 Regular | 稀有 | Rerolls cost nothing | fixed | 60 张池的搜索机制之三(联票/赞助之后) |
| J-68 | 守财 Saver | 罕见 | Buy nothing at shop: +40% | burst | ⚠ 反构筑动机(不买卡变强),想清楚再留 |
| J-69 | 打包 Doggy Bag | 普通 | Double the target: +3 coins | burst | 溢出分→金币;twin 的天然伴生 |
| J-70 | 逆袭 Underdog | 罕见 | Behind target at settle: +40% | burst | ⚠ 橡皮筋手感;落后补偿 |
| J-71 | 预支 Advance | 罕见 | 8 coins now, then −1 each phrase | decay | ⚠ 自愿贷款(不违金币禁令——那是盲注侧的);feel-bad 风险 |
| J-72 | 常规 Bread & Butter | 普通 | Pairs: +1 coin | burst | twin 经济引擎;平淡而有家 |
| J-73 | 加薪 Raise | 罕见 | Section wages: +2 coins | fixed | 工资线放大;最朴素的经济卡 |
| J-74 | 告别 Farewell Show | 罕见 | Sell a joker: next phrase +150 | burst | ⚠ 卖卡→下拍状态管道;换血流的润滑 |
| J-75 | 点唱机 Jukebox | 稀有 | Shops always offer a rule card | fixed | 定向搜索(独狼 target_guaranteed 先例);规则流的可靠性来源 |

### 2.16 规则/牌库/信息族续

| ID | 名称 | 稀有度 | 卡面 | curve | 备注 |
|---|---|---|---|---|---|
| J-76 | 保底 Floor | 罕见 | High Card scores as Pair | fixed | kind 重映射(结算层,非判定手术);新手/独狼垫。与 J-77 同族选一 |
| J-77 | 升格 Promotion | 稀有 | Two Pair scores as Trips | fixed | 同上;三连音路线的桥 |
| J-78 | 转型 Reinvention | 罕见 | Each Target change: +40% forever | growth | 成长挂换旗(有代价 A4✓);pivot 弧的奖励侧 |
| J-79 | 修剪 Trim | 稀有 | Twos and threes leave deck | fixed | 牌库手术(enable_wilds 先例);抽牌质量的构筑投资 |
| J-80 | 加签 Extra Aces | 稀有 | Two extra Aces join deck | fixed | 牌库注入;高音/尖峰/独狼一家 |
| J-81 | 第六人 Sixth Man | 稀有 | Draw a sixth card each phrase | fixed | ⚠ 手牌布局手术;若聚光 boon 落地则机制现成 |
| J-82 | 透牌 X-Ray | 稀有 | Preview your next refill | fixed | 信息增益卡(构筑侧唯一);被砍的预视 boon 转世;belief 通路 |
| J-83 | 盲奏 Blind Play | 罕见 | +15 chips per hidden card | fixed | 只在蒙面/暗补/暗灯墙下点亮——不读脸 ID 的墙联动;C3 sleeper 典型 |
| J-84 | 半途 Halfway | 普通 | Three ranks in a row: +80 | burst | 顺子上坡垫;与台阶灯/排练一家 |
| J-85 | 大满贯 Jackpot | 普通 | Quads or better: +500 | burst | ⚠ 彩票尖峰;kind_in 零词汇 |

### 2.17 Target 候选续

| ID | 名称 | 卡面 | 流派 | 备注 |
|---|---|---|---|---|
| T-07 | 拆迁 Demolition | Three discards: made hands ×3.5 | 弃牌行为流 | 周转/快手/黑胶的旗;与配给墙对赌 |
| T-08 | 串流 Flow | After a swap: hands ×3 | 交换行为流 | 交换轴的旗;单换墙下每拍一次抉择 |
| T-09 | 满花 All Suits | Four suits in hand: ×4 | 反同花纹理流 | 彩虹的旗;与单色正面互斥 |

### 2.18 有意不开的空间(不是漏了,是不该去)

| 空间 | 不开的理由 |
|---|---|
| 第二张复制卡 | B4 槽序无意义 → 邻位复制无法定义;镜面保持唯一(C6) |
| 万能牌扩张(第三张 wild) | 判定暴力代入 ≤2 是引擎硬顶 |
| 读脸 ID 的卡(「某某墙下 ×2」) | 盲注不检查小丑,反向也一样——耦合爆炸;盲奏(J-83)读的是「盖住的牌」这个状态,不是脸 ID,是唯一合法形态 |
| 主角联动卡 | 主角 roster 自己还是初稿,过早耦合 |
| 主动技能卡 | 全被动是拍板(8 秒的注意力归时钟) |
| 算术条件卡(「手牌点数和 ≥N」) | 压力语言是操作不是心算 |

### 2.19 标准自查记录(2026-08-10,用户点名「回忆标准再说」之后补)

对照 design/jokers.md 的 A1–A5 / B1–B4 / C1–C6 / D1–D3 逐张过了一遍,结果:

| 处置 | 卡 | 违反的条款 |
|---|---|---|
| **出局 ×2** | 走位(J-57) | A4:交换免费且无限,按次付钱 = 刷分机 |
| | 铜管(J-37) | B2:无条件 % 不是任何档位的合法货币 |
| **降普通 ×12** | 双点/首演/回旋/排练/三重唱/双A/清流/拆台/舍身/原班/休止符/大满贯 | B2:**平加(+N)是普通档的货币**——「条件更难」不是货币,不能靠它抬稀有度 |
| **升罕见 ×1** | 逆袭(J-70) | B2 反向:条件 % 不是普通档的货币 |
| **降罕见 ×1** | 保险柜(J-55) | B2:% 不是稀有档的货币(稀有 = ×倍率/复制/改规则) |
| **待改支付 ×1** | 穷开心(J-66) | 保稀有的话,回报应从 +35% 改成 ×1.3 一类(规则是稀有货币,报酬也该是) |

我犯的系统性错误就一条:**拿条件难度当稀有度**——这是 B2「升稀有度只许换货币、不许只加大数字」的镜像违规。
另有四张衰减形(荧光棒现役/烟花/快闪/热场)争 ≤2 席、两张无条件甜品(灯牌现役/灯串)争 ≤2 席,删选时按席位裁。

---

## 3. 新增词汇账单(实现前过 D1 门)

| 成本 | 内容 | 解锁 |
|---|---|---|
| 零 | `diff_from_prev` `base_gte` `top_rank_gte` `coins_gte` `kind/kind_in` `acted_late` `discards_gte` | T-02/04/05、J-B3/B5/B6、J-15、J-29~33 等 12+ 张 |
| 小(谓词/信号) | `first_phrase` `phrase_idx` `swaps 计数` `批量大小` `cache_min_rank` `cache_run` `cache_rank_trio` `cache_all_faces` `prev2` | 时机/缓存/序列三族 |
| 中(操作码) | `chip_per_card{filter}`(解锁整个牌面族 6 张) · `additive_low_value` · shelf 键扩展(联票/赞助/回收) · 自毁(烟花) | 牌面族、规则族、经济族 |
| 大(手术,标远期) | 判定层(首尾 J-28) | 单卡 |

## 4. 删选建议与回传格式

自查后有效候选 **99 张**(2 张出局见 §2.19),对 37 个名额约 2.7 倍超额——按你的方法论,大量不好是覆盖的成本。
建议按族删:每族至少留一对张力(早 vs 晚、动 vs 稳、红 vs 黑、存 vs 花),
单卡自足 ≥2/3,带 ⚠ 的十余张优先怀疑,四张衰减选一、两张甜品选一。
删完后我按 60 口径重写 jokers.md 配额表、`curve` 进 schema、逐张入 json(数值留你调)。

```text
Target 保留:T-0x, T-0x, T-0x
Support 删除:J-xx, J-xx, ...
系统三旋钮:联票赞助前置 同意/否;按段权重软旋钮 留档/删;curve 进 schema 同意/否
需要拍板:延长音×第四轮语义 / 首演 A3 边缘 / 烟花 C5 第二席
```

---

## 5. 终选 60(2026-08-10 筛选+融合,待用户复核)

**60 = 现役 23 + 新 Target 3 + 新 Support 34。**

### 5.1 新 Target(3):行为流派补齐动词矩阵

| 卡 | 卡面 | 流派 |
|---|---|---|
| 速弹 Shredder | Lock early: made hands ×4 | 时机(身份之作;秒表/惯性/定格成套) |
| 万花筒 Kaleidoscope | Hand differs from last: ×4 | 变化(禁回/炒冷饭/曲目墙的构筑级答案) |
| 拆迁 Demolition | Three discards: made hands ×3.5 | 弃牌(周转/黑胶/贝斯线终于有旗;与配给墙对赌) |

Target 8 = 牌型四旗(双子/阶梯/单色/三连音)+ 行为四旗(独狼=不弃/拆迁=狠弃/速弹=快/万花筒=变)。
落选:夜猫(与速弹同轴,Target 层互斥自动成立、镜像价值低)、囤积(独狼的地盘)、
串流(「换过就 ×3」一次免费交换就满足,条件太贱)、常青/满花/全场(纹理位交给 support)。

### 5.2 新 Support(34,按族)

**时机+序列(9,连现役 5 张达标 ≥14 的身份线)**
秒表(罕/burst)· 谢幕(罕/burst)· 定格(罕/burst)· 早弃(普/burst)· 快闪(普/decay)
· 变奏(普/burst)· 开场(罕/burst)· 渐强(普/burst)· 复读(罕/burst)

**缓存/交换(5,连和弦 =6 达标)**
串场(普/burst)· 静物(普/burst)· 排练(普/burst)· 三重唱(普/burst)· 伴唱(普/burst)

**牌面(6)**
暖色(普/fixed)· 冷色(普/fixed)· 低声部(普/fixed)· 彩虹(普/burst)· 清流(普/burst)· 全员(普/burst)

**弃牌内容(2)**
断舍离(罕/burst)· 让位(普/burst)

**经济(5;连现役 2 + 收藏家铁粉 = 9)**
联票(稀/fixed,前置)· 赞助(罕/fixed,前置)· 打包(普/burst)· 分成(罕/floating)· 淘碟(罕/growth)

**成长/浮动补位(2)**
收藏家(罕/growth,每买一张 +15 永久)· 铁粉(罕/floating,+5%/2◆)

**规则/牌库/信息(5)**
穷开心(稀/fixed,"Coins cap at 5; ×1.3" —— 顶替被砍的延长音,报酬按 B2 改成 ×;见 §5.4 裁决)
· 低音谱(罕/fixed,vip 先例降罕见)· 转型(罕/growth)· 修剪(稀/fixed)· 透牌(罕/fixed,信息轴唯一)

### 5.3 配额审计(52 张 Support)

| 维度 | 实配 | 目标 | 偏差说明 |
|---|---|---|---|
| rarity | 普 24 / 罕 20 / 稀 **8** | 24/18/10 | **稀有刻意少 2**:8 张时特定稀有卡一局出现率 ≈12.5%,10 张就掉破 10%——稀释保护优先,批 4 再补 |
| curve | burst 25 / fixed 15 / growth 6 / floating 4 / decay 2 | 22/10/8/6/2 | 成长与浮动缺口是**A4 合法驱动稀缺**所致(付费动作就那几种),不硬凑;burst 超编是牌面/平贴族天性 |
| 功能轴 | 时机+序列 14 ✓ · 经济 9 ✓ · 规则 9(超 1)· 缓存/交换 6 ✓ · 复制 1 ✓ · 甜品 1 ✓ · 衰减 2 ✓ 不入稀有 ✓ | — | — |

### 5.4 融合与交互斩杀记录(减法的理由,逐条可翻案)

**融合(数字档位并入本体)**:常规⊂分成 · 台阶灯/调色⊂全员 · 候场⊂三重唱 · 高阁⊂伴唱
· 暖房⊂和弦 · 快手⊂拆迁(Target 化)· 原班⊂静物+小费罐 · 半途⊂排练 · 尖峰/高音⊂独狼现役路
· 清唱⊂低声部+低音谱(低牌路两张卡撑得起,三张太肥)· 加薪⊂工资数值表(改 economy.json 不用发卡)。

**交互斩杀(单卡合格、组合违法)**:
- **保底/升格**:kind 重映射连根改 Target 触发条件——保底+双子 = 垃圾手全额触发 ×6。这类卡要等「重映射×Target」交互规则先定。
- **常客×淘碟**:免费刷新 × 每刷新永久成长 = 无限成长环;且「刷新免费」抹掉整条刷新定价经济,属排他性 overpower(C4 判死)。留淘碟杀常客。
- **第六人×聚光**:与 S4 聚光 boon 机制重复——持有它时开出聚光 = 空气,正是盲注审查里「返场开出已购牌」的同款病。
- **烟花**:双重违法无处安放(× 是稀有货币,而衰减不许入稀有)。
- **盲奏**:只在三张信息墙下点亮(≈12% 的段)——低频答案,死于用户判据。
- **独奏/熟脸**:为成长/浮动补位让路(收藏家/铁粉 顶替),独奏另有「奖励失败拍」的决策密度疑点。

**2026-08-10 用户裁决与后续**:

- **延长音:砍**(用户:「谁差这一秒」)。教训入册:**有用但无感 = 没用**——+1 秒在模型里
  可测(rush 实测 −837),在幻想里一文不值,卡的价值必须能被"感受"而不只是被"测量"。
  顺带立了先例:若将来再有时间卡,与 S4 固定 6s **直接叠加**(6→7s),不做豁免。
  顶替:穷开心(报酬 ×1.3,B2 合法);备选:加签 / 点唱机。
- **拆迁 × 配给(对赌数学)**:12 额度 ÷ 每拍 3 张 = 只能点亮 4/6 拍,
  产出上限 ≈76%(−24%),属 bend 不属 brick;且「三次弃牌」**按张数计不按按键计**,
  一口气墙(单次确认弃任意张)不砖它。实装后跑交叉臂(拆迁队列 × ration@S3 到达者死亡率),
  健康带 30–60%,超 70% 的旋钮:额度 12→15(税收敛到 −12%)或触发 3→2 张。
- **稀有档 8 张(稀释账)**:特定稀有卡一局出现率 12.3%(约 8 局一遇);
  补到 10 张 → 10.0%,12 张 → 8.4%。联票落地后货架曝光 +33%(21→28 位),
  8 张口径回到 ≈16%——**补员窗口在联票实装之后**,不在现在。
