class_name Uplink
extends RefCounted

## 回传的**簿记层**(1.1 · 2026-08-19)。Tape 一局一个 `run_*.jsonl`(采集侧早齐,
## 事件表见 core/tape.gd + 「能重放任意时刻」判据), 这里管三件事:**哪些文件该传 · 传完怎么记账 ·
## 随包带什么元数据**。网络与时机在 `view/beacon.gd`(HTTPRequest 要挂树, 重试要时钟,
## 都不是 core 的事);本文件守 core 铁律:无时钟、不 import view, 碰文件系统走
## `core/save.gd`/`core/tape.gd` 的同一先例。
##
## ⚑ 记账 = **搬进 `sent/` 子目录**, 不删文件:上传成功的日志仍留在本机
## (用户自己的 Tape 分析线还要用), 只是不再出现在待传清单里。
## 失败不记账 —— 下次扫描自然重试, **「重试」的持久化就是「还没搬走」本身**。
##
## ⚑ 它直接服务两个卡了很久的洞(TODO 1.1 第 4 件):发挥系数(D2)与会话边界(D4)
## 只有真人数据能填 —— 回传上线后不再依赖用户本机拷日志。
## ⚠ 隐私口径:包体 = 游玩事件, 无 PII;install_id 是本机随机数, 只用来把同一台机器的
## 局串起来(D4 的会话边界正需要它)。隐私页已公开, 启用前该不该补一句「匿名遥测」归用户。

const SENT_SUBDIR := "sent"


## 上传配置(data/tape.json 的 upload 节)。缺省全关 —— 端点是用户的部署决定。
static func cfg() -> Dictionary:
	return DB.tape().get("upload", {})


static func enabled() -> bool:
	return bool(cfg().get("enabled", false)) and String(cfg().get("url", "")) != ""


static func url() -> String:
	return String(cfg().get("url", ""))


static func batch_max() -> int:
	return int(cfg().get("batch_max", 3))


static func retry_seconds() -> float:
	return float(cfg().get("retry_seconds", 30.0))


## 待传清单:tape 目录下所有 `run_*.jsonl`, 排除**正在写的那局**(Tape.path())。
## 返回文件名(不含目录), 排序 = 旧局先走(文件名带时间戳, 字典序即时间序)。
static func pending(active_path: String = "") -> Array:
	var out: Array = []
	var d := DirAccess.open(Tape.dir)
	if d == null:
		return out
	var active_file := active_path.get_file()
	for f in d.get_files():
		var name := String(f)
		if name.begins_with("run_") and name.ends_with(".jsonl") and name != active_file:
			out.append(name)
	out.sort()
	return out


## 传成之后:搬进 sent/。返回是否搬成(搬不动就留着, 下次再传一遍 ——
## 服务端按 install_id + 文件名去重, 重复上传无害)。
static func mark_sent(name: String) -> bool:
	var d := DirAccess.open(Tape.dir)
	if d == null:
		return false
	d.make_dir_recursive(SENT_SUBDIR)
	return d.rename(name, SENT_SUBDIR + "/" + name) == OK


static func read_file(name: String) -> PackedByteArray:
	var f := FileAccess.open(Tape.dir + "/" + name, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	return f.get_buffer(f.get_length())


## 随包元数据(HTTP 头)。⚠ 不进包体 —— 包体保持纯 JSONL, 服务端原样落盘,
## 分析线拿到的文件和用户本机的一字不差。
static func headers(name: String) -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/x-ndjson",
		"X-Sync5-Install: %s" % SaveState.install_id(),
		"X-Sync5-File: %s" % name,
		"X-Sync5-Ver: %s" % String(ProjectSettings.get_setting("application/config/version", "dev")),
		"X-Sync5-Platform: %s" % OS.get_name(),
	])
