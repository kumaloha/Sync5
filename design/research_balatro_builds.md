# Balatro 构筑流派结构化目录(社区公认 Build Archetypes 全集)

> 2026-08-12 由网络调研 agent 产出。**这是参考研究,不是 Sync5 设计决定** ——
> 与 [`research_balatro_jokers.md`](research_balatro_jokers.md)(150 张卡的普查)互为一对:
> 那篇按**卡**分类,这篇按**流派**分类(42 条,13 大类)。
> Sync5 侧的流派映射与提案见 [`archetypes.md`](archetypes.md)。

**方法说明**:交叉核对了 15+ 来源,包括 balatrowiki.org(含 Guide: Deck Manipulation / Naneinf 词条)、Balatro Fandom Wiki(词条经搜索摘要获取,整页抓取被 402 拦截)、balatrocalc.com、balatrohq.com、games.gg、TheGamer、GameRant、Digital Trends、Mobalytics、Switchblade Gaming、DualShockers、balatrocalculator.blog、setsideb.com(Balatro University 的 naneinf 解读)、PC Gamer、Steam 社区讨论串等。Reddit 域名对爬虫封锁,r/balatro 的观点通过转述其讨论的二手源(balatrohq「Reddit 最爱组合」、Steam 同题讨论)间接覆盖。所有卡名均经 wiki 词条核实;个别拿不准处标注「待验证」。

---

## 一、牌型专精类(分数来源 = 牌型基础值 + Planet 升级)

### 1. 同花流(Flush Build)
- **核心机制**:最容易稳定组出的 5 张牌型,靠 Planet(Jupiter)升级 + 花色 Joker 加成,chips 与 mult 双吃。
- **核心卡**:Four Fingers(4 张成同花)、The Tribe(含 Flush ×2 Mult)、Lusty/Greedy/Wrathful/Gluttonous Joker(对应花色 +3 Mult)、Smeared Joker、Checkered Deck。
- **成型路径**:前期天然能打出同花活过 Ante 1-2;中期拐点 = 花色收敛(Tarot 的 Star/Sun/Moon/World 转花色)+ Four Fingers;后期天花板靠花色 ×Mult Joker(见 §14)与 Flush Five 升级。
- **可靠性 vs 方差**:社区公认**最稳的入门流派**,线性可靠,天花板中等。
- **混搭**:花色偏置类(§14)、Castle(弃指定花色攒 chips)、Bloodstone 概率流。

### 2. 顺子流(Straight Build)
- **核心机制**:靠放宽顺子判定的 Joker 把「难组的高分牌型」变成「常规输出」。
- **核心卡**:Shortcut(允许隔 1 点成顺)、Four Fingers、The Order(含 Straight ×3)、Runner(打顺子 +15 chips 成长)。
- **成型路径**:前期最难活(天然顺子频率低),一般先拿 Runner/杂牌过渡;拐点 = Shortcut 或 Four Fingers 到手;后期 The Order + 重触发。
- **可靠性 vs 方差**:中方差——没拿到 Shortcut 前很脆,拿到后判定极宽。
- **混搭**:数字偏好类(低点数顺子喂 Fibonacci/Wee Joker)、Abandoned Deck(无人头,数字密度高)。

### 3. 对子/两对/小手牌流(Pair / Two Pair Spam)
- **核心机制**:打「几乎必然抓到」的低门槛牌型,靠挂对子的 ×Mult 和永久成长牌把量变堆成质变。
- **核心卡**:The Duo(含 Pair ×2)、Spare Trousers(打含两对的手 +2 永久 Mult)、Half Joker(≤3 张 +20 Mult)、Jolly Joker、Sly Joker。
- **成型路径**:前期即战力最强的档;中期靠 Spare Trousers 线性攒 Mult;后期天花板偏低,需转 ×Mult 或葫芦。
- **可靠性 vs 方差**:**生存性最高、爆发最低**的稳健线。
- **混搭**:天然升级成葫芦流;与 Raised Fist/持牌类兼容(打小手牌,手里留高价值牌)。

### 4. 葫芦流(Full House)
- **核心机制**:两对流的进阶形态——Spare Trousers 成长 + The Duo/The Trio 双 ×Mult 同时触发(葫芦同时含对子和三条)。
- **核心卡**:Spare Trousers、The Duo、The Trio、Death(复制点数凑三条)。
- **成型路径**:从对子流自然演化;拐点 = Duo/Trio 任一到手;后期两张 ×Mult 齐触发即 ×6。
- **可靠性 vs 方差**:中等——组葫芦比组两对明显吃手气,但补牌 Tarot 可修。
- **混搭**:四条/五条流的中继站;DNA 增殖。

### 5. 四条/五条流(Four / Five of a Kind)
- **核心机制**:用 Death/DNA/Cryptid 把牌库改造成大量同点数,打基础值最高的常规/隐藏牌型。
- **核心卡**:The Family(含 Four of a Kind ×4)、Death(左牌变右牌)、Cryptid(复制 1 张成 2 张)、DNA、Hack(低点数四条可重触发)。
- **成型路径**:前期靠杂牌 + 攒经济买 Tarot 包;拐点 = 同点数密度过阈值(约 8-12 张同点);后期 Five of a Kind 基础值 + The Family 天花板极高。
- **可靠性 vs 方差**:**阈值型**——成型前很弱,过了阈值一波质变。
- **混搭**:隐藏牌型流(§6)、玻璃/多彩增强集中在那一个点数上。

