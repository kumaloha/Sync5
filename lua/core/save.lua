-- core/save.gd 的镜像:跨局存档(教学标记 · 会话/局数 · 语言 · install_id · 战绩/见过的脸 · 体力 · 断点)。
-- 存储注入:SaveState.storage = { read = function() -> string|nil, write = function(string) }(她接云变量/本地存档)。
-- 时钟注入:SaveState.now = function() -> unix 秒;SaveState.day_key = function() -> "YYYY-MM-DD"。
-- 探针闸:SaveState.probe = true 时恒当老玩家、绝不落盘(对拍/截图的实验条件不依赖机器本地状态)。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("core%.$", ""))
local num = require(R .. "num")
local json = require(R .. "json")
local Rng = require(R .. "rng")
local DB = require(P .. "db")

local SaveState = {}
SaveState.SAVE_VERSION = 2
SaveState.probe = false
SaveState.storage = nil
SaveState.now = function() return os.time() end
SaveState.day_key = function() return os.date("%Y-%m-%d") end
SaveState.fresh = false           -- true = 启动时清档当新玩家(--fresh)

local _cache = {}
local _loaded = false
local _session_gap = -1
local _session_runs = 0

local function is_probe() return SaveState.probe end
function SaveState.is_probe() return is_probe() end

function SaveState._data()
	if _loaded then return _cache end
	_loaded = true
	_cache = {}
	if SaveState.fresh then return _cache end
	if SaveState.storage and SaveState.storage.read then
		local raw = SaveState.storage.read()
		if type(raw) == "string" and raw ~= "" then
			local parsed = json.decode(raw)
			if type(parsed) == "table" then _cache = SaveState._migrate(parsed) end
		end
	end
	return _cache
end

function SaveState._flush()
	_cache.v = SaveState.SAVE_VERSION
	if SaveState.storage and SaveState.storage.write then
		SaveState.storage.write(json.encode(_cache))
	end
end

function SaveState._migrate(d)
	local v = num.int(num.get(d, "v", 0))
	if v < 1 then d.v = 1 end
	if v < 2 then
		for _, k in ipairs({ "tickets", "tickets_day", "grant_day", "ticket_rolls", "hero", "gems", "assets", "wins_total" }) do
			d[k] = nil
		end
		d.v = 2
	end
	return d
end

-- 测试用:清内存缓存(下次 _data 重读存储)
function SaveState._reload()
	_loaded = false
	_cache = {}
end

function SaveState.seen_tutorial()
	if is_probe() then return true end
	return num.get(SaveState._data(), "seen_tutorial", false) and true or false
end

function SaveState.mark_tutorial_seen()
	if is_probe() or SaveState.seen_tutorial() then return end
	SaveState._data().seen_tutorial = true
	SaveState._data().tutor_gamma = true
	SaveState._flush()
end

function SaveState.tutor_gamma_due()
	if is_probe() then return false end
	return num.get(SaveState._data(), "tutor_gamma", false) and true or false
end

function SaveState.mark_tutor_gamma_done()
	if is_probe() then return end
	if SaveState._data().tutor_gamma ~= nil then
		SaveState._data().tutor_gamma = nil
		SaveState._flush()
	end
end

function SaveState.clear_tutorial()
	if is_probe() then return end
	SaveState._data().seen_tutorial = nil
	SaveState._flush()
end

-- 会话边界:{id, gap, runs_prev};首次启动 gap = -1;探针 id = -1
function SaveState.session_start()
	local now = num.int(SaveState.now())
	if is_probe() then return { id = -1, gap = -1, runs_prev = 0 } end
	local d = SaveState._data()
	local last = num.int(num.get(d, "last_seen", 0))
	local out = {
		id = num.int(num.get(d, "sessions", 0)) + 1,
		gap = (last <= 0) and -1 or num.maxi(0, now - last),
		runs_prev = num.int(num.get(d, "runs_total", 0)),
	}
	_session_gap = out.gap
	_session_runs = 0
	d.sessions = out.id
	d.last_seen = now
	SaveState._flush()
	return out
