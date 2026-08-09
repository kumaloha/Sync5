# Balatro 小丑牌深度调研(阶段② 设计前置研究)

> 2026-08 由三个并行调研 agent 产出:①全量普查(150/150 张,四轴分类统计);
> ②设计意图(LocalThunk 访谈/博客 + 社区分析,17 条原则);③结算时序与成长机制深挖。
> 数据源以 balatrowiki.org 为主(fandom 402 不可用),分类统计脚本见会话 scratchpad `balatro_jokers.py`。
> 本文件是参考研究,不是 Sync5 设计决定;Sync5 侧结论见对话记录与后续 05 号文档修订。

---

# Balatro 全量小丑牌普查与四轴分类报告

**数据源**:balatrowiki.org /w/Jokers(版本 1.0.1o-FULL,官方口径共 150 张);fandom 镜像返回 HTTP 402,未采用。实抓 150/150:普通 (Common) 61、罕见 (Uncommon) 64、稀有 (Rare) 20、传说 (Legendary) 5,与已知分布完全一致。

**标签口径**(统计只计主标签,副标签在观察中说明):
- 成长型小丑(如 Ride the Bus、Vampire)的「触发时机」按**效果结算位置**记(多为独立常驻),成长事件放入条件/曲线轴;
- 「带重置的成长」(Ride the Bus / Obelisk / Campfire / Hit the Road,共 4 张)计入永久成长并单独说明;
- Cavendish 的 1/1000 自毁视作可忽略,计固定收益;Gros Michel 的 1/6 计衰减/自毁;
- 传说牌不进商店,价格记「—」。

---

## A. 分布统计

### 轴1 作用通道(主标签)

| 通道 | 张数 | 占比 |
|---|---|---|
| ×Mult | 35 | 23.3% |
| +Mult | 33 | 22.0% |
| +Chips | 20 | 13.3% |
| 金钱 | 19 | 12.7% |
| 规则改变 | 10 | 6.7% |
| 生成消耗牌 | 8 | 5.3% |
| 重触发 | 6 | 4.0% |
| 生成/改造卡牌 | 5 | 3.3% |
| 手牌上限 | 3 | 2.0% |
| 复制其他小丑 | 3 | 2.0% |
| 弃牌次数 | 2 | 1.3% |
| 牌型升级(其他) | 2 | 1.3% |
| 出牌次数 | 1 | 0.7% |
| 牌堆改造 | 1 | 0.7% |
| 其他(生成小丑 Riff-Raff / 生成 Tag Diet Cola) | 2 | 1.3% |

### 轴2 触发时机(主标签)

| 时机 | 张数 | 占比 |
|---|---|---|
| 独立常驻(结算末尾) | 65 | 43.3% |
| 出牌计分时(逐牌/整手) | 33 | 22.0% |
| 被动(常驻改规则) | 17 | 11.3% |
| 回合结束时 | 8 | 5.3% |
| 选盲注时(含回合开始) | 7 | 4.7% |
| 概率触发 | 6 | 4.0% |
| 买卖时或商店时 | 6 | 4.0% |
| 手中持有时 | 4 | 2.7% |
| 弃牌时 | 4 | 2.7% |

### 轴3 条件维度(主标签)

| 条件 | 张数 | 占比 |
|---|---|---|
| 无条件 | 47 | 31.3% |
| 特定点数或人头 | 24 | 16.0% |
| 特定牌型 | 20 | 13.3% |
| 特定花色 | 13 | 8.7% |
| 牌堆构成 | 10 | 6.7% |
| 剩余资源(弃牌/最后一手) | 5 | 3.3% |
| 连续行为 | 5 | 3.3% |
| 出牌张数 | 4 | 2.7% |
| 金钱阈值 | 4 | 2.7% |
| 其他(槽位/自伤/依赖对象/Boss/计轮等长尾) | 18 | 12.0% |

### 轴4 时间曲线(主标签)

| 曲线 | 张数 | 占比 |
|---|---|---|
| 条件爆发 | 64 | 42.7% |
| 固定收益 | 31 | 20.7% |
| 永久成长(含 4 张带重置) | 29 | 19.3% |
| 资源浮动 | 16 | 10.7% |
| 衰减或自毁 | 6 | 4.0% |
| 延迟兑现 | 4 | 2.7% |

### 交叉表 1:稀有度 × 作用通道

| 通道 | 普通 | 罕见 | 稀有 | 传说 | 合计 |
|---|---|---|---|---|---|
| ×Mult | 2 | 18 | 12 | 3 | 35 |
| +Mult | 26 | 7 | 0 | 0 | 33 |
| +Chips | 14 | 4 | 2 | 0 | 20 |
| 金钱 | 11 | 8 | 0 | 0 | 19 |
| 规则改变 | 1 | 8 | 0 | 1 | 10 |
| 生成消耗牌 | 3 | 3 | 1 | 1 | 8 |
| 重触发 | 1 | 5 | 0 | 0 | 6 |
| 生成/改造卡牌 | 0 | 4 | 1 | 0 | 5 |
| 手牌上限 | 1 | 2 | 0 | 0 | 3 |
| 复制小丑 | 0 | 0 | 3 | 0 | 3 |
| 牌型升级 | 0 | 1 | 1 | 0 | 2 |
| 弃牌次数 | 1 | 1 | 0 | 0 | 2 |
| 出牌次数 | 0 | 1 | 0 | 0 | 1 |
| 牌堆改造 | 0 | 1 | 0 | 0 | 1 |
| 其他 | 1 | 1 | 0 | 0 | 2 |
| **合计** | **61** | **64** | **20** | **5** | **150** |

### 交叉表 2:稀有度 × 时间曲线

| 曲线 | 普通 | 罕见 | 稀有 | 传说 | 合计 |
|---|---|---|---|---|---|
| 条件爆发 | 34 | 19 | 10 | 1 | 64 |
| 固定收益 | 11 | 16 | 2 | 2 | 31 |
| 永久成长 | 8 | 15 | 4 | 2 | 29 |
| 资源浮动 | 5 | 8 | 3 | 0 | 16 |
| 衰减/自毁 | 3 | 3 | 0 | 0 | 6 |
| 延迟兑现 | 0 | 3 | 1 | 0 | 4 |

---

## B. 关键观察