### 6. 隐藏牌型流(Flush Five / Flush House)
- **核心机制**:同点数 + 同花色的极端牌库改造,打全游戏基础值最高的秘密牌型(Flush Five base 160 chips ×16 Mult)。
- **核心卡**:Death(**连增强带改**整张复制,是唯一能量产「多彩玻璃红封蜡同一张牌」的工具)、Cryptid、DNA、Hologram(顺带吃加牌成长)。
- **成型路径**:通常从四条/同花流晚期演化;wiki 明言 Death「最适合用来凑 Five of a Kind / Flush Five / Flush House 这类需要大量 deck fixing 的牌型」;后期是 endless 冲分的标准出口之一。
- **可靠性 vs 方差**:高投入高回报,成型极晚;金注下靠它翻盘的案例多但路径长。
- **混搭**:Plasma Deck(chips/mult 取平均再平方级放大)、多彩 + 红封蜡玻璃牌(naneinf 路线之一:4 张 Polychrome Red Seal Glass 2 + Lv20 四条)。

### 7. 高牌流(High Card / Photograph)
- **核心机制**:只打 1 张牌,把所有 ×Mult 和重触发集中到这一张上;「牌型弱」被「单卡质量」补偿。
- **核心卡**:Photograph(首张计分人头 ×2)、Ancient Joker(当轮指定花色 ×1.5/张)、The Idol(指定点数花色 ×2/张)、Sock and Buskin、Death(把牌库改成同一张牌喂 Idol)。
- **成型路径**:前期 High Card 有 Planet(Pluto)升级撑着;拐点 = Photograph + 任一 per-card ×Mult;后期 Idol+Ancient+ 重触发指数叠乘。
- **可靠性 vs 方差**:Steam 社区评「当前最强但要中彩票」——上限极高、组件依赖重。
- **混搭**:人头流、重触发流、Baron 持牌流(打 1 张留 7 张手牌)。

---

## 二、卡牌增强类(分数来源 = 增强牌自带效果)

### 8. 钢铁国王流(Steel Kings / Baron + Mime)⭐ 社区公认最强上限
- **核心机制**:分不靠打出、靠**手里握着**——每张手中钢铁 K 提供多层 ×1.5(Baron ×1.5 → Mime 重触发 ×1.5 → 红封蜡再触发 → Steel 增强 ×1.5),单卡约 ×5.06,满手指数爆炸。
- **核心卡**:Baron、Mime、红封蜡钢铁 K、DNA(K 增殖)、Juggler/Troubadour(手牌上限)、Steel Joker(全牌库钢铁数 ×0.2/张)。
- **成型路径**:前期靠 High Card + 经济;中期拐点 = Baron 到手(Mime 紧随);后期 DNA 循环复制红封钢 K,是 **naneinf(分数溢出 1.8e308)的标准引擎**。
- **可靠性 vs 方差**:组件依赖极重(两张 Uncommon+ 必须齐),但成型后几乎无对抗盲注能拦(除持牌 debuff 类 Boss)。
- **混搭**:Raised Fist / Shoot the Moon(§9)、Blueprint 复制 Baron、Triboulet。

### 9. 持牌 Mult 流(Held-in-Hand:Raised Fist / Shoot the Moon)
- **核心机制**:钢铁国王流的平民版——手里握着的牌直接给 +Mult(Raised Fist = 手中最小点数 ×2 的 Mult;Shoot the Moon = 每张手中 Q +13 Mult)。
- **核心卡**:Raised Fist、Shoot the Moon、Baron、Mime、钢铁 Q(注意手牌从左到右结算,+Mult 牌要摆在 ×Mult 牌左边)。
- **成型路径**:前期即可用(Common 起步);拐点 = 与 Mime/钢铁增强联动;后期被真·Baron 体系吸收。
- **可靠性 vs 方差**:低方差、低天花板的过渡型。
- **混搭**:对子/高牌流(打小手牌才有牌可握)。

### 10. 玻璃牌流(Glass)
- **核心机制**:每张玻璃牌 ×2,代价 1/4 概率打碎;碎了喂 Glass Joker(每碎一张永久 ×0.75)——**碎与不碎都赚**。
- **核心卡**:Glass cards(Justice Tarot)、Glass Joker、Hologram、红封蜡玻璃(多触发一次 ×2)。
- **成型路径**:前期一两张玻璃就是最便宜的 ×Mult;中期 Glass Joker 把「碎牌损失」转成成长引擎;后期多彩红封玻璃是 endless 标配组件。
- **可靠性 vs 方差**:**主动选择的高方差**——Oops! All 6s 会把碎牌概率也翻倍(风险同步放大)。
- **混搭**:概率流(Oops 双刃剑)、五条流(玻璃集中于同一点数)、Canio(碎的是玻璃人头则双吃)。

