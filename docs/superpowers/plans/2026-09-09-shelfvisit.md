# 商店授予记账三份收口 · 计划(2026-09-09)

> TODO 0 ②(mirror.md §12 认下的第二个代价):联票名额 / 免费刷新 / 折扣 / 挑高 / 5 选 1 计数 / 帕奇欧一次 / 离店清零,
> 今天住在 **三处**:`view/shop.gd`(`_grant_*` `_reroll_count` `_buys_left`)+ `view/phrase.gd`(`_shop_buys` `_coffer_used` `_perkeo_fired`)·
> `tools/golden.gd::ShopSim` · `lua/app/shop.lua`。改一条商店规则要三处同改,整局金样只能证「ShopSim = Lua」,证不了「= view」。

**Goal:** 记账收成 `core/shelf.gd` 的一个实例类 `Shelf.Visit`(一次进店 = 一个实例),view / ShopSim / Lua 三方都消费它;金样加一族替它对拍。

**边界(不动的)**:货架组装(`Shelf.deal/refill/candidates`)已是一份;经济动作仍只在编排器发生(Visit 只记账、不碰 `coins`、不装卡);渲染不动;规则一条不改(改前改后行为逐字节相同 —— 金样与既有单测就是判据)。

## 1. `Shelf.Visit`(core/shelf.gd 内部类,引擎无关)

字段:`reroll_count · buys_left · shelf_bonus · grant_shelf · grant_extra_buys · grant_price · grant_free_reroll · grant_min_rarity · shop_buys · coffer_used · perkeo_fired · closed`。

| 方法 | 语义(= 今天三处各自那份) |
|---|---|
| `open(run_shelf_bonus: int)` | 进店归零:`shop_buys=0 · perkeo_fired=false · reroll_count=0 · buys_left=0 · grant_min_rarity="" · coffer_used=false · closed=false · shelf_bonus=run_shelf_bonus`(其余授予**不**清 —— 「下次货架」类授予是上一店给的,进店时消费) |
| `price(j, slots) -> int` | `Economy.shelf_price` + `grant_price`,地板 1,免费保 0 |
| `affordable(j, slots, coins) -> bool` | 今天 `Shop._affordable` 的算法(含满槽回收预算) |
| `reroll_cost_now() -> int` | `Economy.reroll_cost(reroll_count, grant_price)` |
| `take_free_reroll() -> bool` | 有则减一返回 true |
| `note_reroll()` | `reroll_count += 1` |
| `buy_limit(slots) -> int` | `Joker.slots_buy_limit(slots) + grant_extra_buys` |
| `note_buy()` | `shop_buys += 1`(Target 换旗不计,由调用方判 —— 与今天同) |
| `stay(slots) -> bool` | `shop_buys < buy_limit` ⇒ `buys_left = limit − shop_buys`,true;否则 `close()`,false |
| `apply_action(act) -> Dictionary` | 只做记账:`shelf_slots`(取大)· `extra_buys`(加)· `price_delta`(加)· `free_reroll`(加)· `min_rarity`(覆盖);返回 `{"redeal": bool}`(shelf_slots / min_rarity 在店内要重掷);`rule_guaranteed / loan / wilds / trim_low / deck_rule / copy_one_destroy_rest` **不归它**(跨店或碰 deck/coins,留在调用方) |
| `close()` | 清「这次商店」类授予(`grant_shelf/extra_buys/price/free_reroll`),`closed=true`;`grant_min_rarity` 不清(它是「下次货架」类,进店时清 —— 与今天 `Shop.open()` 同) |

Lua 孪生 `lua/core/shelf.lua` 加 `Shelf.Visit`(同名方法),`tools/mirror.py` 不查内部类(只查顶层 func),对拍靠金样。

## 2. 三方改成消费者

- `view/shop.gd`:去掉 `_grant_*` / `_reroll_count` / `_buys_left` 字段,持有 `visit: Shelf.Visit`(编排器 `open()` 前注入);`_price / _affordable / _reroll_cost_now / consume_free_reroll / granted_extra_buys / grant_shelf / grant_extra_buys / grant_price_delta / grant_free_reroll / grant_min_rarity / set_buys_left` **保留名字**,内部改成对 `visit` 的一行委托(测试与探针不用改名);`close()` 调 `visit.close()`。
- `view/phrase.gd`:`_shop_buys / _coffer_used / _perkeo_fired` → `_visit.*`;`_apply_shop_action` 先 `var r := _visit.apply_action(act)`,再做视图/deck/coins 那一半(`redeal` ⇒ `shop.redeal(...)`;loan / deck_rule / rule_next / anvil 照旧);三处 `buy_limit` 算式改 `_visit.buy_limit(run.joker_slots)`;`_after_sale` 逻辑改 `_visit.stay(...)`。
- `tools/golden.gd::ShopSim`:字段换成一个 `visit`,方法委托;行为不变。
- `lua/app/shop.lua`:同上,`self.visit = Shelf.Visit.new()`。

## 3. 金样

`tools/golden.gd` 加第六族 `visit`:若干条脚本化序列(open → apply_action 各键 → note_buy/stay → reroll/take_free_reroll → close),每步后记录全部字段;`lua/check.lua` 重放 `Shelf.Visit` 逐位相同。整局族(`run`)照旧跑 ShopSim,它现在经由 Visit ⇒ 「ShopSim = Lua」这条证明覆盖到了 view 用的同一份记账。

## 4. 测试与门

- 既有 `t_shop / t_consumable / t_draft` 里 14 处对记账字段的引用改成走 Visit(或保留委托名);断言值不变。
- 新增 `t_shop` 一节:`Shelf.Visit` 的表(每方法一条,数从 `Joker.slots_buy_limit` / `Economy.reroll_cost` 推导)。
- 六门 + adsprobe + `SYNC5_TEST_DOMAINS=t_shop,t_consumable,t_draft,t_ads,t_lingo` 绿;改了 `core/` ⇒ `golden.gd` 重生成 ⇒ `check.lua` 绿。
- 视觉零改动:`_shot_draft*.png`(`tools/draft_sheet.gd`)改前改后逐像素一致(NON-headless 各截一次,`python3` 比对)。

## 5. 分批

T1 `Shelf.Visit` + Lua 孪生 + 金样族 + 单测(core 侧,可独立提交)· T2 view 两文件改消费者 + 探针 + 截图对照 · T3 ShopSim / lua app 改消费者 + 整局金样重生成 · T4 mirror.md §12 与 STATUS/CHANGELOG 收账。
