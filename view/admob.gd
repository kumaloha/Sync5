extends Node
## AdMob 后端(Poing Studios godot-admob-plugin v5;2026-09-08 调研, 规格 §8.2)。
## ⚠ **只有这个文件碰插件 API**, 且全部**动态查类**(ProjectSettings.get_global_class_list)——
## 插件不在时本文件照样解析, 桌面 / Web 导出与 `--import` 不受影响。
## 契约与 view/ads.gd 相同:has_ad / load_ad / show_ad + rewarded / failed / closed。
## 插件没有 is_loaded():has_ad = 持有一个已加载、未展示的 RewardedAd;dismiss 后置空并立刻重载。
## 所有回调 call_deferred 回主线程(插件是否已转发到 Godot 主线程未核实, 一律兜底)。
## ⚠ 类名 / 回调字段名以插件文档站为准(reference/classes/RewardedAd 等), 真机冒烟时逐个校对:
##   RewardedAdLoader.load(unit_id, AdRequest, RewardedAdLoadCallback{on_ad_loaded, on_ad_failed_to_load})
##   RewardedAd.show(OnUserEarnedRewardListener(func(reward)))
##   RewardedAd.full_screen_content_callback = FullScreenContentCallback{on_ad_dismissed_full_screen_content,
##     on_ad_failed_to_show_full_screen_content(err)}

signal rewarded(kind: String)
signal failed(kind: String, why: String)
signal closed(kind: String)

var _ads := {}          # kind -> RewardedAd(已加载未展示)
var _loading := {}      # kind -> bool
var _cfg: Dictionary = DB.ads()
var _classes := {}      # 类名 -> Script(查过的缓存, null = 不存在)


func _ready() -> void:
	var mobile_ads = _cls("MobileAds")
	if mobile_ads != null:
		mobile_ads.initialize()
	for k in Ads.KINDS:
		load_ad(k)


func _cls(cls_name: String):
	if _classes.has(cls_name):
		return _classes[cls_name]
	for c in ProjectSettings.get_global_class_list():
		if String(c["class"]) == cls_name:
			_classes[cls_name] = load(String(c["path"]))
			return _classes[cls_name]
	push_warning("[Ads] AdMob 插件类 %s 不存在 —— 这一种广告永远无货" % cls_name)
	_classes[cls_name] = null
	return null


func _unit(kind: String) -> String:
	if bool(_cfg["test_mode"]):
		return String(_cfg["test_unit"])
	return String(_cfg["android"].get("rewarded_" + kind, ""))


func has_ad(kind: String) -> bool:
	return _ads.get(kind) != null


func load_ad(kind: String) -> void:
	if has_ad(kind) or bool(_loading.get(kind, false)):
		return
	var loader_cls = _cls("RewardedAdLoader")
	var req_cls = _cls("AdRequest")
	var cb_cls = _cls("RewardedAdLoadCallback")
	if loader_cls == null or req_cls == null or cb_cls == null or _unit(kind) == "":
		return
	_loading[kind] = true
	var cb = cb_cls.new()
	cb.on_ad_failed_to_load = func(err) -> void:
		call_deferred("_on_load_failed", kind, str(err.message) if err != null else "load")
	cb.on_ad_loaded = func(ad) -> void:
		call_deferred("_on_loaded", kind, ad)
	loader_cls.new().load(_unit(kind), req_cls.new(), cb)


func _on_loaded(kind: String, ad) -> void:
	_loading[kind] = false
	var fsc_cls = _cls("FullScreenContentCallback")
	if fsc_cls != null:
		var fsc = fsc_cls.new()
		fsc.on_ad_dismissed_full_screen_content = func() -> void:
			call_deferred("_on_dismissed", kind)
		fsc.on_ad_failed_to_show_full_screen_content = func(err) -> void:
			call_deferred("_on_show_failed", kind, str(err.message) if err != null else "show")
		ad.full_screen_content_callback = fsc
	_ads[kind] = ad


func _on_load_failed(kind: String, why: String) -> void:
	_loading[kind] = false
	_ads[kind] = null
	push_warning("[Ads] %s 加载失败:%s" % [kind, why])


func show_ad(kind: String) -> void:
	var ad = _ads.get(kind)
	if ad == null:
		failed.emit(kind, "not_ready")
		return
	var listener_cls = _cls("OnUserEarnedRewardListener")
	if listener_cls == null:
		failed.emit(kind, "no_listener")
		return
	ad.show(listener_cls.new(func(_reward) -> void:
		call_deferred("_on_rewarded", kind)))


func _on_rewarded(kind: String) -> void:
	rewarded.emit(kind)


func _on_dismissed(kind: String) -> void:
	_ads[kind] = null
	closed.emit(kind)
	load_ad(kind)


func _on_show_failed(kind: String, why: String) -> void:
	_ads[kind] = null
	failed.emit(kind, why)
	load_ad(kind)
