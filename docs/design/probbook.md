# 概率账本(仪器读数,手改无效 —— 重刷:`python3 tools/probbook.py <sim日志>`)

生成:2026-08-27 03:15 · 真人样本:16 局 · bot 来源:**未提供(缺 bot 列)**
真人列两态:**无R** = 未持有任何规则牌(近道/四指/双色调/百搭)的拍,**有R** = 持有的拍。bot 列未拆态(仪器债)。

| id | 名 | 稀有 | 通道数额 | p̂ 设计 | p_bot (n拍) | p_人·无R (n拍) | p_人·有R (n拍) | 诊断 |
|---|---|---|---|---|---|---|---|---|
| encore | 回响 | common | bonus_target_pct 0.577 | 0.35(重复上一拍:需刻意保型,且被禁回族脸打断) | — | 33% (15) | — | ⚠人样本薄 |
| finale | 尾声 | common | bonus_target_pct 0.24 | 0.65(最后2秒有操作:节奏玩家多数拍会压秒) | — | 62% (21) | — | ⚠人样本薄 |
| turnover | 周转 | common | per discard | 0.75(弃过牌:免费弃牌下多数拍会弃) | — | 73% (15) | — | ⚠人样本薄 |
| tipjar | 小费罐 | common | coins 2 | 0.35(整拍零弃:与弃牌自由互斥,少数拍) | — | 50% (6) | — | ⚠人样本薄 |
| chord | 和弦 | common | bonus 140.0 | 0.70(建成态:缓存三同花建好后可持续;建设期2-4拍) | — | — | — | · |
| neonsign | 灯牌 | common | bonus_target_pct 0.12 | 1.00(无条件) | — | 100% (9) | — | ⚠人样本薄 |
| popup | 快闪 | common | bonus_target_pct 0.8 | 0.10(S1 专属×商店最早段中开:窗口错位) | — | 0% (6) | — | ⚠人样本薄 |
| vinyl | 黑胶 | common | per counter:n | — | — | 93% (27) | — | ⚠人样本薄 |
| chorus | 副歌 | uncommon | bonus_pct 0.75 | 0.17(每段末拍:1/6 结构概率) | — | — | — | · |
| interest | 利息 | uncommon | cap 5 | 0.85(持币≥4◆ 多数拍为真) | — | — | — | · |
| advance | 预支 | uncommon | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |
| momentum | 惯性 | uncommon | per counter:stacks | — | — | 17% (6) | — | ⚠人样本薄 |
| vip | 贵宾 | uncommon | additive_face_value 20 | — | — | — | — | · |
| glowstick | 荧光棒 | uncommon | bonus_pct … | — | — | — | — | · |
| shortcut | 近道 | uncommon | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |
| fourfingers | 四指 | uncommon | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |
| blacktone | 黑调 | rare | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |
| redtone | 红调 | rare | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |
| bassline | 贝斯线 | rare | step 8 | — | — | — | — | · |
| mirror | 镜面 | rare | mult_from_target_factor 0.5 | — | — | — | — | · |
| wildcard | 百搭 | rare | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |
| superwild | 超级百搭 | rare | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |
| variation | 变奏 | common | bonus_target_pct 0.204 | 0.70(换牌型:五张重抽下不同牌型是自然态) | — | 71% (21) | — | ⚠人样本薄 |
| reprise | 复读 | uncommon | bonus_pct 0.8 | 0.35(同回响) | — | — | — | · |
| fullcast | 全员 | common | bonus_target_pct 0.769 | 0.12(顺/同花/葫芦成手:等价于打出大牌型) | — | 0% (9) | — | ⚠人样本薄 |
| superfan | 铁粉 | uncommon | cap 0.15 | 0.90(持币≥2◆ 几乎恒真) | — | — | — | · |
| opener | 开场 | uncommon | bonus_pct 1.5 | 0.17(每段首拍:1/6 结构概率) | — | — | — | · |
| rainbow | 彩虹 | common | bonus_target_pct 0.433 | 0.28(成牌四花色:C(4,4)分布+换牌可凑,偏彩票) | — | 38% (24) | — | ⚠人样本薄 |
| nopair | 清流 | common | bonus_target_pct 0.457 | 0.40(五张无对:高牌/顺/同花态,可刻意保持) | — | 0% (3) | — | ⚠人样本薄 |
| rehearsal | 排练 | common | bonus 200.0 | 0.08(缓存三连号:同上) | — | 0% (6) | — | ⚠人样本薄 |
| bassclef | 低音谱 | uncommon | additive_low_value 15 | — | — | 83% (18) | — | ⚠人样本薄 |
| warmtone | 暖色 | common | card_filter red | — | — | 33% (3) | — | ⚠人样本薄 |
| cooltone | 冷色 | common | card_filter black | — | — | 100% (6) | — | ⚠人样本薄 |
| undertone | 低声部 | common | card_filter rank_lte_5 | — | — | 67% (21) | — | ⚠人样本薄 |
| duo | 对唱 | common | additive 10 | — | — | — | — | · |
| duet | 二重唱 | uncommon | bonus_pct 0.25 | — | — | 100% (3) | — | ⚠人样本薄 |
| triad | 三和弦 | common | additive 25 | — | — | — | — | · |
| triplebill | 三重 | uncommon | bonus_pct 0.6 | — | — | — | — | · |
| backer | 后台 | common | per coins:2 | — | — | — | — | · |
| bench | 替补 | uncommon | additive_cache_top 1 | — | — | — | — | · |
| boxseats | 包厢 | rare | per cache_face | — | — | — | — | · |
| trim | 修剪 | rare | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |
| doublebill | 联票 | rare | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |
| sponsor | 赞助 | uncommon | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |
| jukebox | 点唱机 | rare | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |
| freeze | 定格 | uncommon | bonus_pct 0.3 | — | — | 33% (6) | — | ⚠人样本薄 |
| stilllife | 静物 | common | bonus_target_pct 0.144 | — | — | — | — | · |
| segue | 串场 | common | per swapped_scoring | — | — | — | — | · |
| stageexit | 让位 | common | per face_discard | — | — | 25% (12) | — | ⚠人样本薄 |
| royalty | 分成 | uncommon | coins_factor 2 | — | — | — | — | · |
| skint | 穷开心 | rare | mult_add 0.3 | — | — | — | — | · |
| curtain | 谢幕 | uncommon | bonus_pct 0.6 | — | — | 83% (6) | — | ⚠人样本薄 |
| stopwatch | 秒表 | uncommon | per second_left | — | — | — | — | · |
| earlyout | 早弃 | common | bonus_target_pct 0.192 | — | — | — | — | · |
| digger | 淘碟 | uncommon | per counter:n | — | — | — | — | · |
| collector | 收藏家 | uncommon | cap 30 | — | — | — | — | · |
| rebrand | 转型 | uncommon | per counter:n | — | — | 25% (12) | — | ⚠人样本薄 |
| fastforward | 快进 | rare | per counter:stacks | — | — | — | — | · |
| deejay | 打碟 | rare | per counter:n | — | — | — | — | · |
| goldenvoice | 金嗓 | rare | per coins:6 | — | — | — | — | · |
| hush | 静场 | rare | mult_add 0.4 | — | — | — | — | · |
| harmony | 和声 | rare | mult_add 0.3 | — | — | — | — | · |
| ensemble | 合奏 | rare | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |
| allin | 孤注 | rare | mult 4.0 | — | — | — | — | · |
| jackpot | 彩头 | uncommon | mult 3.0 | — | — | — | — | · |
| loadeddice | 灌铅骰 | rare | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |
| recycle | 回收 | uncommon | per cache_rank_sum | — | — | — | — | · |
| gueststar | 客串 | uncommon | mult_add 0.5 | — | — | — | — | · |
| matador | 斗牛士 | uncommon | 规则牌 | — | → Δp 表 | → Δp 表 | → Δp 表 | 概率放大器,不入 fired |
| blindplay | 盲奏 | uncommon | per hidden_scoring | — | — | — | — | · |

## 规则牌 Δp(真人牌型频率两态 —— numbers.md §2 概率放大器的计价输入)

「无该牌」池 = 全部合格局里未持有该牌的拍(跨局对照,混着构筑差异,样本大了才可用);
有态样本 < 30 拍 ⇒ **规则牌不定价**(numbers.md §1 的封锁纪律)。

| 规则牌 | 态 | n拍 | 顺子族 | 同花族 | 大牌型族 |
|---|---|---|---|---|---|
| shortcut | 持有 | 0 | — | — | — |
|  | 未持有 | 218 | 1.4% | 5.5% | 10.6% |
| fourfingers | 持有 | 0 | — | — | — |
|  | 未持有 | 218 | 1.4% | 5.5% | 10.6% |
| twotone | 持有 | 0 | — | — | — |
|  | 未持有 | 218 | 1.4% | 5.5% | 10.6% |
| wildcard | 持有 | 0 | — | — | — |
|  | 未持有 | 218 | 1.4% | 5.5% | 10.6% |
