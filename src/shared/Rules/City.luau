--!strict
-- Everything that happens inside one kingdom: production, the build, training and research queues, heroes, healing
-- and the quest chain. Timers are absolute timestamps and `settle` catches up lazily, so a kingdom keeps growing
-- while its owner is offline and nothing ticks per frame.

local Army = require(script.Parent.Army)
local Balance = require(script.Parent.Balance)
local Economy = require(script.Parent.Economy)

local City = {}

export type Event = { kind: string, [string]: any }

local function nextJobId(data: any): number
	data.jobSeq = (data.jobSeq or 0) + 1
	return data.jobSeq
end

function City.queueSlots(data: any): number
	return 1 + (if Economy.level(data, "manor") >= Balance.EFFECTS.manorBuilderLevel then 1 else 0)
end

function City.staminaSeconds(data: any): number
	return Balance.STAMINA_SECONDS / (1 + Economy.researchBonus(data, "staminaRegen"))
end

-- Brings the kingdom up to `now`: production, stamina and every finished job. Returns what finished.
function City.settle(data: any, now: number): { Event }
	local events: { Event } = {}
	local dt = now - data.lastSettle
	if dt > 0 then
		local rates = Economy.production(data)
		local cap = Economy.storageCap(data)
		for res, rate in rates do
			local have = data.resources[res] or 0
			if have < cap then
				data.resources[res] = math.min(cap, have + rate * dt / 3600)
			end
		end
		data.lastSettle = now
	end

	local regen = City.staminaSeconds(data)
	if data.stamina >= Balance.STAMINA_MAX then
		data.staminaAt = now
	else
		local gained = math.floor((now - data.staminaAt) / regen)
		if gained > 0 then
			data.stamina = math.min(Balance.STAMINA_MAX, data.stamina + gained)
			data.staminaAt += gained * regen
		end
	end

	local keep = {}
	for _, job in data.builds do
		if job.endAt <= now then
			data.buildings[job.building] = job.level
			table.insert(events, { kind = "built", building = job.building, level = job.level, id = job.id })
		else
			table.insert(keep, job)
		end
	end
	data.builds = keep

	local training = data.training
	if training and training.endAt <= now then
		data.troops[training.troop] = (data.troops[training.troop] or 0) + training.count
		data.stats.trained += training.count
		data.training = nil
		table.insert(events, { kind = "trained", troop = training.troop, count = training.count, id = training.id })
	end

	local researching = data.researching
	if researching and researching.endAt <= now then
		data.research[researching.tech] = researching.level
		data.stats.researched += 1
		data.researching = nil
		table.insert(
			events,
			{ kind = "researched", tech = researching.tech, level = researching.level, id = researching.id }
		)
	end
	return events
end

-- Buildings -----------------------------------------------------------------------------------------------------------

function City.pendingLevel(data: any, building: string): number
	local level = Economy.level(data, building)
	for _, job in data.builds do
		if job.building == building then
			level = math.max(level, job.level)
		end
	end
	return level
end

-- Checks an upgrade and returns the error key, or nil plus the cost, time and target level.
function City.checkUpgrade(data: any, building: string): (string?, Economy.Resources?, number?, number?)
	local def = Balance.BUILDINGS[building]
	if not def then
		return "err.unknown"
	end
	for _, job in data.builds do
		if job.building == building then
			return "err.alreadyBuilding"
		end
	end
	local nextLevel = Economy.level(data, building) + 1
	if nextLevel > def.maxLevel then
		return "err.maxLevel"
	end
	local keep = Economy.level(data, "keep")
	if building == "keep" then
		if nextLevel >= 3 and Economy.level(data, "wall") < nextLevel - 1 then
			return "err.needWall"
		end
	else
		if keep < math.max(1, def.unlockKeep) then
			return "err.locked"
		end
		if nextLevel > keep then
			return "err.needKeep"
		end
	end
	if #data.builds >= City.queueSlots(data) then
		return "err.queueFull"
	end
	local cost = Economy.buildingCost(building, nextLevel)
	if not Economy.canAfford(data.resources, cost) then
		return "err.notEnough", cost, Economy.buildingTime(building, nextLevel), nextLevel
	end
	return nil, cost, Economy.buildingTime(building, nextLevel), nextLevel
end

function City.startUpgrade(data: any, building: string, now: number): (string?, any)
	local err, cost, time, level = City.checkUpgrade(data, building)
	if err then
		return err
	end
	Economy.pay(data.resources, cost :: Economy.Resources)
	local job = {
		id = nextJobId(data),
		building = building,
		level = level,
		startAt = now,
		endAt = now + (time :: number),
	}
	table.insert(data.builds, job)
	return nil, job
end

-- Troops --------------------------------------------------------------------------------------------------------------

function City.checkTraining(data: any, troop: string, count: number): (string?, Economy.Resources?, number?)
	local def = Balance.TROOPS[troop]
	if not def then
		return "err.unknown"
	end
	if not Army.tierUnlocked(data, def.tier) then
		return "err.locked"
	end
	if data.training then
		return "err.queueFull"
	end
	if count < 1 or count > Army.batchSize(data) then
		return "err.batch"
	end
	local cost = Army.trainCost(troop, count)
	local time = Army.trainTime(data, troop, count)
	if not Economy.canAfford(data.resources, cost) then
		return "err.notEnough", cost, time
	end
	return nil, cost, time
end

function City.startTraining(data: any, troop: string, count: number, now: number): (string?, any)
	local err, cost, time = City.checkTraining(data, troop, count)
	if err then
		return err
	end
	Economy.pay(data.resources, cost :: Economy.Resources)
	data.training = {
		id = nextJobId(data),
		troop = troop,
		count = count,
		startAt = now,
		endAt = now + (time :: number),
	}
	return nil, data.training