1. **×Mult 是稀有度的硬通货,渗透率单调上升**:普通 2/61 (3.3%) → 罕见 18/64 (28.1%) → 稀有 12/20 (60%) → 传说 3/5 (60%)。而且普通仅有的两张 ×Mult 都被上了枷锁——Cavendish 带自毁风险、Photograph 只对首张人头生效。价格同样说明问题:×Mult 均价 $6.84,远高于 +Mult 的 $4.91 和 +Chips 的 $4.95。
2. **加法是低稀有度的专利**:33 张 +Mult 中 26 张 (79%) 是普通,稀有和传说合计 0 张;稀有档的加法通道只剩 2 张 +Chips,且都数值极端化(Stuntman 一次给 250、Wee Joker 无上限成长)。稀有度爬升 = 从"+"换成"×",而不是把"+"的数字调大。
3. **永久成长的重心压在罕见档,且"普通做加法成长、罕见做乘法成长"**:29 张成长牌中罕见占 15 张 (占罕见档 23.4%),普通 8 张、稀有 4 张、传说 2 张。普通档的成长全是小步加法(Supernova、Green Joker、Runner、Square、Red Card、Egg 等);×Mult 型成长(Constellation、Hologram、Vampire、Lucky Cat、Glass、Madness、Throwback、Campfire、Obelisk、Canio、Yorick…)除 0 张在普通外全部位于罕见及以上。
4. **条件牌与无条件牌约 2.2 : 1**:无条件 47 张 (31.3%),带条件 103 张 (68.7%)。条件爆发是最大曲线类 (64 张,42.7%),且在普通档最密——普通 34/61 (55.7%) 是条件爆发,承担"教玩家围绕条件构筑"的教学职能;固定收益反而在罕见档最多 (16 张),多为规则改变类被动。
5. **三分之二的牌挂在计分管线上**:独立常驻 65 (43.3%) + 计分时 33 (22%) + 手持 4 = 68%;剩下约 1/3 (被动 17、回合末 8、选盲注 7、商店 6、概率 6、弃牌 4) 把小丑的存在感铺到商店、选盲注、弃牌等非计分节拍上——每个游戏节拍都有牌在"说话"。
6. **衰减/自毁只有 6 张 (4%),全部在普通/罕见,价格≤$6**:Gros Michel、Ice Cream、Popcorn (普通),Turtle Bean、Ramen、Seltzer (罕见)。它们的共性是数值超额报价(如 Ice Cream +100 Chips 对比同价常驻牌的 +30~50),定位是"前期租赁、逼你中期换掉"。稀有/传说 0 张——高稀有度从不衰减。
7. **金钱通道 19 张全部集中在普通 (11) / 罕见 (8),稀有以上 0 张**;与之配对的是把钱转成分数的资源浮动牌(Bull、Bootstraps,金钱阈值条件共 4 张)。经济引擎被刻意压在低稀有度,保证任何一局的前期商店都能组出现金流。
8. **稀有档的身份 = ×Mult 爆发 + 复制**:20 张稀有中,5 张是统一定价 $8 的牌型爆发套 (The Duo/Trio/Family/Order/Tribe),3 张是全游戏仅有的复制牌 (Blueprint $10、Brainstorm $10、Invisible $8;复制通道均价 $9.33 为全通道最高),再加 Baron/Obelisk/Campfire 等成长×Mult。工具型通道(重触发、手牌上限、弃牌、金钱)在稀有档完全消失。
9. **"轮换条件"是一个隐性家族**:Ancient、Castle、The Idol、To Do List、Mail-In Rebate 共 5 张的条件每回合随机更换——用随机轮换把"特定花色/点数/牌型"类条件从构筑锁定变成回合适应,分散在 4 个通道里。
10. **概率主标签仅 6 张 (4%),但存在一张放大器**:8 Ball、Business Card、Space、Bloodstone、Reserved Parking、Hallucination 为概率主导;Oops! All 6s (规则改变) 专门翻倍所有概率,再加 Gros Michel/Cavendish 的自毁掷骰作副标签——概率作为主机制刻意保持低占比,但给了它一张全局杠杆牌。

---

## C. 全量清单(150 张)

稀有度:普通=Common,罕见=Uncommon,稀有=Rare,传说=Legendary。