### 11. 黄金牌流(Gold + Midas Mask + Vampire)
- **核心机制**:两条支线——A)Gold 牌握手里每轮 +$3、Golden Ticket 打出每张 +$4,纯经济;B)Midas Mask 把人头变 Gold → Vampire 吃掉增强永久 ×0.1/张,**增强当饲料**。
- **核心卡**:Midas Mask、Vampire、Golden Ticket、Pareidolia(全员人头,喂养提速)、The Devil。
- **成型路径**:前期 Gold 牌撑利息;拐点 = Midas Mask 放 Vampire **左侧**(先镀金再吸血,每 5 张人头 +×0.5);后期 Pareidolia + Midas + Vampire 被多源评为「最强长线之一」。
- **可靠性 vs 方差**:线性偏慢但极稳,Vampire 不挑牌库。
- **混搭**:人头流、经济流(Bull/Bootstraps 吃金币存量)。

### 12. 幸运牌概率流(Lucky + Oops! All 6s)
- **核心机制**:把「1/5 得 +20 Mult、1/15 得 $20」的 Lucky 牌用 Oops! All 6s(全概率 ×2,可叠加)推成必然事件,概率牌变永动机。
- **核心卡**:Lucky cards、Oops! All 6s(×2 张 = 概率 ×4)、Lucky Cat(每次 Lucky 触发永久 ×0.25)、Bloodstone(红心 1/2 概率 ×1.5 → 必触发)、Business Card、Hallucination。
- **成型路径**:前期概率牌纯赌;拐点 = 第一张 Oops;后期 Lucky Cat 滚成主 ×Mult,双 Oops 后 Bloodstone 每张红心必 ×1.5。
- **可靠性 vs 方差**:**从高方差被驯化成低方差**的独特曲线;注意 Oops 也翻倍 Glass 碎牌/Gros Michel 自毁等坏概率。
- **混搭**:红心同花流(Bloodstone)、玻璃流(风险共振,慎混)。

### 13. 石头牌流(Stone Deck)【冷门收录】
- **核心机制**:Stone 牌无点无花但固定 +50 chips/张;Stone Joker 每张库中石头 +25 chips;5 张石头算 High Card——**用 chips 密度替代牌型**。
- **核心卡**:Stone Joker、Marble Joker(每盲注 +1 石头,自动喂 Stone Joker)、Blueprint(复制 Marble = 双倍产石)、Vampire(石头当增强饲料;待验证:Stone 是否算 enhancement 喂 Vampire——wiki 表述为可行)。
- **成型路径**:前期 Marble 白送引擎;中期 High Card/四张内牌型为主(石头稀释 5 张牌型);后期 chips 巨大但缺 ×Mult,需外接。
- **可靠性 vs 方差**:线性稳定、天花板受限;社区定位「能赢但非最优」的趣味流。
- **混搭**:高牌流、Hack/重触发(石头也吃重触发)。

---

## 三、花色偏置与花色操控类

### 14. 单花色/花色 ×Mult 流(Mono-Suit)
- **核心机制**:牌库收敛到 1-2 个花色,让「每张 X 花色 ×1.5/加 chips」类 Joker 全额命中。
- **核心卡**:Bloodstone(红心)、Arrowhead(黑桃 +50 chips)、Onyx Agate(梅花 +7 Mult)、Rough Gem(方片 +$1)、Ancient Joker + Death(把全库改成当轮花色)、Star/Sun/Moon/World Tarot。
- **成型路径**:同花流的深化;拐点 = 花色密度 >70%;后期 Ancient Joker(×1.5/张 × 5 张)是顶级 per-card 引擎。
- **可靠性 vs 方差**:中等——Ancient 花色每轮随机,靠 Death/Wild 修正。
- **混搭**:同花流、高牌流(Idol/Ancient 同构)、Seance(同花顺产 Spectral)。

### 15. Smeared Joker 花色合并流
- **核心机制**:红心=方片、黑桃=梅花,四色变两色——所有花色判定类 Joker 覆盖面翻倍。
- **核心卡**:Smeared Joker、Checkered Deck(开局即两色,叠加后≈单色全库)、任意花色 Joker。
- **成型路径**:Checkered Deck 开局 → Smeared 到手即「全库一个花色」,Flush 想打就打、直通 Flush Five。
- **可靠性 vs 方差**:低方差放大器;注意 wiki 警告:Checkered(只剩黑桃红心)别配「只吃梅花方片」的 Joker,除非 Smeared 在场。
- **混搭**:同花流、单花色流、Seeing Double。

### 16. 花色多样流(Rainbow:Flower Pot / Seeing Double)【冷门收录】
- **核心机制**:反向偏置——一手打齐四花色拿 Flower Pot ×3(Seeing Double 同条件再 ×2)。
- **核心卡**:Flower Pot、Seeing Double、Wild cards(万能花色,4 张 Wild 必触发)、Sigil(待验证:Sigil 全库变一色属反 synergy)。
- **成型路径**:围绕 Wild 牌铺设;拐点 = Wild 密度足以稳定触发;上限 = 两张卡固定 ×6。
- **可靠性 vs 方差**:触发即爆、不触发即零的**二值型**;与 Blackboard、Ancient 互斥。
- **混搭**:顺子流(顺子天然易凑四色)。

