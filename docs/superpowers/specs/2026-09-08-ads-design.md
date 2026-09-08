# 激励视频变现(海外 Godot 版)· 设计 2026-09-08

> **用户拍板(2026-09-08)**:渠道 = **B 海外 Godot 版**(TapMaker 国内版不管);
> 形式 = **局外看广告买体力 · 局内看广告买金币**;**不做内购道具**;
> 原「不做内购」整行按「赶紧删了」从 TODO 明确不做表删除(禁的是道具,不是内购这个词)。
> 设计口头过审同日。SDK 假设 AdMob、先只 Android(用户未反对)。

---

## 0. 一页纸

- **两个判断**:① **目标分不假设你看广告** —— 经济/目标分/bot 基线全按零广告标定,广告金币是纯盈余;
  ② **局内入口只在商店** —— 整局唯一没有钟的地方,30 秒广告不碰 8 秒拍。
- **两个入口,都长在「想要但拿不到」的那一刻(2026-09-08 二审改)**:
  商店里**点了买不起的卡或刷新**(`denied` 那一刻)弹出行内「差 N◆ · 看广告 +3◆」(每店 1 次、每局 2 次)·
  **体力为 0 时按「再来一次 / 开始」**,墙本身变成「看广告 +1⚡ · 马上开局」,看完**直接进局**(每日上限 = 满值)。
  ~~商店常驻第三键~~ ~~首页胶囊随时 +1~~ ~~看完回首页再按一次~~ 三处二审否掉(理由见 §1.3)。
- **一条红线**:**离线 = 今天的游戏原样** —— 没有广告可放时任何按钮都不出现,「继续 ▸」免费出口原样保留。
- **架构**:`view/ads.gd` 适配层(假后端 + AdMob 后端),core 不认识广告,发放只在编排器,Tape 记四种事实(show / reward / fail / drop)。
- **仪器**:bot 加 `ads` 臂(缺省关 = 零广告基线),parity 表加键;验收带 = 通关率抬升 ≤ +5pt、每局多买 ≤ 2 张。

---

## 1. 两个判断与它们的反面

### 1.1 目标分不假设你看广告

| | 选 | 反面 |
|---|---|---|
| 标定口径 | 经济、`section_targets`、bot 基线全按**零广告** | 按「含广告」标定 |
| 不看的人 | 零损失 | 偏难 ⇒ 怨气(调研:Balatro 零变现所以零怨气) |
| 看的人 | 变容易,所以**必须封顶** | 只是回到基线 |
| catch-up 判据 | 看起来像**奖励** | 看起来像**同情**(不看就被罚) |

封顶数:每局 2 次 × 3◆ = 6◆ = **至多多买 2 张卡**。08-30 收紧到「一局买 ≈10 张」的稀缺守得住。

### 1.2 局内入口只在商店

商店期间没有拍钟(`Run.advance()` 返回 `shop_break`,编排器只 `_open_draft()`);首页也没有钟。
**两个入口都天然无钟**,广告把应用切后台再回来,不会吞任何一拍。
反面(拍间 / HUD 上放入口)= 把广告塞进节奏,「时间是唯一压力货币」这条就破了。否掉。

### 1.3 入口长在哪(二审,用户 2026-09-08「思考商业化嵌入的合理性」)

候选时刻按自然度:

| 时刻 | 判 | 为什么 |
|---|---|---|
| 商店里点了买不起的卡/刷新(`denied` 已有) | **选** | 欲望具体(就那张卡)、缺口小(差 1~2◆)、无钟、决策真实(值不值 30 秒) |
| 体力 0 时按「再来一次 / 开始」(`_deny_no_energy` 已有) | **选** | 墙在那,钥匙挂墙上;**看完直接进局** —— 零摩擦重开是留存核心,绕回首页是自己加摩擦 |
| 首页体力胶囊随时看 +1 | 否 | 没需求时囤体力只有计划型玩家会做;多数人看到一个不知为何在那的角标 |
| 商店常驻第三键 | 否 | 对不缺钱的人是视觉负担;「指令外的加法比做少了贵得多」 |
| 开局公示卡「+3◆ 开局」 | 否 | 没有具体欲望,会变成每局仪式,人人都点 ⇒ 零广告标定在实际上漂掉 |
| 失败屏续命 | **明确不做** | 最赚钱。生死线一软,倍率奖励波动性那套逻辑失去根基(追稀有型的风险溢价前提是凑不成会真死)—— 机制理由,不是口味 |
| 成功屏 / 图鉴 | 否 | 没有需求,也没有东西可翻倍 |

**代价认下**:deny 触发的 offer 有可发现性成本 —— 从不点买不起的东西的玩家永远看不到它。用 Tape 的转化率量(§6)。

---

## 2. 数据(全部 JSON,镜像不许手抄数字)

| 文件 | 新键 | 值 | 含义 |
|---|---|---|---|
| `data/economy.json` | `ad_coins` | 3 | 一次广告给的金币 = 一张卡的钱(`joker_prices` 平价 3◆) |
| | `ad_coins_per_shop` | 1 | 每店上限 |
| | `ad_coins_per_run` | 2 | 每局上限 |
| `data/profile.json` | `ad_energy` | 1 | 一次广告给的体力 |
| | `ad_energy_per_day` | 5 | 每日上限(= `energy_max`,一天最多 10 局) |
| `data/ads.json`(新) | `test_mode` | true | 开发期恒用测试广告 ID;出正式包前由用户翻 false |
| | `android.app_id` / `android.rewarded_coins` / `android.rewarded_energy` | 测试 ID 占位 | 真 ID 由用户填,**不进仓库注释以外的任何代码** |
| `data/ui.json` `shop` 节 | `ad_offer_text` | 「差 %d◆ · 看广告 +%d◆」 | 行内 offer 文案(缺口未知时用 `ad_offer_text_plain` 「看广告 +%d◆」) |
| | `ad_offer_pos` | 现「买不起」浮字的位置 | offer 的锚点;两键布局零改动 |
| 挡开局(`phrase.gd`) | 字面量包 `Lingo.t()` | 「看广告 +%d⚡ · 马上开局」·「广告暂时没有,稍后再试」 | home 既有做法(`ui.json` 没有 home 节,不新开) |
| `data/lingo.json` | 上述所有新中文的英文;删「看广告补体力 · 敬请期待」 | | `tests/t_lingo` 守完整性(ui.json 叶子与 `Lingo.t()` 字面量都要在表里) |

文案口味:「赞助插播 +3◆」比「看广告」更像这个巡演游戏说的话,但 AdMob 政策要求玩家明知这是广告,
所以缺省仍写「看广告」;要换只改 JSON,归用户。

`core/db.gd` 校验:economy 三键 ≥ 0 且 `ad_coins_per_shop ≤ ad_coins_per_run`;profile 两键 ≥ 0;
`ads.json` 三个 ID 非空字符串。缺键/坏值在 `tests/t_db` 直接红(测试期门禁,运行时不拒绝启动,沿用既有口径)。
`tools/luagen.py` 重生成 `lua/data/`(零成本)。

---

## 3. core 层(引擎无关、不含时钟、不 import view)

### 3.1 `core/economy.gd`

```gdscript
static func ad_coins() -> int                                   # 读 economy.json
static func ad_coins_allowed(run_used: int, shop_used: int) -> bool   # 两个上限都没到
```

纯函数,数全部来自 JSON。

### 3.2 `core/run.gd`

- 新字段 `ad_used: int = 0`(本局已看次数)。
- `snapshot()` 加 `"ad_used"`,`restore()` 缺键当 0,快照版本 `v` 不变(与 `consumables` 补键同一先例)。
- **每店计数不进 run** —— 它是商店会话内的量,和编排器的 `_shop_buys` 同一归属。

