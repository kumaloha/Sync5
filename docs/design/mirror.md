# Sync5 · Lua 镜像(TapMaker 版)—— 手工镜像 + 机械门

> **2026-09-06 用户拍板。** 分工:**本仓库是唯一真源**,我写 `lua/`,TapMaker 侧的 agent 从 GitHub 拉、
> 自己读、自己搬进她的 `scaffold-2d.lua`(urhox-libs/UI,Yoga Flexbox + NanoVG)。
> 「同步」= **规则 / 数值 / 内容长期同步**;存档互通**不做**(要账号后端,与「纯单机离线」的发行形态冲突)。
> 用户原话:「我的建议是你写好,我给她 github 就可以了」「你能用 scaffold-2d.lua 做完,让她自己读,自己搬」「手工镜像 + 机械门 这个可以」。

---

## 0. 一页纸

- **三层同步**:① 数据共用(同一份 `data/*.json`)· ② 逻辑镜像(`core/*.gd` ↔ `lua/core/*.lua` 逐文件同名)· ③ 金样对拍(Godot 生成、Lua 重放、逐位相同)+ 覆盖门(每个文件、每个公开函数都有孪生,缺一个红)。
- **⚑ 判据:镜像不许手抄数字。** Lua 侧需要的每一个数都必须来自 `lua/data/`;抄不进去的,搬进 JSON。这与「机器人的倍率从 jokers.json 推导,不许再手抄第二份」是同一条铁律。
- **我不写渲染。** urhox-libs 的接口没有公开资料,盲写的代码验不了。编排层向外给「该画什么」的状态表、向内收「玩家做了什么」的意图,她写 Yoga/NanoVG 那层。
- **代价认下**:今后每条规则改动两边都要动,门保证不会忘,但不会变免费;改数据零成本(而日常调平衡全是改数据)。

---

## 1. 三条路,为什么是①

| 路 | 一句话 | 为什么不选 |
|---|---|---|
| **① 手工镜像 + 机械门(选)** | 逐文件写成 Lua,金样对拍,覆盖门守孪生 | 付两份规则税,但税是显性的、门会报 |
| ② GDScript → Lua 转译器 | 一份源码两边生成 | 7.7k 行里 14 处 lambda、167 处 `%s`、typed Array、字典语义;转译器本身是一个项目,**而且它的 bug 不报错** |
| ③ 共享原生库(C/Rust,GDExtension + Lua FFI) | 一份二进制两边调 | TapMaker 是沙箱 Lua + 远程构建,几乎肯定装不了原生模块;Godot 侧也得重写 |

---

## 2. 范围:搬什么、不搬什么

| `core/` 文件 | 搬? | 备注 |
|---|---|---|
| card / deck / pattern / settle / fx / joker / consumable / economy / modifier / blind_boon / beat / phrase / run / director / tutorial / config | **搬,逐文件同名** | 规则本体 |
| db | **只搬访问器** | 1.4k 行校验是**测试期门禁**(`core/db.gd` 文件头),数据在 Godot 侧过检后共享,镜像消费的是已验证的数据 |
| lingo | 搬 `t()` + 数据 | 语言判定注入(她接 UrhoX 的 locale) |
| save | **只搬纯函数层**(体力闸门、快照 schema、版本迁移) | 存储注入:`storage.get/set(key, string)`,她接云变量或本地存档 |
| tape | 搬**事实记录**(内存队列) | 毫秒由注入时钟给;写文件与上传不搬。它同时是金样摘要的输入 |
| uplink | **不搬** | 回传通道缺省关、等端点 |

| `view/` | 搬? | 备注 |
|---|---|---|
| `phrase.gd` 的**编排逻辑**(开局三步、拍钟、每 3 拍开店、经济动作、结算、段末、终局、教学门、打点、待播队列) | **搬成 `lua/app/phrase.lua`** | 那是规则的一部分,不能让她重写 |
| 其余全部(widgets / fxburst / run_end / home / shop / hand / …) | **不搬** | 「怎么画」属于渲染器;给她 `ui_meta.md` + `docs/mockups/*.html` + 视图契约 |