### 17. 暗花色流(Blackboard)【冷门收录】
- **核心机制**:手中全为黑桃/梅花(或空手)时 ×3——弃牌把红色弃干净、或全库转黑。
- **核心卡**:Blackboard、黑花色转换 Tarot、Smeared(黑桃梅花合并后更容易全黑)。
- **可靠性 vs 方差**:条件苛刻,通常作为黑花色同花流的搭车 ×Mult 而非主轴。

---

## 四、人头牌流(Face Cards)

### 18. 人头牌大类(Pareidolia 体系)
- **核心机制**:围绕 J/Q/K 触发的一整族 Joker,Pareidolia(所有牌视为人头)把条件牌全部变成无条件牌。
- **核心卡**:Pareidolia、Sock and Buskin(人头全重触发)、Scary Face(+30 chips/人头)、Smiley Face(+5 Mult/人头)、Photograph、Triboulet(K/Q ×2,传奇)、Midas Mask、Business Card / Reserved Parking(人头产钱)、Canio(毁人头永久 ×1)。
- **成型路径**:前期 Scary/Smiley 便宜好用;拐点 = Pareidolia 或人头密度改造(Familiar 加增强人头);后期 Sock and Buskin + Photograph/Triboulet 重触发爆炸。
- **可靠性 vs 方差**:线性成长、组件冗余度高(族内可互替);**致命短板 = The Plant/The Mark 两个 Boss 直接封人头**(多源同警告)。
- **混搭**:黄金牌流(Midas)、重触发流、Canio 毁牌流、高牌流(Photograph)。

---

## 五、数字偏好类(Rank-Based)

### 19. Fibonacci 流
- **核心机制**:A/2/3/5/8 每张计分 +8 Mult,把牌库收敛到斐波那契点数。
- **核心卡**:Fibonacci、Hack(2/3/4/5 重触发,与 Fib 重叠 3 个点数 = 双倍触发)、Abandoned Deck(无人头,Fib 点数密度天然高)、Odd Todd(A/3/5 重叠)。
- **成型路径**:Abandoned Deck 开局即半成型;拐点 = Hack;后期低点顺子(A-2-3-4-5)同时喂 Runner/Order。
- **可靠性 vs 方差**:线性稳定,+Mult 属性决定天花板中等,需外接 ×Mult。
- **混搭**:顺子流、低牌 chips 流、奇数流。

### 20. 奇偶流(Even Steven / Odd Todd)
- **核心机制**:偶数牌 +4 Mult(Even Steven)或奇数牌 +30 chips(Odd Todd),点数二分偏置。
- **核心卡**:Even Steven、Odd Todd、配套点数收敛 Tarot(Strength 升点改变奇偶)。
- **可靠性 vs 方差**:Common 级前期过渡,常与 Fibonacci/Scholar(A +20 chips +4 Mult)拼成「点数联盟」,很少单独成军。

### 21. 低牌重触发 chips 流(Wee Joker + Hack)
- **核心机制**:2 每次计分给 Wee Joker 永久 +8 chips,Hack 让每张 2 触发两次——五张 2 一手 +80 chips 永久成长。
- **核心卡**:Wee Joker、Hack、Stuntman(+250 chips,-2 手牌上限,低牌型最大 payoff)、红封蜡 2、DNA(复制 2)。
- **成型路径**:前期弱;拐点 = Wee+Hack 齐;后期 Flush Five of 2s 是隐藏胜利姿势。
- **可靠性 vs 方差**:滚雪球型,起速慢;chips 单边成长需外接 Mult。
- **混搭**:五条流、DNA 增殖、Fibonacci。

---

## 六、重触发类(Retrigger)

### 22. 重触发引擎(Dusk / Seltzer / Hanging Chad / Sock and Buskin / Hack)
- **核心机制**:不自产分,把每张计分牌的全部效果(增强、per-card ×Mult、Joker 触发)按倍数复读——**per-card ×Mult 的乘区放大器**。
- **核心卡**:Dusk(最后一手全重触发)、Seltzer(10 手内全重触发)、Hanging Chad(首张牌 +2 次)、Sock and Buskin(人头)、Hack(低牌)、Mime(持牌侧)、红封蜡(+1 次;注意 Sock and Buskin 不重触发红封蜡本身)。
- **成型路径**:必须先有「值得复读的东西」(玻璃/钢铁/Photograph/Idol);中期一张重触发 ≈ 分数直接翻倍;后期与 Blueprint 叠复读。
- **可靠性 vs 方差**:依附型——本身零方差,方差继承自宿主流派。
- **混搭**:几乎所有 per-card 流派的终端配件;naneinf 引擎必含。

---

## 七、牌库结构操控类

