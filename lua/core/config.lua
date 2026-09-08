-- core/config.gd 的镜像:data/run.json + economy.json 之上的静态门面。数只在 data 里。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("core%.$", ""))
local num = require(R .. "num")
local DB = require(P .. "db")

local GameConfig = {}
local _run = DB.run()
local _eco = DB.economy()

local function ints(a)
	local out = {}
	for i, v in ipairs(a) do out[i] = num.int(v) end
	return out
end

GameConfig.PHRASES_PER_SECTION = num.int(_run.phrases_per_section)
GameConfig.PHRASES_PER_SHOP = num.int(_run.phrases_per_shop)
GameConfig.SHOPS_PER_SECTION = num.idiv(GameConfig.PHRASES_PER_SECTION, GameConfig.PHRASES_PER_SHOP)
GameConfig.SECTIONS_PER_GIG = num.int(_run.sections_per_gig)
GameConfig.GIGS_PER_RUN = num.int(_run.gigs_per_run)
GameConfig.SECTIONS_PER_RUN = GameConfig.SECTIONS_PER_GIG * GameConfig.GIGS_PER_RUN
GameConfig.BLIND_NAMES = _run.blind_names
GameConfig.GIG_NAMES = _run.gig_names
GameConfig.SECTION_TARGETS = ints(_run.section_targets)
GameConfig.S1_FACE_MIN_RUN = num.int(_run.s1_face_min_run)
GameConfig.S1_EASY_CHANCE = _run.s1_easy_chance + 0.0
GameConfig.RESOLVE_FEEDBACK = (_run.resolve_feedback or 0.25) + 0.0
GameConfig.LATE_ACT_WINDOW = _run.late_act_window + 0.0
GameConfig.FINAL_ACT_WINDOW = _run.final_act_window + 0.0
GameConfig.EARLY_DISCARD_WINDOW = _run.early_discard_window + 0.0
GameConfig.EARLY_FINISH_LEFT = _run.early_finish_left + 0.0
GameConfig.HAND_SIZE = num.int(_run.hand_size)
GameConfig.CACHE_CAP = num.int(_run.cache_cap)
GameConfig.CACHE_MAX = GameConfig.CACHE_CAP
GameConfig.BEAT_DISCARDS = num.int(_run.beat_budget.discards)
GameConfig.BEAT_DISCARD_BATCH = num.int(_run.beat_budget.discard_batch)
GameConfig.BEAT_SWAPS = num.int(_run.beat_budget.swaps)
GameConfig.BLIND_SAMPLES = num.int(DB.sim().solver.blind_samples)
GameConfig.STARTING_COINS = num.int(_eco.starting_coins)
GameConfig.DISCARD_COST = num.int(_eco.discard_cost)
GameConfig.SECTION_CLEAR_REWARD = num.int(_eco.section_clear_reward)
GameConfig.DRAFT_RARITY_WEIGHTS = _eco.draft_rarity_weights
GameConfig.JOKER_PRICES = _eco.joker_prices
GameConfig.JOKER_PRICE_OVERRIDES = _eco.joker_price_overrides
GameConfig.DRAFT_REROLL_BASE = num.int(_eco.reroll.base)
GameConfig.DRAFT_REROLL_STEP = num.int(_eco.reroll.step)
-- 激励视频换金币的两级上限(2026-09-08);一次给多少 2026-09-09 搬到赞助碟, 走 Economy.ad_coins()
GameConfig.AD_COINS_PER_SHOP = num.int(_eco.ad_coins_per_shop)
GameConfig.AD_COINS_PER_RUN = num.int(_eco.ad_coins_per_run)

function GameConfig.is_wall(section_idx)
	return (section_idx + 1) % GameConfig.SECTIONS_PER_GIG == 0
end

function GameConfig.gig_of(section_idx)
	return num.idiv(section_idx, GameConfig.SECTIONS_PER_GIG)
end

local function walls()
	local out = {}
	for i = 0, GameConfig.SECTIONS_PER_RUN - 1 do
		if GameConfig.is_wall(i) then out[#out + 1] = i end
	end
	return out
end
GameConfig.WALL_SECTIONS = walls()

-- 一局的平均每拍目标(bonus_target_pct 没有真实段目标时的基准, 只此一份)
function GameConfig.avg_beat_target()
	local t = 0.0
	for _, v in ipairs(GameConfig.SECTION_TARGETS) do t = t + v end
	local n = #GameConfig.SECTION_TARGETS
	if n <= 0 then return 0.0 end
	return t / n / GameConfig.PHRASES_PER_SECTION
end

function GameConfig.phrase_duration(section_idx)
	return _run.gig_clocks[num.mini(GameConfig.gig_of(section_idx), GameConfig.GIGS_PER_RUN - 1) + 1] + 0.0
end

function GameConfig.warning_time(duration)
	return duration - _run.warning_offset
end

function GameConfig.lock_time(duration)
	return duration - _run.lock_offset
end

-- 手速预算随实际拍长缩放(动作次数)
function GameConfig.beat_discards(duration, section_idx)
	local full = GameConfig.phrase_duration(section_idx)
	return num.maxi(0, num.int(math.floor(GameConfig.BEAT_DISCARDS * duration / num.maxf(0.1, full))))
end

function GameConfig.discard_batch(duration, section_idx)
	local full = GameConfig.phrase_duration(section_idx)
	return num.maxi(0, num.int(math.floor(GameConfig.BEAT_DISCARD_BATCH * duration / num.maxf(0.1, full))))
end

function GameConfig.blind_name(section_idx)
	return tostring(GameConfig.BLIND_NAMES[section_idx % GameConfig.SECTIONS_PER_GIG + 1])
end

function GameConfig.gig_name(section_idx)
	return tostring(GameConfig.GIG_NAMES[num.mini(GameConfig.gig_of(section_idx), GameConfig.GIGS_PER_RUN - 1) + 1])
end

function GameConfig.section_target(section_idx)
	return GameConfig.SECTION_TARGETS[num.clampi(section_idx, 0, #GameConfig.SECTION_TARGETS - 1) + 1]
end

-- run.json 的其它键(warning_offset / lock_offset 等)的直读口, 编排层用
function GameConfig.raw_run() return _run end

return GameConfig
