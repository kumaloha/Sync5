# 调研 · 跨局周期化课程设计 & 操作收费经济

> **这一篇是外部事实**(research_* 惯例:刻意独立,不混设计判断)。
> 起因 = 2026-08-26 用户四条规定(经济三条 + 10-run 周期,见 levels.md 经济 v2 /
> difficulty.md §2.5)点名「需调研」。消费侧的设计判断写在那两篇,不在这里。

- 性质:**只含外部事实**,每条注明来源站点;不含任何设计建议(设计判断归主会话)。
- 采集日期:2026-08-26。检索与页面抓取均为当日快照;付费墙/反爬(Fandom、mobilegamer.biz、
  grokipedia)拦掉的页面,以搜索摘要转述并如实标注「搜索摘要」。
- 标注约定:〔汇算〕= 由上文已引数字直接相加/推得,非独立出处。

---

## 主题 A · 跨局关卡周期化 / 机制课程设计(curriculum)

### A1 · Candy Crush 的「复杂度阶梯」(机制引入节奏)

- King 官方说法(设计师 Davies):新 blocker(阻碍物机制)按 **"complexity staircase"(复杂度阶梯)**
  引入——新手接触简单机制,老玩家面对复杂组合。(来源:PocketGamer.biz,
  "Crafting Candy Crush's difficulty: Blockers, level design, AI and the 'complexity staircase'")
- 新机制的准入门槛:任何新 blocker 必须 "offer a distinct behaviour or interaction",
  不能只是已有机制的变体。(PocketGamer.biz,同上)
- 新机制**逐步灰度推出**:2025 年的 Mal-O-Matic blocker 不是立即全量上线,而是逐步测试、
  收集数据与玩家反馈。(PocketGamer.biz,同上)
- 引入后要保证「可见性」:玩家要有足够多的关卡时间学会并习惯新机制;
  日常关卡混用新旧 blocker,靠全量机制库维持多样性。(PocketGamer.biz,同上)
- **明确否认固定模式**:King 自述关卡难度「无固定模式」「每关不一定比前一关难」,
  但**困难关之后刻意跟相对简单的关**,提供 "sense of variation and momentum"。
  (PocketGamer.biz,同上)
- 20,000+ 关的后期难度来源:更复杂的目标与限制、需要优先级决策的 blocker 组合、
  更复杂的棋盘布局——而不是单纯数值。(PocketGamer.biz,同上)

### A2 · 数据驱动的难度校准

- King 用 **bot 大规模模拟**估计每关难度:"We use bots to simulate large numbers of plays
  to help us estimate difficulty",但强调这是 "support tool rather than replacement for
  human judgement"。AI 也用于生成草稿关卡。(PocketGamer.biz,同上)
- 每个新关卡先由自动化系统暴力搜索所有走法,输出一个难度分,帮设计师定位在曲线上的位置。
  (Medium,Fran Ruiz,"Match 3 level design study — Building three Candy Crush levels")
- 行业通行做法:头部三消按固定节奏(有的每周)出新关包;难度打分算法负责**标记偏离
  预期曲线的离群关卡**,作为生产流水线的一环。(Room 8 Studio / GameRefinery 相关文章,
  搜索摘要)

### A3 · 难度尖峰(考试关)与留存/付费的数据结论

- Candy Crush 的难度曲线是**锯齿形**:「令人沮丧的难关之后,通常跟 5–6 个简单到中等难度
  的关卡」;作者称这种「不一致的难度曲线」是其全部货币化手段的地基。
  (Game Developer / Gamasutra,"Candy Crush Saga: A Sweet Journey into Monetization")
- 难度尖峰与生命系统协同:生命限制游戏时长、尖峰迫使玩家反复尝试,两者共同拉长玩家
  在难关上的停留;"+5 moves" 是冲动购买设计——玩家「非常接近过关但失败」时触发,
  「轻易是游戏中货币化最强的部分,驱动大部分转化」。(Game Developer,同上)
- **King 自己公布的教训(考试关的留存代价)**:Level 65 原本是设计上的最终关,
  成为**转化率最高**的关,同时也是**流失最严重**的关;King 的结论是
  「crazy hard levels never pay off, at least in the long term」「retention always wins」——
  提高难度短期抬转化,长期看把关调容易反而留人更久。
  (mobilegamer.biz,"How King defines a 'good' Candy Crush Saga level",搜索摘要;
  原页 403,未能直接核对原文)