### 23. 缩牌库流(Deck Thinning)
- **核心机制**:牌越少、想要的牌越常抓到——一切专精流派的地基,自身也有直接收益(Erosion:低于 52 张每张 +4 Mult)。
- **核心卡**:The Hanged Man(毁 2 张)、Trading Card(首次单弃毁牌 +$3)、Immolate(毁 5 随机 +$20)、Familiar/Grim/Incantation(毁 1 换 3 增强牌)、Abandoned Deck(40 张开局)、Erosion。
- **成型路径**:从 Ante 1 就该开始(wiki:「所有 deck 都受益于尽早 thinning」);中期与目标流派共振;极限形态 = DNA 单卡牌库。
- **可靠性 vs 方差**:降方差手段本身;过度缩库会被「加牌 Boss」和 Stone 牌反噬。
- **混搭**:万金油,与 §5/§6/§8 强绑定。

### 24. DNA 单卡增殖流
- **核心机制**:每轮首手单打一张 → DNA 复制连增强封蜡一起进库;配合缩库,最终「整副牌都是同一张神卡」。
- **核心卡**:DNA、Blueprint/Brainstorm(复制 DNA = 一手 +2/+3 张)、红封蜡钢铁 K 或多彩玻璃牌(增殖标的)。
- **成型路径**:前期 DNA 单独很弱(浪费一手);拐点 = 有值得复制的成品牌;后期是钢铁国王/五条流的增殖泵。
- **可靠性 vs 方差**:阈值爆发型;组件贵(Rare+Rare)。
- **混搭**:§5 §6 §8 的共享子引擎。

### 25. 手牌尺寸/出手次数操控(Hand-Size Manipulation)
- **核心机制**:手牌上限、出手数、弃牌数是三种可交易资源,围绕交换比构筑。
- **核心卡**:Juggler(+1 手牌)、Troubadour(+2 手牌 −1 出手)、Merry Andy(+3 弃 −1 手牌)、Burglar(+3 出手,弃牌归零)、Stuntman(+250 chips −2 手牌)、Turtle Bean(+5 手牌递减)、Wasteful/Drunkard。
- **成型路径**:依附型——Baron 体系要手牌上限(Juggler/Troubadour 是钢铁国王标配),弃牌流要 Merry Andy,爆发打法要 Burglar。
- **可靠性 vs 方差**:纯配件,自身无分。
- **混搭**:方向必须与主流派一致(Burglar 进弃牌流 = 自杀,多源同警告)。

---

## 八、复制类(Copy Engines)

### 26. Blueprint / Brainstorm 复制引擎
- **核心机制**:复制右邻(Blueprint)/最左(Brainstorm)Joker 的效果——复制 ×Mult 是乘法、复制 +Mult 只是加法,故**永远优先复制 ×Mult 或重触发**。
- **核心卡**:Blueprint、Brainstorm、被复制标的(Baron/Photograph/Bloodstone/Dusk/DNA/Yorick/Mail-In Rebate)。
- **摆位口诀**(社区共识):标的放最左,Brainstorm 随便放都读最左,Blueprint 贴标的右侧——同一效果三重生效。
- **可靠性 vs 方差**:后期几乎所有流派的最优终端槽;本身无方差。
- **混搭**:万金油顶配;Yorick ×8 时 Blueprint 等效再 ×8。

### 27. Invisible Joker / Showman 增殖流【冷门收录】
- **核心机制**:Invisible Joker 攒 2 轮后卖出 = 复制随机一张自有 Joker(连版本带成长值);Showman 允许商店出重复卡,可屯双 Soul、双 Baron。
- **核心卡**:Invisible Joker、Showman、高价值标的(Triboulet/Baron/Perkeo)。
- **可靠性 vs 方差**:高方差(复制目标随机,需卖到只剩想要的);旧版无限刷钱 exploit 已修复。
- **混搭**:传奇 Joker 体系、负片经济。

---

## 九、成长/滚雪球类(按触发条件区分——这是本类的关键轴)

### 28. 打出成长流(per-hand-played)
- **触发 = 每打出一手**:Ride the Bus(无人头手 +1 Mult,见人头清零)、Green Joker(+1/手,弃牌 −1)、Square Joker(恰 4 张 +4 chips)、Supernova(本牌型累计次数→Mult)、Obelisk(不打最常用牌型则 ×0.2 递增,打了清零——**轮换牌型流**的核心,配 Hologram/Hit the Road 这类不依赖出手的 ×Mult 最佳)。
- **特性**:线性成长、前期即产出;Ride the Bus 与人头流互斥、与 Runner 数字顺子共振。

### 29. 弃牌成长/弃牌资源流(per-discard)⭐ 自成大类
- **核心机制**:把「弃牌」从修牌手段升格为**主要资源产出动作**。
- **核心卡**:Yorick(传奇:每 23 张弃牌 ×1 Mult,永不回退)、Hit the Road(每弃 J ×0.5,回合末重置)、Castle(弃指定花色 +3 chips 永久)、Mail-In Rebate(弃指定点数 +$5)、Faceless Joker(一次弃 3+ 人头 +$5)、Trading Card、Burnt Joker(首次弃牌升级该牌型)、Drunkard/Merry Andy(弃牌次数扩容)。
- **成型路径**:前期 Castle/Mail-In 就有产出;拐点 = 弃牌扩容 + 多张弃牌触发器同时挂;后期 Yorick + Blueprint。
- **可靠性 vs 方差**:线性稳定;**Burglar 是本流派毒药**(弃牌归零)。
- **混搭**:缩牌库(Trading Card 双职)、Blueprint 复制 Yorick。