| 名称 | 稀有度 | 价格 | 效果 | 通道 | 触发 | 条件 | 曲线 |
|---|---|---|---|---|---|---|---|
| Joker | 普通 | $2 | +4 Mult | +Mult | 独立常驻 | 无条件 | 固定收益 |
| Greedy Joker | 普通 | $5 | 方块牌计分时+3 Mult | +Mult | 计分时 | 特定花色 | 条件爆发 |
| Lusty Joker | 普通 | $5 | 红心牌计分时+3 Mult | +Mult | 计分时 | 特定花色 | 条件爆发 |
| Wrathful Joker | 普通 | $5 | 黑桃牌计分时+3 Mult | +Mult | 计分时 | 特定花色 | 条件爆发 |
| Gluttonous Joker | 普通 | $5 | 梅花牌计分时+3 Mult | +Mult | 计分时 | 特定花色 | 条件爆发 |
| Jolly Joker | 普通 | $3 | 含对子+8 Mult | +Mult | 独立常驻 | 特定牌型 | 条件爆发 |
| Zany Joker | 普通 | $4 | 含三条+12 Mult | +Mult | 独立常驻 | 特定牌型 | 条件爆发 |
| Mad Joker | 普通 | $4 | 含两对+10 Mult | +Mult | 独立常驻 | 特定牌型 | 条件爆发 |
| Crazy Joker | 普通 | $4 | 含顺子+12 Mult | +Mult | 独立常驻 | 特定牌型 | 条件爆发 |
| Droll Joker | 普通 | $4 | 含同花+10 Mult | +Mult | 独立常驻 | 特定牌型 | 条件爆发 |
| Sly Joker | 普通 | $3 | 含对子+50 Chips | +Chips | 独立常驻 | 特定牌型 | 条件爆发 |
| Wily Joker | 普通 | $4 | 含三条+100 Chips | +Chips | 独立常驻 | 特定牌型 | 条件爆发 |
| Clever Joker | 普通 | $4 | 含两对+80 Chips | +Chips | 独立常驻 | 特定牌型 | 条件爆发 |
| Devious Joker | 普通 | $4 | 含顺子+100 Chips | +Chips | 独立常驻 | 特定牌型 | 条件爆发 |
| Crafty Joker | 普通 | $4 | 含同花+80 Chips | +Chips | 独立常驻 | 特定牌型 | 条件爆发 |
| Half Joker | 普通 | $5 | 出牌≤3张时+20 Mult | +Mult | 独立常驻 | 出牌张数 | 条件爆发 |
| Joker Stencil | 罕见 | $8 | 每个空小丑槽×1 Mult(自身计入) | ×Mult | 独立常驻 | 其他(槽位) | 资源浮动 |
| Four Fingers | 罕见 | $7 | 4张即可成同花/顺子 | 规则改变 | 被动 | 无条件 | 固定收益 |
| Mime | 罕见 | $5 | 重触发所有手持牌效果 | 重触发 | 手持时 | 无条件 | 固定收益 |
| Credit Card | 普通 | $1 | 可负债至-$20 | 金钱 | 被动 | 无条件 | 固定收益 |
| Ceremonial Dagger | 罕见 | $6 | 选盲注时毁右侧小丑,其2倍卖价永久转Mult | +Mult | 选盲注时 | 其他(自伤) | 永久成长 |
| Banner | 普通 | $5 | 每剩1次弃牌+30 Chips | +Chips | 独立常驻 | 剩余资源 | 资源浮动 |
| Mystic Summit | 普通 | $5 | 弃牌次数为0时+15 Mult | +Mult | 独立常驻 | 剩余资源 | 条件爆发 |
| Marble Joker | 罕见 | $6 | 选盲注时加1张石头牌入牌堆 | 生成/改造卡牌 | 选盲注时 | 无条件 | 固定收益 |
| Loyalty Card | 罕见 | $5 | 每出6次牌,第6次×4 Mult | ×Mult | 独立常驻 | 连续行为 | 延迟兑现 |
| 8 Ball | 普通 | $5 | 计分的8有1/4几率产塔罗 | 生成消耗牌 | 概率触发 | 特定点数/人头 | 条件爆发 |
| Misprint | 普通 | $4 | +0~23随机Mult | +Mult | 独立常驻 | 无条件 | 固定收益 |
| Dusk | 罕见 | $5 | 回合最后一手重触发所有出牌 | 重触发 | 计分时 | 剩余资源 | 条件爆发 |
| Raised Fist | 普通 | $5 | 手持最低点数×2加入Mult | +Mult | 手持时 | 其他(最低点) | 资源浮动 |
| Chaos the Clown | 普通 | $4 | 每商店1次免费重掷 | 金钱 | 商店/买卖 | 无条件 | 固定收益 |
| Fibonacci | 罕见 | $8 | A/2/3/5/8计分时+8 Mult | +Mult | 计分时 | 特定点数/人头 | 条件爆发 |
| Steel Joker | 罕见 | $7 | 牌堆每张钢铁牌×0.2 Mult(基础×1) | ×Mult | 独立常驻 | 牌堆构成 | 资源浮动 |
| Scary Face | 普通 | $4 | 人头牌计分时+30 Chips | +Chips | 计分时 | 特定点数/人头 | 条件爆发 |
| Abstract Joker | 普通 | $4 | 每持有1张小丑+3 Mult | +Mult | 独立常驻 | 其他(小丑数) | 资源浮动 |
| Delayed Gratification | 普通 | $4 | 整回合未弃牌则每次弃牌机会$2 | 金钱 | 回合结束 | 剩余资源 | 条件爆发 |
| Hack | 罕见 | $6 | 重触发所有2/3/4/5 | 重触发 | 计分时 | 特定点数/人头 | 条件爆发 |
| Pareidolia | 罕见 | $5 | 所有牌视为人头牌 | 规则改变 | 被动 | 无条件 | 固定收益 |
| Gros Michel | 普通 | $5 | +15 Mult,每回合末1/6自毁 | +Mult | 独立常驻 | 无条件 | 衰减/自毁 |
| Even Steven | 普通 | $4 | 偶数牌计分时+4 Mult | +Mult | 计分时 | 特定点数/人头 | 条件爆发 |
| Odd Todd | 普通 | $4 | 奇数牌计分时+31 Chips | +Chips | 计分时 | 特定点数/人头 | 条件爆发 |
| Scholar | 普通 | $4 | A计分时+20 Chips且+4 Mult | +Chips(副+Mult) | 计分时 | 特定点数/人头 | 条件爆发 |
| Business Card | 普通 | $4 | 人头计分1/2几率$2 | 金钱 | 概率触发 | 特定点数/人头 | 条件爆发 |
| Supernova | 普通 | $5 | 该牌型本局已打次数加入Mult | +Mult | 独立常驻 | 无条件 | 永久成长 |
| Ride the Bus | 普通 | $6 | 连续每手无人头+1 Mult,出人头重置 | +Mult | 独立常驻 | 连续行为 | 永久成长(带重置) |
| Space Joker | 罕见 | $5 | 出牌1/4几率升级该牌型等级 | 牌型升级 | 概率触发 | 无条件 | 固定收益 |
| Egg | 普通 | $4 | 每回合末自身卖价+$3 | 金钱 | 回合结束 | 无条件 | 永久成长 |
| Burglar | 罕见 | $6 | 选盲注+3出牌次数,弃牌清零 | 出牌次数 | 选盲注时 | 无条件 | 固定收益 |
| Blackboard | 罕见 | $6 | 手持牌全为黑桃/梅花时×3 Mult | ×Mult | 独立常驻 | 特定花色 | 条件爆发 |
| Runner | 普通 | $5 | 每出含顺子永久+15 Chips | +Chips | 独立常驻 | 特定牌型 | 永久成长 |
| Ice Cream | 普通 | $5 | +100 Chips,每出一手-5 | +Chips | 独立常驻 | 无条件 | 衰减/自毁 |
| DNA | 稀有 | $8 | 首手只出1张则永久复制入牌堆 | 生成/改造卡牌 | 计分时 | 出牌张数 | 条件爆发 |
| Splash | 普通 | $3 | 所有出牌都参与计分 | 规则改变 | 被动 | 无条件 | 固定收益 |
| Blue Joker | 普通 | $5 | 抽牌堆每剩1张+2 Chips | +Chips | 独立常驻 | 牌堆构成 | 资源浮动 |
| Sixth Sense | 罕见 | $6 | 首手单张6:摧毁并产幻灵牌 | 生成消耗牌(副牌堆改造) | 计分时 | 特定点数/人头 | 条件爆发 |
| Constellation | 罕见 | $6 | 每使用1张星球牌永久×0.1 Mult | ×Mult | 独立常驻 | 无条件 | 永久成长 |
| Hiker | 罕见 | $5 | 每张计分牌永久+5 Chips | 生成/改造卡牌 | 计分时 | 无条件 | 永久成长 |
| Faceless Joker | 普通 | $4 | 一次弃≥3张人头得$5 | 金钱 | 弃牌时 | 特定点数/人头 | 条件爆发 |
| Green Joker | 普通 | $4 | 出牌+1 Mult,弃牌-1 Mult | +Mult | 独立常驻 | 连续行为 | 永久成长(可回退) |
| Superposition | 普通 | $4 | 含A的顺子产1张塔罗 | 生成消耗牌 | 计分时 | 特定牌型 | 条件爆发 |
| To Do List | 普通 | $4 | 打出指定牌型得$4,每回合更换 | 金钱 | 计分时 | 特定牌型(轮换) | 条件爆发 |
| Cavendish | 普通 | $4 | ×3 Mult,每回合末1/1000自毁 | ×Mult | 独立常驻 | 无条件 | 固定收益(副自毁) |
| Card Sharp | 罕见 | $6 | 本回合已打过该牌型则×3 Mult | ×Mult | 独立常驻 | 连续行为 | 条件爆发 |
| Red Card | 普通 | $5 | 每跳过补充包永久+3 Mult | +Mult | 独立常驻 | 其他(跳过包) | 永久成长 |
| Madness | 罕见 | $7 | 选小/大盲注+×0.5并毁1张随机小丑 | ×Mult | 选盲注时 | 其他(自伤) | 永久成长 |
| Square Joker | 普通 | $4 | 每出恰好4张牌永久+4 Chips | +Chips | 独立常驻 | 出牌张数 | 永久成长 |
| Séance | 罕见 | $6 | 打出同花顺产随机幻灵牌 | 生成消耗牌 | 计分时 | 特定牌型 | 条件爆发 |
| Riff-Raff | 普通 | $6 | 选盲注时产2张Common小丑 | 其他(生成小丑) | 选盲注时 | 无条件 | 固定收益 |
| Vampire | 罕见 | $7 | 计分强化牌:永久×0.1并移除强化 | ×Mult(副牌堆改造) | 独立常驻 | 牌堆构成 | 永久成长 |
| Shortcut | 罕见 | $7 | 顺子允许隔1个点数 | 规则改变 | 被动 | 无条件 | 固定收益 |
| Hologram | 罕见 | $7 | 每有1张牌加入牌堆永久×0.25 | ×Mult | 独立常驻 | 无条件 | 永久成长 |
| Vagabond | 稀有 | $8 | 持金≤$4时出牌产塔罗 | 生成消耗牌 | 计分时 | 金钱阈值 | 条件爆发 |
| Baron | 稀有 | $8 | 手持每张K ×1.5 Mult | ×Mult | 手持时 | 特定点数/人头 | 条件爆发 |
| Cloud 9 | 罕见 | $7 | 牌堆每张9回合末$1 | 金钱 | 回合结束 | 牌堆构成 | 资源浮动 |
| Rocket | 罕见 | $6 | 回合末$1,每胜Boss产出+$2 | 金钱 | 回合结束 | 无条件 | 永久成长 |
| Obelisk | 稀有 | $8 | 连续不打最常用牌型每手×0.2,打了重置 | ×Mult | 独立常驻 | 连续行为 | 永久成长(带重置) |
| Midas Mask | 罕见 | $7 | 计分人头牌变为黄金牌 | 生成/改造卡牌 | 计分时 | 特定点数/人头 | 固定收益 |
| Luchador | 罕见 | $5 | 卖出时禁用当前Boss盲注 | 规则改变 | 商店/买卖 | 无条件 | 延迟兑现 |
| Photograph | 普通 | $5 | 首张计分人头牌×2 Mult | ×Mult | 计分时 | 特定点数/人头 | 条件爆发 |
| Gift Card | 罕见 | $6 | 回合末所有小丑/消耗牌卖价+$1 | 金钱 | 回合结束 | 无条件 | 永久成长 |
| Turtle Bean | 罕见 | $6 | +5手牌上限,每回合-1 | 手牌上限 | 被动 | 无条件 | 衰减/自毁 |
| Erosion | 罕见 | $6 | 牌堆低于初始每少1张+4 Mult | +Mult | 独立常驻 | 牌堆构成 | 资源浮动 |
| Reserved Parking | 普通 | $6 | 手持人头牌各1/2几率$1 | 金钱 | 概率触发(手持) | 特定点数/人头 | 条件爆发 |
| Mail-In Rebate | 普通 | $4 | 弃指定点数每张$5,每回合更换 | 金钱 | 弃牌时 | 特定点数/人头(轮换) | 条件爆发 |
| To the Moon | 罕见 | $5 | 每$5额外$1利息 | 金钱 | 回合结束 | 金钱阈值 | 资源浮动 |
| Hallucination | 普通 | $4 | 开补充包1/2几率产塔罗 | 生成消耗牌 | 概率触发 | 无条件 | 条件爆发 |
| Fortune Teller | 普通 | $6 | 本局每用1张塔罗+1 Mult | +Mult | 独立常驻 | 无条件 | 永久成长 |
| Juggler | 普通 | $4 | +1手牌上限 | 手牌上限 | 被动 | 无条件 | 固定收益 |
| Drunkard | 普通 | $4 | +1弃牌次数 | 弃牌次数 | 被动 | 无条件 | 固定收益 |
| Stone Joker | 罕见 | $6 | 牌堆每张石头牌+25 Chips | +Chips | 独立常驻 | 牌堆构成 | 资源浮动 |
| Golden Joker | 普通 | $6 | 回合末$4 | 金钱 | 回合结束 | 无条件 | 固定收益 |
| Lucky Cat | 罕见 | $6 | 每次幸运牌触发永久×0.25 | ×Mult | 独立常驻 | 牌堆构成 | 永久成长 |
| Baseball Card | 稀有 | $8 | 每张Uncommon小丑×1.5 Mult | ×Mult | 独立常驻 | 其他(小丑构成) | 资源浮动 |
| Bull | 罕见 | $6 | 每持有$1 +2 Chips | +Chips | 独立常驻 | 金钱阈值 | 资源浮动 |
| Diet Cola | 罕见 | $6 | 卖出获得免费Double Tag | 其他(Tag) | 商店/买卖 | 无条件 | 延迟兑现 |
| Trading Card | 罕见 | $6 | 首次弃牌若单张:摧毁并得$3 | 牌堆改造(副金钱) | 弃牌时 | 出牌张数 | 条件爆发 |
| Flash Card | 罕见 | $5 | 每次商店重掷永久+2 Mult | +Mult | 独立常驻 | 其他(重掷) | 永久成长 |
| Popcorn | 普通 | $5 | +20 Mult,每回合-4 | +Mult | 独立常驻 | 无条件 | 衰减/自毁 |
| Spare Trousers | 罕见 | $6 | 每出含两对永久+2 Mult | +Mult | 独立常驻 | 特定牌型 | 永久成长 |
| Ancient Joker | 稀有 | $8 | 指定花色计分×1.5,每回合更换 | ×Mult | 计分时 | 特定花色(轮换) | 条件爆发 |
| Ramen | 罕见 | $6 | ×2 Mult,每弃1张牌-×0.01 | ×Mult | 独立常驻 | 无条件 | 衰减/自毁 |
| Walkie Talkie | 普通 | $4 | 10/4计分+10 Chips且+4 Mult | +Chips(副+Mult) | 计分时 | 特定点数/人头 | 条件爆发 |
| Seltzer | 罕见 | $6 | 之后10手所有出牌重触发,然后自毁 | 重触发 | 计分时 | 无条件 | 衰减/自毁 |
| Castle | 罕见 | $6 | 弃指定花色每张永久+3 Chips,每回合换 | +Chips | 独立常驻 | 特定花色(轮换) | 永久成长 |
| Smiley Face | 普通 | $4 | 人头牌计分时+5 Mult | +Mult | 计分时 | 特定点数/人头 | 条件爆发 |
| Campfire | 稀有 | $9 | 每卖1张卡×0.25,胜Boss后重置 | ×Mult | 独立常驻 | 其他(卖出) | 永久成长(带重置) |
| Golden Ticket | 普通 | $5 | 黄金牌计分时$4 | 金钱 | 计分时 | 牌堆构成 | 条件爆发 |
| Mr. Bones | 罕见 | $5 | 分数达25%时免死,然后自毁 | 规则改变 | 被动 | 其他(保险) | 条件爆发(一次性) |
| Acrobat | 罕见 | $6 | 回合最后一手×3 Mult | ×Mult | 独立常驻 | 剩余资源 | 条件爆发 |
| Sock and Buskin | 罕见 | $6 | 重触发所有计分人头牌 | 重触发 | 计分时 | 特定点数/人头 | 条件爆发 |
| Swashbuckler | 普通 | $4 | 其他小丑卖价总和加入Mult | +Mult | 独立常驻 | 其他(小丑卖价) | 资源浮动 |
| Troubadour | 罕见 | $6 | +2手牌上限,每回合-1出牌次数 | 手牌上限(副出牌次数) | 被动 | 无条件 | 固定收益 |
| Certificate | 罕见 | $6 | 回合开始加1张带随机蜡封的随机牌 | 生成/改造卡牌 | 选盲注时 | 无条件 | 固定收益 |
| Smeared Joker | 罕见 | $7 | 红心=方块,黑桃=梅花 | 规则改变 | 被动 | 无条件 | 固定收益 |
| Throwback | 罕见 | $6 | 本局每跳过1个盲注×0.25 Mult | ×Mult | 独立常驻 | 其他(跳过盲注) | 永久成长 |
| Hanging Chad | 普通 | $4 | 首张计分牌额外重触发2次 | 重触发 | 计分时 | 无条件 | 固定收益 |
| Rough Gem | 罕见 | $7 | 方块牌计分时$1 | 金钱 | 计分时 | 特定花色 | 条件爆发 |
| Bloodstone | 罕见 | $7 | 红心计分1/2几率×1.5 Mult | ×Mult | 概率触发 | 特定花色 | 条件爆发 |
| Arrowhead | 罕见 | $7 | 黑桃牌计分时+50 Chips | +Chips | 计分时 | 特定花色 | 条件爆发 |
| Onyx Agate | 罕见 | $7 | 梅花牌计分时+7 Mult | +Mult | 计分时 | 特定花色 | 条件爆发 |
| Glass Joker | 罕见 | $6 | 每碎1张玻璃牌永久×0.75 | ×Mult | 独立常驻 | 牌堆构成 | 永久成长 |
| Showman | 罕见 | $5 | 小丑/消耗牌可重复出现 | 规则改变 | 被动 | 无条件 | 固定收益 |
| Flower Pot | 罕见 | $6 | 计分含全部4花色×3 Mult | ×Mult | 独立常驻 | 特定花色 | 条件爆发 |
| Blueprint | 稀有 | $10 | 复制右侧小丑能力 | 复制小丑 | 被动 | 其他(依赖对象) | 资源浮动(随对象) |
| Wee Joker | 稀有 | $8 | 每计分1张2永久+8 Chips | +Chips | 独立常驻 | 特定点数/人头 | 永久成长 |
| Merry Andy | 罕见 | $7 | +3弃牌次数,-1手牌上限 | 弃牌次数(副手牌上限) | 被动 | 无条件 | 固定收益 |
| Oops! All 6s | 罕见 | $4 | 所有列出概率翻倍 | 规则改变 | 被动 | 无条件 | 固定收益 |
| The Idol | 罕见 | $6 | 指定点数+花色的牌计分×2,每回合换 | ×Mult | 计分时 | 特定点数/人头(轮换,副花色) | 条件爆发 |
| Seeing Double | 罕见 | $6 | 计分含梅花+另一花色×2 Mult | ×Mult | 独立常驻 | 特定花色 | 条件爆发 |
| Matador | 罕见 | $7 | 出牌触发Boss盲注能力得$8 | 金钱 | 计分时 | 其他(Boss) | 条件爆发 |
| Hit the Road | 稀有 | $8 | 本回合每弃1张J ×0.5,回合末重置 | ×Mult | 独立常驻 | 特定点数/人头 | 永久成长(带重置) |
| The Duo | 稀有 | $8 | 含对子×2 Mult | ×Mult | 独立常驻 | 特定牌型 | 条件爆发 |
| The Trio | 稀有 | $8 | 含三条×3 Mult | ×Mult | 独立常驻 | 特定牌型 | 条件爆发 |
| The Family | 稀有 | $8 | 含四条×4 Mult | ×Mult | 独立常驻 | 特定牌型 | 条件爆发 |
| The Order | 稀有 | $8 | 含顺子×3 Mult | ×Mult | 独立常驻 | 特定牌型 | 条件爆发 |
| The Tribe | 稀有 | $8 | 含同花×2 Mult | ×Mult | 独立常驻 | 特定牌型 | 条件爆发 |
| Stuntman | 稀有 | $7 | +250 Chips,-2手牌上限 | +Chips(副手牌上限) | 独立常驻 | 无条件 | 固定收益 |
| Invisible Joker | 稀有 | $8 | 持有2回合后卖出:复制1张随机小丑 | 复制小丑 | 商店/买卖 | 其他(计轮) | 延迟兑现 |
| Brainstorm | 稀有 | $10 | 复制最左侧小丑能力 | 复制小丑 | 被动 | 其他(依赖对象) | 资源浮动(随对象) |
| Satellite | 罕见 | $6 | 回合末每种本局用过的星球牌$1 | 金钱 | 回合结束 | 其他(星球种类) | 永久成长 |
| Shoot the Moon | 普通 | $5 | 手持每张Q +13 Mult | +Mult | 手持时 | 特定点数/人头 | 条件爆发 |
| Driver's License | 稀有 | $7 | 牌堆强化牌≥16张时×3 Mult | ×Mult | 独立常驻 | 牌堆构成 | 条件爆发(阈值) |
| Cartomancer | 罕见 | $6 | 选盲注时产1张塔罗 | 生成消耗牌 | 选盲注时 | 无条件 | 固定收益 |
| Astronomer | 罕见 | $8 | 星球牌与天体包免费 | 金钱 | 商店/买卖 | 无条件 | 固定收益 |
| Burnt Joker | 稀有 | $8 | 每回合首次弃牌升级该牌型等级 | 牌型升级 | 弃牌时 | 无条件 | 固定收益 |
| Bootstraps | 罕见 | $7 | 每持有$5 +2 Mult | +Mult | 独立常驻 | 金钱阈值 | 资源浮动 |
| Canio | 传说 | — | 每摧毁1张人头牌永久×1 Mult | ×Mult | 独立常驻 | 特定点数/人头 | 永久成长 |
| Triboulet | 传说 | — | K/Q计分时×2 Mult | ×Mult | 计分时 | 特定点数/人头 | 条件爆发 |
| Yorick | 传说 | — | 每累计弃23张牌永久×1 Mult | ×Mult | 独立常驻 | 其他(弃牌累计) | 永久成长 |
| Chicot | 传说 | — | 禁用所有Boss盲注效果 | 规则改变 | 被动 | 无条件 | 固定收益 |
| Perkeo | 传说 | — | 离开商店时复制1张消耗牌为Negative | 生成消耗牌 | 商店/买卖 | 无条件 | 固定收益 |

