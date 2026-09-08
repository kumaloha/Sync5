-- core/economy.gd 的镜像:金币的出口(弃牌 / 买牌)与货架抽卡算法。
local P = (...):match("^(.-)[^%.]+$") or ""
local R = (P:gsub("core%.$", ""))
local num = require(R .. "num")
local Rng = require(R .. "rng")
local GameConfig = require(P .. "config")
local Joker = require(P .. "joker")

local Economy = {}
local _fallback_rng = nil   -- Godot 侧 rng == null 时走全局 randi_range;镜像用一条随机种子流替代

function Economy.discard_cost(count)
	if count <= 0 then return 0 end
	return count * GameConfig.DISCARD_COST
end

-- 首张 Target 免费三选一, 之后走同一张价目表(稀有度 + 单卡覆盖)。
function Economy.joker_price(j, has_target)
	if j == nil or j == false then return 0 end
	if j.kind == "target" and not has_target then return 0 end
	local ov = GameConfig.JOKER_PRICE_OVERRIDES[j.id]
	if ov ~= nil then return num.int(ov) end
	local pr = GameConfig.JOKER_PRICES[j.rarity]
	if pr == nil then return 4 end
	return num.int(pr)
end

-- 货架实价 = 基础价 + 装备的 shelf 增减, 地板 1◆(免费只属于首张 Target)。
function Economy.shelf_price(j, slots)
	local has_target = #slots > 0 and slots[1] ~= false and slots[1] ~= nil
	local p = Economy.joker_price(j, has_target)
	if p <= 0 then return p end
	return num.maxi(1, p + Joker.slots_price_delta(slots))
end

-- 所有金币入账都必须走 grant(穷开心的上限卡收入, 不没收存量)。
function Economy.grant(current, gain, slots)
	if gain <= 0 then return current + gain end
	local cap = Joker.slots_coin_cap(slots)
	return num.maxi(current, num.mini(current + gain, cap))
end

function Economy.cap_held(coins, slots)
	return num.mini(coins, Joker.slots_coin_cap(slots))
end

-- 卖回 / 替换退一半(按「有 Target 时」的价目表, 否则 Target 恒 0)。
function Economy.sell_value(j)
	return num.idiv(Economy.joker_price(j, true), 2)
end

function Economy.shelf_weight(j, target_mult, rarity_mult)
	rarity_mult = rarity_mult or {}
	local w = GameConfig.DRAFT_RARITY_WEIGHTS[j.rarity]
	if w == nil then w = 1 end
	w = num.int(w)
	if j.kind == "target" then
		w = num.round(w * target_mult)
	end
	if next(rarity_mult) ~= nil then
		local rm = rarity_mult[j.rarity]
		if rm == nil then rm = 1.0 end
		w = num.round(w * rm)
	end
	return num.maxi(1, w)
end

function Economy._boosted(j, target_mult, rarity_mult, boost)
	local w = Economy.shelf_weight(j, target_mult, rarity_mult)
	if boost == nil or next(boost) == nil then return w end
	local b = boost[tostring(j.id)]
	if b == nil then b = 1.0 end
	return num.maxi(1, num.round(w * b))
end

-- 按每卡权重不放回抽 count 张。rng == nil ⇒ 镜像自己的后备流(Godot 侧是全局 randi_range)。
function Economy.weighted_pick(candidates, count, target_mult, rng, rarity_mult, boost)
	rarity_mult = rarity_mult or {}
	boost = boost or {}
	if rng == nil then
		if _fallback_rng == nil then
			_fallback_rng = Rng.new():seed(os.time())
		end
		rng = _fallback_rng
	end
	local pool = num.shallow(candidates)
	local picked = {}
	while #picked < count and #pool > 0 do
		local total = 0
		for _, j in ipairs(pool) do
			total = total + Economy._boosted(j, target_mult, rarity_mult, boost)
		end
		local roll = rng:randi_range(1, num.maxi(1, total))
		for k = 1, #pool do
			roll = roll - Economy._boosted(pool[k], target_mult, rarity_mult, boost)
			if roll <= 0 then
				picked[#picked + 1] = pool[k]
				table.remove(pool, k)
				break
			end
		end
	end
	return picked
end

-- 第 n 次刷新的价(阶梯);delta = 本店降价, 地板 1◆。
function Economy.reroll_cost(n, delta)
	delta = delta or 0
	return num.maxi(1, GameConfig.DRAFT_REROLL_BASE + n * GameConfig.DRAFT_REROLL_STEP + delta)
end

-- 激励视频换金币(2026-09-08):数在 economy.json;两个上限都没到才发。
function Economy.ad_coins()
	return GameConfig.AD_COINS
end

function Economy.ad_coins_allowed(run_used, shop_used, coins, slots)
	if shop_used >= GameConfig.AD_COINS_PER_SHOP or run_used >= GameConfig.AD_COINS_PER_RUN then return false end
	return Economy.grant(coins, Economy.ad_coins(), slots) > coins
end

return Economy