end

function SaveState.runs_total()
	return num.int(num.get(SaveState._data(), "runs_total", 0))
end

function SaveState.install_id()
	if is_probe() then return "probe" end
	local d = SaveState._data()
	if d.install_id == nil then
		local rng = Rng.new():seed(SaveState.now() * 7919 + num.int((os.clock() * 1e6) % 1000))
		d.install_id = num.hex8(rng:randi()) .. num.hex8(rng:randi())
		SaveState._flush()
	end
	return tostring(d.install_id)
end

function SaveState.run_history()
	if is_probe() then return {} end
	return SaveState._data().history or {}
end

-- 纯函数:战绩圈 → 连胜(正)/连败(负)
function SaveState.streak_of(h)
	local s = 0
	for i = #h, 1, -1 do
		local w = num.get(h[i], "w", false) and true or false
		if s == 0 then s = w and 1 or -1
		elseif s > 0 and w then s = s + 1
		elseif s < 0 and not w then s = s - 1
		else break end
	end
	return s
end

function SaveState.streak() return SaveState.streak_of(SaveState.run_history()) end

function SaveState.faces_seen()
	if is_probe() then return {} end
	return SaveState._data().faces_seen or {}
end

function SaveState.boons_seen()
	if is_probe() then return {} end
	return SaveState._data().boons_seen or {}
end

function SaveState.targets_used()
	if is_probe() then return {} end
	return SaveState._data().targets_used or {}
end

function SaveState.returning_run()
	if is_probe() then return false end
	local Director = require(P .. "director")
	return _session_gap >= Director.return_gap_s() and _session_runs == 0
end