(核对:普通 61 + 罕见 64 + 稀有 20 + 传说 5 = 150,与官方总数一致;所有统计由脚本对该 150 行数据计算,脚本留存于 scratchpad `balatro_jokers.py`。)

---

# Balatro 小丑牌设计调研报告:LocalThunk 的设计意图与社区深度分析

## 来源说明(先纠正一个前提)

LocalThunk **没有做过 GDC 2025 演讲**——他是匿名开发者,GDC 2025 上只以普通参会者身份匿名出现(GamesRadar 报道过有观众看他试玩机上打 Balatro 后惊呼 "You must have played this before!" 而不知他就是作者)。Balatro 在 GDCA 2025 拿了 Game of the Year、Best Design、Innovation、Best Debut 四奖(Game Developer 报道)。因此一手来源以他的博客与文字/播客访谈为准:

- **LocalThunk 博客《The Balatro Timeline》**(localthunk.com/blog/balatro-timeline-3aarh)——开发全程自述
- **Game Informer《Balatro Was Almost Called Joker Poker》访谈**(2024-03)
- **Rogueliker 访谈《an indie take on solitaire with a poker coat of paint》**
- **AIAS Game Maker's Notebook 播客**(2024-12,谈灵感、平衡、Joker 设计与反赌博立场)
- 二手:balatrowiki.org 的 Mult/Scaling 指南、Steam 计分指南、各家 tier list 与 Gold Stake 攻略、社区讨论