### 30. 毁牌成长流(per-card-destroyed)
- **核心机制**:毁牌三重收益——缩库 + 触发成长 + (玻璃)本身是 ×Mult。
- **核心卡**:Glass Joker(每碎玻璃 ×0.75)、Canio(传奇:每毁人头 ×1)、Madness(每过小/大盲 ×0.5 但随机毁一张自家 Joker)、Hanged Man/Immolate(主动毁牌泵)、Pareidolia(全员算人头,Hanged Man 一张喂 Canio ×3)。
- **可靠性 vs 方差**:Madness 是「拿自家 Joker 换指数」的高风险高回报;Glass/Canio 稳健。
- **混搭**:玻璃流、人头流、缩牌库。

### 31. 消耗牌成长流(per-consumable-used)→ 见 §36-38 引擎类(Fortune Teller / Constellation 等)。

### 32. 加牌成长流(per-card-added)【冷门收录】
- **核心卡**:Hologram(每加一张牌入库 ×0.25)——与缩牌库哲学相反,吃 DNA/Marble Joker/Certificate/Familiar 系加牌。
- **混搭**:DNA 增殖、石头流(Marble 每盲注自动 +1)、Obelisk。

---

## 十、经济类(金币即分数)

### 33. 利息滚存流(Interest Economy)
- **核心机制**:$5 存款生 $1 利息(上限 $25→$5/轮),经济雪球换商店翻牌权。
- **核心卡**:To the Moon(利息翻倍,可叠加)、Golden Joker(+$4/轮)、Seed Money/Money Tree voucher、Cloud 9(每张 9 +$1/轮)、Rocket(过 Boss 递增)、Satellite(每种用过的 Planet +$1/轮)、Egg。
- **成型路径**:纪律型打法——Ante 3-4 前存到 $25 红线,靠刷新权碾压卡池方差;本身不产分,靠买出主流派。
- **可靠性 vs 方差**:**降低全局方差的元流派**。

### 34. 金币转分流(Bull / Bootstraps)
- **核心机制**:存款直接进乘区——Bull 每 $1 +2 chips,Bootstraps 每 $5 +2 Mult;利息流的分数出口。
- **核心卡**:Bull、Bootstraps、To the Moon、Golden Ticket/Business Card(现金流)。
- **可靠性 vs 方差**:线性、够打常规 8 Ante,endless 天花板不足(无 ×Mult)。

### 35. 卖价/牺牲流(Sell-Value:Egg + Ceremonial Dagger)【冷门收录】
- **核心机制**:养肥 Joker 卖价再变现——Ceremonial Dagger 每轮吞右邻 Joker,得其卖价 ×2 的永久 Mult;Egg 每轮自增 $3 卖价 = 完美饲料。
- **核心卡**:Ceremonial Dagger、Egg、Gift Card(全体 +$1 卖价/轮)、Swashbuckler(其余 Joker 卖价总和 = Mult)、Campfire(每卖一张 ×0.25,Boss 后重置)。
- **可靠性 vs 方差**:节奏型——Dagger 吞错位置是经典事故;Campfire 要「攒着 Boss 前卖」。
- **混搭**:利息流(Egg 与利息冲突需权衡)、Invisible Joker(卖出即触发)。

---

## 十一、消耗牌引擎类(Tarot / Planet / Spectral)

### 36. Tarot 引擎流(Fortune Teller 体系)
- **核心机制**:高频使用 Tarot 本身产出分数与改造——Fortune Teller 每用一张 +1 Mult(全程累计)。
- **核心卡**:Fortune Teller、Cartomancer(每盲注免费产 Tarot)、Vagabond(≤$4 时打手产 Tarot——**故意受穷的 poverty build**)、Hallucination(开包 1/2 送 Tarot)、8 Ball(每张 8 计分 1/4 产 Tarot)、Perkeo(离店复制消耗牌为负片)。
- **成型路径**:前期 Tarot 顺手用就成长;拐点 = Cartomancer/Perkeo 自动化;后期 Fortune Teller 比 Green Joker 快(商店里用 Tarot 也算)。
- **混搭**:一切需要 deck fixing 的流派的供给侧;Oops(Hallucination/8 Ball 概率翻倍)。

### 37. Planet 引擎流(Space Race:Constellation / Observatory)
- **核心机制**:牌型等级是「不会被 Boss 拆掉的分」;Planet 使用次数喂 Constellation(×0.1/张),Observatory voucher 让**持有的** Planet 每张给对应牌型 ×1.5。
- **核心卡**:Constellation、Astronomer(Planet 免费)、Satellite(经济)、Space Joker(1/4 免费升级)、Burnt Joker(弃牌升级)、Observatory、Nebula Deck、Telescope voucher。
- **成型路径**:选定主牌型 → 所有 Planet 集中喂它;后期 Observatory + Perkeo 复制同名 Planet(naneinf 案例:115 张负片 Mars = ×1.5^115)。
- **可靠性 vs 方差**:线性极稳,「除 The Arm 外几乎没有 Boss 能反制」(TheGamer);endless 上限极高。
- **混搭**:任意牌型专精流的第二引擎;Perkeo 负片循环。

