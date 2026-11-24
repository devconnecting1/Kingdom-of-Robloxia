--!strict
-- Troop counts, march limits and the stats an army fights with.

local Balance = require(script.Parent.Balance)
local Economy = require(script.Parent.Economy)

local Army = {}

export type Troops = { [string]: number }

function Army.total(troops: Troops): number
	local n = 0
	for _, count in troops do
		n += count
	end
	return n
end

function Army.power(troops: Troops): number
	local p = 0
	for id, count in troops do
		local def = Balance.TROOPS[id]
		if def then
			p += def.power * count
		end
	end
	return p
end

function Army.add(into: Troops, troops: Troops)
	for id, count in troops do
		into[id] = (into[id] or 0) + count
	end
end

function Army.remove(from: Troops, troops: Troops)
	for id, count in troops do
		local left = (from[id] or 0) - count
		from[id] = if left > 0 then left else nil
	end
end

function Army.has(available: Troops, troops: Troops): boolean
	for id, count in troops do
		if (available[id] or 0) < count then
			return false
		end
	end
	return true
end

function Army.copy(troops: Troops): Troops
	local out = {}
	for id, count in troops do
		if count > 0 then
			out[id] = count
		end
	end
	return out
end

-- Keeps only known troop ids with positive whole counts. Anything else from a client makes the whole order invalid.
function Army.sanitize(raw: any): Troops?
	if type(raw) ~= "table" then
		return nil
	end
	local out = {}
	local any = false
	for id, count in raw do
		if type(id) ~= "string" or not Balance.TROOPS[id] then
			return nil
		end
		if type(count) ~= "number" or count ~= count or count % 1 ~= 0 or count < 0 or count > 1e7 then
			return nil
		end
		if count > 0 then
			out[id] = count
			any = true
		end
	end
	return if any then out else nil
end

function Army.batchSize(data: any): number
	local level = Economy.level(data, "barracks")
	return Balance.EFFECTS.barracksBatchBase + Balance.EFFECTS.barracksBatchPerLevel * level
end

function Army.tierUnlocked(data: any, tier: number): boolean
	local level = Economy.level(data, "barracks")
	if tier >= 3 then
		return level >= Balance.EFFECTS.tier3Barracks
	elseif tier == 2 then
		return level >= Balance.EFFECTS.tier2Barracks
	end
	return level >= 1
end

function Army.infirmaryCap(data: any): number
	return Economy.level(data, "infirmary") * Balance.EFFECTS.infirmaryPerLevel
end

function Army.marchSize(data: any): number
	return Balance.EFFECTS.marchSizeBase + Balance.EFFECTS.marchSizePerLevel * Economy.level(data, "warhall")
end

function Army.marchSlots(data: any): number
	local level = Economy.level(data, "warhall")
	return math.min(Balance.EFFECTS.marchSlotsMax, 2 + level // Balance.EFFECTS.marchSlotsEvery)
end

function Army.trainTime(data: any, troopId: string, count: number): number
	local def = Balance.TROOPS[troopId]
	local speed = 1 + Economy.researchBonus(data, "trainSpeed")
	return math.max(1, math.floor(def.time * count / speed))
end

function Army.trainCost(troopId: string, count: number): Economy.Resources
	return Economy.scale(Balance.TROOPS[troopId].cost, count)
end

function Army.healCost(troops: Troops): Economy.Resources
	local cost: Economy.Resources = {}
	for id, count in troops do
		local def = Balance.TROOPS[id]
		if def then
			for res, amount in def.cost do
				cost[res] = (cost[res] or 0) + amount * count * Balance.HEAL_COST_SHARE
			end
		end
	end
	for res, amount in cost do
		cost[res] = math.ceil(amount)
	end
	return cost
end

-- Effective per-unit stats of a troop type in a given army.
function Army.unitStats(data: any, troopId: string, heroId: string?, heroLevel: number?): (number, number, number)
	local def = Balance.TROOPS[troopId]
	local atk = def.atk
		* (1 + Economy.researchBonus(data, "atk") + Economy.heroBonus(heroId, heroLevel, "atk", def.class))
	local defence = def.def
		* (1 + Economy.researchBonus(data, "def") + Economy.heroBonus(heroId, heroLevel, "def", def.class))
	local hp = def.hp * (1 + Economy.researchBonus(data, "hp"))
	return atk, defence, hp
end

function Army.load(data: any, troops: Troops, heroId: string?, heroLevel: number?): number
	local total = 0
	for id, count in troops do
		total += Balance.TROOPS[id].load * count
	end
	local bonus = 1 + Economy.researchBonus(data, "load") + Economy.heroBonus(heroId, heroLevel, "load", nil)
	return math.floor(total * bonus)
end

-- Tiles per minute: the slowest troop sets the pace.
function Army.speed(data: any, troops: Troops, heroId: string?, heroLevel: number?): number
	local slowest = math.huge
	for id in troops do
		slowest = math.min(slowest, Balance.TROOPS[id].speed)
	end
	if slowest == math.huge then
		slowest = 12
	end
	local bonus = 1 + Economy.researchBonus(data, "marchSpeed") + Economy.heroBonus(heroId, heroLevel, "march", nil)
	return slowest * bonus
end

function Army.distance(ax: number, ay: number, bx: number, by: number): number
	return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

function Army.travelSeconds(
	data: any,
	troops: Troops,
	heroId: string?,
	heroLevel: number?,
	ax: number,
	ay: number,
	bx: number,
	by: number
): number
	local tiles = Army.distance(ax, ay, bx, by)
	return math.max(3, math.ceil(tiles / Army.speed(data, troops, heroId, heroLevel) * 60))
end

return Army