---

## 提炼的设计原则(17 条)

**1. 计分公式用「加法通货 × 乘法通货」两种资源,分工自然涌现,不必刻意教学。**
证据:LocalThunk 自述 "The game had the CHIP X MULT mechanic already… it seemed very natural for a scoring system"(《The Balatro Timeline》)。社区共识公式为 `(基础Chips + 加Chips) × (基础Mult + 加Mult) × xMult`(Steam《Score Calculation in Balatro》指南)。
实例:+Chips 的 Banner、+Mult 的 Half Joker、×Mult 的 Cavendish 各占一层。

**2. 乘法必须稀缺,因为它作用在整条结算链的末端,吃掉之前所有投资。**
证据:balatrowiki《Mult》页:×Mult 在所有加法之后结算;两张 ×1.5 叠加是超线性的(100 Mult → +50 再 +75)。这就是 ×Mult 牌集中在 Uncommon/Rare、而 +Mult 遍地都是 Common 的数学原因。
实例:The Family(×4,Rare)、Baron(每张手持 K ×1.5,Rare)vs 满地的 +4 Mult 类 Common。

**3. 加法牌解决前期节奏,乘法牌解决后期通胀——玩家用「何时买」而非「强不强」给牌估值。**
证据:Gold Stake 攻略把 Ante 1–3 定义为 "investment rounds, not power rounds",Ante 4–6 才 "identify your scaling build and commit"(The Mancunion《A guide to Gold Stake Balatro》、Switchblade Gaming Gold Stake 指南)。×1.5 在 10 Mult 时只值 +5,在 300 Mult 时值 +150——同一张牌价值随阶段翻几十倍。
实例:Gros Michel(+15 Mult)是前期解,Vampire/Campfire(成长 ×Mult)是后期引擎。

**4. 成长型牌的卖点是「超过任何固定牌的上限」,代价是前期占格子白吃饭。**
证据:balatrowiki《Guide: Scaling》:"after long-term holding and scaling, their effects will exceed any of the Jokers with fixed effects"。反面证据:Yorick(弃 23 张牌才开始 ×1)被社区评为最弱 Legendary,因为 "a slot dedicated to a Joker that does nothing for 5+ rounds is devastating"(Gameranx/DualShockers Legendary 排名)。成长速度必须和游戏总长度对表。
实例:强成长 Vampire、Glass Joker、Campfire;失败成长 Yorick。

**5. 稀有度映射的是「构筑依赖度 + 变形力」,不是裸强度;必须存在「普通但顶级」和「传说但垫底」。**
证据:社区 tier list 反复强调 "rarity does not equal power, as Cavendish (Common) outperforms most Rare Jokers"(Choost Games/PropelRC tier list);Yorick 是 Legendary 却公认最弱,与 Triboulet 之间 "a canyon-esque gap"(Steam 讨论/Gameranx)。分布上 Common 61 张占 70% 商店权重、Rare 20 张占 5%(Fandom《Jokers》)——稀有池小而怪,普通池大而稳。
实例:Cavendish(Common,无条件 ×3)、Blueprint(Rare,单卡无用、全靠邻居)、Yorick(Legendary,垫底)。

**6. 全游戏强度天花板给「复制/放大别人」的牌,而不是数值最大的牌。**
证据:Blueprint/Brainstorm(复制相邻/最左 Joker)被评 "the most powerful two-card combo in the game because it doesn't require a specific deck archetype"(Switchblade Gaming《Jokers Ranked》)。复制牌的强度 = 你已有构筑的强度,天然不会独立超模。
实例:Blueprint、Brainstorm。

**7. 说明文字硬上限(≤4 行、20 词)是机制复杂度的真正闸门。**
证据:LocalThunk:"descriptions can't be more than four lines and 20 words… They need to do things that are relatively simple, and that kind of breeds this elegant strategy by itself"(Game Informer Afterwords)。
实例:150 张 Joker 无一张需要展开二级说明。

**8. 平衡靠手感,不靠精密校准;删牌只看两条红线。**
证据:LocalThunk 的挂画比喻:"instead of making it perfectly level… it's better to just do it by feel";问题牌只有两类——"cannibalise all the adjacent strategies around it" 或 "so bad that there are few reasons to ever take it"(Rogueliker 访谈)。7 个月 beta 里 "way too overpowered, or nobody takes it, or it's too niche" 的牌被删改(Game Informer)。
实例:beta 期被砍掉的效果无数,上线的都过了这两条线。

**9. 「好玩的超模」保留,「排他的超模」处理——超模本身不是罪。**
证据:LocalThunk:"Something can be overpowered in a fun way… Something can be overpowered in a way that excludes the player from experiencing other fun"(Game Informer)。
实例:Cavendish ×3 无条件保留(爽但不排他);而会让其他策略全部失效的效果被删。