**v1 的界面范围**:首页 → 公示卡 → 对局(手牌/缓存/小丑槽/盲注卡/唱片位/HUD)→ 商店 → 结算两屏 → 教学关。**图鉴(album)放 v2**。

---

## 3. 目录(一词化,无下划线)

```
lua/
  README.md          给她的中文说明:目的、目录、怎么 require、怎么跑对拍、契约、别碰什么
  core/*.lua         core/ 的镜像,文件名与 class_name 一一对应(deck.lua ↔ Deck)
  num.lua            数值语义助手(见 §5)
  rng.lua            Godot PCG32 的复刻(见 §5)
  data/*.lua         由 tools/luagen.py 从 data/*.json 生成 —— 仪器输出,手改无效
  golden/*.lua       由 tools/golden.gd 生成 —— 仪器输出,手改无效
  app/phrase.lua     编排层(时钟 / 存储 / locale 注入;view() / intents / events 契约)
  app/CONTRACT.md    视图契约(状态表字段、意图清单、一次性事件清单、坐标与色板的出处)
  check.lua          一条命令跑全部对拍:lua lua/check.lua(秒级)
```

她整目录拷进自己项目的 `scripts/` 下即可。模块内部一律**相对 require**(`(...):match("(.-)[^%.]+$")` 取自己的前缀),不依赖她的 `package.path`。

---

## 4. 数据共用

- `data/*.json` 仍是**唯一可编辑**的内容;`tools/luagen.py` 生成 `lua/data/<name>.lua`(`return {...}`),Lua 侧**零解析依赖**。
- 按 `ranking.json` 的规矩:**生成物手改无效**;`python3 tools/luagen.py --check` 比对「重生成 == 已提交」,进 CLAUDE.md 那行秒级预检。
- 生成器的三条语义:JSON 数组 → Lua 序列(1 基,见 §5 索引规矩);对象 → 字符串键表;**数组里的 `null` → 哨兵 `NULL`**(nil 会把序列截断)。整数/浮点按 JSON 原样写(`3` 与 `3.0` 不互转;Lua 5.3+ 分整数与浮点子类型)。
- 数据顺序:核心的数据遍历**全部走数组**(`for e in DB.jokers()` 等,已 grep 核对),没有依赖字典插入顺序的地方。若今后出现,整局重放金样会当场红,再补 `__keys`。

**⚑ 「镜像不许手抄数字」筛出的四处,搬进 JSON(各自一个提交)**:

| 现在在代码里 | 搬去 | 时机 |
|---|---|---|
| 牌型表 `Pattern.BASE_CHIPS` / `BASE_MULT` / `NAMES`(`core/pattern.gd`,文件里写着「另案, 别顺手动」—— 这次**就是那个另案**) | `data/patterns.json`;`Pattern.BASE_*` 改成从 DB 读的 `static var`,调用方语法不变(`runner.gd` 里「牌型倍率从 BASE_MULT 推导」的测试因此照旧) | 第 1 段 |
| `GameConfig.RESOLVE_FEEDBACK = 0.25`(`core/config.gd`) | `run.json` | 第 3 段 |
| 色板 21 个常量(`view/theme.gd`) | `data/theme.json`;`StageTheme.CYAN` 等改成从 DB 读,调用方不变。CLAUDE.md「以 `view/theme.gd` 为准」那句改指 JSON | 第 4 段 |
| 15 处一次性装配坐标(`view/layout.gd`,文件头已承认是待办) | `ui.json` 的 `stage` 节 | 第 4 段(写契约时顺手) |

**不搬的**:`widgets.gd` 712 个数字、`fxburst.gd` 649 个、`run_end.gd` 628 个 —— 玻璃剖面、辉光半径、动画时长,是「怎么画」。它们属于渲染器,由 `ui_meta.md` 与设计稿承担。

---

## 5. 核心镜像的规矩

**同名。** 类名 = 模块名(`Deck`),函数名逐字相同(`Deck.new(seed)` / `deck:draw()`),静态函数写成模块函数,枚举值同名同值(`Pattern.Kind.HIGH_CARD`)。覆盖门(§7)靠这条做机械比对。

