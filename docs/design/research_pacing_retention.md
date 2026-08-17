# 节奏、体感与留存 · 外部调研

> 2026-08-07。`docs/design/gates.md` 列的四个方向的调研结果。
> 目的不是综述,是**给 Director 和体感量化找可用的外部依据**,并把「我们已经拍板的东西
> 有没有外部支持」核一遍。
>
> 每节末尾有 **→ 对我们的意思**,那是这份文档真正的输出。
> 来源见文末。

---

## 0. 先说四个最重要的发现

| # | 发现 | 为什么重要 |
|---|---|---|
| 1 | **手游 session 中位数 = 4分45秒,我们一局 4.9 分钟** | 参照系确认了:**我们的留存结构更像短局手游,不像 Balatro(30-90 分钟)**。docs/design/gates.md 的预判成立 |
| 2 | **「高 D1 低 D7」的公认解读 = 缺中期深度或 meta 进度** | 我们的 meta(`docs/design/ui_meta.md`)**整块未做**。这不是"以后再说",它直接决定 D7 |
| 3 | **近失效应依赖「玩家对结果有选择权」** —— 纯运气场景下它会衰减 | 我们是技巧游戏且玩家全程在选 → **近失对我们特别有效**,而且它被解读成「我快学会了」,直接喂养**成长感** |
| 4 | **DDA 必须不可见;可见的 DDA(橡皮筋)是被公认讨厌的** | 而 L4D 的解法给出了正路:**改内容不改数值**。这印证了我们已拍板的「个性化只动货架权重,不动目标分和价格」 |

---

## 1. Dynamic Difficulty Adjustment(DDA)

### 学术起点

Hunicke & Chapman 的 **Hamlet**(2005,ACM ACE)是这条线的奠基工作:
系统周期性检查玩家进度,用**库存/补给的随机管理**去调整难度,目标是把玩家维持在一个
「舒适区」里。后续研究普遍报告 DDA 对**enjoyment / flow / motivation / engagement /
immersion** 有显著影响,但也普遍指出:**还不清楚玩家偏好该怎么映射到具体参数上。**

### ⚑ 最硬的一条约束:被察觉就失效

这是全部调研里最一致、也最该当铁律的一条:

> 玩家喜欢不可预测和新鲜感,但一旦感到游戏「在过程中被调整」,他们会觉得**被骗**。
> 研究反复确认玩家**出乎意料地敏感**;一旦怀疑游戏在作弊或人为操纵难度,
> 信任和投入会迅速崩掉。

**橡皮筋(rubber banding)是最好的反面教材**:它机制上和其他 DDA 没有本质区别,
唯一的差别是**容易被看见**。结论被反复表述为同一句话:

> **DDA 要成功就必须不可见——玩家永远不该感觉到它在发生。**

还有一条对我们特别相关:**隐蔽的、以变现为目的的 DDA 会操纵情绪、抬高消费压力、
扭曲公平感**。

### DDA ≠ Director:一条有用的概念区分

调研里有一个我认为很关键的区分:

| | 做什么 | 可见性 |
|---|---|---|
| **DDA(狭义)** | 对**现有数值**做微调(血量、伤害、目标分) | 高 —— 同一个挑战突然变软,玩家能感觉到 |
| **Director** | **雕塑一个不同的体验**(换内容、换编排、换节奏) | 低 —— 换的是"遇到什么",不是"同一个东西变弱了" |

> **→ 对我们的意思(这条直接决定 Director 的作用点)**
>
> **Director 绝对不能偷偷调目标分** —— 目标分**玩家看得见**(HUD 上就写着 `0 / 2083`),
> 调它就是可见 DDA,是橡皮筋。
>
> 能调的是**玩家看不见来源的东西**:哪张脸出现、货架上有什么。这和我们
> 2026-08-06 已拍板的「个性化只动货架池内权重,不动目标分/价格/刷新费,
> 偏置上限 ≤2×,不许穿帮」**完全一致** —— 外部研究印证了那条拍板,不是推翻它。
>
> ⚠ 而且商业化那一步要特别小心:「变现驱动的隐蔽 DDA 扭曲公平感」正是
> 「个性化货架 + 商业化」撞在一起会踩的雷。到时候那条 ≤2× 的上限要重新审。

---