### 3.3 `core/save.gd`(纯函数层 + 带闸外层,沿用体力那一套)

```gdscript
static func can_add_energy_from_ad() -> bool         # 未满 且 今日次数未到;探针恒 false
static func add_energy_from_ad() -> bool             # 成功 = 入账落盘 true;探针 no-op false
static func _ad_energy_in(d, day, cap, per_day, amount) -> bool   # 算术(测试直打)
```

- 存档新键 `ad_energy_day` / `ad_energy_used`;跨日清零;旧档缺键 = 今天 0 次。
- 入账 = `min(amount, cap − cur)`,永不超满值;**未满才允许**(不能囤)。
- 探针恒满 ⇒ `can_add` 恒 false ⇒ 探针画面永远没有这个入口(截图稳定)。

### 3.4 Lua 镜像

`lua/core/economy.lua` / `save.lua` 补同名孪生(各一两行),**只为 `tools/mirror.py` 覆盖门保持绿**,
不给 TapMaker 做任何广告设计(用户:「maker 国内你别管了」)。金样不需要重生成
(新函数没有金样族;既有函数未动)。

---

## 4. view 层

### 4.1 `view/ads.gd` —— 适配层(一词化命名)

对外只有三件事:**有没有货 / 放 / 回调发奖**。

```gdscript
signal rewarded(kind: String)          # 看完,该发奖了
signal failed(kind: String, why: String)
signal closed(kind: String)            # 关掉(含未看完)
func ready(kind: String) -> bool       # 该种类有已加载的激励视频
func show(kind: String) -> void
func preload(kind: String) -> void
```

`kind ∈ {"coins", "energy"}`,两种各一个广告位(AdMob 侧两个 rewarded unit)。

**两个后端**,启动时选一次:

| 后端 | 何时 | 行为 |
|---|---|---|
| **Fake**(桌面 / 编辑器) | 非 Android,或 Android 上插件单例不存在 | `ready()` 恒 true;`show()` 下一帧 `call_deferred` 发 `rewarded`。环境变量 `SYNC5_ADS=fail` 改成发 `failed`,`SYNC5_ADS=off` 改成 `ready()` 恒 false —— 三条路径单测都打得到 |
| **AdMob**(Android) | `OS.has_feature("android")` 且插件脚本在 `addons/` 里可加载、`MobileAds.initialize()` 成功 | 包插件;`ready()` = 持有已加载未展示的 `RewardedAd`(插件没有 `is_loaded`,见 §8.2);`test_mode` 为 true 时一律用测试 unit ID;`show` 之前必 `ready`;回调统一 `call_deferred` 回主线程再发信号 |
| **探针** | `SaveState.is_probe()` | 强制 Fake 且 `ready()` 恒 false —— 探针日志与截图零广告痕迹(两台机器的日志必须长一样) |

预加载时机:进商店时 `preload("coins")`;回首页 / 进结算屏时**体力为 0 才** `preload("energy")`;发奖或失败后立刻再 `preload`。

### 4.2 商店(`view/shop.gd`)

- `denied` 信号加一个参数:`denied(why: String, need: int)`,`need` = 想买/想刷的那件差多少◆(算不出时 0)。
  它已经是「想要但拿不到」的信号,这次只是让它把缺口也说出来。
- 新入口 `show_ad_offer(need: int, amount: int)` / `hide_ad_offer()`;新信号 `ad_requested()`。
  offer = 一枚行内小键,锚在 `ad_offer_pos`(现「买不起」浮字的位置),文案 `ad_offer_text`。
  **底栏两键布局一像素不动**;没 offer 时商店与今天完全一样。offer 节点只建一次(08-21 审查的泄漏教训)。
- 视图不判条件、不数次数、不碰钱 —— 何时能 show 由编排器说了算(经济动作只发生在编排器)。

### 4.3 编排器(`view/phrase.gd`)

