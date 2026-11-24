--!strict
-- Costs, production, storage and the bonuses that research and heroes add. Pure functions of a kingdom's data.

local Balance = require(script.Parent.Balance)

local Economy = {}

export type Resources = { [string]: number }

function Economy.level(data: any, building: string): number
	return data.buildings[building] or 0
end

-- Cost to raise `building` to `level`.
function Economy.buildingCost(building: string, level: number): Resources
	local def = Balance.BUILDINGS[building]
	local factor = Balance.COST_GROWTH ^ (level - 1)
	local cost = {}
	for res, amount in def.baseCost do
		cost[res] = math.floor(amount * factor)
	end
	return cost
end

function Economy.buildingTime(building: string, level: number): number
	local def = Balance.BUILDINGS[building]
	return math.floor(def.baseTime * Balance.TIME_GROWTH ^ (level - 1))
end

function Economy.researchCost(tech: string, level: number): Resources
	local def = Balance.RESEARCH[tech]
	local factor = Balance.RESEARCH_COST_GROWTH ^ (level - 1)
	local cost = {}
	for res, amount in def.baseCost do
		cost[res] = math.floor(amount * factor)
	end
	return cost
end

function Economy.researchTime(data: any, tech: string, level: number): number
	local def = Balance.RESEARCH[tech]
	local speed = 1 + Economy.level(data, "academy") * Balance.EFFECTS.academySpeedPerLevel
	return math.max(1, math.floor(def.baseTime * Balance.RESEARCH_TIME_GROWTH ^ (level - 1) / speed))
end

-- Sum of a research stat over every tech that boosts it.
function Economy.researchBonus(data: any, stat: string): number
	local total = 0
	for tech, level in data.research do
		local def = Balance.RESEARCH[tech]
		if def and def.stat == stat then
			total += def.perLevel * level
		end
	end
	return total
end

function Economy.heroBonus(heroId: string?, level: number?, stat: string, class: string?): number
	if not heroId then
		return 0
	end
	local def = Balance.HEROES[heroId]
	if not def or def.stat ~= stat then
		return 0
	end
	if def.class and class and def.class ~= class then
		return 0
	end
	if def.class and not class then
		return 0
	end
	return def.base + def.perLevel * ((level or 1) - 1)
end

-- Resources per hour, research included.
function Economy.production(data: any): Resources
	local rates = {}
	for _, res in Balance.RESOURCES do
		rates[res] = 0
	end
	for building, def in Balance.BUILDINGS do
		local level = Economy.level(data, building)
		if def.produces and def.baseRate and level > 0 then
			local base = def.baseRate * level ^ Balance.RATE_EXPONENT
			rates[def.produces] += base * (1 + Economy.researchBonus(data, def.produces))
		end
	end
	for res, rate in rates do
		rates[res] = math.floor(rate)
	end
	return rates
end

-- Production stops at the storage cap; gathering, loot and rewards may go past it.
function Economy.storageCap(data: any): number
	return math.floor(Balance.STORAGE_BASE * Balance.STORAGE_GROWTH ^ (Economy.level(data, "keep") - 1))
end

function Economy.protected(data: any): number
	local level = Economy.level(data, "vault")
	if level <= 0 then
		return 0
	end
	return math.floor(Balance.EFFECTS.vaultBase * level ^ Balance.EFFECTS.vaultExponent)
end

function Economy.missing(resources: Resources, cost: Resources): Resources?
	local missing: Resources = {}
	local short = false
	for res, amount in cost do
		local have = resources[res] or 0
		if have < amount then
			missing[res] = amount - have
			short = true
		end
	end
	return if short then missing else nil
end

function Economy.canAfford(resources: Resources, cost: Resources): boolean
	return Economy.missing(resources, cost) == nil
end

function Economy.pay(resources: Resources, cost: Resources)
	for res, amount in cost do
		resources[res] = (resources[res] or 0) - amount
	end
end

function Economy.add(resources: Resources, gains: Resources)
	for res, amount in gains do
		resources[res] = (resources[res] or 0) + amount
	end
end

function Economy.scale(cost: Resources, factor: number): Resources
	local out = {}
	for res, amount in cost do
		out[res] = math.floor(amount * factor)
	end
	return out
end

-- Gold to finish a task now: free in the last seconds, then a little gold per started minute.
function Economy.finishGold(secondsLeft: number): number
	if secondsLeft <= Balance.FREE_FINISH_SECONDS then
		return 0
	end
	return math.ceil(secondsLeft / 60) * Balance.GOLD_PER_MINUTE
end

function Economy.buildingPower(building: string, level: number): number
	if level <= 0 then
		return 0
	end
	return math.floor(Balance.BUILDINGS[building].power * level ^ 1.4)
end

return Economy