## 2. Left 4 Dead 的 AI Director(应用侧的标杆)

这是 2008 年以来最有影响力的一个实装,后来被 Far Cry 系列、Watch Dogs 2 沿用。
它值得细看,因为**它要解决的问题和我们的 Director 几乎一样**。

### 四相循环

Director 有一个显式的相位机 —— 这不是隐喻,是代码里的状态:

| 相 | 做什么 |
|---|---|
| **Build Up** | 离开安全区后进入,普通敌人和特殊敌人正常刷,尸潮定期出现 |
| **Sustain Peak** | 维持满威胁人口一小段时间,并**保证 Build Up 有最小时长** |
| **Peak Fade** | 威胁人口降到最低,**不再主动生成** |
| **Relax** | 玩家休息恢复,**Wanderer / 尸潮 / 特殊敌人一个都不刷** |

驱动它的是每个玩家的 **Intensity**:被攻击时上升、在近处击杀时也上升;
Intensity 打满 = 到达 Peak。整体沿一条**预定的张力曲线**走,可调的内容是
敌人数量与位置、节奏、以及视听效果(动态配乐、角色台词)。

### 三条可以直接搬的做法

**① Relax 是「完全不刷」,不是「少刷一点」。**
这是我觉得最容易做错的地方。半放松等于没放松——玩家的紧张不会因为压力从 100% 降到 70%
而解除。要给恢复,就得**真的清零**。

**② Director 控制的是内容,不是数值。** 它从不把僵尸调弱,它改的是"什么时候来、来多少、从哪来"。
这正是 §1 那条"不可见"约束的工程解法。

**③ 有最小时长保护。** `Sustain Peak` 明确"保证 Build Up 有最小时长" ——
防止相位被玩家的异常表现瞬间打穿。任何相位机都需要这个。

### 一条批评

也有对它的批评,而且切中要害:

> 「把玩家推进不适区」和「不公平地整玩家」之间只有一条细线。
> 这套东西**只有在新情况下玩家仍有足够多的选项**时才成立。

> **→ 对我们的意思**
>
> ① **四相循环可以直接借,但我们的分辨率不够。** 一局只有 4 段,画不出
> Build Up → Peak → Fade → Relax 一个完整周期。**所以相位必须落在段内**
> (24 拍 / 8 商店),或者跨局(见 §5 的 meta 讨论)。
>
> ② **「Relax 要清零」翻译到我们这里 = 放松段应该是「没有脸」,不是「弱一点的脸」。**
> 而现在 **4 段全是墙,段段带脸**,结构上根本没有 Relax 相。这是个真实的缺口。
>
> ③ **「新情况下仍有足够选项」正是我们「弯折不报废」那条铁律。**
> 两者是同一条原则的不同说法,可以互相引用。

---

## 3. 心流:能当词汇,不能当指标

### 标准说法

技能与挑战的平衡是心流的**核心前提**:挑战超过技能会焦虑,技能超过挑战会无聊。
Sweetser & Wyeth 的 **GameFlow** 把它落成八条:concentration / challenge /
player skills / control / clear goals / feedback / immersion / social interaction。

### ⚑ 但批评才是有用的部分

调研里对心流的批评相当一致,而且直接决定我们能不能拿它当目标函数:

1. **心流模型没有给「高」「低」技能/挑战的可操作判据** —— 主观性因此无法排除;
2. **自陈量表的适用性受质疑**,实验里连"诱发心流 / 诱发非心流"都很难做到;
3. **"完美匹配挑战与技能就产生心流"这条预测在实验里站不住** ——
   模型可能把关系过度简化了;
4. 还有反例方向的研究(Soulslike 的「Struggle as Flow」):**持续的高挑战也能产生心流**,
   这直接反驳"必须匹配"。

> **→ 对我们的意思**
>
> **不要把心流当 Director 的目标函数。** 它没有可操作判据,拿它做目标等于把主观性
> 塞进一个看起来客观的公式里。
>
> 正确用法:**当词汇,不当指标**。用它描述我们想要什么(不要一直紧绷、不要一直放松),
> 但真正优化的量必须是**可计算的**——也就是 `docs/design/gates.md` 那三个因子。
>
> 这条同时支持 `docs/design/gates.md` 的做法:**先做敏感性分析,不要拟合权重**。
> 因为连"心流"这种研究了四十年的构念都还没操作化,我们自己拍的权重更不该被当真。

