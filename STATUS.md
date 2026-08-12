# Sync5 · 当前状态

> **这份文档只回答一件事:现在是什么样。**
> 待办看 [TODO.md](TODO.md) · 变更史看 [CHANGELOG.md](CHANGELOG.md) · 经验看 [LESSONS.md](LESSONS.md)
> 规则与美术的**原则**在 [CLAUDE.md](CLAUDE.md) · 设计规格在 `design/`
>
> **最后更新:2026-08-12**(08-09 之后的增量见文末「增量快照」节,数字冲突以那节为准)

---

## 一句话

**5 秒乐句 × 扑克 Roguelite**,Godot 4.6.2 / GDScript,竖屏 720×1280。
Lumines 的节奏推进 + Balatro 的构筑。一局 4 段 × 6 拍 × 8 秒 ≈ 4.9 分钟。

---

## 回归状态(2026-08-09)

| 项 | 状态 | 命令 |
|---|---|---|
| 单元测试 | **948 passed / 0 failed**(2026-08-12) | `godot --headless --path . --script res://tests/runner.gd` |
| 小丑牌覆盖门 | **23/23 量到**(score 16 · solver 4 · coin 金币臂 3),262s | `godot --headless --path . --script res://tools/kit.gd`(单卡:`SYNC5_KIT_ID=<id>`,十几秒) |
| 内容门 | **全过,910s** | `./tools/gate.sh` |
| 求解器一致性 | **三关配对差 +0.0** | `godot --headless --path . --script res://tools/pair.gd` |
| 流程/打点/重放 | 0 违规 | 已并进 `gate.sh` |

---

## 三层的完成度

### ① 游戏本体 —— **可玩,已封盘**

一局能完整走完:首页 → 选主角 → 4 段 × 6 拍 → **7 次商店**(段中 4 + 段末 3)→ 结算两屏。
⚠ **不是 8 次** —— 末段没有段末商店(Tape 实测 37/37 局)。旧文档里的「8 次」按 7 读,
多出来那一次曾经只存在于 `tools/runloop.gd`,2026-08-09 已修。

| | 现役 |
|---|---|
| 小丑牌 | **23 张**(Target 5 + Support 18) |
| Boss 脸 | **13 张**在池(`raisedbar` 2026-08-09 由用户拍板进第三轮);另有 1 张退役(`rotation`) |
| 主角 | 8 个,被动数值是初稿 |
| 结构 | 4 段 × 6 拍 × 8 秒,每 3 拍一次商店 |

**UI/美术已完成并暂告段落**(霓虹舞台风格已锁定)。唯一未达标的是玻璃卡的**光影**
—— 用户 2026-08-06 明确表示不满意后中止,现状与根因记在 `design/` 与记忆里。

### ② 模型(求解器) —— **能跑,但绝对值不可信**

```
core/pattern.gd + settle.gd    计分       ← 游戏与模型**共用同一份**
core/beat.gd                   一拍的转移  ← 游戏 + 全部探针共用
tools/runloop.gd               一局的循环  ← **只给探针用**(游戏是实时异步的)
tools/solver.gd                拍内枚举 C(8,5)=56 切法 × 弃牌子集, 调真实计分
tools/bot.gd                   玩家策略(完美玩家 / 规则 bot)
```

**拍内是精确的**(与 draw poker 的领域标准一致,`pair.gd` 逐手验过)。
**跨拍是 λ-平衡贪心**(近似)。**构筑是手写规则**(最粗)。

⚠⚠ **当前最重要的限制:通关率的绝对值系统性低估约 8.4 个百分点**(z≈−3.5,
加样本加档数都修不掉)。原因已部分定位(见 [LESSONS.md](LESSONS.md) 与 `design/solving_history.md`),
**但主因仍未完全找到**。

> **所以:模型给出的相对排序可信,绝对难度不可信。**

### ③ 生成器 —— **只生成目标分,而且那两张表是占位**