**数值语义走 `num.lua`,不许裸写。** GDScript 与 Lua 在这几处**默默分叉**:

| GDScript | Lua 原生 | `num.lua` |
|---|---|---|
| `int(x)` 向零截断 | `math.floor` 向下 | `num.int(x)` |
| `round(x)` 半数远离零 | 没有 round | `num.round(x)` |
| 整数 `/` 向零截断(C 语义) | `//` 向下取整 | `num.idiv(a, b)` |
| 整数 `%` 取被除数符号(C 语义) | `%` 取除数符号 | `num.imod(a, b)` |
| `float` = double | number = double | 同,**操作顺序照抄**即逐位相同 |
| `maxi/mini/clampi/floor/ceil` | 有 | 直接映射 |

**索引规矩。** Lua 内部 1 基;**跨契约的一切索引一律 0 基**(意图里的 `hand_indices`、`ui.json` 的 `patterns` 键、金样、Tape 事实),在边界 `+1`。理由:和 Godot、和 JSON 里的键、和已有日志口径一致,她那边读 Tape 或对金样时不用换脑子。

**随机数:照搬 Godot 4.6 的 PCG32**(`core/math/random_pcg.{h,cpp}`),Godot 侧种子基线**一个都不换**。
- 用 **32 位肢体**实现 64 位乘加,配一个位运算垫片(`bit` / `bit32` / 5.3+ 运算符三选一,5.3+ 那支用 `load` 延迟解析,免得 `&` 在 5.1 里是语法错误)⇒ **5.1 / LuaJIT / 5.3 / 5.4 都能跑**,Lua 版本不用问。
- `seed(s)`:state=0 → 走一步 → state += s → 走一步(`pcg32_srandom_r`);`inc` 用 Godot 的缺省。
- `randi_range(a, b)`:Godot 的 `random(int, int)` + `pcg32_boundedrand_r`(拒绝采样,阈值 `-bound % bound`),**逐行搬**,不自己写「更简单的」。
- ⚠⚠ **`randf()` 是两步 + float32**:Godot 4 的 canonical 法先 `rand()` 取指数偏移(0 时返回 0),再 `ldexp((float)(rand() | 0x80000001), -32 - clz32(offset))`。`director.gd:373` 量到的「randf 消耗两步」就是它。**`(float)` 那一步把 32 位整数舍入到 24 位尾数**,Lua 没有 float32,要手写 round-to-nearest-even 再 ldexp。双精度那支三步。这是最容易做出「差一个 ulp」的地方,rng 金样专门覆盖。
- `state` 可读写(存档快照用),Lua 侧用 `{hi, lo}` 两个 32 位或字符串十六进制表示,金样里一律十六进制字符串。

**容器映射。** `Dictionary` → 表;`Array` → 序列;`.duplicate(true)` → 递归拷贝助手;`typeof` 分支 → `type()` + 整数/浮点判别(`math.type`,5.1 下退化为整数性检查)。`Callable`/lambda(14 处)→ 闭包。

**排序。** 核心只有整数数组 `.sort()` 与 `hand.sort_custom(Card.sort_desc)`。整数排序无歧义;`Card.sort_desc` 若存在并列(同点同花不可能,但万能牌可能),在**两边同时**补索引级平局规则 —— 规则不许依赖不稳定排序的实现细节,`table.sort` 与 Godot 的 introsort 在并列上的行为都不可复现。

**字符串。** `%s` 格式化只在 Tape / 文案 / 调试用;数值进文案前一律走 `Lingo.t()` 或契约给出的整数,**格式化留给渲染侧**。
**摘要里的浮点用 IEEE 位串**(`num.f64hex` ↔ Godot `PackedFloat64Array.to_byte_array()`), 不用 `%.10f` —— 两边 printf 的最后一位不可信, 位串逐位相同才算过(实施时改的, 09-06)。
整值一律按整数印(`canon`:`v == floor(v)` ⇒ `%d`), 因为 LuaJIT 分不出 3 与 3.0。

---

## 6. 金样对拍,五族

`tools/golden.gd`(headless Godot 探针)生成 `lua/golden/<族>.lua`;`lua lua/check.lua` 逐条重放比对。**每一族的比对标准 = 字符串逐字相同。**

