--!strict
-- Computer kingdoms. A bot sends the same orders a player can, through World.command, so it can never break a rule a
-- player has to follow. Each personality weighs the same choices differently.

local Army = require(script.Parent.Army)
local Balance = require(script.Parent.Balance)
local City = require(script.Parent.City)
local Combat = require(script.Parent.Combat)
local Economy = require(script.Parent.Economy)
local Rng = require(script.Parent.Rng)

local Bot = {}

Bot.PERSONALITIES = { "builder", "raider", "gatherer", "hunter" }

-- Building priorities per personality; the bot upgrades the first one it can afford.
local PRIORITIES = {
	builder = {
		"farm",
		"sawmill",
		"keep",
		"wall",
		"quarry",
		"manor",
		"academy",
		"mine",
		"vault",
		"barracks",
		"embassy",
		"warhall",
		"infirmary",
		"watchtower",
	},
	raider = {
		"barracks",
		"keep",
		"wall",
		"warhall",
		"farm",
		"sawmill",
		"infirmary",
		"quarry",
		"mine",
		"academy",
		"manor",
		"watchtower",
		"vault",
		"embassy",
	},
	gatherer = {
		"farm",
		"sawmill",
		"quarry",
		"keep",
		"wall",
		"mine",
		"vault",
		"warhall",
		"manor",
		"academy",
		"barracks",
		"embassy",
		"infirmary",
		"watchtower",
	},
	hunter = {
		"keep",
		"wall",
		"barracks",
		"farm",
		"sawmill",
		"warhall",
		"academy",
		"quarry",
		"mine",
		"infirmary",
		"manor",
		"vault",
		"embassy",
		"watchtower",
	},
}

local CLASS_FOR = {
	builder = { "infantry", "ranged" },
	raider = { "cavalry", "infantry", "siege" },
	gatherer = { "infantry", "siege" },
	hunter = { "ranged", "cavalry" },
}

function Bot.newName(rng: Rng.Rng, taken: { [string]: boolean }): string
	for _ = 1, 50 do
		local name = rng:pick(Balance.BOT_NAME_PREFIX) .. rng:pick(Balance.BOT_NAME_SUFFIX)
		if not taken[name] then
			return name
		end
	end
	return "Realm" .. rng:int(100, 999)
end

-- How a new bot starts: a little ahead of a new player, so the realm is not empty of challenge.
function Bot.prepare(data: any, rng: Rng.Rng)
	local keep = rng:int(2, 6)
	data.buildings.keep = keep
	for _, id in Balance.BUILDING_ORDER do
		local def = Balance.BUILDINGS[id]
		if id ~= "keep" and def.unlockKeep <= keep then
			data.buildings[id] = math.max(data.buildings[id] or 0, rng:int(math.max(1, keep - 2), keep))
		end
	end
	data.troops.inf1 = (data.troops.inf1 or 0) + rng:int(100, 400) * keep
	data.troops.rng1 = (data.troops.rng1 or 0) + rng:int(80, 300) * keep
	data.troops.cav1 = (data.troops.cav1 or 0) + rng:int(40, 200) * keep
	-- Bots keep beginner protection off: they are fair game, but they do not attack beginners either.
	data.peaceBroken = keep >= Balance.BEGINNER_KEEP
end

local function tryCommand(world: any, kid: string, name: string, payload: any, now: number): boolean
	local ok = world:command(kid, name, payload, now)
	return ok
end

local function bestTroop(data: any, class: string): string?
	for tier = 3, 1, -1 do
		for id, def in Balance.TROOPS do
			if def.class == class and def.tier == tier and Army.tierUnlocked(data, tier) then
				return id
			end
		end
	end
	return nil
end

-- Up to `share` of the home troops, capped by the march size, strongest first.
local function pickTroops(data: any, share: number): Army.Troops
	local limit = Army.marchSize(data)
	local out = {}
	local total = 0
	for _, id in Balance.TROOP_ORDER do
		local count = math.floor((data.troops[id] or 0) * share)
		local take = math.min(count, limit - total)
		if take > 0 then
			out[id] = take
			total += take
		end
	end
	return out
end

local function freeHero(world: any, k: any): string?
	local ids = {}
	for id in k.data.heroes do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		if not world:heroBusy(k.id, id) then
			return id
		end
	end
	return nil