### 38. Spectral 引擎流(Ghost Deck 体系)【冷门收录】
- **核心机制**:Spectral 是改造力度最大的消耗牌(封蜡/传奇/负片都从这来),围绕其获取渠道构筑。
- **核心卡**:Ghost Deck(商店出 Spectral)、Seance(同花顺产 Spectral)、Sixth Sense(首手单张 6 毁之产 Spectral)、Ectoplasm(随机 Joker 变负片,代价手牌上限递减)、Cryptid、Deja Vu(红封蜡)。
- **成型路径**:Ghost Deck 开局或 Sixth Sense 早拿;中期红封蜡/增强铺设提速一切流派;Ectoplasm 连点是负片军团的来源,但手牌代价指数上升。
- **可靠性 vs 方差**:高方差(Spectral 多带副作用),回报是别的引擎给不了的组件。

---

## 十二、版本与负片经济

### 39. 负片军团流(Negative Economy)
- **核心机制**:Negative 版本 = +1 Joker 槽,槽位本身就是复利——6-8 张 Joker 同场,流派间的取舍消失。
- **核心卡**:负片 Joker(商店随机/Negative Tag/Ectoplasm)、Perkeo(负片消耗牌 = +1 消耗槽,无限屯)、Anaglyph Deck(每过 Boss 送 Double Tag,屯着等 Negative/Ethereal Tag 翻倍)、Invisible Joker(复制负片;待验证:复制品保留 Negative——wiki 表述为「保留几乎全部属性」)。
- **成型路径**:Anaglyph 路线:攒 Double Tag → 押中 Negative Tag → 负片经济 Joker 白嫖槽位;Perkeo 路线见 §37。
- **可靠性 vs 方差**:Tag 赌博属性强;成型后是 endless 标配底盘。
- **混搭**:跳盲注流(Tag 获取)、Planet/Tarot 引擎(Perkeo)。

### 40. 版本增值流(Foil / Holo / Polychrome)【支线】
- **核心机制**:Foil +50 chips / Holo +10 Mult / Polychrome ×1.5 直接贴在 Joker 或(经 Spectral)牌上;Hone/Glow Up voucher 提高出现率。多彩贴在关键 ×Mult Joker 或增殖标的牌上是所有后期流派的公共升级路径,不单独成军。

---

## 十三、节奏与元策略类

### 41. 跳盲注 Tag 流(Skip / Throwback)
- **核心机制**:跳过小/大盲换 Tag(免费包/负片/翻倍钱),放弃过关收入换资源期权;Throwback 每跳过一个盲注 ×0.25(**补拿也算历史跳过数**)。
- **核心卡**:Throwback、Double Tag、Charm/Ethereal/Negative/Orbital Tag、Anaglyph Deck。
- **可靠性 vs 方差**:高方差高节奏——跳了商店就没钱;速通社区主流技术。
- **混搭**:负片经济、Anaglyph。

### 42. 一把梭高方差流(Gamble Builds)
- **核心机制**:主动吃大方差换期望——Misprint(0-23 随机 Mult)、Gros Michel(+15 Mult,1/6 自毁;死后解锁商店出 Cavendish ×3 无条件)、Wheel of Fortune(1/4 给版本)、玻璃、Lucky 裸奔(无 Oops)。
- **核心卡**:Misprint、Gros Michel→Cavendish、Wheel of Fortune、Mr. Bones(保命底,分数 25%+ 时免死一次)。
- **可靠性 vs 方差**:定义级高方差;Oops! All 6s 是它的驯化剂(§12),Mr. Bones 是它的保险。
- **混搭**:概率流、玻璃流。

---

## 总表:分数来源 × 成长曲线