`tools/curve.gd`:不死局录分 → 按 `death_spec` 查分位数 → 反解目标分。

⚠⚠ **`run.json section_targets` 与 `sim.json bot_targets` 是占位,不是定稿。**
整套目标分体系要跟着新目标函数(留存最大化)重新设计。**别把它们当待修的 bug。**

而配置 `c` 的其余维度(脸的排布、经济、货架)**全是手写的** —— 那是**设计**,
不是待自动化的技术债(用户 2026-08-08 明确)。

---

## 数据与配置

**所有数值与内容在 `data/*.json`**,`core/db.gd` 校验 ——
未知键/坏引用**在测试里直接红**(⚠ 是**测试期门禁**,运行时不拒绝启动;理由见 `core/db.gd` 文件头)。

| 文件 | 管什么 |
|---|---|
| `jokers.json` | 小丑牌(效果 DSL,`core/fx.gd` 解释) |
| `faces.json` | Boss 脸(参数表 + `tier` + `proof` 通路 + `weak_upper_bound`)。**纯数据,散文一律在 `design/blinds.md`,`db.gd` 拒绝散文键** |
| `run.json` | 关卡结构 · 目标分 · `death_spec` · `beat_budget` |
| `economy.json` `characters.json` `sim.json` `ui.json` `tape.json` | 经济 / 主角 / 机器人信念 / 界面坐标文案 / 打点开关 |

**改卡改平衡 = 改 JSON**,不用动代码。

---

## 工具链(`tools/`,41 个文件)

| 工具 | 干什么 | 耗时 |
|---|---|---|
| **`gate.sh`** ⚑ | **加了内容就要过的门**(测试+脸覆盖自证+**小丑牌覆盖自证**+单调性+哨兵+流程+打点+重放+尺子) | **~15 分钟**(2026-08-09 加入 `kit.gd` 后从 8 分钟涨上来;快路径:单脸 `gate.sh <face_id>`、单卡 `SYNC5_KIT_ID=<id>`,各十几秒) |
| `pair.gd` | 守「求解器 = 游戏代码」,三关递进 | ~3 分钟 |
| `curve.gd` | 生成器:录分 → 反解目标分 | — |
| `sim.gd` | 全队列通关率,**自带尺子自检**(非零退出) | ~107s |
| `price.gd` | 每(脸, 轮)一个价 | — |
| `addit.gd` | 可加性检验(脸能不能相加) | ~10 分钟 |
| `coin.gd` `blind.gd` `warm.gd` `lam.gd` `attrib.gd` | 金币影子价 / 盖牌族 / 养牌价值 / λ 扫描 / 分数归因 | — |
| `formal.gd` `dp.gd` `dpcheck.gd` `dpdiag.gd` `udp.gd` | `design/solving.md` 的建模验证 | 各 10-25 分钟 |
| `replay.gd` | **L2 决策重放门**(建模侧完整性) | 秒级 |
| 各 `*_sheet.gd` `shoot.gd` `glass.gd` | 截图探针 | — |

**四层真相各只有一份**(2026-08-09 补齐后两层):
`core/beat.gd` 一拍的转移 · `tools/runloop.gd` 一局的循环 ·
**`tools/probe.gd`(`Probe`)+ `tools/shot.gd`(`Shot`)一次实验的骨架** ·
**`tools/stat.gd`(`Stat`)一份统计**。

⚠ **探针数量本身不是问题** —— 41 个文件 / 6777 行,它们是**不同的实验**,各占一个文件是对的。
真正要守的是「别再抄第五层」:新探针一律 `extends Probe`、统计走 `Stat`、截图走 `Shot`。

---

## 真人数据:**有了**(2026-08-12 起,详见下方增量快照;本节以下为 08-09 旧文)

磁盘上 1067 局 Tape 日志**全部是探针产物**(时长 >60s 的只有 1 局,而真人一局 ≈ 294s)。