| 族 | 输入(写在金样里) | 期望(Godot 算的) | 守什么 |
|---|---|---|---|
| **rng** | 若干种子 × 一条混合调用序列(`randi` / `randi_range(a,b)` / `randf` / 读写 `state`;GDScript 不暴露双精度那支, 镜像照样实现但不入金样) | 每次调用的返回值 | §5 的 PCG32 复刻,含 float32 舍入 |
| **pattern** | 随机手牌(含 0~4 张万能牌、规则牌位 `RULE_BITS` 各组合) | `kind / chips / pmult / score` + 选中的五张 | `_classify` 与 `_score_many_wilds` 捷径 |
| **settle** | 随机结算上下文(牌型、槽内小丑与 state、脸、增益、`extra`、预掷的 `rolls`) | 分数、金币、每个小丑的 state 变化 | 乘法链顺序与舍入(`settle.gd` §「aggregate rounding」) |
| **fx** | 每张小丑牌 / 消耗牌 × 它每条 `effects` 的触发场景 | 结算差分 + `on_*` 钩子后的 state | DSL 解释器逐操作码覆盖(**每个操作码至少一条**,新操作码没金样 = 红) |
| **run** | 种子 + Bot 打出的整局动作序列(`RunLoop` + `bot.gd` 生成,Lua 侧不需要 bot) | 每一拍结束后的**状态摘要** | 整条链:开局三步 → 拍 → 商店 → 段末 → 终局;含教学关一局 |

**状态摘要 `digest()`**,两边各自实现、同一定义:`section_idx · phrase_in_section · phrase_index · section_score · coins · debt · deck.rng.state(hex) · 牌堆顺序 · 手牌 · 缓存 · 弃牌堆 · 槽(id + state 按键名排序)· 待播队列 · 货架 · face · boon · mod · prev_kind · tape 事件计数`,用 `|` 拼成一行。只含整数、`%.10f` 浮点、字符串。

**规模(实施值, 09-06)**:rng 20 种子 × 200 步 · pattern 1500 手 × 11 项(四成带万能;全带时 Lua 5.5 重放要 30 s)· settle 1200 例 ·
fx = 64 卡 × 16 上下文 + 钩子序列 + 40 组槽统计/经济 + 59 脸参数电池 + 120 次掷脸 + 消耗牌 + 增益 + 配置常量, 附 DSL 操作码覆盖断言 ·
run 30 局(3 局教学)逐拍摘要 1260 条。合计 **27397 条**, LuaJIT ≈ 3.5 s、Lua 5.5 ≈ 9.5 s(pattern 占九成)。金样文件共 ≈ 3.8 MB(2000/24 例的初版 5.6 MB, 按仓库体积裁到 1200/16)。

**重生成时机**:改了 `core/` 就重生成(它是 Godot 侧的真相,不是 Lua 侧的);重生成后 `check.lua` 红 = 该搬了。

---

## 7. 覆盖门 `tools/mirror.py --check`

- `core/` 下每个 `.gd` 在 `lua/core/` 有同名 `.lua`,每个**公开** `func`(不带 `_` 前缀)在孪生里有同名 `function`;`db.gd` 只查访问器清单,`save.gd` 只查纯函数清单,`uplink.gd` 豁免(清单写在脚本顶部,和 `parity.py` 的键表一个形状)。
- `view/phrase.gd` 的编排函数按一份**显式清单**查 `lua/app/phrase.lua`(它还有大量节点函数,不能全查)。
- `lua/data/` 与 `data/` 文件一一对应(由 `luagen.py --check` 兼管)。
- `lua/golden/fx.lua` 覆盖 `fx.gd` 的每个操作码(操作码表从 `fx.gd` 抓)。

进秒级预检那一行:`parity.py --check && evsync.py --check && counts.py --check && luagen.py --check && mirror.py --check && lua lua/check.lua`。
⚑ 这道门的形状 = 「规则在游戏里,不在模型里,而且不报错」那类错在这条线上的翻版([LESSONS.md](../../LESSONS.md),踩过五次)。

---