-- 一局收尾的跨局记账(纯函数版 settle_run_meta_in + 带闸的外层)
function SaveState.settle_run_meta_in(d, won, sections_cleared, faces, boon, target_id)
	local h = d.history or {}
	h[#h + 1] = { w = won, d = won and -1 or sections_cleared }
	while #h > 20 do table.remove(h, 1) end
	d.history = h
	d.sections_total = num.int(num.get(d, "sections_total", 0)) + num.maxi(0, sections_cleared)
	local fs = d.faces_seen or {}
	for _, f in ipairs(faces) do
		local s = tostring(f)
		if s ~= "" then fs[s] = num.int(num.get(fs, s, 0)) + 1 end
	end
	d.faces_seen = fs
	if boon ~= nil and boon ~= "" then
		local bs = d.boons_seen or {}
		bs[boon] = num.int(num.get(bs, boon, 0)) + 1
		d.boons_seen = bs
	end
	if target_id ~= nil and target_id ~= "" then
		local tu = d.targets_used or {}
		tu[target_id] = num.int(num.get(tu, target_id, 0)) + 1
		d.targets_used = tu
	end
	return d
end

function SaveState.settle_run_meta(won, sections_cleared, faces, boon, target_id)
	if is_probe() then return end
	SaveState.settle_run_meta_in(SaveState._data(), won, sections_cleared, faces, boon or "", target_id or "")
	SaveState._flush()
end

function SaveState.lang()
	if is_probe() then return "" end
	return tostring(num.get(SaveState._data(), "lang", ""))
end

function SaveState.set_lang(l)
	if is_probe() then return end
	if l == "" then SaveState._data().lang = nil else SaveState._data().lang = l end
	SaveState._flush()
	require(P .. "lingo").force("")
end

function SaveState.note_run_started()
	if is_probe() then return end
	_session_runs = _session_runs + 1
	local d = SaveState._data()
	d.runs_total = num.int(num.get(d, "runs_total", 0)) + 1
	if tostring(num.get(d, "runs_day", "")) ~= SaveState.day_key() then
		d.runs_day = SaveState.day_key()
		d.runs_today = 0
	end
	d.runs_today = num.int(num.get(d, "runs_today", 0)) + 1
	d.last_seen = num.int(SaveState.now())
	SaveState._flush()
end

-- ---- 体力(纯函数层 + 带闸外层) ----
function SaveState.energy_max()
	return num.int(num.get(DB.profile(), "energy_max", 5))
end

function SaveState._energy_in(d, day, cap)
	if tostring(num.get(d, "energy_day", "")) ~= day then return cap end
	return num.clampi(num.int(num.get(d, "energy", cap)), 0, cap)
end

function SaveState._spend_in(d, n, day, cap)
	local cur = SaveState._energy_in(d, day, cap)
	if cur < n then return false end
	d.energy_day = day
	d.energy = cur - n
	return true
end

function SaveState._spend_for_run_in(d, tutorial, day, cap)
	if tutorial then return true end
	return SaveState._spend_in(d, 1, day, cap)
end

function SaveState.energy()
	if is_probe() then return SaveState.energy_max() end
	return SaveState._energy_in(SaveState._data(), SaveState.day_key(), SaveState.energy_max())
end

function SaveState.spend_energy(n)
	n = n or 1
	if is_probe() then return true end
	if not SaveState._spend_in(SaveState._data(), n, SaveState.day_key(), SaveState.energy_max()) then return false end
	SaveState._flush()
	return true
end

function SaveState.spend_energy_for_run(tutorial)
	if is_probe() then return true end
	if not SaveState._spend_for_run_in(SaveState._data(), tutorial, SaveState.day_key(), SaveState.energy_max()) then return false end
	SaveState._flush()
	return true
end

-- 看广告换体力(2026-09-08):未满才许 · 每日上限 · 入账不超满值 · 只有真发奖才计数。
function SaveState.ad_energy_amount()
	return num.int(num.get(DB.profile(), "ad_energy", 0))
end

function SaveState.ad_energy_per_day()
	return num.int(num.get(DB.profile(), "ad_energy_per_day", 0))
end

function SaveState._ad_energy_used_in(d, day)
	if tostring(num.get(d, "ad_energy_day", "")) ~= day then return 0 end
	return num.maxi(0, num.int(num.get(d, "ad_energy_used", 0)))
end

function SaveState._ad_energy_can_in(d, day, cap, per_day)
	return SaveState._energy_in(d, day, cap) < cap and SaveState._ad_energy_used_in(d, day) < per_day
end

function SaveState._ad_energy_in(d, day, cap, per_day, amount)
	if not SaveState._ad_energy_can_in(d, day, cap, per_day) then return false end
	local cur = SaveState._energy_in(d, day, cap)
	local used = SaveState._ad_energy_used_in(d, day)
	d.energy_day = day
	d.energy = num.mini(cap, cur + num.maxi(0, amount))
	d.ad_energy_day = day
	d.ad_energy_used = used + 1
	return true
end

function SaveState.can_add_energy_from_ad()
	if is_probe() then return false end
	return SaveState._ad_energy_can_in(SaveState._data(), SaveState.day_key(),
		SaveState.energy_max(), SaveState.ad_energy_per_day())
end

function SaveState.add_energy_from_ad()
	if is_probe() then return false end
	if not SaveState._ad_energy_in(SaveState._data(), SaveState.day_key(), SaveState.energy_max(),
			SaveState.ad_energy_per_day(), SaveState.ad_energy_amount()) then
		return false
	end
	SaveState._flush()
	return true
end

function SaveState.profile()
	local per = num.maxi(1, num.int(num.get(DB.profile(), "xp_per_level", 4)))
	local xp = is_probe() and 0 or num.int(num.get(SaveState._data(), "sections_total", 0))
	return { level = num.idiv(xp, per) + 1, xp = num.imod(xp, per), xp_max = per }
end

-- ---- 断点续玩 ----
function SaveState.checkpoint()
	if is_probe() then return {} end
	return SaveState._data().resume or {}
end

function SaveState.save_checkpoint(d)
	if is_probe() then return end
	SaveState._data().resume = d
	SaveState._flush()
end

function SaveState.clear_checkpoint()
	if is_probe() then return end
	if SaveState._data().resume ~= nil then
		SaveState._data().resume = nil
		SaveState._flush()
	end
end

return SaveState