---

## 4. 近失效应(near-miss):对我们特别有效,但证据比工业界的信心弱

### 机制

近失 = 客观上输了,但「差一点就赢」。已确认的效应:

- **激活与获胜相同的脑区**,提升继续下注的动机(Clark 等,fMRI);
- 生理上:近失和输都会让心率加快,且**都让玩家更快开始下一次** ——
  也就是它确实缩短了重试间隔;
- 认知上:近失抬高了"下一次会赢"的预期,并助长**控制错觉**。

### ⚑ 最关键的一条:它依赖「玩家有选择权」

这条决定了它对我们是强还是弱:

> 要让近失解释成立,该活动**必须包含技巧成分**,或至少让玩家**觉得技巧与结果有关**。
> Clark 团队的发现是:这些效应更符合**控制错觉**的框架 ——
> 玩家把近失读成"**我已经在这个游戏上练出本事了**"的证据。
> 而这种解读**最容易发生在玩家能自己选择怎么赌的时候**。
>
> 反过来:在明确无技巧的纯运气环境里,近失**并不比完全输**更能提升动机。

> **→ 对我们的意思(这是全篇最有价值的一条)**
>
> 我们是**技巧游戏,而且玩家全程在做选择**(八选五、弃哪张、买哪张牌)。
> 所以近失对我们**处在最有效的那一端**。
>
> 更重要的是:**近失被解读成「我快学会了」** —— 那和 `docs/design/gates.md` 的
> **成长感**是同一个心理量。所以:
>
> **缺口分布不只是难度指标,它是成长感的燃料。** 死的时候差 3% 和差 40%,
> 前者产出"再来一局我能过",后者产出"这游戏不讲道理"。
> 而缺口是我们**现在就能算**的(`curve.gd` 已经录了逐段分数)。
>
> ⚠ 附带一条设计推论:**近失要发生在玩家真的有选择的段落上**才有效。
> 如果一段是"运气不好就是过不了",近失就退化成纯运气场景 —— 效应衰减。
> 这给「技巧空间」这个指标又加了一层意义:**技巧空间小的段落,近失也不值钱。**

### 剂量,以及一个必须写下来的怀疑

工业界(老虎机)的实践值:近失率控制在 **15%–45%**,**~30% 最优**;
低于 15% 玩家失去兴趣,高于 45% 玩家开始**起疑**。实现靠"虚拟卷轴",
是受专利保护的设计参数,并用行为数据持续优化。

⚠ **但学术侧的复现是失败的**:在鸽子和人类被试上的实验**都没能支持近失效应假说**,
提示其心理机制比通行说法复杂。

> **→ 对我们的意思**
>
> ① 那个 30% 是**待检验的假设,不是事实**。工业界的信心明显强于证据强度。
> 我们应该把它当作**先验值**填进去,然后**等留存数据检验**——正好符合
> `docs/design/gates.md` 的纪律(绝对值不可信,只信相对排序)。
> ② 但「>45% 会起疑」这条和 §1 的「DDA 被察觉就失效」是**同一个现象**,
> 两条独立来源互相支持,可信度比 30% 那个具体数字高得多。
> **所以宁可偏少不偏多。**

---

## 5. 短局与留存:我们的参照系不是 Balatro

### 基准数据

| 指标 | 全类型 | 益智类(最接近我们的一档) |
|---|---|---|
| D1 | 26%–33% | **31.9%** |
| D7 | 6%–14% | **12.2%**(全类型最高) |
| D30 | 1%–7% | **5.4%** |

**session 时长中位数(全区域)= 4 分 45 秒。**

### ⚑ 三条直接命中我们的结论

**① 我们一局 4.9 分钟 ≈ 手游 session 中位数。**

这不是巧合能忽略的量级差异 —— Balatro / 杀戮尖塔是 **30–90 分钟**一局。
**重试摩擦差一个量级,松紧结构的最优解就不可能一样。**
`docs/design/gates.md` 的预判成立:**参照系应该是短局手游,不是 Balatro。**

