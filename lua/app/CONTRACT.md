# 视图契约 —— 编排层(`app/phrase.lua`)与渲染层之间的全部接口

> 给 TapMaker 侧(scaffold-2d.lua / urhox-libs UI)的实现者。规则、经济、计时、打点**一行都不在渲染层**:
> 你只做两件事 —— **读 `app:view()` 画**、**把手势翻成下面的意图**;一次性动画从 `app:events()` 取。
> 索引一律 **0 基**(与 Godot、Tape 日志、`data/ui.json` 的键同口径)。

## 0. 接线(三样注入)

```lua
local App = require("sync5.app.phrase")      -- 前缀按你放的位置(整目录拷进 scripts/sync5/)
local app = App.new({
  storage = { read = function() return <string|nil> end, write = function(s) ... end },  -- 存档(JSON 串;云变量或本地文件)
  locale  = function() return "cn" end,     -- "cn" | "en"(存档里的覆写优先于它)
  now_ms  = function() return <单调毫秒> end,  -- 编排层自己算拍钟、警告线、锁定线、早收线;没有定时器
  seed    = 12345,                          -- 可选:货架随机流的种子(缺省按时间)
  tape_sink = function(path, lines) ... end, -- 可选:Tape 落盘(JSONL 行);不接就只在内存
})
-- 每帧:
app:tick(now_ms)            -- 返回当前 screen
local v = app:view()        -- 纯数据表, 见 §1
for _, e in ipairs(app:events()) do ... end   -- 一次性事件, 见 §3(每帧取空)
```

`lua/tools/drive.lua` 是一个能跑通整局的无头驱动, 照它接就对了。

## 1. `app:view()` 的形状(按 `screen` 分)

`screen` ∈ `front`(首页) · `intro`(段首盲注特写 / γ 公示卡) · `decision`(出牌中) · `resolve`(结算动画)
· `cutin`(教学特写) · `draft`(商店) · `end`(结算两屏)。另有 `paused`(bool)与 `resume_prompt`(bool, 首页上要不要问「继续上次的演出」)。

| 键 | 何时有 | 内容 |
|---|---|---|
| `home` | front | `runs_total · energy · energy_max · profile{level,xp,xp_max} · seen_tutorial` —— 首页顶栏与开始键 |
| `hud` | 非 front | `section_idx · coins · score · target · phrase_no · fraction(0..1) · elapsed · duration · warning · lock · seconds_left · warn(bool, 倒数亮起) · countdown(3·2·1) · progress(0..1 轨道进度)` |
| `blind` | 非 front | `section_idx · gig(1 起) · blind_name · gig_name · is_wall · target · face{id,name,fx,base} 或 false · next_face · boon · status(状态行) · roll_note(明掷文案) · visible · route[{name,state}]`(state 0 已打过 / 1 当前 / 2 未来) |
| `jokers[4]` | 非 front | 每槽 `{id,name,kind,rarity,fx,state}` 或 `false`;0 号 = Target 槽 |
| `vinyl` | 非 front | 待播队列 `[{id, beat(碟面刻的字), name}]`, 左→右 = 播放顺序;空 = 画转着的唱片 |
| `hand` | 有拍时 | `cards[5]` / `cache[3]`:每张 `{rank,suit,label,glyph,red,wild,selected,scoring,hidden,mask_rank,mask_suit,discard_blocked,swap_blocked,(cache)marked}`;`decide`(能不能操作)· `fee`(弃当前选中要几◆)· `can_discard_sel · can_drop · can_swap · best_kind · best_name · spotlight · request · request_label` |
| `shop` | draft | `open · mid · offers[{id,kind,rarity,price,aff}] · consumables[2]{id,name,price,stamp,armed,fx} 或 false · reroll_cost(0 = 免费)· buys_left · coins · first_target · replace_pick(nil 或货架下标 = 替换态)· section_idx · score/left/need(段中 ≥0, 段末 -1)· target · route` |
| `end_screen` | end | `win · score · target · wage · gig · why`(预支违约的死因行) |
| `intro` | intro | `kind`("closeup"/"gamma")· `left`(秒)· `route` |
| `cutin` | cutin | `key · command · focus[区域名] · left · coins` |
| `tutorial` | 教学关 | `step · hint{command,signal} · pending(欠的动作)· focus[区域名] · shot · spot · unlocked[部件名] · shop_step` |

区域名 → 矩形:`data/ui.json` 的 `tutor_focus`;部件名:`data/tutorial.json` 的 `components`。

## 2. 意图(全部返回是否被接受;拒因走 `deny` 事件)