- Candy Crush 官方在关卡表上**显式标注考试关**:有 "Hard" / "Super Hard" 级别标记
  (橙/红标识)。(Candy Crush Fandom Wiki "Hard levels" / "Difficulty" 词条,
  搜索结果;Fandom 页面本体未能抓取)
- 满意感的来源不是裸难度而是反馈:成功动作有明确视听强化;成功感是推动进度与留存的
  主驱动。(lootbar.gg 分析文 + Game Developer,搜索摘要)

### A4 · 近失效应(near-miss)的实验数据

- 老虎机研究里,near-miss 频率对「坚持继续玩」的作用呈**倒 U 形,峰值约 30%**:
  30% 近失条件下的坚持时间显著长于 15% 与 45% 条件。
  (Journal of Gambling Studies,"The Near-Miss Effect in Slot Machines: A Review and
  Experimental Analysis Over Half a Century Later",2019/2020,link.springer.com 与
  PMC7214505)
- 近失会激活与「赢」相关的脑区并提高继续赌的动机(fMRI 证据)。
  (Neuron,"Gambling Near-Misses Enhance Motivation to Gamble and Recruit Win-Related
  Brain Circuitry",sciencedirect.com)
- 高冲动性个体在高频近失下坚持更久(其他条件不变)。
  (International Gambling Studies 2023 / J. Gambling Studies 2025,搜索摘要)
- 注:这组是赌博文献,对象是老虎机;把它映射到关卡设计属于设计判断,此处只记数据。

### A5 · roguelite 跨局难度阶梯(同一批内容如何跨局重复可玩)

**Slay the Spire · Ascension(线性强制叠加型)**
- 解锁规则:在当前 Ascension 打过第三幕 Boss,解锁下一级;每个角色独立。
  ("Beating an Act 3 Boss on a given Ascension level will then unlock the next.")
  (slaythespire.wiki.gg/wiki/Ascension)
- 20 级,**逐级累加**(打 A5 = 1–5 全部生效),每级一个离散修改。1 代完整表:
  A1 精英更常出现(约 +60%);A2 普通敌更致命;A3 精英更致命;A4 Boss 更致命;
  A5 Boss 战后只回 75% 已失生命;A6 开局扣 10% 血;A7 普通敌更硬;A8 精英更硬;
  A9 Boss 更硬;A10 开局带一张诅咒;A11 少一个药水槽;A12 升级卡出现率 -50%;
  A13 Boss 掉落金币 -25%;A14 最大生命降低;A15 事件更差;A16 商店贵 10%;
  A17–19 敌人行为模式更难;A20 第三幕双 Boss。(slaythespire.wiki.gg/wiki/Ascension)
- 外部评论对这套系统的正面归因:修改「单个不难、叠起来才重」,让玩家逐级学习系统;
  A20 双 Boss 被认为是针对特定 build 的检验,迫使构筑真正多样。
  (frostilyte.ca 评论文 + Steam 社区讨论,搜索摘要;frostilyte 原页 403)

**Hades · Heat / Pact of Punishment(自选菜单型)**
- 通关一次后解锁;共 **15 种条件(Hell Mode 16 种)**,每种条件分档(rank),
  每档给若干 Heat,玩家**自由勾选组合**凑出总 Heat。
  (GameSkinny,"Hades Pact of Punishment: Conditions, Bounties, & Heat Explained";
  RPG Site 同题指南)
- 例:Hard Labor = 敌伤 +20%/档,+1 Heat/档,最多 5 档;
  Lasting Consequences = 治疗效果 -25%/档,+2 Heat/档,最多 4 档(共 8 Heat)。
  (GameSkinny / PlayStationTrophies,搜索摘要)
- 奖励(Bounty)结构:**只有「该武器在更高 Heat 下的首次通过」给一次性奖励**;
  每个区域 Boss 各有一份;每把武器的 Heat 奖励门槛独立计——
  即「重复可玩性」由「武器 × Heat 档」这张二维表撑起。(GameSkinny / RPG Site,搜索摘要)

**Balatro · Stakes(线性强制、但改的是经济与商店)**
- 8 档,逐档解锁(在当前最高 Stake 通关才开下一档),**每个牌组独立进度**;
  通关给牌组与 Joker 贴对应色贴纸(收集向标记)。(balatrowiki.org/w/Stakes)
- 全表:White 基础;Red 小盲注不给奖励金;Green 每 Ante 目标分涨得更快;
  Black 商店 Joker 30% 概率带 Eternal 贴纸(不可卖);Blue -1 弃牌;
  Purple 目标分涨得再快;Orange Joker 30% 概率带 Perishable(若干回合后失效);
  Gold Joker 30% 概率带 Rental(每回合扣 $3)。(balatrowiki.org/w/Stakes)
- 社区已知批评:高 Stake 主要砍**金币获取**,被指「迫使玩家依赖 Joker 随机质量、
  减少与商店构筑系统的互动」,与 StS A20「用双 Boss 检验构筑」形成对比。
  (Steam 社区讨论,搜索摘要;属玩家观点,非官方)

### A6 · 「固定周期表」优缺点的已归因外部说法

- 支持「变化优先于固定」的:King 明说自家关卡表「无固定模式」,难后跟易是**刻意做的
  变化感**(见 A1);难度曲线的锯齿形本身是被外部分析者归因为其货币化与参与度的基础
  (见 A3)。(PocketGamer.biz;Game Developer)
- 支持「周期可预测性」的:三消行业通行「教学关→巩固关」的排布,「学新招给玩家带来
  快乐」,教学之外还专门做教育性关卡;特殊规则关/支线 dungeon 用来打断主线节奏、
  维持新鲜感。(Room 8 Studio 三消关卡设计指南;GameRefinery Harry Potter Puzzles &
  Spells 分析,搜索摘要)
- 「考试关」的量化代价与收益并存:转化率最高与流失最高可以是同一关(Level 65,见 A3)。
  (mobilegamer.biz,搜索摘要)
- 未找到:公开的「每 N 关一考试」固定周期表的 A/B 留存数据(King 只给了结论性引述,
  未公布分关数据)。近失-坚持的量化数据只在赌博文献里(见 A4)。

---

## 主题 B · 弃牌/操作收费的资源经济

### B1 · Balatro 的操作配额(hands / discards)

- 默认每个盲注 **4 hands + 3 discards**,多数牌组如此;蓝牌组 +1 hand,红牌组 +1 discard
  等由牌组改。(balatrowiki.org/w/Hands、/w/Discards;Steam 社区确认帖,搜索摘要)
- 配额**每盲注重置**,不跨盲注结转;跨局不变(不是升级项),局内可用 Voucher 永久 +1
  hand 或 +1 discard。(balatrowiki.org;TouchArcade LocalThunk 访谈提及 Voucher 给
  「每轮额外一手/一弃」)
- Blue Stake 的难度手段之一就是 **-1 discard**(见 A5),即官方把弃牌配额当难度旋钮。
  (balatrowiki.org/w/Stakes)

### B2 · Balatro 的金币来源(具体数字)

- 开局资金:标准牌组 **$4**;黄牌组额外 +$10;"Rich get Richer" 挑战 $100 起。
  (balatrowiki.org/w/Money)
- 盲注通关奖励(White Stake):小盲 **$3**、大盲 **$4**、普通 Boss **$5**、
  Ante 8 终局 Boss **$8**。(balatrowiki.org/w/Money、/w/Blinds_and_Antes)
- **剩余 hands 返利:每剩 1 手 +$1**(绿牌组改为每剩 1 手 $2、每剩 1 弃 $1——
  绿牌组同时失去利息)。**默认规则下剩余 discards 不给钱**。(balatrowiki.org/w/Money)
- 目标分结构:小盲 1×基础分,大盲 1.5×,Boss 多为 2×(The Wall 4×、The Needle 1×,
  终局 Boss 2× 或 6×);共 8 个 Ante,打完进无尽。(balatrowiki.org/w/Blinds_and_Antes)
- 小盲/大盲**可跳过换 Tag**(各种延迟奖励),Boss 必打。(balatrowiki.org/w/Blinds_and_Antes)

### B3 · Balatro 的利息(存钱奖励)

- 每回合结算:**每持有 $5 得 $1,单轮上限 $5**(即 $25 以上不再生息)。
  (balatrowiki.org/w/Interest、/w/Money)
- 上限扩展:Voucher「Seed Money」上限 $10(即 $50 生息)、升级版「Money Tree」上限
  $20(即 $100 生息);Joker「To the Moon」每 $5 **额外** +$1(利率翻倍)。
  (balatrowiki.org/w/Interest)
- 反面开关:绿牌组与 Mad World 挑战**完全无利息**。(balatrowiki.org/w/Interest)
- 结算顺序细节:Golden Joker、Rocket 等「回合结束后触发」的进账不计入当轮利息本金;
  Gold 卡、Reserved Parking 等「利息计算前触发」的计入。(balatrowiki.org/w/Interest)
- 社区通行策略口径:尽快存到 $25 吃满 $5/轮;也公认「先存满再买」有死于缺强度的风险。
  (games.gg Balatro 经济指南;Steam 新手指南,搜索摘要)

### B4 · Balatro 的卡价分布与商店结构

- 货架构成:每次进店 2 张卡位 + 2 个卡包 + 1 张 Voucher。(balatrowiki.org/w/The_Shop)
- 基础价:Joker——Common **$1–6**、Uncommon **$4–8**、Rare **$7–10**、Legendary $20
  (Legendary 不上架,只能由 The Soul 生成);Tarot/Planet $3、Spectral $4;
  卡包 $4/$6/$8(普/大/巨);Voucher **$10**。(balatrowiki.org/w/The_Shop;
  稀有度权重:店内 70% Common / 25% Uncommon / 5% Rare,balatrowiki.org/w/Jokers,搜索摘要)
- 版本溢价:Foil +$2、Holographic +$3、Polychrome +$5、Negative +$5。
  (balatrowiki.org/w/The_Shop)
- **Reroll:起价 $5,每刷 +$1,进新店重置回 $5**;有 Voucher 降低起价。
  (balatrowiki.org/w/The_Shop)
- 卖卡回收:**sell = floor(买价 / 2)**。(balatrowiki.org/w/The_Shop)
- 持续性扣费的反例卡:Rental 贴纸 Joker **每回合扣 $3**(Gold Stake 引入)。
  (balatrowiki.org/w/Money、/w/Stakes)

### B5 · 一个 Ante 的典型收支〔汇算,基于 B2/B3 已引数字〕

- 一个 Ante 打满三盲注的固定进项 = $3+$4+$5 = **$12**;
  若每盲注平均剩 1 手,+$3;利息吃满时 +$5/盲注结算 ×3 = +$15。
  即无利息新手 ≈ $12–15/Ante,满利息熟练玩家 ≈ $27–30/Ante。〔汇算〕
- 对照单价:一张 Uncommon Joker($4–8)≈ 半个到一个 Ante 的基础进项;
  一次 Voucher($10)≈ 一个 Ante 基础进项的 80%。〔汇算〕
- 社区攻略的口径与此一致:每 Ante 的购买决策围绕「买卡 vs 攒利息本金 vs reroll」三选。
  (casualgameguides.com "How Should You Spend Money and Rerolls Each Ante?",
  搜索结果;原页 429 未能核对全文)

### B6 · 其他卡牌/赌博 roguelite 的「操作次数」货币化

**Luck Be a Landlord(定期缴税型:操作免费、结果收税)**
- 转轮(操作)本身免费,资源压力全部来自**房租死线**:每隔固定次数的 spin 必须交租,
  交不起即被驱逐(run 结束);目标 = 交满 12 次租后进无尽。(Wikipedia
  "Luck Be a Landlord";LBAL Wiki "Rent" 词条,搜索摘要)
- 递增表(搜索摘要口径):首次租金 **25 币**,到第 12 次涨到 **777 币**;
  两次交租之间的 spin 数从开局 **5 次**逐步增至第 11 次起的 **10 次**。
  (LBAL Wiki / Wikipedia,搜索摘要;Fandom 原页未能抓取)
- 每次 spin 后三选一加一个 symbol 进池——即「每次操作 = 一次构筑决策」,
  操作与构筑同频。(Wikipedia / TV Tropes,搜索摘要)
- 外部评论把「交租」认定为该游戏戏剧张力的主来源。(nerdgirlthoughts.game.blog 等评测)

**Ballionaire(定期缴税型的变体)**
- 每回合投固定数量的球(评测口径:**每 7 球**一次结算),到点必须交出递增的
  "tribute",交不起即 game over;每次落球间隙做一次放置/三选一。
  (GodisaGeek、PC Gamer、GamingOnLinux、MonsterVine 评测)

**Dungeons & Degenerate Gamblers(把赌注直接换算成血)**
- 21 点对局,输局不扣钱而是**扣 HP**,伤害 = 赢家点数 − 输家点数,爆牌视作 0
  (吃满伤害)——即「下注失败」以生命值计价。(PC Gamer、Gamecritics、
  Indie Hell Zone 评测;Wikipedia)
- 花色自带经济通道:红桃回血、梅花加伤、黑桃加盾、**方片给筹码(店内货币)**——
  打出操作本身就在产币。(PC Gamer / Indie Hell Zone 评测)

**Balatro 自身的「操作定价」结构(对照)**
- 操作(出牌/弃牌)不直接花钱,而是**每盲注配额制**;未用完的 hand 按 $1/手回购
  (= 官方给「省着用操作」标了价),discard 剩余不回购(见 B2)。
  (balatrowiki.org/w/Money)
- LocalThunk 自述:设计多靠反复试错而非预先规划;灵感源含 Big Two(锄大地/大老二)
  与 Luck Be a Landlord 的视频。(Rogueliker / TouchArcade / Rolling Stone 访谈)

### B7 · Coin-op / 赌场的「按操作付费 + 按结果返利」闭环

- 街机标准定价:1980s–90s 通行 25 美分/局(部分新机 50–75 美分);
  运营商可调难度档,**平均玩家单币时长被调到约 3–5 分钟**。
  (bitvint.com "The Economics of Arcades";JVL、MEL Magazine)
- 「三分钟规则」:整个生态要求高翻台率,设计端把单币局面做成「数学上注定在约 180 秒
  内 Game Over」,同时用快节奏短局维持继续投币的意愿。
  (gamesfreezer.co.uk "From Coin-Op to Cloud";MEL Magazine,搜索摘要)
- Gauntlet 的连续计费结构:生命值持续流失、投币回血——把「时间」直接标成钱;
  巅峰期单台周入约 **$900**。(bitvint.com / MEL Magazine,搜索摘要)
- 「按结果返利」在街机侧的原生形态:高分续命/免费局(replay)与弹珠台 extra ball
  一脉;学术侧把街机经济归纳为「小额高频投入 + 技能延长回报」模型。
  (ResearchGate,"Coin-drop capitalism: Economic lessons from the video game arcade",
  搜索结果,未能抓取全文)
- 赌场侧与「返利节奏」直接相关的量化研究即 A4 的近失倒 U 曲线(30% 峰值);
  另见 fMRI 证据:近失激活赢奖脑区。(Springer JGS 2019;Neuron/ScienceDirect)
- 行业迁移评论:手游的体力/生命系统被多位作者直接追溯到 coin-op 的按次收费结构
  (Candy Crush 生命系统 = 变相投币口的说法)。(PocketGamer.biz "Lessons from
  coin-op";gamesfreezer.co.uk,搜索摘要)

---

## 来源索引(按站点)

- pocketgamer.biz — Candy Crush complexity staircase 专访;Lessons from coin-op
- gamedeveloper.com — Candy Crush Saga: A Sweet Journey into Monetization
- mobilegamer.biz — King 谈好关卡与 Level 65 教训(403,搜索摘要)
- medium.com (Fran Ruiz) — Match 3 level design study
- room8studio.com / gamerefinery.com — 三消关卡设计与机制引入节奏(搜索摘要)
- candycrush.fandom.com — Hard levels / Difficulty(未能抓取,搜索结果)
- slaythespire.wiki.gg — Ascension 全表与解锁规则
- gameskinny.com / rpgsite.net / playstationtrophies.org — Hades Pact of Punishment 条件与 Bounty
- balatrowiki.org — Interest / Money / Blinds and Antes / The Shop / Stakes / Hands / Discards
- games.gg / steamcommunity.com — Balatro 经济攻略与社区讨论(策略口径、Stake 批评)
- casualgameguides.com — Balatro 每 Ante 花钱节奏(429,搜索结果)
- en.wikipedia.org — Luck Be a Landlord;Dungeons & Degenerate Gamblers;Balatro
- luck-be-a-landlord.fandom.com — Rent 词条(未能抓取,搜索摘要)
- godisageek.com / pcgamer.com / gamingonlinux.com / monstervine.com — Ballionaire 评测
- gamecritics.com / indiehellzone.com — D&DG 评测
- rogueliker.com / toucharcade.com / rollingstone.com — LocalThunk 访谈
- link.springer.com / ncbi.nlm.nih.gov (PMC) / sciencedirect.com / tandfonline.com — 近失效应文献
- bitvint.com / melmagazine.com / jvl.ca / gamesfreezer.co.uk / researchgate.net — 街机经济
- frostilyte.ca — StS 难度系统评论(403,搜索摘要)