具体差别:一局 90 分钟的游戏,"最后一段极难 + 失败重开"的代价是毁灭性的,
所以它必须把难度铺得很缓;我们一局 5 分钟,**重开几乎不痛** ——
这反而允许更陡的难度和更高的死亡率,前提是**重开摩擦真的低**。

**② 「高 D1、低 D7」被公认解读为:缺中期深度或 meta 进度。**

我们的 meta(`docs/design/ui_meta.md`)**整块未做**,`HomeScreen.PROFILE` 里 LV/经验/金币/宝石
全是占位。按这条基准,**我们现在的结构大概率就是"高 D1 低 D7"**。
这不是"以后再说"的事项,它是 D7 的主要决定因素。

**③ 首次价值必须在 5–15 分钟落地,否则 D30 队列已经没了。**

我们一局 **4.9 分钟** —— 所以**第一局就是 FTUE 窗口的全部**。

⚠ 这条直接命中一个 CLAUDE.md 里已经标着"待验"的问题:
**4 段全是墙 → 教学空间归零,S1 就带 Boss 规则。**
现在这条有外部依据了:**教学空间归零是 D1/D30 的结构性风险**,不只是"手感问题"。

另外:**短 session 本身不能桥接 D10–30** —— 一天玩 4-6 次短局也补不上,
还得靠内容/活动的节奏。这又指回 meta。

### Balatro 为什么黏(对照组)

综述里归纳的机制:**可变奖励节奏 + 随机中的玩家能动性 + 递增难度 + 短 session +
一局结束到下一局开始的零摩擦**。

两条特别值得抄:

**① 零摩擦重开。** 「一局结束到下一局开始之间没有摩擦」被单列为核心机制之一。
> **→ 我们的失败屏是全屏中断 + 「再来一次」。该量一下重开摩擦:几次点击、几秒。
> 这是留存的直接杠杆,而且改起来很便宜。**

**② 学习是留存引擎。** 「Balatro 留住人,是因为每一局都让你学到一点系统之间怎么交互」。
> **→ 这正是我们的成长感因子,而且它说明「新鲜感」和「成长感」不是两件事:
> 新内容的价值在于它带来新的交互可学,不在于它"新"。**

一条反向的观察也值得记:Balatro **没有内购、没有体力、没有每日登录、没有付费皮肤**,
综述明确指出「**没有变现,就消除了通常会累积起来的那种怨气**」,玩家回来是因为
机制在奖励他们,不是因为弹窗提醒。
> **→ 这条对我们是个警告,不是禁令:商业化会引入一个 Balatro 没有的负向项,
> 而我们的目标函数是「有一定商业化能力的前提下留存最大化」——
> 那个"前提下"是有代价的,应该显式建模,不该假装免费。**

### Meta 进度的两难

roguelite meta 的目的很清楚:**让失败也产出进度**,好让玩家撑过反复的失败。
但风险同样清楚:**它会把技巧核心稀释掉**——把游戏变得太容易、太重复、通关不再有意义。
学术侧(2026)正在研究这个 retention vs gameplay integrity 的取舍。
手游 roguelite 常见的做法是 **catch-up meta**(挣扎的玩家获得加速的升级)。

> **→ 对我们的意思**
>
> ⚠ **catch-up meta 和「DDA 不可见」是冲突的** —— catch-up 本质就是被察觉的
> 难度补偿。如果要做,得做成**看起来像奖励**而不是**看起来像同情**。
> 这条要在 docs/design/ui_meta.md 动工前先想清楚,别做到一半才发现和 §1 的铁律撞车。

---

## 5.5 ⚑ 起承転結:每个单元都带挑战时,节奏怎么做

（2026-08-07 追加。用户指出 §2 的 L4D 类比套错了:**放松应该来自难度,不是来自「没有脸」**——
我们 8 秒的钟一直在走,本来就不存在 L4D 那种"安静走廊"。于是问题变成:
**每个单元都必须带挑战时,节奏从哪来?** 这一节是补的调研。）

### 结构:任天堂的四步关卡设计

**起承転結**(kishōtenketsu)是中日韩越叙事的四段结构:**起**(introduction)·
**承**(development)· **転**(twist/reversal)· **結**(conclusion)。
任天堂几十年来用它设计关卡,最典型的是《超级马里奥银河》和《3D 世界》。

四步对应到机制教学:

| 步 | 做什么 | 难度 |
|---|---|---|
| **起** Ki | 呈现这一关的主机制,给玩家一个**安全的地方**去用它、理解它,**不受任何惩罚** | 低 |
| **承** Shō | 同一个机制换不同方式呈现,让玩家学到围绕它的不同概念、练出相关技巧 | 中 |
| **転** Ten | 机制被**意外地**使用 —— 加入别的元素、或把它整个翻过来,玩家必须用已有的理解去找新解法 | 变 |
| **結** Ketsu | 一个需要**掌握**该机制才过得去的硬挑战 | 高 |

### ⚑ 尺寸吻合得离谱

综述里对这个结构的一句总结:

> 「这些关卡是四段式的、自成一体的新点子展示柜 —— 一个机制在**大约五分钟**里
> 被成功地**教会、发展、扭转,然后丢掉**。」

**四段。五分钟。**
我们是 **4 段 × 6 拍 = 4.9 分钟**。

这不是牵强附会:任天堂之所以收敛到"四段五分钟",和我们收敛到同样的数字,
背后是同一个约束 —— **一个机制能在玩家的工作记忆里活多久**。

### ⚑ 它直接解掉了 Relax 的问题

我在 §2 里说「段段有脸 = 结构上没有 Relax」,那个结论是错的,因为它假设
放松必须来自**挑战的缺席**。起承転結 给出的答案完全不同:

> **結 之后是下一个 起,而「起」按定义就是低难度、安全、无惩罚的。**
> **放松不是空白,是「一个新东西被安全地介绍给你」。**

这比"留一段没有脸"好得多,因为它**同时**给了放松和新鲜感 ——
而新鲜感是三因子之一,空白段落一分都拿不到。

**所以「4 段全是墙」这条拍板不需要推翻。** 需要的是给这 4 段套上 起承転結 的**难度形状**,
而难度我们已经能控制(脸的定价 + 目标分)。

### 落到我们的结构上

两种套法:

| 方案 | 形态 | 代价 |
|---|---|---|
| **A · 一局一弧** | 一局有一张**主脸**,在 4 段里走完 起承転結 | 和「4 段 4 张不同的脸」冲突 |
| **B · 只借形状** | 4 段仍是 4 张不同的脸,但按 起承転結 的**难度形状**排序 | 拿不到「同一机制被发展」的教学价值 |

**A 更接近原意**(起承転結 的核心是**同一个机制**被展开),而且它直接兑现
`docs/design/gates.md` 那条推论——「引入新脸的那段定得更松,下一段用同一张脸产生掌握感」。
**这两条是同一件事,只是我当时只推出了前两步(起 + 承),没看到还有 転 和 結。**

⚠ **A 案要求脸在段间「有意地重复」。**

### ⚠ 由此发现我自己加的一条测试断言是错的

2026-08-07 我给脸池加了一条结构断言:**相邻段的池子不得完全相同**(理由是多样性 C6),
还从 Balatro 抄了「所有脸露过一次之前不重复」。

**在 A 案下这条是反的。** 起承転結 要求同一张脸**跨段复现**,那是教学弧的载体,不是重复的浪费。

两边都对,只是适用条件不同:

| | 脸的总数 : 一局槽位 | 重复的含义 |
|---|---|---|
| Balatro | 28 : 8 = **3.5×** | 重复 = 纯粹的多样性损失 → 该禁 |
| 我们 | 12 : 4 = **1.5×** | 重复 = 教学弧的载体 → 该**有意安排** |

**正确的规则不是「不许重复」,是「重复必须是有意的,不能是偶然的」。**
那条测试断言应该改成:**同一局里的重复必须由 Director 显式安排,不能来自独立掷点。**
(而 pools 0/1 逐字相同 + 独立均匀掷 —— 那是**偶然**重复,仍然该禁。)

### 一条配套的通用做法:倒着排

关卡设计的通行做法里有一条很实用:**从战斗(高潮)倒着往回排**,
这样才保证前面留得出教学和休息的空间 —— 而不是先把高潮塞满、再看剩多少地方。

> **→ 对我们的意思**:Director 应该**先定 結**(这一局的高潮难度),
> 再倒推 起/承/転 的难度。而不是从 S1 往后累加。

---

## 6. 汇总:这次调研给出的可执行结论

