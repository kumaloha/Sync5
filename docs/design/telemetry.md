# 打点(Tape)

**状态:§0 已实装(2026-08-06,`core/tape.gd` + `data/tape.json`)。**
§1 起是 2026-08 之前写的分析愿景,**保留为存档**——它的三级事件清单基本被 §0 覆盖,
指标/验证问题两节仍然未做(那是分析侧的活,不是采集侧)。

---

## 0. 实装规格(2026-08-06)

### 0.1 为什么做

`SECTION_TARGETS` 2026-08-05 起已经换成**人锚**(真人产出比机器人高约一个数量级),
但真人这一侧一直没有账本 —— `tools/report.gd` 只覆盖机器人。G/D 对抗校准(`docs/design/history_adversarial.md`、17)
的 loss 要拿真人实测跟预测对账,这条日志流就是那份实测数据的来源。

三个用途,按重要性:
1. **G/D 校准的真人锚** —— `docs/design/history_parametric.md` §6 第 3 问「真机埋 (s,a) 日志」的答案就是这个模块;
2. **数值平衡** —— 经济流水、商店购买力、牌型分布、小丑牌触发率;
3. **流程 QA** —— `flow_probe` 只能在 headless 里守不变量,真人手里的异常
   (2026-08-05 那次「连点跳段」)只能靠事件序列回看。

### 0.2 口径铁律:只记事实,不记特征

> 2026-08-06 用户拍板:「记录事实,G/D 那边的系统自己去读。
> 至于做成他需要的特征的样子,**特征是会迭代的,你记录了反而不好做**。」

**判据:发生过的判定 = 事实(记);没发生的假设 = 特征(不记)。**

- 据此**删掉**过 `beat.best0`(「不动手会是什么牌型」):它是反事实、可从 `hand` 推,
  而且值依赖当时的牌型表和 `Deck.rules` —— 牌型表 2026-08-06 刚改过一次(抄 Balatro),
  老日志的 `best0` 会和同一行的 `hand` 打架**且不报错**。
- 据此 `settle` 的 `kind/base/mult/bonus` **保留**:分数就是按它们入的账,它们是**账本本身**,
  要复现得重跑整条 joker DSL 链。

**事实完整性的判据 = 能不能重放出任意时刻的局面。**

### 0.3 事件表(21 类)

每条事件都自带 `n`(run 内序号,从 0)/ `ms`(run 内相对毫秒)/ `e`(事件名)。
⚠ **payload 不许用这三个键**,元字段后写会静默盖掉它们(`Tape.on()` 撞名会 `push_error`)。

| e | 何时 | payload |
|---|---|---|
| `run` | 开局 | `char`, `cn`, `faces`, `targets`, `coins`, `struct{sec,pps,ppshop,dur}`, `retry?` |
| `sec` | 进段 | `i`, `target`, `face`, `wall`, `coins` |
| `intro` | 公示卡关闭 | `skip`(true=玩家点掉 / false=等它自动关) |
| `beat` | 起拍 | `i`(全局拍号), `p`(段内), `dur`, `coins`, `hand[5]`, `cache[3]` |
| `pick` | 点选 | `z`(hand/cache), `i`, `on`(true=选中 false=取消), `at` |
| `swap` | 对调 | `h`, `c`, `at` |
| `sort` | 理牌 | `at` |
| `disc` | 弃牌 | `k`(张数), `h`, `c`, `cost`, `coins`, **`cards`(弃掉的)**, **`got`(补进来的)**, `at` |
| `deny` | 动作被拒 | `why`(empty/coins/price/reroll/replace), `k?`, `at?` |
| `settle` | 结算 | `kind`, `chips`, `base`, `mult`, `bonus`, `score`, `coin`, `total`, `disc`, `late`, `act`, `mod`, `cards[5]`, `fired[]` |
| `sec_end` | 段末判定 | `i`, `score`, `target`, `ok`, `coins`, `beats` |
| `shop` | 开店 | `mid`, `sec`, `coins`, `offer[{id,kind,rarity,price,aff}]`, `slots[4]`, `left`, `need` |
| `buy` | 买入 | `id`, `kind`, `price`, `coins` |
| `repl_open` | 进入替换 | `id`, `price`, `coins`, `slots[4]` |
| `repl_off` | 取消替换 | `id`, `coins` |
| `repl` | 完成替换 | `in`, `out`, `slot`, `price`, `back`, `coins` |
| `rerl` | 刷新 | `k`(第几次), `cost`, `coins` |
| `leave` | 继续 ▸ | `coins` |
| `focus` | 切前后台 | `on`, `at` |
| `nav` | 界面跳转 | `to`(home/pick/retry/back) |
| `close` | run 终 | `ok`, `sec`, `score`, `target`, `beats` |