- 新计数 `_shop_ads`(进店清零,与 `_shop_buys` 同款)。
- `denied(why, need)` ⇒ 既有的 `Tape.on("deny", …)` 照打 ⇒ 若
  `ads.ready("coins") and Economy.ad_coins_allowed(run.ad_used, _shop_ads) and not run.tutorial`
  ⇒ `shop.show_ad_offer(need, Economy.ad_coins())`。offer 留到本店离开 / 成交 / 发奖为止。
- `ad_requested` ⇒ 守 `state == St.DRAFT and replace.pick == null`(与买/刷同一把守门)⇒
  `Tape.on("ad", {"k": "coins", "ev": "show"})` ⇒ `ads.show("coins")`。
- `rewarded("coins")` ⇒ 三种情形一份判定:

| run 状态 | 做什么 | Tape |
|---|---|---|
| 还在这家店(`DRAFT`) | `phrase.coins += ad_coins`;`run.ad_used += 1`;`_shop_ads += 1`;`shop.hide_ad_offer()`;刷货架的钱 | `{"k":"coins","ev":"reward","coins":N}` |
| run 还活着但店已关(回调晚到) | 照发进 `phrase.coins`(玩家真看了;钱只能在下家店花,无害) | 同上加 `"late": true` |
| run 已结束 / 回首页 | 丢弃 | `{"k":"coins","ev":"drop"}` |

- `failed("coins", why)` ⇒ `Tape.on("ad", {"k":"coins","ev":"fail","why":why})` ⇒ 浮字「广告暂时没有,稍后再试」⇒ `shop.hide_ad_offer()`,本店不再弹,下家店再试。
- **只有 `reward` 计数**:失败不计、关掉没看完(`closed` 无 `rewarded`)不计;上限只数真发出去的钱。
- **不**调 `Joker.notify_shop(...)`:看广告不是「付费动作」(淘碟 A4 那条只挂刷新),不许让它成长任何卡。
- 教学关永不弹(`run.tutorial`)。

### 4.4 体力墙(`view/phrase.gd::_deny_no_energy`)

首页体力胶囊**只显示,不是入口**(二审删)。入口 = 墙本身。

- 开局与重开都走 `_begin_run()`,它返回 false 时调用方进 `_deny_no_energy()`。改这一个函数:
  - 若 `ads.ready("energy") and SaveState.can_add_energy_from_ad()` ⇒ **不回首页**,在当前屏(首页或结算屏)之上弹一层:
    一行「体力不足」+ 一枚键「看广告 +1⚡ · 马上开局」+ 点空白处关闭;记下**待重放的开局意图**(`_pending_start: Callable`,就是刚才那条调用)。
  - 否则 ⇒ 今天的行为(回首页 + 「体力不足,明天回满」),「敬请期待」那行删。
- 点键 ⇒ `Tape.on("ad", {"k":"energy","ev":"show"})` ⇒ `ads.show("energy")`。
- `rewarded("energy")` ⇒ `SaveState.add_energy_from_ad()` ⇒ `Tape.on("ad", {"k":"energy","ev":"reward"})` ⇒ 关层 ⇒
  **`call_deferred` 一帧后重放 `_pending_start`** —— 它会再走一遍 `_begin_run()` 三步,这次扣得起,run 开了。
  开局仍只有那一份入口(「第二条入口漏掉主路径的步骤」是这个项目最贵的形状);多等一帧是让 Android 的 RESUMED 与 EGL surface 先回来。
- `closed` 无 `rewarded`(关掉没看完)⇒ 关层,回首页 + 「体力不足,明天回满」,`_pending_start` 清空。
- `failed` ⇒ 浮字「广告暂时没有,稍后再试」⇒ 同上回首页;只有 `reward` 计入每日次数。
- `_pending_start` 只活到这一层关闭;不落盘、不跨场景。

### 4.5 生命周期