**10. 不设纯陷阱牌:看着废的牌必须有构筑归宿(sleeper),惊喜感来自「发现它的家」。**
证据:上一条红线("没人拿的牌会被删")意味着上线的弱牌都留了后门。Egg(只涨卖价,零战力)配 Swashbuckler(+Mult = 所有 Joker 卖价)或 Temperance 塔罗变现(Fandom《Egg》:"nest egg" 主题);Obelisk(不打最常用牌型才成长)靠「先刷 High Card 再转牌型」变成顶级 ×Mult(Fandom《Obelisk》)。
实例:Egg、Obelisk、Midas Mask(单看是负面,喂 Vampire 变引擎)。

**11. 故意造互斥对,逼玩家对同一资源表态——张力比协同更便宜地制造决策。**
证据:Banner(每剩 1 次弃牌 +30 Chips)与 Mystic Summit(弃牌用光才 +15 Mult)是公认反协同对,"Banner will never give chips if Mystic Summit is activated"(balatrowiki《Mystic Summit》,主题即「登顶后无路可走」)。同理 Ride the Bus 内部自带张力:每打一手无人头牌 +1 Mult、见人头即清零,与 Baron/Photograph 人头流正面冲突。
实例:Banner vs Mystic Summit;Ride the Bus vs 人头构筑。

**12. 自毁牌 = 「租借的前期强度」:给超额数值、按时序折旧,教玩家计算卖点。**
证据:Ice Cream(+100 Chips,每手 −5,融化)被社区评 "one of the best early-game Jokers… once past Ante 2 or 3 loses its relative effectiveness"(balatrowiki/Steam 讨论);Popcorn(+20 Mult,每回合 −4)主题即「爆米花吃完就没了」(Fandom《Popcorn》)。它们的账面数值远超同期 Common,折旧就是租金。
实例:Ice Cream、Popcorn、Turtle Bean(手牌上限版折旧,忘卖 = 死格子,Switchblade Gaming)。

**13. 概率自毁的死亡可以「播种」更强的牌,把坏运气变成剧情。**
证据:Gros Michel(+15 Mult,每回合 1/6 摧毁)被摧毁后,Cavendish(×3 Mult,1/1000 摧毁)才会进卡池(Fandom《Cavendish》"香蕉灭绝史"梗)。损失事件本身成为解锁器。
实例:Gros Michel → Cavendish。

**14. 版本/材质是正交第二轴:同一张牌 × 4 种版本 = 内容乘法,且各版本奖励不同资源类型。**
证据:Foil(+50 Chips)、Holographic(+10 Mult)、Polychrome(×1.5 Mult)分别挂在计分三层上,出现率 1.7%/1.4%/0.3% 与其层级强度反相关(balatrowiki 各版本页)。设计要点:版本不改变牌的机制身份,只叠一层通货,所以任何牌 × 任何版本都合法。
实例:Polychrome Blueprint = 复制 + 自带 ×1.5,双轴叠加。

**15. 最稀有的奖励发「空间」而不是「数值」:槽位是比分数更高阶的通货。**
证据:Negative(0.3%,最稀有)效果是 +1 Joker 槽,社区公认 "significantly more potential than even Polychrome"(balatrowiki《Negative》/Twinfinite)。全游戏默认 5 槽,所有牌的强度实际以「每格子产出」为分母——Riff-Raff、过期的 Turtle Bean 被批评的本质都是 "dead slot"(Switchblade Gaming)。
实例:Negative 版任意 Joker;Invisible Joker(攒 2 回合换复制)也是槽位经济牌。

**16. 随机性可以偏多,只要元策略是「风险缓释」而非「祈祷」。**
证据:LocalThunk:"There is a lot of randomness, possibly too much, but the metastrategy for Balatro is around mitigating risk and having a build that can't be easily countered while still being powerful enough to win"(Rogueliker 访谈)。
实例:弃牌、商店 reroll、塔罗改牌都是玩家侧的方差压缩工具。

