class_name Asset
extends RefCounted

## META 资产层(1.1, 2026-08-19)——「买资产 → 变现 → 买更多」的循环本体。
## 规格挂在 `docs/design/ui_meta.md` META 节(永久层);数据全在 `data/assets.json`。
##
## ⚑ 与 `core/ticket.gd` 同一个形状:**接字典的纯函数**(data = SaveState 的整包存档),
## 时钟与落盘都归调用方 —— 这一层测试直测(tests/t_asset.gd), 不隔着探针闸。
## ⚑ 两条出口(数据文件头有整段推导):财富 = 宝石(gems, 只能再买资产),
## 力量 = 券(每日加发, 日清零)。**循环碰不到局内金币** —— 红线结构性成立。


static func _cfg() -> Dictionary:
	return DB.assets()


static func roster() -> Array:
	return _cfg().get("assets", [])


static func ids() -> Array:
	var out: Array = []
	for e in roster():
		out.append(String(e["id"]))
	return out


static func by_id(id: String) -> Dictionary:
	for e in roster():
		if String(e["id"]) == id:
			return e
	return {}


static func price(id: String) -> int:
	return int(by_id(id).get("price", 0))


static func yield_gems(id: String) -> int:
	return int(by_id(id).get("yield_gems", 0))


static func ticket_of(id: String) -> String:
	return String(by_id(id).get("ticket", ""))


## v2 的两类内容出口(2026-08-19 晚拍板「买了就想玩」):
## track = 场馆歌单加曲(assets/audio 的文件名, 不带 .wav)· flair = 局内/结算视觉声势。
static func track_of(id: String) -> String:
	return String(by_id(id).get("track", ""))


static func flair_of(id: String) -> String:
	return String(by_id(id).get("flair", ""))


## 赛季上架窗口(meta.md §4 批 B 案):season 空 = 常驻;非空 = 只在该赛季**上架**。
## ⚠ 下架 ≠ 没收:已持有的资产永远生效, on_shelf 只管货架显示。
static func season_now() -> String:
	return String(_cfg().get("season_now", ""))


static func on_shelf(id: String) -> bool:
	var s := String(by_id(id).get("season", ""))
	return s == "" or s == season_now()


## 玩家档案等级(meta.md §8, 2026-08-22):**纯函数**, 喂它累计通关段数, 返回
## {"level": 1 起, "xp": 本档内已得, "xp_max": 本档跨度(顶级 = 0), "title": 档位条目(cn/name), "total": xp}。
## 零数值:等级的产出只有称号(data 键白名单锁着)。
static func level_for(xp: int) -> Dictionary:
	var levels: Array = _cfg().get("profile", {}).get("levels", [])
	if levels.is_empty():
		return {"level": 0, "xp": 0, "xp_max": 0, "title": {}, "total": xp}
	var i := 0
	while i + 1 < levels.size() and xp >= int(levels[i + 1]["xp"]):
		i += 1
	var cur := int(levels[i]["xp"])
	var span := 0 if i + 1 >= levels.size() else int(levels[i + 1]["xp"]) - cur
	return {"level": i + 1, "xp": xp - cur, "xp_max": span, "title": levels[i], "total": xp}


## 宝石的**基础**收入(资产分红之外的那部分):挂通关段数, 不挂分数。
static func gems_per_section() -> int:
	return int(_cfg().get("gems", {}).get("per_section", 1))


static func full_clear_bonus() -> int:
	return int(_cfg().get("gems", {}).get("full_clear_bonus", 2))


# ---- 簿记(接字典的纯函数)----

static func owned(data: Dictionary) -> Array:
	return data.get("assets", [])


static func has_asset(data: Dictionary, id: String) -> bool:
	return owned(data).has(id)


## 每种资产**一件**(阶梯靠更贵的下一档, 不靠堆数量)—— 「买更多资产」指往上爬, 不是囤。
static func can_buy(data: Dictionary, id: String) -> bool:
	if by_id(id).is_empty() or has_asset(data, id) or not on_shelf(id):
		return false   # 下架的不卖(评审 R4):货架不摆 + 读取点守卫, 两道门
	return int(data.get("gems", 0)) >= price(id)


static func buy(data: Dictionary, id: String) -> bool:
	if not can_buy(data, id):
		return false
	data["gems"] = int(data.get("gems", 0)) - price(id)
	var a: Array = data.get("assets", [])
	a.append(id)
	data["assets"] = a
	return true


## 一局结束的分红总额(变现的宝石侧)。
static func run_yield(data: Dictionary) -> int:
	var t := 0
	for id in owned(data):
		t += yield_gems(String(id))
	return t


## 持有的券类资产每天该加发哪些券(变现的力量侧;发放本体在 SaveState 的日结算里)。
static func daily_ticket_ids(data: Dictionary) -> Array:
	var out: Array = []
	for id in owned(data):
		var t := ticket_of(String(id))
		if t != "":
			out.append(t)
	return out


## 持有的唱片解锁了哪些曲目(Music.track_pool 的输入)。
static func owned_tracks(data: Dictionary) -> Array:
	var out: Array = []
	for id in owned(data):
		var t := track_of(String(id))
		if t != "":
			out.append(t)
	return out


static func has_flair(data: Dictionary, kw: String) -> bool:
	for id in owned(data):
		if flair_of(String(id)) == kw:
			return true
	return false