三条口径上的取舍:

- **`settle` 是最重的一条**。`fired` 记 joker **id 而不是 popup 文案** —— 只有 id 能和
  `report.gd` 的 `trigger_n` 直接对齐,文案改一个字就对不上。主角用 `@character`。
- **失败动作也要打**(`deny`)。只记成交会把「想弃但弃不起」这个挫败点和购买力压力整个漏掉,
  而那正是弃牌定价和商店经济的直接证据。同理 `repl_off` —— 只记成交就分不出
  「换不起」和「不值得换」。
- **`shop` 分段中/段末两态**(`mid`)。段中是「已知缺口下的解题」、段末是「对下一场下注」,
  买牌行为本就不该混在一起看(docs/design/levels.md 的核心论证)。

`run` 事件里**连结构参数一起记**(`struct`):表会改,老日志不能被新结构的口径误读。

### 0.4 不记什么,以及为什么不记

**不打**每帧计时、动画、渲染、指针移动 —— 只打决策与状态转移。

下面这些是**可推导**的,按 §0.2 的铁律一律不记:

| 项 | 怎么推 |
|---|---|
| 金币余额全程 | `beat`/`disc`/`buy`/`repl`/`rerl` 记余额,`settle` 记增量,段末工资固定 +3,入场费可反推 |
| 牌堆内容与重洗时刻 | 露过面的牌全记了(`beat.hand/cache` + `disc.got`) |
| 小丑牌成长计数器 | 只挂弃牌(有 `disc`)与拍末 `early_finish`(判据是 `settle.act`) |
| 规则牌 / 大小王入池 | 从 `buy`/`repl` 的 id 推 |
| Boss 脸的具体效果 | `settle.mod` + `data/faces.json` |
| 每拍实际耗时 | 相邻事件 `ms` 差 |
| 选中集合 | `pick` 序列前向累积;拖拽与弃牌导致的清空是 `swap`/`disc` 的必然后果 |
| 理牌后的顺序 | 确定性排序(rank desc, suit desc) |

### 0.5 流的形状与不变量

- **一 run 一个文件**:`user://tape/run_<秒级时间戳>_<进程内序号>.jsonl`。
  序号不是装饰 —— 时间戳只到秒,工具一秒能开好几局。
- **首事件必是 `run`**。开局前的 `nav`(首页/选角)不属于任何一局,`begin()` 会丢掉它们。
- **正常结束的末事件必是 `close`**,`close()` 之后 sink 关闭。
- **半途退出的 run 有事件、没有 `close`** —— 那本身就是「玩家弃局」的信号,**别去补假收尾**。
- `sec` 的 `i` 只能 0→1→2→3,断号 = 流程 bug(2026-08-05 那次连点跳段就长这样)。

### 0.6 开关与读法

配置全在 `data/tape.json`(`core/db.gd` 硬校验):`enabled` 总开关 / `to_file` 落盘 /
`dir` / `max_events`(满了就落盘,纯内存模式下退化成环形缓冲)/ `mute`(按事件名屏蔽)。

```bash
python3 -c "import json,sys;[print(json.loads(l)['e'], json.dumps(json.loads(l),ensure_ascii=False)) for l in open(sys.argv[1])]" <文件>
```

macOS 路径:`~/Library/Application Support/Godot/app_userdata/Sync5 · Project Rhythm/tape/`

