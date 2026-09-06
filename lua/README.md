# Sync5 · Lua 镜像(TapMaker 版)

> 这目录是 Godot 版 `core/` 的**逐文件 Lua 孪生** + 生成的数据 + 金样对拍 + 编排层。规则、数值、内容与 Godot 版
> **长期同步**(规格 `docs/design/mirror.md`);渲染归你。5.1 / LuaJIT / 5.3+ 都能跑(位运算有垫片, 随机数用 32 位肢体复刻 Godot 的 PCG32)。

## 怎么用

1. 整目录拷进你的项目(例如 `scripts/sync5/`)。模块内部全是相对 `require`, 前缀随你放的位置走。
2. 接编排层:读 [`app/CONTRACT.md`](app/CONTRACT.md)。`tools/drive.lua` 是一个能从首页打到终局的无头驱动, 照它接。
3. 每次从 GitHub 拉了新版本, 先跑对拍:

```bash
lua lua/check.lua        # 或 luajit;五族金样逐位比对, 全绿才算与 Godot 同步(本机 ≈ 3~10 s)
lua lua/selftest.lua     # 数值语义与 64 位算术自测
lua lua/tools/drive.lua 1 3   # 无头跑 3 局
```

## 目录

| 路径 | 是什么 | 谁维护 |
|---|---|---|
| `core/*.lua` | `core/*.gd` 的镜像(同名类、同名函数);`shelf.lua` = 货架组装 | Godot 仓库(改规则两边同改, 覆盖门 `tools/mirror.py` 守着) |
| `num.lua` `bits.lua` `rng.lua` `json.lua` `init.lua` | 数值语义 / 位运算垫片 / PCG32 / JSON / 前缀助手 | 同上 |
| `data/*.lua` | 由 `tools/luagen.py` 从 `data/*.json` 生成 —— **手改无效** | 仪器 |
| `golden/*.lua` | 由 `tools/golden.gd` 在 Godot 里生成的期望值 —— **手改无效** | 仪器 |
| `app/phrase.lua` `app/shop.lua` | 编排层(拍钟 / 商店 / 结算 / 段末 / 教学门 / 打点)与商店逻辑 | Godot 仓库 |
| `app/CONTRACT.md` | 视图契约(你要读的那份) | Godot 仓库 |
| `check.lua` `tools/fams.lua` `tools/runloop.lua` | 对拍器 | 仪器 |
| `tools/drive.lua` | 无头驱动范例 | — |

## 规矩

- **规则不许写在渲染层**。分数、价格、可购性、剩余秒数、能不能弃/换 —— 全部从 `app:view()` 读。
- **数只在 `lua/data/`**(它是 `data/*.json` 的生成物)。要调平衡去改 Godot 仓库的 JSON, 拉下来重生成。
- 对拍红了 = 你本地改过 `core/` 或 `app/`。别改那两处;要改规则去 Godot 仓库提。
- 存档走 `storage.read/write`(JSON 串), 语言走 `locale()`, 时钟走 `now_ms()` —— 三样注入, 见契约 §0。
- Tape(打点)不走语言层, 记的是事实;`tape_sink` 接上就能落 JSONL。

## 已知的边界

- 渲染层这边我(Godot 仓库)验不了, 唯一证据是你跑起来的截图对 `docs/mockups/*.html`。
- 商店的授予记账(联票名额 / 免费刷新 / 折扣)在 Godot 侧是 view 代码, 镜像在 `app/shop.lua`, 金样生成器里有第三份(`tools/golden.gd::ShopSim`);改商店规则要三处同改(`docs/design/mirror.md` §12 认下的代价)。
- 图鉴页 / 回传通道(Uplink)不在 v1。