end

function City.heal(data: any): string?
	if Army.total(data.wounded) <= 0 then
		return "err.nothing"
	end
	local cost = Army.healCost(data.wounded)
	if not Economy.canAfford(data.resources, cost) then
		return "err.notEnough"
	end
	Economy.pay(data.resources, cost)
	Army.add(data.troops, data.wounded)
	data.wounded = {}
	return nil
end

-- Research ------------------------------------------------------------------------------------------------------------

function City.checkResearch(data: any, tech: string): (string?, Economy.Resources?, number?, number?)
	local def = Balance.RESEARCH[tech]
	if not def then
		return "err.unknown"
	end
	local academy = Economy.level(data, "academy")
	if academy < 1 then
		return "err.locked"
	end
	if data.researching then
		return "err.queueFull"
	end
	local nextLevel = (data.research[tech] or 0) + 1
	if nextLevel > def.maxLevel then
		return "err.maxLevel"
	end
	if nextLevel > academy then
		return "err.needAcademy"
	end
	local cost = Economy.researchCost(tech, nextLevel)
	local time = Economy.researchTime(data, tech, nextLevel)
	if not Economy.canAfford(data.resources, cost) then
		return "err.notEnough", cost, time, nextLevel
	end
	return nil, cost, time, nextLevel
end

function City.startResearch(data: any, tech: string, now: number): (string?, any)
	local err, cost, time, level = City.checkResearch(data, tech)
	if err then
		return err
	end
	Economy.pay(data.resources, cost :: Economy.Resources)
	data.researching = {
		id = nextJobId(data),
		tech = tech,
		level = level,
		startAt = now,
		endAt = now + (time :: number),
	}
	return nil, data.researching
end

-- Jobs: finishing early and guild help --------------------------------------------------------------------------------

function City.findJob(data: any, jobId: number): any
	for _, job in data.builds do
		if job.id == jobId then
			return job
		end
	end
	if data.training and data.training.id == jobId then
		return data.training
	end
	if data.researching and data.researching.id == jobId then
		return data.researching
	end
	return nil
end

function City.finishJob(data: any, jobId: number, now: number): string?
	local job = City.findJob(data, jobId)
	if not job then
		return "err.unknown"
	end
	local gold = Economy.finishGold(job.endAt - now)
	if (data.resources.gold or 0) < gold then
		return "err.notEnough"
	end
	data.resources.gold -= gold
	job.endAt = now
	return nil
end

function City.reduceJob(data: any, jobId: number, seconds: number): boolean
	local job = City.findJob(data, jobId)
	if not job then
		return false
	end
	job.endAt -= seconds
	return true
end

-- Heroes --------------------------------------------------------------------------------------------------------------

function City.heroXpToNext(level: number): number
	return math.floor(Balance.HERO_XP_BASE * level ^ Balance.HERO_XP_EXPONENT)
end

function City.recruitHero(data: any, heroId: string): string?
	local def = Balance.HEROES[heroId]
	if not def then
		return "err.unknown"
	end
	if data.heroes[heroId] then
		return "err.owned"
	end
	if (data.resources.gold or 0) < def.recruitGold then
		return "err.notEnough"
	end
	data.resources.gold -= def.recruitGold
	data.heroes[heroId] = { level = 1, xp = 0 }
	return nil
end

function City.giveHeroXp(data: any, heroId: string?, xp: number): number
	if not heroId then
		return 0
	end
	local hero = data.heroes[heroId]
	if not hero then
		return 0
	end
	local gained = 0
	hero.xp += xp
	while hero.level < Balance.HERO_MAX_LEVEL and hero.xp >= City.heroXpToNext(hero.level) do
		hero.xp -= City.heroXpToNext(hero.level)
		hero.level += 1
		gained += 1
	end
	if hero.level >= Balance.HERO_MAX_LEVEL then
		hero.xp = 0
	end
	return gained
end

-- Quests --------------------------------------------------------------------------------------------------------------

function City.quest(data: any): (Balance.QuestDef?, number, boolean)
	local def = Balance.QUESTS[data.questIndex]
	if not def then
		return nil, 0, false
	end
	local progress
	if def.kind == "building" then
		progress = Economy.level(data, def.target :: string)
	else
		progress = data.stats[def.kind] or 0
	end
	return def, math.min(progress, def.amount), progress >= def.amount
end

function City.claimQuest(data: any): (string?, any)
	local def, _, done = City.quest(data)
	if not def then
		return "err.nothing"
	end
	if not done then
		return "err.notDone"
	end
	Economy.add(data.resources, def.reward)
	data.questIndex += 1
	return nil, def
end

-- Status --------------------------------------------------------------------------------------------------------------

function City.power(data: any, marching: Army.Troops?): number
	local p = 0
	for building, level in data.buildings do
		if Balance.BUILDINGS[building] then
			p += Economy.buildingPower(building, level)
		end
	end
	p += Army.power(data.troops) * 3
	if marching then
		p += Army.power(marching) * 3
	end
	for _, level in data.research do
		p += level * 25
	end
	for _, hero in data.heroes do
		p += hero.level * 15
	end
	return p
end

function City.isShielded(data: any, now: number): boolean
	if data.shieldUntil > now then
		return true
	end
	return Economy.level(data, "keep") < Balance.BEGINNER_KEEP and not data.peaceBroken
end

function City.addReport(data: any, report: any, now: number)
	data.reportSeq += 1
	report.id = data.reportSeq
	report.t = now
	report.read = false
	table.insert(data.reports, 1, report)
	while #data.reports > Balance.REPORTS_KEPT do
		table.remove(data.reports)
	end
end

return City