### 0.7 架构约束

- **打点只在编排器打**(`view/phrase.gd` 调 `Tape.on()`),和「金币/装槽等经济动作只发生在
  编排器」同一条线 —— 组件各打各的必然打重、打漏。组件要上报就**发信号**:
  `shop.denied(why)` 和 `hand.card_picked(zone,i,on)` 都是为此加的。
- `card_picked` **不复用 `selection_changed`**:后者是重绘信号、连着无参的 `_refresh()`,
  改签名会打断连接;而且「重画一下」不该兼职说明发生了什么。
- `core/tape.gd` 守 core/ 铁律:不含时钟(毫秒由 `Time` 静态取**且可注入**,测试才断言得了)、
  不 import view、除 `Card`/`Joker` 外不认识任何游戏对象。

### 0.8 踩过的坑(全是看真实输出才发现的)

1. **run_id 只到秒** → 探针一秒开几局会追加进同一个文件,一个文件两条 `run`。加了进程内自增序号。
2. **`user://logs/` 是 Godot 引擎自己**写 `godot.log` 的地方,还会按 `max_files` 轮转删除。
   改落 `user://tape/`。
3. **`close()` 必须关掉 sink**,否则结算屏之后的「返回主页」`nav` 会继续追加进已收尾的文件。
4. **payload 撞保留字会被静默吞掉**:`disc` 的张数曾用 `n`,被序号吃了整整一轮,
   而 `cost` 恰好等于张数,肉眼读日志看上去还是对的。改名 `k`,并让 `Tape.on()` 撞名报错。
5. **探针断言用 `d["k"]` 在字段整个消失时是静默放过的** —— 改用 `d.get("k", -1)` 哨兵值。
6. **`quit()` 不等 `PREDELETE`** —— 探针不 `Tape.flush()` 就只有内存里那份,
   「日志真写得出来」等于没验(踩过:探针全绿而文件是空的)。

> **教训(本模块反复吃到两次):测试绿 ≠ 事情成了。**
> 采集类代码必须去读它真正产出的文件,而且要让探针跑到那条路径上 ——
> ①④⑥ 三个坑全都是「所有自动检查都通过」的状态下靠人眼看输出发现的。

### 0.9 回归

| 命令 | 守什么 |
|---|---|
| `tests/runner.gd` | Tape 单元契约(JSON 往返、元字段防覆盖、时钟注入、环形缓冲、close 边界、DB 校验) |
| `tools/flow_probe.gd` | 流程不变量(顺带产出多局真实日志) |
| `tools/tapeprobe.gd` | **重放链**:`disc` 的 `cards`/`got` 长度 == `k` 且无交集;点选分得出选中/取消;公示卡、替换流程的进入与取消都留痕;流的形状 |

基线 **361 passed**,两个探针 0 违规。`tapeprobe` 的每条断言都做过 A/B(逐条注掉打点确认报警)。

**只有真机能验的两条**:`focus` 切前后台、关窗 flush —— 都要真实窗口焦点,headless 碰不到。

### 0.10 未做

- **步级表二**(`docs/design/history_parametric.md` §4:`φ(a_t,s_t), π_t, a_t, R_t`)—— 给 REINFORCE 用,量大。
  行为克隆(C2)不需要它,φ 可离线算;而且按 §0.2 的铁律它更可疑:**存 φ 就是把一版
  特征定义冻进日志**。等 `docs/design/history_parametric.md` §6 拍板。
- `early_settle()` 提前锁定 —— 钩子在,UI 还没接,接上就要记。
- **会话边界**(一次坐下玩了几局、隔多久回来)—— 跨 run,不属于「一局一文件」模型,
  要做得单开一条 session 流。那是留存指标,不是 G/D 的输入。
- 下面 §1 起愿景里的 **near miss 类型**(差一张能成什么)—— 要现算,较重;
  需要时可从 `beat.hand` + `disc` 序列离线补算。
- **指标与验证问题两节全部未做** —— 那是分析侧,采集侧已经把料备齐。

---

