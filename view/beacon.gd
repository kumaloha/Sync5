class_name Beacon
extends Node

## 回传的**网络与时机层**(1.1 · 2026-08-19)。簿记在 `core/uplink.gd`, 这里只管:
## 什么时候扫(开机稳定后一次 + 每次回首页 poke 一次)· 一次传几个(batch_max)·
## 失败等多久再试(retry_seconds, 本次会话最多 RETRY_MAX 轮 —— 之后留给下个会话,
## 「还没搬进 sent/」本身就是持久化的重试队列)。
##
## ⚠ 探针恒不传(和 Music 自静音同一条纪律):探针的日志是探针产物, 传上去会污染
## 真人数据 —— 这比省带宽重要得多。
## ⚠ 一次只挂一个 HTTPRequest, 串行走完 batch —— 移动端并发连接不值得为日志付出。

const RETRY_MAX := 3
const FIRST_SCAN_DELAY := 5.0   # 开机让路:别和启动加载抢 IO

var _req: HTTPRequest
var _queue: Array = []
var _cur := ""
var _retries := 0
var _busy := false


func _ready() -> void:
	if SaveState.is_probe() or not Uplink.enabled():
		set_process(false)
		return
	_req = HTTPRequest.new()
	_req.timeout = 20.0
	add_child(_req)
	_req.request_completed.connect(_on_done)
	get_tree().create_timer(FIRST_SCAN_DELAY).timeout.connect(poke)


## 编排器在回首页时调(一局刚收尾, 正好是它的文件刚写完的时刻)。
## 正在传就不打扰 —— 队列走完自然会把新文件捞进下一轮。
func poke() -> void:
	if _req == null or _busy:
		return
	_queue = Uplink.pending(Tape.path()).slice(0, Uplink.batch_max())
	_retries = 0
	_next()


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	_cur = String(_queue[0])
	var body := Uplink.read_file(_cur)
	if body.is_empty():
		# 空文件/读不到:直接记账搬走, 不值得为它走网络
		Uplink.mark_sent(_cur)
		_queue.pop_front()
		_next()
		return
	var err := _req.request_raw(Uplink.url(), Uplink.headers(_cur),
		HTTPClient.METHOD_POST, body)
	if err != OK:
		_fail()


func _on_done(result: int, code: int, _hdrs: PackedStringArray, _body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
		Uplink.mark_sent(_cur)
		_queue.pop_front()
		_retries = 0
		_next()
	else:
		_fail()


func _fail() -> void:
	_retries += 1
	if _retries > RETRY_MAX:
		_busy = false   # 本会话放弃;文件还在待传清单里, 下个会话接着来
		return
	get_tree().create_timer(Uplink.retry_seconds()).timeout.connect(_next)
