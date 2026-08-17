# 首页大卡的玻璃壳素材

`glass.png`(842×1355)= `docs/mockups/godot-handoff/card_glass_full.png` 的原样拷贝
(灰白预烘焙版,自带 y 1197–1355 的镜面倒影;它又是 `docs/mockups/assets/frame-glass4.png`
的去色版 —— 三张是同一张图)。

- **接管范围只有首页大卡**:`Widgets.StageCard.draw_card` 的贴图分支按 `tail` 取键,
  `tail=true`(全仓只有 home 大卡一处)读 `glass.png` 整图拉伸;档位色靠 modulate。
- **⚠ `glassface.png` 这个文件名永远别放进来** —— `tail=false` 的所有调用点
  (顶栏/商店/图鉴页/荣誉面板)都会被它接管走九宫格,小板尺寸下必坏。
- home 的镜像倒影层(TailLayer)在检测到 `glass.png` 时自动跳过 —— 倒影已烘在图里,
  再画一层就是双影。

## 判决史(2026-08-05 判死 → 2026-08-12 反转)

当年 4× 放大实测三宗罪(alpha 硬边切辉光 / 辉光区 RGB 麻点 / 玻璃体内部抠烂),
判「不能直接贴」,程序化画了一版。2026-08-12 用户拍板换回素材,复盘发现:
**用户觉得质感更好的设计稿(home.html)贴的就是这张图** —— 缩到 0.76 倍、放在
近黑底上,三宗罪全部读不出来。教训进了 [LESSONS.md](../../LESSONS.md) 判据 5:
**素材成色要在显示尺寸 + 真实底色下判,不要只看放大镜。**

另:抠图确实是坏的且**不可修**(α=0 处 RGB 0.00% 存活,tools/art/glassprobe.gd
实测)——但显示尺寸下不需要修。要重量剖面就跑那个探针。