**17. 上线后玩家会超越作者——修「读不懂」而不是修「太强」,并信任涌现。**
证据:beta 阶段 "players knew more about how to play the game properly than I did"(《The Balatro Timeline》);1.1 版重做的是「语义混乱」的 Matador 而非砍强牌,"I play a lot too, and notice flaws all the time"(PC Gamer 1.1 报道);"it makes me feel good that this game ended up being so emergent"(Game Informer)。另一条同源原则:计分过程要做成可观看的演出——他起初讨厌朋友提议的「高分着火特效」,后来承认自己错了(《The Balatro Timeline》);社区分析称看着分数滚动的 Rube Goldberg 效应是核心爽点(Error & Experience Substack《Unpacking Balatro's Addicting Game》)。

---

## 主要来源清单

- LocalThunk 博客:https://localthunk.com/blog/balatro-timeline-3aarh
- Game Informer Afterwords:https://gameinformer.com/interview/2024/03/21/balatro-was-almost-called-joker-poker-and-other-details-from-its-creator
- Rogueliker 访谈:https://rogueliker.com/balatro-interview/
- Game Maker's Notebook 播客:https://gamemakersnotebook.libsyn.com/balatro-creator-localthunk-talks-inspirations-and-jokers
- PC Gamer(1.1 与 Matador 重做):https://www.pcgamer.com/games/roguelike/balatro-1-1-will-include-new-jokers-plus-a-revamp-of-a-really-confusing-existing-one/
- balatrowiki:Mult / Guide: Scaling / Mystic Summit / Negative 各页(https://balatrowiki.org)
- Steam 社区计分指南:https://steamcommunity.com/sharedfiles/filedetails/?id=3169032575
- Switchblade Gaming Joker 分析与 Gold Stake 指南:https://www.switchbladegaming.com/strategy-games/balatro-jokers-guide/
- The Mancunion Gold Stake 指南:https://mancunion.com/2025/09/01/a-guide-to-gold-stake-balatro/
- Gameranx / DualShockers Legendary 排名;Fandom Wiki(Egg / Obelisk / Popcorn / Cavendish / Jokers 总览)
- Error & Experience Substack:https://errorandexp.substack.com/p/unpacking-balatros-addicting-game

**对 Sync5 最直接可用的四条**:①计分双通货分层(第 1、2 条)决定 ×Mult 必须稀缺且放结算链末端;②稀有度绑「构筑依赖度」而非裸强度(第 5 条);③自毁/折旧牌是廉价的前期节奏工具(第 12 条);④互斥对(第 11 条)用 8 张牌的小 roster 也能造出决策张力。

---

# Balatro 结算时序与成长型小丑机制调研报告

---

## A. 结算时序流程(文字版流程图)

### 阶段 0:选盲注(On Blind Select)
- 触发:Riff-Raff、Marble Joker、Burglar、Cartomancer、Chicot、**Madness**(×0.5 成长)、**Ceremonial Dagger**(吞右侧小丑)。跳过盲注则不触发。此类可被 Blueprint/Brainstorm 复制。

### 阶段 1:按下出牌,计分开始
```
1. Boss 盲注效果先行(The Arm 降牌型等级、The Flint 减半基础值……)
2. On Played 小丑(计分前触发):
   计数/成长类在此累加 —— Ride the Bus、Green Joker、Runner、Square Joker、
   Spare Trousers、Obelisk 的计数器;DNA 复制、Vampire 吸取增强、
   Midas Mask 镀金、Space Joker 概率升级牌型、To Do List 发钱
3. 逐张计分(只计入构成牌型的牌;Splash 则全上),每张牌从左到右依次:
   a. 基础 Chips(点数面值 + 加成)
   b. 增强(Bonus / Mult / Glass / Lucky / Stone …)
   c. 蜡封(计分阶段只有 Gold Seal 给钱)
   d. 版本(Foil +50 Chips / Holo +10 Mult / Polychrome ×1.5)
   e. On Scored 小丑,从左到右(花色 Mult 系、Fibonacci、Photograph、
      Bloodstone、Wee Joker 成长、8 Ball、Golden Ticket …)
   f. 重触发:Red Seal 最先,然后重触发型小丑从左到右
      (Dusk / Hack / Sock and Buskin / Seltzer / Hanging Chad)。
      每次重触发把 a→e 整段重跑一遍
4. 手中持有的牌,从左到右每张:
   a. Steel ×1.5
   b. On Held 小丑(Baron、Raised Fist、Shoot the Moon、Reserved Parking)
   c. 重触发:Red Seal 先,Mime 从左到右
5. 小丑区从左到右,逐个小丑:
   a. 该小丑的 Foil/Holo 版本加成
   b. 该小丑的 Independent 效果(Joker、Abstract、Fortune Teller、
      Green Joker 的加分段、Obelisk 的乘算段 …)
   c. Baseball Card(On Other Jokers,目前唯一)
   d. 该小丑的 Polychrome ×1.5
6. 消耗品:有 Observatory 时星球牌从左到右各 ×1.5
7. Plasma Deck:Chips 与 Mult 取平均
8. 得分 = Chips × Mult
```

### 阶段 2:回合结束
- 自毁判定(Gros Michel 1/6、Cavendish 1/1000)、Popcorn/Turtle Bean 衰减、经济结算(Golden Joker、Rocket、Cloud 9、利息、To the Moon)、Egg/Gift Card 卖价增长、Castle/Mail-In Rebate/To Do List 换目标、Invisible Joker 计数。

### Blueprint / Brainstorm 的位置语义
- **Blueprint 复制紧邻右侧的小丑;Brainstorm 复制最左侧的小丑;复制体在复制者自身的位置生效**,不在原件位置。
- 不能复制:被动/经济类(回合末收钱、手牌上限、永久改牌)、版本与贴纸效果、**成长过程本身(只复制当前最终数值)**。共 29 张完全不兼容。
- 可以链式:Blueprint→Blueprint→X 得到多份拷贝。

### 摆位影响收益的三个算例

**算例 1(加法在乘法左边,+33%)**
手牌 40 Chips × 4 Mult,持有 Joker(+4)与 Ramen(×2):
- Joker 在左:40 × ((4+4)×2) = **640**
- Joker 在右:40 × ((4×2)+4) = **480**

**算例 2(激活类型分层 > 槽序)**
Photograph(首张人头 ×2,On Scored)+ Joker(+4,Independent),手牌 30 Chips × 4 Mult:
On Scored 永远先于 Independent,所以无论 Joker 摆在哪,结算都是 4×2=8 再 +4=12 → 360 分。理论上「先加后乘」的 (4+4)×2=16 → 480 分**通过摆位无法达成**。跨激活类型时,摆位失效。

**算例 3(复制体在复制者的位置生效)**
同样三张牌 Joker(+4)、Blueprint、Ramen(×2),基础 4 Mult:
- [Joker, Blueprint, Ramen]:4+4=8 → ×2(拷贝)=16 → ×2=**32 Mult**
- [Blueprint, Ramen, Joker]:4×2(拷贝)=8 → ×2=16 → +4=**20 Mult**
复制牌本身也是摆位博弈的一员。

---

## B. 成长型小丑全表(按驱动源分组)

> 「累积」= 内部计数器永久累加;「读取」= 动态读取当前状态,可逆。

### 弃牌驱动
| 牌名 | 稀有度 | 成长速率 | 上限 | 重置条件 |
|---|---|---|---|---|
| Castle | Uncommon | +3 Chips / 弃 1 张指定花色(花色每轮换) | 无 | 永不重置(累积) |
| Yorick | Legendary | 每累计弃 23 张 → ×1 Mult | 无 | 永不重置(累积) |
| Hit the Road | Rare | ×0.5 / 本轮每弃 1 张 J | 无 | **回合结束归 ×1** |
| Burnt Joker | Rare | 每轮首次弃牌 → 升级该牌型等级 | 无 | 永久(升级留存) |
| Green Joker(负向段) | Common | 每次弃牌 −1 Mult | 下限 0 | — |

### 出牌驱动
| 牌名 | 稀有度 | 成长速率 | 上限 | 重置条件 |
|---|---|---|---|---|
| Ride the Bus | Common | +1 Mult / 连续一手不含计分人头牌 | 无 | 计分人头牌出现 → 归零 |
| Green Joker | Common | +1 Mult / 每出一手 | 无 | 弃牌 −1 |
| Runner | Common | +15 Chips / 含顺子的手 | 无 | 无 |
| Square Joker | Common | +4 Chips / 恰好 4 张的手 | 无 | 无 |
| Spare Trousers | Uncommon | +2 Mult / 含两对的手 | 无 | 无 |
| Wee Joker | Rare | +8 Chips / 每张计分的 2(吃重触发) | 无 | 无 |
| Obelisk | Rare | ×0.2 / 连续一手不打最常用牌型 | 无 | 打出最常用牌型 → ×1;**并列时打并列牌型不重置** |
| Supernova | Common | Mult = 该牌型本局已打次数(间接累积) | 无 | 无 |
| Loyalty Card | Uncommon | 每 6 手的第 6 手 ×4(周期型) | 固定 | 周期循环 |
| Vampire | Uncommon | ×0.1 / 每张计分的增强牌(并吃掉增强) | 无 | 无(成本=毁增强) |
| Lucky Cat | Uncommon | ×0.25 / 每次 Lucky 牌成功触发 | 无 | 无 |

### 卖牌 / 销毁驱动
| 牌名 | 稀有度 | 成长速率 | 上限 | 重置条件 |
|---|---|---|---|---|
| Campfire | Rare | ×0.25 / 每卖 1 张卡 | 无 | **击败 Boss 盲注 → ×1** |
| Ceremonial Dagger | Uncommon | 选盲注时吞右侧小丑,+其卖价×2 的 Mult | 无 | 永不重置(累积) |
| Glass Joker | Uncommon | ×0.75 / 每张 Glass 牌碎裂 | 无 | 无 |
| Canio | Legendary | ×1 / 每张人头牌被销毁 | 无 | 无 |
| Madness | Uncommon | ×0.5 / 每次选小/大盲注,随机毁 1 张其他小丑 | 无 | 无(成本=毁友军) |
| Swashbuckler | Common | +Mult = 其他小丑总卖价(读取) | 无 | 随卖价波动 |
| Egg | Common | 自身卖价 +$3/轮(喂上面两张) | 无 | 无 |

### 金钱驱动
| 牌名 | 稀有度 | 成长速率 | 上限 | 备注 |
|---|---|---|---|---|
| Bull | Uncommon | +2 Chips / 每 $1(读取) | 无 | 花钱即降,可逆 |
| Bootstraps | Uncommon | +2 Mult / 每 $5(读取) | 无 | 可逆 |
| To the Moon | Uncommon | 每 $5 多 $1 利息 | 受利息上限 | 经济复利 |
| Rocket | Uncommon | 回合末发钱,每击败 Boss payout +$2 | 无 | 永久累积 |

### 消耗品驱动
| 牌名 | 稀有度 | 成长速率 | 上限 | 重置条件 |
|---|---|---|---|---|
| Constellation | Uncommon | ×0.1 / 每用 1 张星球牌 | 无 | 无 |
| Fortune Teller | Common | +1 Mult / 本局每用 1 张塔罗 | 无 | 无 |
| Space Joker | Uncommon | 1/4 概率升级所打牌型等级 | 无 | 永久(随机→成长) |
| Hologram | Uncommon | ×0.25 / 每有 1 张牌加入牌库 | 无 | 无 |

### 跳过 / 商店行为驱动
| 牌名 | 稀有度 | 成长速率 | 上限 | 重置条件 |
|---|---|---|---|---|
| Throwback | Uncommon | ×0.25 / 本局每跳过 1 个盲注 | 无 | 无 |
| Red Card | Common | +3 Mult / 每跳过 1 个补充包 | 无 | 无 |
| Flash Card | Uncommon | +2 Mult / 每次商店 reroll | 无 | 无 |

### 牌库结构驱动(全部为读取型)
| 牌名 | 稀有度 | 数值 | 备注 |
|---|---|---|---|
| Blue Joker | Common | +2 Chips / 牌库剩余每张 | 鼓励厚牌库 |
| Erosion | Uncommon | +4 Mult / 低于初始牌库每张 | 鼓励毁牌,与上互斥 |
| Steel Joker | Uncommon | ×0.2 / 牌库每张 Steel | 构筑读取 |
| Stone Joker | Uncommon | +25 Chips / 每张 Stone | 构筑读取 |
| Driver's License | Rare | ≥16 张增强牌 → ×3 | 阈值型 |
| Abstract Joker | Common | +3 Mult / 每张持有小丑 | 槽位读取 |

**注意:Balatro 没有任何一张「什么都不做、每回合自动 +Mult」的小丑。** 最接近的 Rocket 也要击败 Boss 才涨,Egg 涨的是卖价而非分数。所有分数成长都绑定玩家的主动行为。

---

## C. 张力 / 惩罚设计表

| 牌名 | 机制 | 逼迫的行为取舍 |
|---|---|---|
| Ride the Bus | 计分人头牌 → 归零 | 整个构筑弃用人头牌,与 Baron/Photograph 流互斥 |
| Green Joker | 弃牌 −1 | 每次弃牌都在「手牌质量」和「已攒成长」之间做交易 |
| Ice Cream | +100 Chips,每出一手 −5,归零融化 | 租来的爆发力:趁新鲜期冲分,并规划何时让它「融化」 |
| Popcorn | +20 Mult,每轮 −4,归零爆掉 | 5 轮租约:早期神牌,逼你算准过渡期何时结束 |
| Turtle Bean | +5 手牌上限,每轮 −1 | 手牌上限租约,窗口期内榨干选牌自由度 |
| Ramen | ×2,每弃 1 张 −0.01,≤×1「Eaten!」自毁 | 给弃牌行为明码标价:弃得越凶,乘区死得越快 |
| Seltzer | 10 手内全牌重触发,然后自毁 | 限时爆发窗口,逼你把重触发协同压进 10 手内 |
| Gros Michel | +15 Mult,每轮 1/6 自毁 | 廉价数值的风险贴现;死后才解锁 Cavendish(×3, 1/1000)作为幸存者奖励 |
| Obelisk | 打最常用牌型 → ×1;**并列不重置,且重置发生在计分前** | 故意不打最优手,甚至刻意维持多牌型并列——与「专精一个牌型升级」的主线彻底对冲 |
| Madness | 每选盲注 ×0.5,随机毁一张友军 | 只在槽里全是垃圾时是白吃,否则成长=拆家 |
| Ceremonial Dagger | 选盲注吞右侧小丑 | 显式献祭:买垃圾小丑喂刀,摆位即喂食顺序 |
| Vampire | 吃掉计分牌的增强换 ×0.1 | 与增强构筑对冲:吸血鬼流不能同时是增强流 |
| Hit the Road | 回合结束归 ×1 | 弃 J 的爆发只活一轮,要把爆发轮对准 Boss |
| Campfire | 击败 Boss → ×1 | Boss 前集中卖卡冲一波,Boss 后归零重来 |
| Loyalty Card | 每 6 手才 ×4 | 把大牌型精确对准周期的第 6 手 |
| Invisible Joker | 白占槽 2 轮,卖出时随机复制一张 | 槽位租约 + 赌局 |
| Egg | 只涨卖价不给分 | 占槽攒钱,纯机会成本投资 |
| Stuntman | +250 Chips,−2 手牌上限 | 数值换选牌自由度 |
| Banner / Mystic Summit | +30 Chips/剩余弃牌 vs 0 弃牌时 +15 Mult | 把「弃牌资源」直接标价成分数,两张方向相反 |

---

## D. 概率型小丑简表

| 牌名 | 稀有度 | 机制 | 随机性的用法定位 |
|---|---|---|---|
| Misprint | Common | +0~23 Mult 均匀随机 | 纯噪声,期望≈11.5:娱乐牌,无构筑深度 |
| Bloodstone | Uncommon | 每张计分红桃 1/2 → ×1.5 | 概率×倍率:期望≈每张×1.25,配红桃洪水+重触发压方差 |
| Space Joker | Uncommon | 1/4 升级所打牌型等级 | **随机→永久成长**:方差被存进不可逆状态,最优雅的一档 |
| Lucky Cat(+Lucky 牌) | Uncommon | 每次 Lucky 成功触发 ×0.25 | 同上:概率事件喂永久计数器 |
| 8 Ball | Common | 每张计分 8,1/4 出塔罗 | 随机资源引擎 |
| Business Card | Common | 计分人头 1/2 → $2 | 概率经济 |
| Reserved Parking | Common | 手持人头 1/2 → $1 | 概率经济(On Held) |
| Hallucination | Common | 开补充包 1/2 出塔罗 | 概率资源 |
| Gros Michel / Cavendish | Common | 1/6、1/1000 自毁 | **负向概率**:给数值定风险价 |
| Oops! All 6s | Uncommon | 所有「1 in X」概率翻倍 | **元概率牌**:把概率本身变成可构筑的轴 |

四档定位:纯噪声(Misprint)→ 概率×收益(Bloodstone)→ 概率转永久成长(Space Joker/Lucky Cat)→ 概率放大器(Oops! All 6s)。深度全在后两档:随机被「存档」,方差被平滑成成长曲线。

---

## E. 关键观察(对 Sync5:实时制 / 结算自动取最优 / 4 槽)

1. **摆位博弈的本质是同一累加器上混用加法和乘法**(算例 1 的 33% 差距)。Sync5 现有链「牌型 → target(×N)→ support(+%)→ 主角」里 ×N 和 +% 全是乘法算子,满足交换律,**槽位顺序对分数天然无影响**。想要 Balatro 式摆位深度,必须在链里引入真正的加法环节(+固定分);不想要就明确承认槽序无意义,别留半吊子。另外 Balatro 用「激活类型分层 > 槽序」(算例 2)限制了摆位自由度——固定链序换可读性,在实时制下是合理取舍。

2. **「结算自动取最优」杀死两类 Balatro 张力**:回避型重置(Ride the Bus——自动选出的最优牌型可能替玩家踩人头牌雷,玩家会觉得被系统坑)和故意打劣手喂成长(Obelisk)。Sync5 的成长/重置条件必须挂在**玩家显式动作**上(弃牌、缓存对调、商店决策),绝不能挂在「结算出的牌型内容」上。

3. **实时 12s 下,「每手」计数器 ≈ 纯时间计时器**(每 phrase 必结算),per-hand 成长会退化成挂机也涨。Balatro 的铁律是没有一张纯挂机成长牌,全部绑定主动行为——Sync5 的成长驱动应绑到弃牌(本来就花 1 金币/张,弃牌驱动+金钱驱动天然双重张力,Bull/Bootstraps vs Green Joker/Ramen 这组对冲最值得抄)。反过来,**衰减牌(Ice Cream/Popcorn)天然适配实时制**:时钟本来就在走,衰减读起来毫无歧义。

4. **重触发是 on-scored 成长与爆发的放大器**(Red Seal 先、重触发小丑左到右,每次重跑整段逐牌流程),但依赖逐牌计分的时间预算。12s phrase 里逐牌重触发动画不现实,可降级为粗粒度版本:「结算链某一环执行两次」或「主角被动本 phrase 触发两次」,保留倍增语义,丢掉逐牌粒度。

5. **4 槽让槽位经济全面涨价**。Balatro 5 槽下最高价值的设计是复制牌(Blueprint/Brainstorm,复制体在复制者位置生效、不能复制成长过程只复制当前值)——4 槽下一张复制牌等于第 5 个虚拟槽,更值得抄。反之,Madness/Ceremonial Dagger 类「毁友军换成长」与 Egg→Swashbuckler 类双卡组合在 4 槽里成本占 25%~50%,惩罚被放大,要么砍掉、要么补偿加倍。

---

Sources:
- [Guide: Activation Sequence — Balatro Wiki (balatrowiki.org)](https://balatrowiki.org/w/Guide:_Activation_Sequence)
- [Activation Type — Balatro Wiki (balatrowiki.org)](https://balatrowiki.org/w/Activation_Type)
- [Jokers — Balatro Wiki (balatrowiki.org)](https://balatrowiki.org/w/Jokers)
- [Obelisk — Balatro Wiki](https://balatrowiki.org/w/Obelisk)
- [Blueprint — Balatro Wiki](https://balatrowiki.org/w/Blueprint)
- [Ramen — Balatro Wiki](https://balatrowiki.org/w/Ramen)
- [Guide: Activation Sequence — Fandom(402 未能直接抓取,内容经 balatrowiki.org 交叉验证)](https://balatrogame.fandom.com/wiki/Guide:_Activation_Sequence)