## 8. 编排层与视图契约(`lua/app/`)

**注入三样**:`clock.now_ms()`(她每帧调 `app:tick(now_ms)`,编排层自己算拍钟、警告线、锁定线、早收线;没有定时器)· `storage.get/set(key, string)` · `env.locale()`。

**三条通道**:
- `app:view()` → **纯数据表**,每帧可读:`hud`(分/目标/金币/第几拍/进度/倒数)· `blind`(档位/序号/第 N 场/脸/增益)· `jokers[4]`(id/state 摘要/高亮)· `hand[5]` / `cache[3]`(牌/选中/待弃/盖面/锁定)· `vinyl`(待播碟列表或空转)· `shop`(货架 5 位、价格、可买、刷新价、盲注板两态)· `banner` · `tutorial`(focus 与文案键)· `screen`(home / intro / play / shop / end)。
- **意图**(纯函数,返回是否被接受 + 拒因键):`start_run / restart / skip_intro / tap_hand(i) / tap_cache(i) / drag_swap(h, c) / discard / sort / buy(shelf_i) / reroll / continue / replace(shelf_i, slot_i) / end_ack`。索引 0 基。
- `app:events()` → **一次性事件队列**,每帧取空:`settle{score, chain}` · `card_fly{from, to}` · `deny{reason}` · `disc_bought` · `disc_fired` · `section_clear` · `run_end{win}`。立即模式渲染需要单次触发,状态表给不了。

**坐标与样式的出处**:`ui.json`(720×1280 绝对坐标,Yoga 用 absolute 定位即可)· `theme.json`(色板)· `assets/fonts/`(Rajdhani)· `docs/design/ui_meta.md`(玻璃卡三件套、辉光、分层)· `docs/mockups/*.html`(她的语言就是 Flexbox,设计稿到她那边的距离比到 Godot 近)。

**她的那层只做两件事**:读 `view()` 画、把手势翻成意图。**规则、经济、计时、打点一行都不在渲染层**(和 Godot 侧「经济动作只发生在编排器」同一条线)。

---

## 9. 给她的 `lua/README.md`

目的与分工 · 目录地图 · 相对 require 与整目录拷贝 · `lua lua/check.lua` 必须绿 · 契约在 `app/CONTRACT.md` · 别碰 `data/` 与 `golden/`(生成物)· 规则不许写在渲染层 · 同步方式 = `git pull` 后重跑 `check.lua`,红了说明她本地改过核心 · 存档接法(storage 两个函数)· locale 接法。全中文。

---

## 10. 工作流:改了什么,做什么

| 改了 | Godot 侧 | Lua 侧 | 门 |
|---|---|---|---|
| `data/*.json` | 单测 | `python3 tools/luagen.py` | `luagen.py --check` |
| `core/*.gd` | 单测 → `tools/golden.gd` 重生成 | `check.lua` 红 → 搬 → 绿 | `mirror.py` + `check.lua` |
| `view/phrase.gd` 编排逻辑 | 同上 | `app/phrase.lua` 同步 | `mirror.py` 清单 |
| `ui.json` / `theme.json` / 文案 | 渲染看图 | 无 | 她 pull |
| `view/` 其余 | 渲染看图 | 无 | 无(不同步,本来就不共用) |

---

## 11. 落地顺序与验收(我定;每段绿了才进下一段)

| 段 | 做什么 | 验收 |
|---|---|---|
| **0 工具链** | 本机装 Lua(`brew install lua luajit`,两种都跑)· `luagen.py` + `--check` · `num.lua` · `rng.lua` · `tools/golden.gd` 的 rng 族 · `check.lua` 骨架 | rng 金样在 5.4 与 LuaJIT 下都绿 |
| **1 牌** | `patterns.json` 搬家(独立提交,Godot 单测 `t_pattern`/`t_wild` 不动)· card / deck / pattern 镜像 · pattern 族 | pattern 金样绿;`Deck` 同种子同序 |
| **2 结算链** | config / db 访问器 / fx / joker / consumable / settle / economy / modifier / blind_boon · settle 与 fx 族 | 两族绿;fx 操作码全覆盖 |
| **3 一局** | run / beat / phrase / director / tutorial / tape / save 纯函数 · `RESOLVE_FEEDBACK` 搬家 · run 族(RunLoop + Bot 生成动作) | 30 局逐拍摘要相同 |
| **4 交付** | `app/phrase.lua` · `CONTRACT.md` · `README.md` · `theme.json` 与 layout 坐标搬家 · `mirror.py` 进预检行 · CLAUDE.md / STATUS / README 导览 · 推送 | 预检行全绿;她拉下来能 `require` 并跑 `check.lua` |

