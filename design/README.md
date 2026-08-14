# Sync5 · 设计文档导览

> **这一篇只回答:我该看哪一篇。**
> 项目状态看 [`../STATUS.md`](../STATUS.md) · 待办 [`../TODO.md`](../TODO.md) ·
> 变更史 [`../CHANGELOG.md`](../CHANGELOG.md) · 经验 [`../LESSONS.md`](../LESSONS.md) ·
> 规则与美术的**原则** [`../CLAUDE.md`](../CLAUDE.md)
>
> **2026-08-09 重组完成:30 篇 → 20 篇,编号全部去掉,按主题命名。**

---

## 主结构(用户 2026-08-09 定)

| # | 篇 | 管什么 |
|---|---|---|
| ① | **README**(本篇) | 导览 |
| ② | [**jokers**](jokers.md) | 小丑牌与主角 —— 16 条设计原则 · 钩子契约 · 校准史 |
| ③ | [**blinds**](blinds.md) | 盲注(Boss 脸)—— 一张脸怎么设计 · `tier`/`proof` 两道强制门 |
| ④ | [**generating**](generating.md) | 生成方案 —— P 是向量 · 生成 = 优化 · 评估与随机搜索的陷阱 |
| ⑤ | [**solving**](solving.md) | 求解方案 —— 形式化对象 · 玩家参数化 · DP · L0-L2 验收 |
| ⑥ | [**ui_meta**](ui_meta.md) | UI 与 META(**均为前瞻,未实施**) |
| ⑦ | [**levels**](levels.md) | 关卡设计 —— 段/拍/商店的形状 + **经济与商店** |
| ⑧ | [**tech**](tech.md) | 技术文档 —— 分层 · `data/*.json` schema · 一套规则 |
| ⑨ | [**vision**](vision.md) | 初衷与玩法逻辑(⚠ 含过期内容,已标注) |
| ⑩ | [**cards**](cards.md) | 牌与牌型 —— 牌流 + 牌型表与定价 |
| ⑪ | [**telemetry**](telemetry.md) | 打点 —— 21 类事件 · 口径铁律 |

**支撑三篇**(不属于主结构,但都是现行的):

| 篇 | 管什么 |
|---|---|
| [**prior**](prior.md) | **先验层 —— ④⑤ 两篇的共同输入**(2026-08-14)。那两篇都假设"分布是已知的",而分布从哪来以前没有一篇文档回答。零数据算出牌型/谓词概率与规则牌 Δp;附**第二把尺子**的用法 |
| [**difficulty**](difficulty.md) | **难度与节奏**(2026-08-14)—— 三轴分清(局内段 / 跨局序列 / 解锁进度)· `death_spec` 形状 = 起承転結 · 脸的轮次集 `tiers` · Director(不读 context 的一张表)· **新手引导** |
| [**gates**](gates.md) | **那道门的规格** —— `gate.sh` 怎么造对照臂、覆盖自证契约、可加性检验 |
| [**capability**](capability.md) | **模型能看见什么、打得多好** —— 七类规则分类 · 三层精度 · 三个缺口 |
| [**numbers**](numbers.md) · [**probbook**](probbook.md) | **定价宪法**(三轴+六步 SOP)与概率账本(仪器读数,手改无效) |
| [**jokers_atlas**](jokers_atlas.md) · [**archetypes**](archetypes.md) | **候选池**:小丑牌 60 张口径(卡片层)· 流派图谱(流派层,2026-08-12) |
| `research_balatro_jokers` · `research_balatro_builds` · `research_balatro_bosses` · `research_pacing_retention` | **调研:原作是怎么做的**(卡普查 / 流派目录 / Boss / 节奏留存) |

⚠ 四篇 `research_*` **刻意保持独立** —— 它们是**外部事实**,不是我们的决定。
混进设计篇会让「调研结论」和「我们的选择」分不开。

---

## 两条约定

### 1. 验证跟着被验的东西走

> 用户 2026-08-09:「验证方案似乎应该在不同文档里有,比如求解有求解的验证方案,
> 小丑牌设计有设计的验证方案,而不是单独的文档。」

**单独开一篇「验证方案」的话,写完设计的人不会去翻它;放在同一篇里,改设计时自然看得见。**

**十一篇每一篇都有自己的验证节。** 范例:

- `solving.md` 的 L0/L1/L2 三级验收
- `blinds.md §6` 加一张新脸的完整流程 + 「测出近零不许改内容」那条铁律
- `vision.md` **诚实地说自己没有自动验证,而且不该有** —— 好不好玩最终是留存,而留存零数据

### 2. 被推翻的内容必须**就地**标注

同一篇里同时躺着旧方案和新方案、读者无从分辨 —— 这是付过学费的坑
(`capability.md` 开头那条矛盾躺了一整轮没被发现)。

规矩:**推翻了就在原地写 `⚠⚠ 已被 X 取代`,别只在新文档里说。**
整篇作废的在开头加横幅;**推导史太长就单独一篇**
([`solving_history.md`](solving_history.md) 是范例),但正文要留一句指过去。

---

## 🟣 历史 —— **别照着做**

| 篇 | 为什么留 |
|---|---|
| [`solving_history.md`](solving_history.md) | 求解方案里**被推翻的 7 条路**及其实测证据 |
| `solver_roadmap.md` | 早期求解器路线图,已被 `solving.md` 覆盖 |
| `history_adversarial.md` | G/D 对抗校准 —— **已作废**(上界不需要「学」,只需要「解」) |
| `history_parametric.md` | 同上,参数化训练路线 |

---

## 从零开始该怎么读

```
想知道这游戏是什么      ../STATUS.md → vision → levels
想改数值 / 加内容       ../CLAUDE.md(原则) → tech(schema) → gates(那道门)
想加一张脸 / 一张牌     blinds / jokers —— 各自末尾有完整流程
想搞懂建模与求解        prior → solving → generating → capability
想知道踩过什么坑        ../LESSONS.md → solving_history
```

⚠ **改任何数值前先读 [`../CLAUDE.md`](../CLAUDE.md)** —— 那里是**现行**的已拍板规则,
本目录讲的是「当初为什么这么定」。两处冲突时,**以 CLAUDE.md 为准**。
