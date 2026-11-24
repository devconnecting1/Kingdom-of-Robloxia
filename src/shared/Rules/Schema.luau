--!strict
-- The saved shape of a kingdom. `migrate` brings any older save up to date by filling what is missing, so adding a
-- field never breaks players who saved before it existed.

local Balance = require(script.Parent.Balance)

local Schema = {}

Schema.VERSION = 1

local function copy(t: { [any]: any }): { [any]: any }
	local out = {}
	for k, v in t do
		out[k] = if type(v) == "table" then copy(v) else v
	end
	return out
end

function Schema.new(name: string, now: number): any
	local heroes = {}
	for _, id in Balance.START_HEROES do
		heroes[id] = { level = 1, xp = 0 }
	end
	return {
		version = Schema.VERSION,
		name = name,
		createdAt = now,
		lastSettle = now,
		resources = copy(Balance.START_RESOURCES),
		buildings = copy(Balance.START_BUILDINGS),
		builds = {},
		training = nil,
		researching = nil,
		research = {},
		troops = copy(Balance.START_TROOPS),
		wounded = {},
		heroes = heroes,
		stamina = Balance.STAMINA_MAX,
		staminaAt = now,
		questIndex = 1,
		stats = { trained = 0, hunts = 0, gathered = 0, researched = 0, battlesWon = 0, guild = 0 },
		reports = {},
		reportSeq = 0,
		shieldUntil = 0,
		peaceBroken = false,
		jobSeq = 0,
	}
end

function Schema.migrate(data: any, name: string, now: number): any
	if type(data) ~= "table" then
		return Schema.new(name, now)
	end
	local template = Schema.new(name, now)
	for key, value in template do
		if data[key] == nil and key ~= "training" and key ~= "researching" then
			data[key] = value
		end
	end
	for key, value in template.stats do
		if data.stats[key] == nil then
			data.stats[key] = value
		end
	end
	for _, res in Balance.RESOURCES do
		if type(data.resources[res]) ~= "number" then
			data.resources[res] = 0
		end
	end
	-- Ids removed from the balance table would break every rule that reads them.
	for id in data.troops do
		if not Balance.TROOPS[id] then
			data.troops[id] = nil
		end
	end
	for id in data.heroes do
		if not Balance.HEROES[id] then
			data.heroes[id] = nil
		end
	end
	data.name = name
	data.version = Schema.VERSION
	return data
end

return Schema
