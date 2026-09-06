-- core/tape.gd 的镜像:游玩打点 —— 一局一条事件流。这里只做内存队列 + 序列化, 落盘/上传由注入的 sink 做。
-- 毫秒由注入的时钟给(Tape.now_ms);探针/对拍恒定 0。口径铁律:只记事实。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("core%.$", ""))
local num = require(R .. "num")
local json = require(R .. "json")
local DB = require(P .. "db")

local Tape = {}
Tape.RESERVED = { "n", "ms", "e" }
local _cfg = DB.tape()
Tape.enabled = _cfg.enabled and true or false
Tape.to_file = _cfg.to_file and true or false
Tape.dir = tostring(_cfg.dir)
Tape.max_events = num.int(_cfg.max_events)
local _mute = {}
for _, k in ipairs(_cfg.mute or {}) do _mute[tostring(k)] = true end

Tape.clock_ms = -1            -- >= 0 时 _now() 直接返回它(测试注入)
Tape.now_ms = nil             -- 注入:function() -> 当前毫秒(单调即可)
Tape.sink = nil               -- 注入:function(path, lines) 落盘一批 JSONL 行
Tape.stamp = nil              -- 注入:function() -> 秒级时间戳串(缺省用 os.date)

local _buf = {}
local _seq = 0
local _t0 = 0
local _path = ""
local _run_id = ""
local _nth = 0

local function clock()
	if Tape.now_ms then return Tape.now_ms() end
	return num.int(os.clock() * 1000)
end

function Tape._now()
	if Tape.clock_ms >= 0 then return Tape.clock_ms end
	return clock() - _t0
end

function Tape._stamp()
	local s
	if Tape.stamp then
		s = Tape.stamp()
	else
		local ok, d = pcall(os.date, "!%Y%m%dT%H%M%S")
		s = ok and tostring(d) or tostring(clock())
	end
	_nth = _nth + 1
	return string.format("%s_%02d", s, _nth)
end

function Tape.begin(meta)
	if not Tape.enabled then return "" end
	Tape.flush()
	_buf = {}
	_seq = 0
	_t0 = clock()
	_run_id = Tape._stamp()
	_path = string.format("%s/run_%s.jsonl", Tape.dir, _run_id)
	Tape.on("run", meta or {})
	return _run_id
end

function Tape.run_id() return _run_id end
function Tape.path() return _path end

function Tape.on(kind, payload)
	if not Tape.enabled or _mute[kind] then return end
	payload = payload or {}
	local e = num.shallow(payload)
	for _, k in ipairs(Tape.RESERVED) do
		if payload[k] ~= nil then
			print(string.format("[Tape] `%s` 事件的 payload 用了保留字 `%s`", kind, k))
		end
	end
	e.n = _seq
	e.ms = Tape._now()
	e.e = kind
	_seq = _seq + 1
	_buf[#_buf + 1] = e
	if #_buf >= Tape.max_events then
		if Tape.to_file then Tape.flush() else table.remove(_buf, 1) end
	end
end

function Tape.close(payload)
	Tape.on("close", payload or {})
	Tape.flush()
	_path = ""
end

function Tape.flush()
	if not Tape.to_file or #_buf == 0 or _path == "" then return end
	if Tape.sink then
		local lines = {}
		for _, e in ipairs(_buf) do lines[#lines + 1] = json.encode(e) end
		Tape.sink(_path, lines)
	end
	_buf = {}
end

function Tape.events() return _buf end

function Tape.set_mute(kinds)
	_mute = {}
	for _, k in ipairs(kinds) do _mute[tostring(k)] = true end
end

function Tape.reset()
	_buf = {}
	_seq = 0
	_t0 = 0
	_path = ""
	_run_id = ""
	Tape.clock_ms = -1
end

function Tape.cards(arr)
	local out = {}
	for _, c in ipairs(arr) do
		if c ~= nil then out[#out + 1] = c:label() end
	end
	return out
end

function Tape.slots(arr)
	local out = {}
	for i = 1, #arr do
		local j = arr[i]
		out[i] = j and tostring(j.id) or ""
	end
	return out
end

function Tape.fired(popups, slot_arr)
	local out = {}
	for _, p in ipairs(popups) do
		local s = num.int(num.get(p, "slot", -99))
		if s >= 0 and s < #slot_arr and slot_arr[s + 1] then
			out[#out + 1] = tostring(slot_arr[s + 1].id)
		end
	end
	return out
end

return Tape