## 1. (存档)Phrase events

Record:

- initial cards
- Initial Best
- every draw time and cost
- Candidate destination  ← 候选牌机制已作废,不适用
- every Hand ↔ Cache swap
- Final Best
- last action time
- improvement or regression
- near miss type
- character/Joker triggers
- score and coin change

## 2. (存档)Section events

- target score
- completion ratio
- Phrase score distribution
- Joker offer and choice
- refresh and skip
- remaining coins
- Cache use and conversion

## 3. (存档)Run events

- character
- Target Joker
- Support Jokers
- dominant risk tendency
- pattern distribution
- best hand
- duration
- failure Section
- replay behavior

## 4. (存档)Skill metrics — 未做

| Skill | Observable data |
|---|---|
| local optimum recognition | early recognition and low unnecessary movement |
| risk judgment | draw count vs improvement probability |
| stopping | draws after failed improvement |
| economy | score gained per coin |
| planning | Cache use and later conversion |
| rule adaptation | behavior shift after Joker |
| flexibility | pattern and route diversity |

## 5. (存档)Core validation — 未做

- Do players act in the final second?
- Do paid draws improve outcomes often enough to feel fair?
- Does Cache create real cross-Phrase planning?
- Does a Joker change behavior within 1–3 Phrases?
- Does mastery increase release?
- Do players immediately continue after settlement?
- Does Run end produce replay intent?

---

## 附:从 `CLAUDE.md` 迁来的完整口径推导(2026-08-09)

> 逐字迁移,未压缩。与 §0.2 / §0.3 / §0.4 / §0.8 有重叠 —— 保留全文是因为这里记着
> **每一类事件「为什么补」的理由**(点选看不到跨区试探 · `repl_off` 分不出换不起还是不值得换 ·
> `intro.skipped` 是「急着打 vs 在读规则」· `focus` 在手机上不是边角情况),那些理由在上面几节里是散的。

接 `../CLAUDE.md` 的「判据:**发生过的判定 = 事实(记);没发生的假设 =」那一行:

  特征(不记)**。据此删掉过 `beat.best0`(「不动手会是什么牌型」是反事实,能从 hand 推,
  且它的值依赖当时的牌型表和 `Deck.rules` —— 牌型表 2026-08-06 刚改过一次,老日志的 best0
  会和同一行的 hand 打架且不报错)。反过来 `settle` 的 kind/base/mult/bonus **要记**:
  分数就是按它们入的账,是账本本身,要复现还得重跑整条 joker DSL 链。
  **事实完整性的判据 = 能不能重放出任意时刻的局面**。唯一不可推导的是**弃牌补进来的牌**
  (随机),所以 `disc` 必须同时记 `cards`(弃掉的)和 `got`(补进来的)——
  少了 got,一拍内第一次弃牌之后手牌就断链,而那正是同拍后续动作的局面,
  行为克隆要的 (s,a) 全卡在这里。其余可推:对调记索引(集合不变)、理牌是确定性排序、
  动作先后有 n/ms、小丑牌成长计数器挂在弃牌与拍末(两者都有日志)、金币流水闭合
  (beat/disc/buy/repl/rerl 记余额,settle 记增量,段末工资固定,入场费可反推)、
  牌堆与重洗时刻可算(露过面的牌全记了)、规则牌与大小王入池从 buy/repl 的 id 推、
  Boss 脸效果从 `settle.mod` + faces.json 推。
  **2026-08-06 补齐的四类**(用户:「文件翻倍不是什么问题,点选也要」):
  ① **`pick` 点选**——原本唯一一整类不可见的玩家动作(从 disc 只看得到最终提交的集合,
  看不到选了又取消、跨区试探);为它给 `hand.gd` 加了独立信号 `card_picked(zone,i,on)`,
  **不复用 `selection_changed`**——那是重绘信号、连着无参的 `_refresh()`,改签名会打断连接,
  而且「重画一下」本来就不该兼职说明发生了什么;
  ② **`repl_open`/`repl_off` 替换流程的进入与取消**——后 3 次商店 100% 是替换场景,
  只记成交和差钱,分不出「换不起」还是「不值得换」;
  ③ **`intro` 公示卡**——`done` 信号分不出「玩家点掉的」和「等它自己走完」(intro 有 `_auto`
  超时自动关),所以在 `intro.gd` 加 `skipped` 标志;这是「急着打 vs 在读规则」的信号,
  也是教学空间那个待验问题的观测点;
  ④ **`focus` 切前后台**——单拍只有 8 秒,中途切出去一下,那一拍的 `at`/`act` 和相邻 `ms` 差
  全是脏的,不留痕就分辨不出来(手机上这不是边角情况);失焦顺手 flush,后台进程会被系统杀。
  ⚠ 四个踩过的坑,全是**看了真实输出/让探针跑到那条路径**才发现的(别只跑测试):
  ① run_id 只到秒,探针一秒开几局会**追加进同一个文件**(现在加了进程内自增序号);
  ② `user://logs/` 是 **Godot 引擎自己**写 `godot.log` 的地方、还会按 `max_files` 轮转删除,
  所以落在 `user://tape/`;③ `close()` 必须把 sink 关掉,否则结算屏之后的「返回主页」nav
  会继续追加进已收尾的文件;④ **payload 不许用保留字 `n`/`ms`/`e`** —— 元字段后写会把它们
  静默盖掉,`disc` 的张数曾用 `n` 装、被序号吃了整整一轮,而 `cost` 恰好等于张数,
  输出看上去还是对的(现改名 `k`,且 `Tape.on()` 撞名会 `push_error` 喊出来)。