| # | 结论 | 依据 | 影响 |
|---|---|---|---|
| 1 | Director **不许调目标分**,只调脸的排布与货架 | §1 不可见约束 + §2 L4D 改内容不改数值 | 印证已拍板的个性化边界 |
| 2 | **Relax = 起**(安全地介绍一个新东西),不是「没有脸」 | §5.5 起承転結 | ✅ 与「4 段全是墙」**不冲突** |
| 3 | 相位机必须落在**段内**(24 拍 / 8 商店) | §2 + 我们只有 4 段 | Director 的作用点 |
| 4 | 心流当词汇不当指标;**先敏感性分析不拟合权重** | §3 心流缺可操作判据 | 支持 docs/design/gates.md |
| 5 | **缺口分布 = 成长感的燃料**,不只是难度指标 | §4 近失依赖选择权 + 被读作技巧获得 | 体感模型的第一优先观测量 |
| 6 | 近失剂量先验 **~30%,宁少不多**;当假设不当事实 | §4 工业值 + 学术复现失败 | 待留存数据检验 |
| 7 | **技巧空间小的段落,近失也不值钱** | §4 纯运气场景效应衰减 | 两个指标要联合看,不能各自排名 |
| 8 | 参照系 = **短局手游**;5 分钟一局允许更陡的难度 | §5 session 中位 4m45s | 可能推翻从 Balatro 抄来的缓坡 |
| 9 | **meta 未做 = D7 的主要风险** | §5「高 D1 低 D7 = 缺 meta」 | docs/design/ui_meta.md 的优先级要上调 |
| 10 | 教学**单开一关**,允许突破 4.9 分钟(用户 2026-08-07 拍板:「教学总要时间,但教学只要一次,不影响整体节奏」) | §5 首次价值 5-15 分钟 | ✅ 不占用局内节奏 |
| 13 | **起承転結 = 4 段的难度形状**;先定 結 再倒推 | §5.5 | Director 的骨架 |
| 14 | ⚠ 我加的「相邻段池子不得相同」在 A 案下是**反的** | §5.5 | 规则应改成「重复必须有意,不能偶然」 |
| 11 | 量一下**重开摩擦**(点击数/秒数) | §5 Balatro 零摩擦 | 便宜的留存杠杆 |
| 12 | catch-up meta 与「DDA 不可见」冲突,要做成奖励不是同情 | §5 + §1 | docs/design/ui_meta.md 动工前的前置约束 |

### 那两条「冲突」已经解掉了(2026-08-07)

初稿认为调研给出了两条反对「4 段全是 BOSS 墙」的依据。**两条都不成立,记在这里
是因为我错的方式有代表性。**

**① Relax —— 我把 L4D 的类比套死了。**
我假设"放松必须来自挑战的缺席",于是推出"段段有脸 = 没有 Relax"。
但 L4D 能有安静走廊,是因为它的压力源(敌人)可以清零;**我们的压力源里有一个
清不掉的 8 秒钟**。所以那个类比根本不适用。
起承転結 给的答案是:**放松 = 起 = 一个新东西被安全地介绍给你**。
它比空白段落好,因为它**同时**给放松和新鲜感,而空白拿不到新鲜感这一分。

**② 教学 —— 我把它当成了局内问题。**
用户拍板:「**教学关是可以突破这个时间的,教学总要时间,但教学只要一次,
不影响整体节奏**」。教学单开一关,4.9 分钟的约束根本不该套在它头上。
而起承転結 正好说明教学该长什么样:**起** 就是"安全的地方、无惩罚地理解机制"。

**教训**:两次都是**把一个外部结论直接套过来,没有先检查它成立的前提**。
L4D 的前提是压力源可清零,留存基准的前提是"这 4.9 分钟要同时承担 FTUE"——
两个前提在我们这里都不成立。**引用外部研究时,先核前提,再核结论。**

---

## 来源