| 流派 | 分数来源主轴 | 成长曲线 |
|---|---|---|
| 同花流 §1 | 牌型频率操控 + chips/mult | 线性成长 |
| 顺子流 §2 | 牌型频率操控 | 阈值爆发(Shortcut 前后两个游戏) |
| 对子/两对流 §3 | mult(+) | 开局即强衰减 |
| 葫芦流 §4 | xmult(Duo/Trio) | 线性 → 阈值 |
| 四条/五条流 §5 | 牌型频率操控 + xmult | 阈值爆发 |
| 隐藏牌型流 §6 | 牌型频率操控 + xmult | 阈值爆发(最晚成型) |
| 高牌 Photograph 流 §7 | xmult(per-card) | 阈值爆发 |
| 钢铁国王 Baron/Mime §8 | xmult + 重触发(持牌) | 指数滚雪球 ⭐naneinf 引擎 |
| 持牌 Mult 流 §9 | mult(+,持牌) | 开局即强衰减 |
| 玻璃牌流 §10 | xmult(per-card)+ 毁牌成长 | 线性 → 指数 |
| 黄金牌 Vampire 流 §11 | 经济 / xmult 成长 | 线性偏慢、不衰减 |
| 幸运概率流 §12 | mult + 经济(概率操控) | 阈值爆发(Oops 到手) |
| 石头牌流 §13 | chips | 线性成长 |
| 单花色流 §14 | xmult(per-card) | 线性成长 |
| Smeared 合并流 §15 | 牌型频率操控 | 开局即强(配 Checkered) |
| 花色多样流 §16 | xmult(条件) | 二值/阈值 |
| 暗花色流 §17 | xmult(条件) | 阈值 |
| 人头牌流 §18 | chips+mult+xmult+重触发 | 线性成长 |
| Fibonacci 流 §19 | mult(+) | 线性成长 |
| 奇偶流 §20 | chips / mult(+) | 开局即强衰减 |
| 低牌 Wee/Hack 流 §21 | chips(永久成长)+ 重触发 | 指数偏慢滚雪球 |
| 重触发引擎 §22 | 重触发(放大器) | 依附宿主 |
| 缩牌库流 §23 | 牌型频率操控 | 线性(降方差) |
| DNA 增殖流 §24 | 牌型频率操控(增殖) | 指数滚雪球 |
| 手牌操控 §25 | (资源交易,无直接分) | 依附宿主 |
| Blueprint/Brainstorm §26 | xmult/重触发(复制) | 乘法放大器 |
| Invisible/Showman §27 | (复制) | 阈值爆发 |
| 打出成长流 §28 | mult/chips(+,永久) | 线性成长 |
| 弃牌流 §29 | chips/mult/xmult + 经济 | 线性成长 |
| 毁牌流 §30 | xmult(永久) | 线性 → 指数(Madness) |
| 加牌 Hologram 流 §32 | xmult(永久) | 线性成长 |
| 利息流 §33 | 经济 | 线性(封顶 $25) |
| Bull/Bootstraps §34 | 经济 → chips/mult | 线性成长 |
| 卖价牺牲流 §35 | mult(永久)+ 经济 | 线性成长 |
| Tarot 引擎 §36 | mult(+)+ 改牌供给 | 线性成长 |
| Planet 引擎 §37 | 牌型等级 + xmult(Observatory) | 线性 → 指数(Perkeo 后) |
| Spectral 引擎 §38 | 改牌供给(组件) | 阈值爆发 |
| 负片军团 §39 | 槽位经济(复利) | 指数滚雪球 |
| 跳盲注 Tag 流 §41 | 经济/期权 + xmult(Throwback) | 高方差前置投资 |
| 一把梭流 §42 | mult/xmult(随机) | 开局即强、全程抖动 |

**三条跨流派规律**(多源一致):
1. **+Mult 与 ×Mult 是两个游戏**:常规 8 Ante 用 +Mult 够活,endless/naneinf 只认 ×Mult 指数链(Baron/Mime、Observatory 堆叠、per-card ×Mult + 重触发是三大指数引擎)。
2. **成长牌的触发条件决定它属于哪个流派**:打出(Ride the Bus/Green)、弃牌(Yorick/Castle)、毁牌(Glass Joker/Canio)、买卡/用消耗牌(Fortune Teller/Constellation)、卖卡(Campfire)、过盲注(Madness/Rocket)、跳盲注(Throwback)、加牌(Hologram)——同一张成长牌进错流派就是死卡(Burglar × 弃牌流是教科书反例)。
3. **复制器(Blueprint/Brainstorm)与重触发器是全流派公共终端**,它们不产分、只做乘法,永远接在最强 ×Mult 上。

---

## 主要来源

- balatrowiki.org(Guide: Deck Manipulation、Naneinf、各卡词条)
- Balatro Fandom Wiki:Guide: General strategy / Guide: naneinf / 各卡词条(经搜索摘要)
- balatrocalc.com/balatro-builds
- games.gg(Baron/Mime 指南、经济指南、Wee Joker 指南、Glass Cards 指南)
- thegamer.com(Best Deck Builds、Ante 16 指南、成长 Joker 榜)
- gamerant.com(Best Strategies、Stone Cards、Plasma Deck)
- digitaltrends.com(全 deck 攻略、Best Jokers)
- setsideb.com(Balatro University naneinf 解读)、pcgamer.com(naneinf 报道)
- balatrohq.com(Yorick、Blueprint/Brainstorm、负片、Gros Michel/Cavendish、Checkered Deck、Reddit 最爱组合)
- switchbladegaming.com(Joker 组合榜/排名)
- dualshockers.com(传奇 Joker 排名)、balatrocalculator.blog(传奇指南)
- mobalytics.gg(金注 Joker tier list,经搜索摘要)
- escapistmagazine.com / gameranx.com(Tags 全解)
- earlyguides.com/balatro/builds(注:该站表述疑似 AI 生成,仅作旁证)
- Steam 社区多个讨论串(经搜索摘要)

**覆盖缺口说明**:Reddit r/balatro 原帖因域名对爬虫封锁未能直接抓取,其社区共识经 balatrohq「Reddit 最爱组合」等转述源间接覆盖。