广告展示时 Godot 收到 `NOTIFICATION_APPLICATION_PAUSED/RESUMED`。两个入口都在无钟场景,
不需要任何暂停补偿;唯一要守的是**回调不在主线程时一律 `call_deferred`**(适配层内部消化,
编排器永远在主线程收信号)。

---

## 5. Tape(只记事实,不记特征)

事件名 `ad`,负载 `{k: coins|energy, ev: show|reward|fail|drop, [why], [coins], [late]}`。
四种 `ev` 都是**发生过的判定**;「广告有没有货」是特征不记。
`data/tape.json` 不需要新开关(`mute` 已能按名关)。探针零广告事件(4.1 探针行)。

---

## 6. 仪器(规则在游戏里也必须在模型里)

- `tools/bot.gd::_draft` 读 `cfg.get("ads", false)`:开 = 每店只要 `Economy.ad_coins_allowed(...)` 就先领 `ad_coins`(与真人「买不起才看」相比是**上界**,量的就是上界);关 = 零广告基线,**缺省关**,所有既有读数不动。
  `run.ad_used` 由 runloop 持有的真 `Run` 记。
- `tools/parity.py::ENTRIES` 加 `ad_coins`(view 与 tools 两侧都要调 `Economy.ad_coins`)。
- sim 队列加一条 `ads` 变体(与基线共用随机数)。

**验收带**(用户喊了才跑,门纪律):`ads` 臂 vs 基线,**通关率抬升 ≤ +5pt、每局多买 ≤ 2 张**。
超带 = 数额或上限回 JSON 改,不改机制。

**自然不自然,用真人 Tape 量**(归用户数据):
- 商店:`deny`(买/刷)之后跟着 `ad show` 的比例 = 转化率;**低于一成**说明位置或数额不对。
- 体力:`deny/energy` 到下一个 run 开始的间隔,与今天的重开摩擦对比;看完广告没开局的比例应接近零(那是 `_pending_start` 没兑现)。

---

## 7. 测试

| 域 | 断言 |
|---|---|
| `t_db` | economy 三键 / profile 两键 / ads.json 三 ID 缺一即红;`per_shop ≤ per_run` |
| `t_economy` | `ad_coins()` 读自 JSON;`ad_coins_allowed` 的两个上限各自封顶 |
| `t_save` | `_ad_energy_in`:未满才加 · 不超满值 · 每日上限 · 跨日清零 · 旧档缺键 = 今天 0 次 · 探针恒 false |
| `t_run` | snapshot/restore 往返带 `ad_used`;缺键 = 0;`v` 不变 |
| `t_shop` | 两键的位置与文案永远与今天相同;`denied` 带出正确的 `need`;`show_ad_offer` 后 offer 可见且点击发 `ad_requested`;`hide_ad_offer` / `close` 后不可见;反复 `_render` 节点只建一次 |
| `t_phrase`(或新域 `t_ads`) | 金币:`denied` 且允许才弹;DRAFT 内发奖入账并计数;晚到发奖带 `late`;run 结束丢弃;`failed` 收 offer;教学关永不弹;每店 1 / 每局 2 封顶 · 体力:体力 0 且有货 ⇒ 弹层不回首页;发奖后 run 真的开了且只走了一次 `_begin_run()`,体力净变化 0;关掉没看完 ⇒ 回首页、不计数;无货 ⇒ 今天的行为 |
| `t_tape` | `ad` 事件四种 `ev` 形状 |
| `t_lingo` | 新文案全部在表里;「敬请期待」已从表与代码同时消失 |
| 秒级门 | `parity --check` · `evsync --check` · `counts --check` · `luagen --check` · `mirror --check` · `lua lua/check.lua` |

真机:桌面 Fake 点通 → APK 用测试 unit ID 验回调 → Tape 里看到 `ad` 的 `show/reward` 两条。

---

## 8. SDK 接线

### 8.1 与插件无关的契约