**采集侧已实装并验过**(`core/tape.gd`,21 类事件,两个探针守着),**分析侧一行没有**。

⚠ 因此这一整族**全部零输入**:发挥系数 · 手速 `beat_budget` · 人群权重 · 三因子权重 · 留存。
**在它们到位前,模型的绝对值不该被当真。**

---

## 设计文档地图

**目录页 = [`design/README.md`](design/README.md)。**

2026-08-09 按用户定的结构重组完成:**30 篇 → 20 篇,编号全部去掉,按主题命名,
每一篇自带自己的验证节**。

```
README      导览                jokers   小丑牌与主角      blinds    盲注(Boss 脸)
generating  生成方案            solving  求解方案          ui_meta   UI 与 META(前瞻)
levels      关卡 + 经济商店      tech     分层与 schema     vision    初衷与玩法逻辑
cards       牌与牌型            telemetry 打点
—— 支撑 ——  gates(那道门的规格) · capability(模型能看见什么、打得多好) · research_* ×3
—— 历史 ——  solving_history · solver_roadmap · history_adversarial · history_parametric
```

---

## 三条一眼就该知道的现状

1. **目标分表是占位** —— 别当待修的 bug,它是整套重新设计的产物。
2. **模型绝对值不可信,只信相对排序** —— 通关率低估 8.4 个百分点,主因未完全定位。
3. **真人数据为零** —— 所有「等真人 Tape」的事项都卡在这里,而这一条只有用户能解。


---

## 增量快照(2026-08-10 ~ 08-12,与上文冲突时以本节为准)

- **roster**:小丑牌 **39 张现役 / 60 张已定稿**(Target 7 + Support 32;19 张待引擎波次);
  盲注 **24 压力 + 赶场 + 4 boon** 全实装,`gate.sh` 上次全量绿在盲注批(08-11)。
- **真人数据**:**不再是零** —— 2013 份 Tape 里分拣出 **11 局合格真人局**
  (分拣判据与账本见 `tools/probbook.py`),已用于 Target 重锚与 bonus 族定价。
- **数值制度**:定价宪法 `design/numbers.md`(三轴模型+六步 SOP)+ 概率账本
  `design/probbook.md`(设计/仪器/真人三列,`python3 tools/probbook.py <sim日志>` 重刷)。
  bonus 族已按 v2 落地(支配序:会玩>保底>赌狗);**复审名单:快闪/伴唱/排练**(结构死卡)。
- **美术**:全部接线(主角八人立绘/行走/舞步、小丑牌 source 原画直出、盲注指纹卡、
  首页玻璃素材壳+顶栏膜);previews/cards 两目录已退役不进包。
- **Web 版**:`godot --headless --path . --export-release Web build/web/index.html`
  (先 --import;模板 4.6.2 已装机)。本地试玩:`python3 tools/webserve.py`(**HTTPS**,自签证书自动生成),
  手机同 WiFi 开 `https://<Mac IP>:8765`,首次点"继续访问"即可(Safari:显示详细信息→
  访问此网站;Chrome:高级→继续前往);换 WiFi 后删 `build/cert/` 重跑。包 147MB(pck 116MB;瘦身后账:立绘转 WebP)。
- **Android**:SDK/JDK 已装,导出模板在 tpz 里 —— 差 keystore/预设/出包(TapTap 线,
  试玩版免版号路线已调研,见 08-12 对话与 TODO)。
- **新工具**:`tools/probbook.py`(概率账本)· `tools/art/fontsubset.sh`(Web 中文字体子集,
  文案加新字要重跑)· `tools/art/glassprobe.gd` / `glassfilm.gd` / `blind_fp_extract.py`。
- **观察点(下轮 Tape 回答)**:① 回响 +240 能不能把真人"保型"触发率从 11% 抬向 0.35;
  ② 锁定时机体感(lock_offset 已归零);③ 阶梯 ×13 实战回评。
