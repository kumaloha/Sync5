# 概率账本(仪器读数,手改无效 —— 重刷:`python3 tools/probbook.py <sim日志>`)

生成:2026-08-12 15:55 · 真人样本:11 局 · bot 来源:`sim_v4.log`

| id | 名 | 稀有 | 通道数额 | p̂ 设计 | p_bot (n拍) | p_人 (n拍) | 诊断 |
|---|---|---|---|---|---|---|---|
| encore | 回响 | common | bonus 160.0 | 0.35(重复上一拍:需刻意保型,且被禁回族脸打断) | 37% (1892) | 11% (9) | ⚠人样本薄 bot≫人:水平相关,锚真人 |
| finale | 尾声 | common | bonus 80.0 | 0.65(最后2秒有操作:节奏玩家多数拍会压秒) | 71% (581) | 54% (24) | ⚠人样本薄 |
| turnover | 周转 | common | per discard | 0.75(弃过牌:免费弃牌下多数拍会弃) | 60% (769) | 73% (15) | ⚠人样本薄 |
| tipjar | 小费罐 | common | coins 2 | 0.35(整拍零弃:与弃牌自由互斥,少数拍) | 71% (15) | 50% (6) | ⚠人样本薄 |
| chord | 和弦 | common | bonus 140.0 | 0.70(建成态:缓存三同花建好后可持续;建设期2-4拍) | 9% (242) | — | p̂≫bot:教学/结构? |
| neonsign | 灯牌 | common | bonus 60.0 | 1.00(无条件) | 100% (2719) | — | · |
| vinyl | 黑胶 | common | per counter:n | — | 84% (273) | 83% (12) | ⚠人样本薄 |
| chorus | 副歌 | uncommon | bonus_pct 0.75 | 0.17(每段末拍:1/6 结构概率) | 13% (52) | — | · |
| interest | 利息 | uncommon | cap 5 | 0.85(持币≥4◆ 多数拍为真) | 100% (17) | — | · |
| momentum | 惯性 | uncommon | per counter:stacks | — | 77% (72) | — | · |
| vip | 贵宾 | uncommon | additive_face_value 15 | — | — | — | · |
| glowstick | 荧光棒 | uncommon | bonus_pct … | — | 98% (234) | — | · |
| shortcut | 近道 | uncommon |  | — | 0% (21) | — | ☠死档(<5%) |
| fourfingers | 四指 | rare |  | — | 0% (15) | — | ☠死档(<5%) |
| twotone | 双色调 | rare |  | — | 0% (14) | — | ☠死档(<5%) |
| bassline | 贝斯线 | rare | step 12 | — | 11% (2) | — | · |
| mirror | 镜面 | rare | mult_from_target_factor 0.5 | — | 48% (117) | — | · |
| wildcard | 百搭 | rare |  | — | 0% (7) | — | ☠死档(<5%) |
| variation | 变奏 | common | bonus 65.0 | 0.70(换牌型:五张重抽下不同牌型是自然态) | 65% (1747) | 71% (21) | ⚠人样本薄 |
| reprise | 复读 | uncommon | bonus_pct 0.5 | 0.35(同回响) | 36% (37) | — | · |
| fullcast | 全员 | common | bonus 240.0 | 0.12(顺/同花/葫芦成手:等价于打出大牌型) | 11% (793) | 0% (6) | ⚠人样本薄 |
| superfan | 铁粉 | uncommon | cap 0.3 | 0.90(持币≥2◆ 几乎恒真) | 100% (26) | — | · |
| opener | 开场 | uncommon | bonus_pct 0.8 | 0.17(每段首拍:1/6 结构概率) | 18% (39) | — | · |
| popup | 快闪 | common | bonus 200 | 0.10(S1 专属×商店最早段中开:窗口错位) | 0% (2061) | 0% (6) | ⚠人样本薄 ☠死档(<5%) |
| rainbow | 彩虹 | common | bonus 180.0 | 0.28(成牌四花色:C(4,4)分布+换牌可凑,偏彩票) | 23% (1773) | 25% (24) | ⚠人样本薄 |
| nopair | 清流 | common | bonus 130.0 | 0.40(五张无对:高牌/顺/同花态,可刻意保持) | 33% (2496) | 0% (3) | ⚠人样本薄 |
| backup | 伴唱 | common | bonus 200.0 | 0.05(缓存三人头:建设成本极高,基本不会为它建) | 1% (1117) | 0% (6) | ⚠人样本薄 p̂≫bot:教学/结构? ☠死档(<5%) |
| rehearsal | 排练 | common | bonus 200.0 | 0.08(缓存三连号:同上) | 6% (2819) | 0% (9) | ⚠人样本薄 |
| bassclef | 低音谱 | uncommon | additive_low_value 10 | — | 79% (21) | 45% (33) | · |
| warmtone | 暖色 | common | card_filter red | — | 93% (374) | — | · |
| cooltone | 冷色 | common | card_filter black | — | 94% (336) | 100% (3) | ⚠人样本薄 |
| undertone | 低声部 | common | card_filter rank_lte_5 | — | 73% (197) | 50% (18) | ⚠人样本薄 |