- 适配层是**唯一**碰插件 API 的文件;游戏其余部分只认 §4.1 的三个方法三个信号。
- `test_mode` 为 true 时**无条件**用官方测试 unit ID,真 ID 只在 false 时读 —— 开发期误放真广告是政策违规。
- Android 导出走 gradle 自定义构建(`export_presets.cfg` 的 `gradle_build/use_gradle_build` 翻 true,编辑器先装 Android Build Template),
  这一步改变出包流程,**出包清单(STATUS.md)要同步一行**。桌面与 Web 导出不受影响(适配层在非 Android 上走 Fake)。

### 8.2 插件选型(2026-09-08 调研,信源当日抓取)

**选 Poing Studios `godot-admob-plugin`**(2026-07 起的单体仓库,旧 `godot-admob-android` 已于 2026-03 归档)。

| 事实 | 读数 | 信源 |
|---|---|---|
| 版本 | **v5.0.0**(2026-07-21);nightly 持续跟进 | [Releases](https://github.com/poingstudios/godot-admob-plugin/releases) |
| Godot 覆盖 | README 写 **4.2.0+**,**没有逐版本兼容表** ⇒ 装完先跑一次冒烟(加载 + 展示测试广告) | [README](https://github.com/poingstudios/godot-admob-plugin) |
| 安装形态 | Godot 4.2+ **v2 Android 插件**:`addons/` + `EditorExportPlugin`,**不是** `.gdap`;原生依赖由编辑器菜单 `Project → Tools → AdMob Manager → Android → Download & Install` 拉取 | 同上 |
| Gradle | **必须** `gradle_build/use_gradle_build=true`(官方:v2 插件 requires the Gradle build process);`export_presets.cfg` 现值 false,要翻;编辑器要先装 Android Build Template | [Godot 文档:Android plugins](https://docs.godotengine.org/en/stable/tutorials/platform/android/android_plugin.html) |
| 备选 | `godot-sdk-integrations/godot-admob` v7.0(2026-05-27),API 是 `load_rewarded_ad()/show_rewarded_ad()` 风格;版本覆盖与线程细节**未核实**,只在 Poing 冒烟失败时再查 | [GitHub](https://github.com/godot-sdk-integrations/godot-admob) |

**API 形状(镜像 Google 原生 SDK)**:`MobileAds.initialize()` → `RewardedAdLoader.new().load(unit_id, AdRequest.new(), cb)`,
`cb: RewardedAdLoadCallback` 的 `on_ad_loaded(ad: RewardedAd)` / `on_ad_failed_to_load(err: LoadAdError)`;
`ad.show(OnUserEarnedRewardListener.new(func(reward: RewardItem)))`;
`ad.full_screen_content_callback: FullScreenContentCallback` 有 `on_ad_dismissed_full_screen_content` /
`on_ad_failed_to_show_full_screen_content(err)` / `on_ad_showed_full_screen_content` / `on_ad_impression` / `on_ad_clicked`。
**没有 `is_loaded()`** —— 适配层的 `ready(kind)` = 「持有一个已加载、未展示过的 `RewardedAd` 对象」;
dismiss 后置空并立刻重新 `load`。这条决定了 §4.1 的 `ready()` 实现,不是细节。
([RewardedAd 参考](https://poingstudios.github.io/godot-admob-plugin/stable/reference/classes/RewardedAd/) ·
[FullScreenContentCallback 参考](https://poingstudios.github.io/godot-admob-plugin/stable/reference/listeners/FullScreenContentCallback/))

**测试 ID**:Android 激励视频官方测试单元 `ca-app-pub-3940256099942544/5224354917`
(Google 原话:不用测试 ID 可能封号)—— `data/ads.json` 的 `test_mode` 为 true 时两个 kind 都用它。
测试设备注册走 `RequestConfiguration`,GDScript 签名**未逐一核实**,实施时翻插件文档站 `reference/classes/RequestConfiguration/`。
([developers.google.com/admob/android/rewarded](https://developers.google.com/admob/android/rewarded))

**政策边界**:
- 激励视频**必须用户主动、明确选择**后才放([Policies for ad units that offer rewards](https://support.google.com/admob/answer/7313578?hl=en))—— 两个入口都是玩家自己点的键,奖励数额刻在键上,合规。
- Play **数据安全表单**必须如实列 Google Mobile Ads SDK 采集项(IP、产品交互、诊断、设备/账号标识符)([Play data disclosure](https://developers.google.com/admob/android/privacy/play-data-disclosure));隐私政策页要补一段广告 SDK 采集。**归用户**。
- GDPR 式 CMP 同意表单只对 **EEA/UK/瑞士强制**([EU 用户同意政策](https://support.google.com/admob/answer/7666519?hl=en));美国州法走 UMP 的「隐私选项」链接,不是启动强制弹窗([US states privacy](https://developers.google.com/admob/android/privacy/us-states)),是否触发法定门槛取决于收入/数据量,**法律判断未核实**。
  ⇒ **本批不做 UMP**;发行国家在 Play 后台**排除 EEA/UK/瑞士**(归用户设置)。要进欧洲时再加 UMP,那是独立一批。

**线程与生命周期**:Godot 4.x 非主线程不得直接 `emit_signal`,必须 `call_deferred`([issue #81148](https://github.com/godotengine/godot/issues/81148));
AdMob 回调在 Android UI 线程触发,插件是否已转发到 Godot 主线程**官方未写明** ⇒ 适配层**无条件** `call_deferred` 再发信号(§4.1 已定),
并在冒烟里打印 `OS.get_thread_caller_id()` 实测一次。展示全屏广告会经过一次 `NOTIFICATION_APPLICATION_PAUSED/RESUMED`,
resume 通知要等 EGL surface 重建后才到 —— 两个入口都无钟,不在 pause 回调里做任何需要渲染上下文的事。
([PR #32064](https://github.com/godotengine/godot/pull/32064) · [issue #85265](https://github.com/godotengine/godot/issues/85265))

### 8.3 用户侧清单(我做不了的)

1. AdMob 账号 + Android 应用 + **两个** rewarded 广告单元(coins / energy),把 App ID 与两个 unit ID 填进 `data/ads.json`,`test_mode` 翻 false 只在出正式包那一步。
2. Play 后台:数据安全表单补 Ads SDK 采集项;发行国家排除 EEA/UK/瑞士(本批不做 UMP)。
3. 隐私政策页补一段「本应用使用 Google AdMob 展示激励视频广告,SDK 会采集……」(已公开的隐私页要更新)。
4. release keystore / 正式包名 / 版本号(1.0 交接里就欠着的三件,与本批无关但同一次出包会撞上)。

---

## 9. 不做 / 边界

- 本批**不做**:任何内购(含去广告)· iOS · TapMaker · 体力定时恢复 · 插屏/横幅(只有玩家主动点的激励视频)· 广告进教学关 · 广告进探针。
- **入口只有两个、都由需求触发**:不做首页胶囊入口、不做商店常驻键、不做开局卡入口、**不做失败屏续命**(§1.3)。
- 广告不是付费动作,不挂任何小丑牌钩子。
- 「继续 ▸」永远是免费出口;广告键从不替代它。

## 10. 认下的账

- **体力闸门是留存负项,至今没量过** —— 要用户的真人 Tape:`deny/energy` 发生率与次日回访。
- AdMob 账号、App ID、两个 unit ID 归用户(我不能替你开账号);隐私政策要补广告 SDK 采集项,Play 数据安全表单要填 —— 具体条目见 §8.2。
- 一局最多两段 30 秒广告,是玩家自己选的;但商店节奏被拉长这件事真实存在,验收带只量通关率不量「商店停留时长」—— 那一维等真人 Tape。