**DDA**
- [The case for dynamic difficulty adjustment in games (Hunicke, ACM ACE 2005)](https://dl.acm.org/doi/10.1145/1178477.1178573)
- [AI for Dynamic Difficulty Adjustment in Games — Hamlet (Hunicke & Chapman)](https://users.cs.northwestern.edu/~hunicke/pubs/Hamlet.pdf)
- [Dynamic Difficulty Adjustment in Games: Concepts, Techniques, and Applications (IntechOpen)](https://www.intechopen.com/chapters/1228576)
- [More Than Meets the Eye: The Secrets of Dynamic Difficulty Adjustment (Game Developer)](https://www.gamedeveloper.com/docs/design/more-than-meets-the-eye-the-secrets-of-dynamic-difficulty-adjustment)
- [Beyond Rubberbanding: Crafting Dynamic Difficulty for Every Player (Wayline)](https://www.wayline.io/blog/dynamic-difficulty-adjustment-beyond-rubberbanding)
- [Dynamic Difficulty Adjustment and Behavioral Control in Games (Bootcamp)](https://medium.com/design-bootcamp/product-design-and-psychology-the-use-of-dynamic-difficulty-adjustment-in-video-game-design-7a1e2d919b96)

**L4D AI Director**
- [The AI Systems of Left 4 Dead (Michael Booth, Valve)](https://steamcdn-a.akamaihd.net/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf)
- [The Director — Left 4 Dead Wiki](https://left4deadwiki.com/wiki/The_Director)
- [The Discomfort Zone: The Hidden Potential of Valve's AI Director (Game Developer)](https://www.gamedeveloper.com/docs/design/the-discomfort-zone-the-hidden-potential-of-valve-s-ai-director)
- [Affective Game Computing: A Survey (arXiv 2309.14104)](https://arxiv.org/pdf/2309.14104)

**心流**
- [Operationalising and Measuring Flow in Video Games (OzCHI)](https://dl.acm.org/doi/10.1145/2838739.2838826)
- [Finding the Sweet Spot: Assessing Skill–Challenge Balance and Flow (Mensch und Computer 2025)](https://dl.acm.org/doi/10.1145/3743049.3748556)
- [Being enjoyably challenged is the key to an enjoyable gaming experience (PMC)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5954478/)
- [Struggle as Flow: Challenge, Design, and Experience in Soulslike Games (arXiv)](https://arxiv.org/pdf/2604.15318)

**近失效应**
- [Gambling Near-Misses Enhance Motivation to Gamble and Recruit Win-Related Brain Circuitry (Clark et al., Neuron)](https://www.sciencedirect.com/science/article/pii/S0896627309000373)
- [The Near-Miss Effect in Slot Machines: A Review and Experimental Analysis Over Half a Century Later (J Gambl Stud)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7214505/)
- [The Psychology of the Near Miss (R. L. Reid)](https://www.stat.berkeley.edu/~aldous/157/Papers/near_miss.pdf)
- [Learning and Affect Following Near-Miss Outcomes in Simulated Gambling (Clark, 2013)](https://onlinelibrary.wiley.com/doi/abs/10.1002/bdm.1774)
- [Gambling and virtual reality: unraveling the illusion of near-misses effect (Frontiers)](https://www.frontiersin.org/journals/psychiatry/articles/10.3389/fpsyt.2024.1322631/full)

**留存与短局**
- [2025 Mobile Gaming Benchmarks (GameAnalytics)](https://www.gameanalytics.com/reports/2025-mobile-gaming-benchmarks)
- [Mobile Game Retention Benchmarks & Guide (AppAgent)](https://appagent.com/blog/mobile-game-retention-benchmarks/)
- [Mobile Game Retention Benchmarks 2026 (Segwise)](https://segwise.ai/blog/mobile-gaming-app-user-retention-strategies)
- [The big list of mobile game retention benchmarks (Mistplay)](https://maf.ad/en/blog/mobile-game-retention-benchmarks/)

**Balatro 与 meta 进度**
- [How Balatro Became One of the Most Addictive Roguelikes (Goomba Stomp)](https://goombastomp.com/how-balatro-became-one-of-the-most-addictive-roguelikes/)
- [Balatro Game Review: Why Is It So Addictive? (Armchair Arcade)](https://armchairarcade.com/perspectives/2026/05/20/balatro-game-review-why-is-it-so-addictive/)
- [How to Design a Roguelite Meta-Progression (Bugnet)](https://bugnet.io/blog/how-to-design-a-roguelite-meta-progression)
- [Meta-progression 学位论文(Univ. of Skövde, 2026)](https://his.diva-portal.org/smash/get/diva2:2072480/FULLTEXT01.pdf)