**状态(2026-09-06 一口气做完五段)**:0~4 全部落地。`lua/check.lua` 五族 27397 条 5.5 与 LuaJIT 双绿;`tools/mirror.py` 393 个公开/编排函数全有孪生;
`tools/drive.lua` 无头驱动整局(含教学关 / 商店 / 消耗牌 / 存档)两种 Lua 各 4 局跑通;Godot 侧四处「手抄数字」搬家(`patterns.json` / `theme.json` / `ui.json.stage` / `run.json.resolve_feedback`)前后截图逐件对照不动。
第 3 段顺手把货架组装从 `view/shop.gd` 抽成 `core/shelf.gd`(游戏 / 金样 / Lua 共用一份)。
**本地启动**(09-06 晚, 用户:「能在本地启动一下 lua 版本吗」):LÖVE 的 cask 被 Homebrew 停用 ⇒ 改用 Fengari(浏览器里的 Lua 5.3)——
`lua/web/index.html` 是契约的可运行范例(JS 只画画布与接鼠标), `tools/webbundle.py` 打包;教学关 → 商店 → 买 Target → 回拍全程点通。
它顺带验出两条运行时差异并落成机械:Fengari 整数只有 32 位(位运算垫片按 `math.maxinteger` 分宽度;牌型记忆键改浮点)· 页面切后台时一帧会吞掉整拍(编排层 dt 限幅 0.5 s)。

---

## 12. 代价与不做

- **付两份规则税**,门让它显性;数据税为零。
- **渲染我构造上验不了**,唯一证据是她跑起来的截图。
- ~~**商店的授予记账有三份**~~ **2026-09-09 已收口**:联票名额 / 免费刷新 / 折扣 / 挑高 / 5 选 1 计数 / 帕奇欧一次 / 离店清零全部住进 `core/shelf.gd::Shelf.Visit`(一次进店一个实例), view / `ShopSim` / `lua/app/shop.lua` 三方都是它的消费者;
  金样加了第六族 `visit`(87 步逐字段对拍), 整局族改后逐字节不变 ⇒ 「ShopSim = Lua」这条证明从此覆盖 view 用的同一份记账。`shop.gd` 公开名保留为委托, 探针与测试不用改名。
  ⚠ 认下的残余:整局金样里 `replace` 路径零覆盖(30 局采样 replace=0), 靠 `visit` 族直接测 `note_buy/stay` 补;截图逐像素对照做不到(舞台光效随时间、手牌随机), T2 用 12 步文本指纹(货架/价签/记账 8 字段/名额/碟位)改前改后逐行相同代替。
- 不做:存档互通 · 图鉴(v2)· Uplink · DB 校验镜像 · 转译器 · 任何「为了 Lua 好写而改规则」(同 CLAUDE.md 那条:不许为了模型好用改内容)。

---

## 13. 验证(本篇自己的)

三道机械门(§4 `luagen --check` · §6 `check.lua` · §7 `mirror.py`)全在秒级预检行里,**一条红就不许提交**。渲染那一半的验证在她那边:截图对 `docs/mockups/*.html`。

---

## 14. 开放问题(都不阻塞)

- 她的 Lua 版本(影响性能不影响正确性;`print(_VERSION, math.maxinteger, jit and jit.version)` 一行可知)。
- 她的运行时若禁 `load()`,位运算垫片改成发两份 `rng.lua`(5.1 版 / 5.3 版)。
- 她若更想读 JSON:JSON 仍在仓库里,但**契约是 `lua/data/`**,读 JSON 就要自己保证与生成物一致。
- 云变量的容量与延迟(存档快照多大、多久写一次)。
