# 美术参考(权威来源)

用户自己用 Claude Design 做的规格和参考图。**实现与它有分歧时以这里为准,不要凭印象猜。**
从原 `docs/mockups/` 精简而来:重复的、已作废的(旧排版截图、JQK 宫廷牌 —— 卡面已简化为
角标数字 + 中央花色)、以及 Claude Design 的运行时 `support.js` 都删掉了。

| 文件 | 用途 |
|---|---|
| `Neon Rain Card Game.dc.html` | **主规格**。整屏布局、20 个关键帧、`startWave` 音浪算法、`startWalk` 走位路径、`doSettle` 结算时间轴、拖拽逻辑、全部配色 |
| `整副卡牌.dc.html` | 54 张牌规格、`chrome()` 配色函数、玻璃卡体配方(点阵排布部分已作废) |
| `手牌样式方案.dc.html` | 卡面风格候选,最终选的是「1a 玻璃底 × 2a 传统点阵」 |
| `ref_wave_particles.png` | 粒子音浪参考,`view/wave_view.gd` 的来源 |
| `ref_wetfloor_club.png` | 湿地面反射参考。卡躺在地上时**整张卡的内容都在倒影里、且被压扁**,`PaperCard` 的倒影按这个做 |
| `ref_joker_holo_beat/bass/synth.png` | 全息小丑牌参考(粉/青/紫三色)。**阶段② 小丑牌正式设计要用** |

注:这些是参考素材,不参与运行时。正式打包前记得在导出预设里排除本目录。