end

local function neededResource(data: any): string
	local lowest, lowestAmount = "food", math.huge
	for _, res in { "food", "wood", "stone", "ore" } do
		local amount = data.resources[res] or 0
		if amount < lowestAmount then
			lowest, lowestAmount = res, amount
		end
	end
	return lowest
end

function Bot.tick(world: any, kid: string, now: number, rng: Rng.Rng)
	local k = world.kingdoms[kid]
	if not k then
		return
	end
	local data = k.data
	local personality = k.personality or "builder"
	world:settleKingdom(k, now)

	tryCommand(world, kid, "claimQuest", {}, now)

	if #data.builds < City.queueSlots(data) then
		for _, building in PRIORITIES[personality] do
			if tryCommand(world, kid, "upgrade", { building = building }, now) then
				break
			end
		end
	end

	if not data.training then
		local class = rng:pick(CLASS_FOR[personality])
		local troop = bestTroop(data, class)
		if troop then
			local perUnit = Balance.TROOPS[troop].cost
			local affordable = math.huge
			for res, amount in perUnit do
				affordable = math.min(affordable, math.floor((data.resources[res] or 0) * 0.5 / amount))
			end
			local count = math.min(Army.batchSize(data), affordable)
			if count >= 10 then
				tryCommand(world, kid, "train", { troop = troop, count = count }, now)
			end
		end
	end

	if not data.researching and Economy.level(data, "academy") > 0 then
		for _, tech in Balance.RESEARCH_ORDER do
			if tryCommand(world, kid, "research", { tech = tech }, now) then
				break
			end
		end
	end

	if Army.total(data.wounded) > 0 then
		tryCommand(world, kid, "heal", {}, now)
	end

	if k.guild then
		world:helpAll(k, now)
	elseif world.guilds[1] then
		tryCommand(world, kid, "guildJoin", { guild = rng:int(1, #Balance.BOT_GUILDS) }, now)
	end

	local castle = world:castleOf(k)
	local free = Army.marchSlots(data) - #world:marchesOf(kid)
	if free <= 0 or Army.total(data.troops) < 20 then
		return
	end

	-- Hunt a monster the army can hurt badly.
	if data.stamina >= Balance.HUNT_STAMINA and (personality == "hunter" or rng:chance(0.4)) then
		local troops = pickTroops(data, 0.5)
		local hero = freeHero(world, k)
		local heroLevel = if hero then data.heroes[hero].level else nil
		local damage = Combat.huntDamage(data, troops, hero, heroLevel)
		local monster = world:nearest(castle.x, castle.y, 30, function(e)
			return e.kind == "monster" and e.hp <= damage * 3
		end)
		if monster and Army.total(troops) > 0 then
			if
				tryCommand(
					world,
					kid,
					"march",
					{ kind = "hunt", x = monster.x, y = monster.y, troops = troops, hero = hero },
					now
				)
			then
				free -= 1
			end
		end
	end

	-- Raiders pick on kingdoms weaker than them, never beginners or guild mates.
	if free > 0 and personality == "raider" and rng:chance(0.15) then
		local myPower = world:power(k)
		local target = world:nearest(castle.x, castle.y, 35, function(e)
			if e.kind ~= "castle" or e.kid == kid then
				return false
			end
			local other = world.kingdoms[e.kid]
			return other ~= nil
				and (k.guild == nil or other.guild ~= k.guild)
				and not City.isShielded(other.data, now)
				and world:power(other) < myPower * 0.8
		end)
		if target then
			local troops = pickTroops(data, 0.7)
			if
				tryCommand(
					world,
					kid,
					"march",
					{ kind = "attack", x = target.x, y = target.y, troops = troops, hero = freeHero(world, k) },
					now
				)
			then
				free -= 1
			end
		end
	end

	-- Send the rest gathering what the kingdom is shortest of.
	if free > 0 then
		local want = neededResource(data)
		local anyKind = rng:chance(0.3)
		local node = world:nearest(castle.x, castle.y, 25, function(e)
			return e.kind == "node" and not e.gatherer and (anyKind or e.res == want)
		end)
		if node then
			tryCommand(
				world,
				kid,
				"march",
				{ kind = "gather", x = node.x, y = node.y, troops = pickTroops(data, 0.4) },
				now
			)
		end
	end
end

return Bot