---

## 验证方案

| 验什么 | 怎么验 |
|---|---|
| **21 类事件都在打** | `tapeprobe`(已并进 `gate.sh`) |
| **能重放出决策问题** | `tools/replay.gd` —— **L2 完备性门**,非零退出,已进 `gate.sh` |
| **不含时钟** | `core/tape.gd` 的毫秒由 `Time` 静态取且**可注入**,测试才断言得了 |
| **payload 不撞保留字** | `Tape.on()` 撞名会 `push_error` 喊出来 |

### 口径铁律 = **只记事实,不记特征**

> 用户 2026-08-06:「记录事实,G/D 那边自己去读。特征是会迭代的,你记录了反而不好做。」

**判据:发生过的判定 = 事实(记);没发生的假设 = 特征(不记)。**

据此删过 `beat.best0`(「不动手会是什么牌型」是反事实,能从 hand 推,
且它的值依赖当时的牌型表 —— 牌型表改过之后,老日志的 `best0` 会和同一行的 `hand` **打架且不报错**)。

反过来 `settle` 的 kind/base/mult/bonus **要记**:分数就是按它们入的账,
**那是账本本身**,要复现还得重跑整条 joker DSL 链。

### 完整性的判据 = **能不能重放出任意时刻的局面**

唯一不可推导的是**弃牌补进来的牌**(随机),所以 `disc` 必须同时记
`cards`(弃掉的)和 `got`(补进来的)—— 少了 `got`,一拍内第一次弃牌之后手牌就断链。

### ⚠ 四个踩过的坑,全是**看了真实输出**才发现的(别只跑测试)

1. `run_id` 只到秒,探针一秒开几局会**追加进同一个文件** → 加了进程内自增序号
2. `user://logs/` 是 **Godot 引擎自己**写 `godot.log` 的地方、还会轮转删除 → 落在 `user://tape/`
3. `close()` 必须把 sink 关掉,否则结算屏之后的「返回主页」nav 会继续追加进已收尾的文件
4. **payload 不许用保留字 `n`/`ms`/`e`** —— 元字段后写会把它们**静默盖掉**。
   `disc` 的张数曾用 `n` 装、被序号吃了整整一轮,而 `cost` 恰好等于张数,**输出看上去还是对的**

### ⚠⚠ 采集侧已实装,分析侧一行没有

磁盘上 1067 局日志**全部是探针产物**。见 [`../STATUS.md`](../../STATUS.md)。