| 意图 | 何时 | 语义 |
|---|---|---|
| `app:start_run()` | front | 开局(体力闸 / 教学关判定 / 开局三步都在里面) |
| `app:resume_run()` / `app:drop_checkpoint()` | front & resume_prompt | 继续上次半局 / 放弃 |
| `app:skip_intro()` | intro | 点掉特写 |
| `app:tap_hand(i)` / `app:tap_cache(i)` | decision | **点击 = 纯选择**(跨区多选, 再点取消) |
| `app:discard()` | decision | 弃掉当前选中(1◆/张, 原位补牌) |
| `app:discard_one(zone, i)` | decision | 拖到弃牌键 = 单张直弃;zone = "hand"/"cache" |
| `app:drag_swap(h, c)` | decision | **拖拽 = 手牌与缓存对调** |
| `app:sort()` | decision | 理牌 |
| `app:pause()` / `app:resume()` / `app:quit_run()` | decision/resolve | 暂停 / 继续 / 退出本局(不计战绩) |
| `app:buy(i)` | draft | 买货架第 i 张;满槽时返回 `{replace=true}` 并进替换态 |
| `app:replace(k)` | 替换态 | 换进第 k 槽(1..3);`k=0` 或 `app:cancel_replace()` 取消 |
| `app:buy_consumable(i)` | draft | 买消耗牌位第 i 张(0/1) |
| `app:reroll()` | draft | 刷新(免费次数用完后按阶梯价) |
| `app:leave()` | draft | 「继续 ▸」—— 商店唯一免费出口 |
| `app:end_next()` / `app:restart()` / `app:end_home()` | end | 下一场 / 再来一次 / 回首页 |

**5 选 1**:3 小丑 + 2 消耗抢同一次购买;联票等授予的名额在 `shop.buys_left`。
时间闸门(收线/锁定)、动作上限、封条、盖牌 —— 全在编排层判, 你只画 `can_*` 与 `*_blocked`。

## 3. `app:events()`(一次性, 立即模式渲染需要)

`deal`(发牌)· `action`(任意动作:音浪抖一下)· `discard{hand,cache}` · `settle{base,mult,score,bonus,pattern_mult,joker_mult,bonus_pct,kind,coins,popups[{slot,text}],total,resolved}`(三段式结算动画:基础 × 乘数 = 分数 → 碎裂 → 滚分;popups 浮在对应槽上)
· `deny{why,text}`(浮字)· `shop_open` / `shop_close` · `replace_open{shelf}` / `replace_cancel` · `disc_bought{shelf}`(碟从货架飞进唱片位)· `disc_fired{names}`(到点播放的碟)
· `section_clear{score,target,wage}`(轻横幅 ≤1s)· `run_end{win}` · `loan_repay{paid}` / `loan_default{owed}` · `guest_exit{slot,name}`(客串到寿谢幕)· `cutin{key,command,focus,coins}`。

## 4. 画什么、从哪拿

- **坐标**:`data/ui.json`(720×1280 绝对坐标;Yoga 用 absolute 定位即可)。`stage` 节 = 舞台装配(饰线/标签/四槽/音浪/均衡器/盲注卡/唱片/轨道框), `hud/shop/hand/banner` 各组件一节。
- **色板**:`data/theme.json`(字符串 = #rrggbb, 数组 = rgba 0..1)。盲注档位色 blue → amber → red → pink 逐档升温。
- **文案**:`data/ui.json` 的 `blindcard/jokercard/consumablecard/patterns/hand.deny`;代码里的字面量已过 `Lingo.t()`(en 走 `data/lingo.json`)。实体名用 `name`(en)/`cn`。
- **字体**:Rajdhani(数字/拉丁, Medium/SemiBold/Bold)+ 系统中文;`assets/fonts/` 里有子集化的 Noto 兜底。
- **画法**:`docs/design/ui_meta.md`(玻璃卡三件套 / 倒影 / 辉光 / 分层顺序)与 `docs/mockups/*.html`(Claude Design 设计稿, 本身就是 Flexbox)。卡面 = 左上数字 + 中央大花色 + 右下倒置数字, 花色只有两色。
- **不要画**:牌堆剩余张数 · 「跳过」按钮 · 主动收工键 · 任何非黑底色(背景是黑, 光全部由光效层承担)。

## 5. 别做的事

- 不要在渲染层重算任何数(分数预览、价格、可购性、剩余秒数都在 view 里)。
- 不要碰 `lua/data/`、`lua/golden/`(仪器生成物)。规则改动从 Godot 仓库来:`git pull` 后 `lua lua/check.lua` 必须绿。
- 不要自己实现「万能牌/规则牌/时机卡」的效果 —— 它们是 core 的数据驱动效果, 已经在结算链里。
