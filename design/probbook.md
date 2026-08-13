# 概率账本(仪器读数,手改无效 —— 重刷:`python3 tools/probbook.py <sim日志>`)

生成:2026-08-12 23:06 · 真人样本:12 局 · bot 来源:`sim2.log`
真人列两态:**无R** = 未持有任何规则牌(近道/四指/双色调/百搭)的拍,**有R** = 持有的拍。bot 列未拆态(仪器债)。

| id | 名 | 稀有 | 通道数额 | p̂ 设计 | p_bot (n拍) | p_人·无R (n拍) | p_人·有R (n拍) | 诊断 |
|---|---|---|---|---|---|---|---|---|
| encore | 回响 | common | bonus 240.0 | 0.35(重复上一拍:需刻意保型,且被禁回族脸打断) | 36% (2245) | 33% (15) | — | ⚠人样本薄 |
| finale | 尾声 | common | bonus 100.0 | 0.65(最后2秒有操作:节奏玩家多数拍会压秒) | 70% (1089) | 62% (21) | — | ⚠人样本薄 |
| turnover | 周转 | common | per discard | 0.75(弃过牌:免费弃牌下多数拍会弃) | 57% (1156) | 73% (15) | — | ⚠人样本薄 |
| tipjar | 小费罐 | common | coins 2 | 0.35(整拍零弃:与弃牌自由互斥,少数拍) | 54% (63) | 50% (6) | — | ⚠人样本薄 |
| chord | 和弦 | common | bonus 140.0 | 0.70(建成态:缓存三同花建好后可持续;建设期2-4拍) | 9% (461) | — | — | p̂≫bot:教学/结构? |
| neonsign | 灯牌 | common | bonus 50.0 | 1.00(无条件) | 100% (1982) | — | — | · |
| vinyl | 黑胶 | common | per counter:n | — | 82% (74) | 93% (27) | — | ⚠人样本薄 |
| chorus | 副歌 | uncommon | bonus_pct 0.75 | 0.17(每段末拍:1/6 结构概率) | 15% (154) | — | — | · |
| interest | 利息 | uncommon | cap 5 | 0.85(持币≥4◆ 多数拍为真) | 100% (92) | — | — | · |
| momentum | 惯性 | uncommon | per counter:stacks | — | 73% (167) | 0% (3) | — | ⚠人样本薄 |
| vip | 贵宾 | uncommon | additive_face_value 20 | — | 84% (2) | — | — | · |
| glowstick | 荧光棒 | uncommon | bonus_pct … | — | 96% (326) | — | — | · |
| shortcut | 近道 | uncommon | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |
| fourfingers | 四指 | uncommon | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |
| twotone | 双色调 | uncommon | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |
| bassline | 贝斯线 | rare | step 12 | — | 0% (6) | — | — | ☠死档(<5%) |
| mirror | 镜面 | rare | mult_from_target_factor 0.5 | — | 49% (130) | — | — | · |
| wildcard | 百搭 | rare | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |
| variation | 变奏 | common | bonus 85.0 | 0.70(换牌型:五张重抽下不同牌型是自然态) | 65% (2398) | 71% (21) | — | ⚠人样本薄 |
| reprise | 复读 | uncommon | bonus_pct 0.8 | 0.35(同回响) | 37% (263) | — | — | · |
| fullcast | 全员 | common | bonus 320.0 | 0.12(顺/同花/葫芦成手:等价于打出大牌型) | 12% (1323) | 0% (9) | — | ⚠人样本薄 |
| superfan | 铁粉 | uncommon | cap 0.15 | 0.90(持币≥2◆ 几乎恒真) | 100% (136) | — | — | · |
| opener | 开场 | uncommon | bonus_pct 1.5 | 0.17(每段首拍:1/6 结构概率) | 18% (290) | — | — | · |
| rainbow | 彩虹 | common | bonus 180.0 | 0.28(成牌四花色:C(4,4)分布+换牌可凑,偏彩票) | 24% (1701) | 40% (15) | — | ⚠人样本薄 |
| nopair | 清流 | common | bonus 190.0 | 0.40(五张无对:高牌/顺/同花态,可刻意保持) | 32% (2668) | 0% (3) | — | ⚠人样本薄 |
| rehearsal | 排练 | common | bonus 200.0 | 0.08(缓存三连号:同上) | 6% (2332) | 0% (6) | — | ⚠人样本薄 |
| bassclef | 低音谱 | uncommon | additive_low_value 15 | — | 74% (273) | 83% (18) | — | ⚠人样本薄 |
| warmtone | 暖色 | common | card_filter red | — | 94% (191) | 33% (3) | — | ⚠人样本薄 bot≫人:水平相关,锚真人 |
| cooltone | 冷色 | common | card_filter black | — | 94% (201) | 100% (3) | — | ⚠人样本薄 |
| undertone | 低声部 | common | card_filter rank_lte_5 | — | 74% (569) | 60% (15) | — | ⚠人样本薄 |
| duo | 对唱 | common | additive 10 | — | 66% (113) | — | — | · |
| duet | 二重唱 | uncommon | bonus_pct 0.25 | — | 63% (208) | — | — | · |
| triad | 三和弦 | common | additive 25 | — | 9% (20) | — | — | · |
| triplebill | 三重 | uncommon | bonus_pct 0.6 | — | 6% (8) | — | — | · |
| backer | 后台 | common | per coins:2 | — | 100% (296) | — | — | · |
| bench | 替补 | uncommon | additive_cache_top 1 | — | 100% (146) | — | — | · |
| boxseats | 包厢 | rare | per cache_face | — | 41% (18) | — | — | · |
| trim | 修剪 | rare | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |
| doublebill | 联票 | rare | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |
| sponsor | 赞助 | uncommon | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |
| jukebox | 点唱机 | rare | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |

## 规则牌 Δp(真人牌型频率两态 —— numbers.md §2 概率放大器的计价输入)

「无该牌」池 = 全部合格局里未持有该牌的拍(跨局对照,混着构筑差异,样本大了才可用);
有态样本 < 30 拍 ⇒ **规则牌不定价**(numbers.md §1 的封锁纪律)。

| 规则牌 | 态 | n拍 | 顺子族 | 同花族 | 大牌型族 |
|---|---|---|---|---|---|
| shortcut | 持有 | 0 | — | — | — |
|  | 未持有 | 168 | 1.8% | 7.1% | 12.5% |
| fourfingers | 持有 | 0 | — | — | — |
|  | 未持有 | 168 | 1.8% | 7.1% | 12.5% |
| twotone | 持有 | 0 | — | — | — |
|  | 未持有 | 168 | 1.8% | 7.1% | 12.5% |
| wildcard | 持有 | 0 | — | — | — |
|  | 未持有 | 168 | 1.8% | 7.1% | 12.5% |
