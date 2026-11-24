--!strict
-- One realm: the map, every kingdom on it (players and bots alike), marches, battles and guilds.
--
-- It is pure Luau with no Roblox API, so the server runs it and the Lune tests run the very same code, including whole
-- sessions with 50 kingdoms. Time always comes in as `now`; randomness from the seeded Rng.
-- Changes are collected in dirty sets that the server drains after each step, so it pushes only what changed.

local Army = require(script.Parent.Army)
local Balance = require(script.Parent.Balance)
local City = require(script.Parent.City)
local Combat = require(script.Parent.Combat)
local Economy = require(script.Parent.Economy)
local MapGen = require(script.Parent.MapGen)
local Protocol = require(script.Parent.Protocol)
local Rng = require(script.Parent.Rng)

local World = {}
World.__index = World

type World = any
type Kingdom = any
type March = any

local SIZE = Balance.MAP_SIZE
local SCOUT_SPEED = 30

local function key(x: number, y: number): number
	return x + y * SIZE
end

function World.new(seed: number, now: number): World
	local self = setmetatable({
		seed = seed,
		rng = Rng.new(seed),
		entities = {},
		tiles = {},
		chunks = {},
		nextEntity = 0,
		nodeCount = 0,
		monsterCount = 0,
		kingdoms = {},
		kingdomCount = 0,
		marches = {},
		nextMarch = 0,
		guilds = {},
		nextGuild = 0,
		colorIndex = 0,
		lastRespawn = now,
		lastNow = now,
		ranking = {},
		rankingAt = -math.huge,
		-- Drained by the server after every step and command.
		dirtyKingdoms = {},
		dirtyChunks = {},
		marchesDirty = false,
		castlesDirty = false,
		toasts = {},
	}, World)
	for i = 0, MapGen.chunkCount() - 1 do
		self.chunks[i] = {}
	end
	self:respawn(now, true)
	for _, pair in Balance.BOT_GUILDS do
		self:newGuild(pair[1], pair[2], nil)
	end
	return self
end

-- Entities ------------------------------------------------------------------------------------------------------------

function World.entityAt(self: World, x: number, y: number): any
	local id = self.tiles[key(x, y)]
	return if id then self.entities[id] else nil
end

function World.touch(self: World, e: any)
	self.dirtyChunks[MapGen.chunkOf(e.x, e.y)] = true
end

function World.addEntity(self: World, e: any): number
	self.nextEntity += 1
	e.id = self.nextEntity
	self.entities[e.id] = e
	self.tiles[key(e.x, e.y)] = e.id
	self.chunks[MapGen.chunkOf(e.x, e.y)][e.id] = true
	if e.kind == "node" then
		self.nodeCount += 1
	elseif e.kind == "monster" then
		self.monsterCount += 1
	end
	self:touch(e)
	return e.id
end

function World.removeEntity(self: World, id: number)
	local e = self.entities[id]
	if not e then
		return
	end
	self.entities[id] = nil
	self.tiles[key(e.x, e.y)] = nil
	self.chunks[MapGen.chunkOf(e.x, e.y)][id] = nil
	if e.kind == "node" then
		self.nodeCount -= 1
	elseif e.kind == "monster" then
		self.monsterCount -= 1
	end
	self:touch(e)
end

function World.moveEntity(self: World, e: any, x: number, y: number)
	self:touch(e)
	self.tiles[key(e.x, e.y)] = nil
	self.chunks[MapGen.chunkOf(e.x, e.y)][e.id] = nil
	e.x, e.y = x, y
	if e.kind == "castle" then
		self.castlesDirty = true
	end
	self.tiles[key(x, y)] = e.id
	self.chunks[MapGen.chunkOf(x, y)][e.id] = true
	self:touch(e)
end

function World.castleSpotFree(self: World, x: number, y: number, ignore: number?): boolean
	if not MapGen.inBounds(x, y) or MapGen.biome(self.seed, x, y) == "lake" then
		return false
	end
	local here = self:entityAt(x, y)
	if here and here.id ~= ignore then
		return false
	end
	for _, k in self.kingdoms do
		local c = self.entities[k.castle]
		if c and c.id ~= ignore then
			if math.max(math.abs(c.x - x), math.abs(c.y - y)) < Balance.CASTLE_SPACING then
				return false
			end
		end
	end
	return true
end

function World.respawn(self: World, now: number, initial: boolean)
	self.lastRespawn = now
	local batch = if initial then math.huge else 40
	local function free(x: number, y: number): boolean
		return self:entityAt(x, y) == nil and MapGen.biome(self.seed, x, y) ~= "lake"
	end
	local spawned = 0
	while self.nodeCount < Balance.NODE_TARGET and spawned < batch do
		local x, y = MapGen.randomTile(self.rng, free)
		if not x then
			break
		end
		self:addEntity(MapGen.newNode(self.rng, x, y :: number))
		spawned += 1
	end
	while self.monsterCount < Balance.MONSTER_TARGET and spawned < batch * 2 do
		local x, y = MapGen.randomTile(self.rng, free)
		if not x then
			break
		end
		self:addEntity(MapGen.newMonster(self.rng, x, y :: number))
		spawned += 1
	end
end

-- Nearest entity matching `filter`, or nil. A linear scan over a few hundred entities is cheaper than keeping an index.
function World.nearest(self: World, x: number, y: number, maxDist: number, filter: (any) -> boolean): any
	local best, bestDist = nil, maxDist
	for _, e in self.entities do
		if filter(e) then
			local d = Army.distance(x, y, e.x, e.y)
			if d < bestDist or (d == bestDist and best and e.id < best.id) then
				best, bestDist = e, d
			end
		end
	end
	return best
end

-- Kingdoms ------------------------------------------------------------------------------------------------------------

function World.addKingdom(self: World, kid: string, data: any, isBot: boolean, now: number): Kingdom?
	if self.kingdoms[kid] then
		return self.kingdoms[kid]
	end
	City.settle(data, now)
	local x, y
	for _, zone in { 1, 2, 3 } do
		x, y = MapGen.randomTile(self.rng, function(tx, ty)
			return self:castleSpotFree(tx, ty)
		end, zone)
		if x then
			break
		end
	end
	if not x then
		return nil
	end
	self.colorIndex += 1
	local k = {
		id = kid,
		name = data.name,
		isBot = isBot,
		data = data,
		castle = 0,
		color = Balance.KINGDOM_COLORS[(self.colorIndex - 1) % #Balance.KINGDOM_COLORS + 1],
		guild = nil,
		joinedAt = now,
	}
	k.castle = self:addEntity({ kind = "castle", kid = kid, x = x, y = y })
	self.kingdoms[kid] = k
	self.kingdomCount += 1
	self.castlesDirty = true
	self.dirtyKingdoms[kid] = true
	self.rankingAt = -math.huge
	return k
end

-- Takes a kingdom off the map, bringing its armies home at once so nothing is lost while the owner is away.
function World.removeKingdom(self: World, kid: string, now: number): any
	local k = self.kingdoms[kid]
	if not k then
		return nil
	end
	for _, m in self:marchesOf(kid) do
		self:recallNow(m, now)
		self:arriveHome(m, now)
	end
	if k.guild then
		self:leaveGuild(k)
	end
	self:removeEntity(k.castle)
	self.kingdoms[kid] = nil
	self.kingdomCount -= 1
	self.castlesDirty = true
	self.rankingAt = -math.huge
	City.settle(k.data, now)
	return k.data
end

function World.castleOf(self: World, k: Kingdom): any
	return self.entities[k.castle]
end

function World.marchesOf(self: World, kid: string): { March }
	local out = {}
	for _, m in self.marches do
		if m.owner == kid then
			table.insert(out, m)
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

function World.marchingTroops(self: World, kid: string): Army.Troops
	local out = {}
	for _, m in self.marches do
		if m.owner == kid then
			Army.add(out, m.troops)
		end
	end
	return out
end

function World.power(self: World, k: Kingdom): number
	return City.power(k.data, self:marchingTroops(k.id))
end

function World.toast(self: World, kid: string, textKey: string, params: any?)
	table.insert(self.toasts, { kid = kid, key = textKey, params = params or {} })
end

function World.report(self: World, kid: string, report: any, now: number)
	local k = self.kingdoms[kid]
	if k then
		City.addReport(k.data, report, now)
		self.dirtyKingdoms[kid] = true
	end
end

-- Commands ------------------------------------------------------------------------------------------------------------

local handlers: { [string]: any } = {}

-- Runs one order for a kingdom. Every player order and every bot order goes through here, under the same checks.
function World.command(self: World, kid: string, name: any, payload: any, now: number): (boolean, any)
	self.lastNow = now
	local k = self.kingdoms[kid]
	if not k then
		return false, "err.unknown"
	end
	local clean, reason = Protocol.validate(name, payload)
	if not clean then
		return false, reason
	end
	local handler = handlers[name]
	if not handler then
		return false, "err.unknown"
	end
	self:settleKingdom(k, now)
	local err, result = handler(self, k, clean, now)
	if err then
		return false, err
	end
	self.dirtyKingdoms[kid] = true
	return true, result
end

function World.settleKingdom(self: World, k: Kingdom, now: number)
	for _, event in City.settle(k.data, now) do
		self.dirtyKingdoms[k.id] = true
		if event.kind == "built" then
			self:toast(k.id, "toast.built", { building = event.building, level = event.level })
			if event.building == "keep" then
				local castle = self:castleOf(k)
				if castle then
					self:touch(castle)
				end
			end
		elseif event.kind == "trained" then
			self:toast(k.id, "toast.trained", { troop = event.troop, count = event.count })
		elseif event.kind == "researched" then
			self:toast(k.id, "toast.researched", { tech = event.tech, level = event.level })
		end
	end
end

handlers.upgrade = function(self: World, k: Kingdom, p: any, now: number)
	local err, job = City.startUpgrade(k.data, p.building, now)
	if not err then
		self:addHelp(k, job, "building", p.building)
	end
	return err, job
end

handlers.train = function(_self: World, k: Kingdom, p: any, now: number)
	return City.startTraining(k.data, p.troop, p.count, now)
end

handlers.research = function(self: World, k: Kingdom, p: any, now: number)
	local err, job = City.startResearch(k.data, p.tech, now)
	if not err then
		self:addHelp(k, job, "tech", p.tech)
	end
	return err, job
end

handlers.finish = function(self: World, k: Kingdom, p: any, now: number)
	local err = City.finishJob(k.data, p.job, now)
	if not err then
		self:settleKingdom(k, now)
	end
	return err
end

handlers.heal = function(_self: World, k: Kingdom)
	return City.heal(k.data)
end

handlers.recruit = function(_self: World, k: Kingdom, p: any)
	return City.recruitHero(k.data, p.hero)
end

handlers.claimQuest = function(_self: World, k: Kingdom)
	return City.claimQuest(k.data)
end

handlers.readReports = function(_self: World, k: Kingdom)
	for _, r in k.data.reports do
		r.read = true
	end
	return nil
end

handlers.march = function(self: World, k: Kingdom, p: any, now: number)
	return self:sendMarch(k, p, now)
end

handlers.recall = function(self: World, k: Kingdom, p: any, now: number)
	local m = self.marches[p.march]
	if not m or m.owner ~= k.id then
		return "err.unknown"
	end
	if m.phase == "back" then
		return "err.nothing"
	end
	self:recallNow(m, now)
	return nil
end

handlers.relocate = function(self: World, k: Kingdom, p: any)
	if #self:marchesOf(k.id) > 0 then
		return "err.marchesOut"
	end
	if not MapGen.inBounds(p.x, p.y) then
		return "err.target"
	end
	local maxZone = 1 + Economy.level(k.data, "keep") // 4
	if MapGen.zone(p.x, p.y) > maxZone then
		return "err.zoneLocked"
	end
	if not self:castleSpotFree(p.x, p.y, k.castle) then
		return "err.occupied"
	end
	if (k.data.resources.gold or 0) < Balance.RELOCATE_GOLD then
		return "err.notEnough"
	end
	k.data.resources.gold -= Balance.RELOCATE_GOLD
	self:moveEntity(self:castleOf(k), p.x, p.y)
	return nil
end

handlers.guildCreate = function(self: World, k: Kingdom, p: any)
	if k.guild then
		return "err.inGuild"
	end
	if p.adj < 1 or p.adj > #Balance.GUILD_ADJECTIVES or p.noun < 1 or p.noun > #Balance.GUILD_NOUNS then
		return "err.unknown"
	end
	for _, g in self.guilds do
		if g.adj == p.adj and g.noun == p.noun then
			return "err.nameTaken"
		end
	end
	if (k.data.resources.gold or 0) < Balance.GUILD_CREATE_GOLD then
		return "err.notEnough"
	end
	k.data.resources.gold -= Balance.GUILD_CREATE_GOLD
	local g = self:newGuild(p.adj, p.noun, k.id)
	self:joinGuild(k, g)
	return nil, g.id
end

handlers.guildJoin = function(self: World, k: Kingdom, p: any)
	local g = self.guilds[p.guild]
	if not g then
		return "err.unknown"
	end
	if k.guild == g.id then
		return "err.inGuild"
	end
	if g.count >= Balance.GUILD_MAX_MEMBERS then
		return "err.guildFull"
	end
	if k.guild then
		self:leaveGuild(k)
	end
	self:joinGuild(k, g)
	return nil
end

handlers.guildLeave = function(self: World, k: Kingdom)
	if not k.guild then
		return "err.nothing"
	end
	self:leaveGuild(k)
	return nil
end

handlers.guildHelp = function(self: World, k: Kingdom, _p: any, now: number)
	local n = self:helpAll(k, now)
	if n == 0 then
		return "err.nothing"
	end
	return nil, n
end

-- Marches -------------------------------------------------------------------------------------------------------------

function World.heroBusy(self: World, kid: string, hero: string): boolean
	for _, m in self.marches do
		if m.owner == kid and m.hero == hero then
			return true
		end
	end
	return false
end

function World.sendMarch(self: World, k: Kingdom, p: any, now: number): (string?, any)
	local data = k.data
	if not Protocol.MARCH_KINDS[p.kind] then
		return "err.unknown"
	end
	if not MapGen.inBounds(p.x, p.y) then
		return "err.target"
	end
	if #self:marchesOf(k.id) >= Army.marchSlots(data) then
		return "err.noSlot"
	end
	local troops = p.troops or {}
	if p.kind ~= "scout" then
		if Army.total(troops) <= 0 then
			return "err.noTroops"
		end
		if not Army.has(data.troops, troops) then
			return "err.noTroops"
		end
		if Army.total(troops) > Army.marchSize(data) then
			return "err.marchSize"
		end
	else
		troops = {}
	end
	local heroLevel = nil
	if p.hero then
		local hero = data.heroes[p.hero]
		if not hero or p.kind == "scout" then
			return "err.unknown"
		end
		if self:heroBusy(k.id, p.hero) then
			return "err.heroBusy"
		end
		heroLevel = hero.level
	end

	local target = self:entityAt(p.x, p.y)
	if not target then
		return "err.target"
	end
	if p.kind == "gather" then
		if target.kind ~= "node" then
			return "err.target"
		end
		if target.gatherer then
			return "err.occupied"
		end
	elseif p.kind == "hunt" then
		if target.kind ~= "monster" then
			return "err.target"
		end
		if data.stamina < Balance.HUNT_STAMINA then
			return "err.stamina"
		end
	else
		if target.kind ~= "castle" or target.kid == k.id then
			return "err.target"
		end
		local enemy = self.kingdoms[target.kid]
		if not enemy then
			return "err.target"
		end
		if k.guild and enemy.guild == k.guild then
			return "err.ally"
		end
		if p.kind == "attack" and City.isShielded(enemy.data, now) then
			return "err.shielded"
		end
	end

	local castle = self:castleOf(k)
	local travel
	if p.kind == "scout" then
		travel = math.max(3, math.ceil(Army.distance(castle.x, castle.y, p.x, p.y) / SCOUT_SPEED * 60))
	else
		travel = Army.travelSeconds(data, troops, p.hero, heroLevel, castle.x, castle.y, p.x, p.y)
	end

	if p.kind == "hunt" then
		data.stamina -= Balance.HUNT_STAMINA
	elseif p.kind == "attack" then
		-- Attacking ends beginner protection and any shield.
		data.peaceBroken = true
		data.shieldUntil = 0
	end
	Army.remove(data.troops, troops)

	self.nextMarch += 1
	local m = {
		id = self.nextMarch,
		owner = k.id,
		kind = p.kind,
		troops = troops,
		hero = p.hero,
		heroLevel = heroLevel,
		targetId = target.id,
		targetKid = target.kid,
		homeX = castle.x,
		homeY = castle.y,
		toX = p.x,
		toY = p.y,
		phase = "out",
		leg = { ax = castle.x, ay = castle.y, bx = p.x, by = p.y, t0 = now, t1 = now + travel },
		cargo = {},
	}
	self.marches[m.id] = m
	self.marchesDirty = true
	if (p.kind == "attack" or p.kind == "scout") and target.kid then
		self.dirtyKingdoms[target.kid] = true
		self:toast(
			target.kid,
			if p.kind == "attack" then "toast.incoming" else "toast.scoutIncoming",
			{ name = k.name }
		)
	end
	return nil, m.id
end

local function legPosition(leg: any, now: number): (number, number)
	local span = leg.t1 - leg.t0
	local t = if span > 0 then math.clamp((now - leg.t0) / span, 0, 1) else 1
	return leg.ax + (leg.bx - leg.ax) * t, leg.ay + (leg.by - leg.ay) * t
end
World.legPosition = legPosition

function World.goHome(self: World, m: March, fromX: number, fromY: number, t: number)
	local k = self.kingdoms[m.owner]
	local seconds
	if m.kind == "scout" then
		seconds = math.max(3, math.ceil(Army.distance(fromX, fromY, m.homeX, m.homeY) / SCOUT_SPEED * 60))
	else
		seconds = Army.travelSeconds(k.data, m.troops, m.hero, m.heroLevel, fromX, fromY, m.homeX, m.homeY)
	end
	m.phase = "back"
	m.leg = { ax = fromX, ay = fromY, bx = m.homeX, by = m.homeY, t0 = t, t1 = t + seconds }
	self.marchesDirty = true
end

function World.recallNow(self: World, m: March, now: number)
	if m.phase == "out" then
		local x, y = legPosition(m.leg, now)
		self:goHome(m, x, y, now)
	elseif m.phase == "work" then
		local done = math.clamp((now - m.workStart) / math.max(1, m.workEndAt - m.workStart), 0, 1)
		self:endGathering(m, math.floor(m.gatherAmount * done), now)
	end
end

function World.endGathering(self: World, m: March, gathered: number, t: number)
	local node = self.entities[m.targetId]
	if node then
		node.gatherer = nil
		node.amount -= gathered
		if node.amount <= 0 then
			self:removeEntity(node.id)
		else
			self:touch(node)
		end
	end
	m.cargo[m.res] = (m.cargo[m.res] or 0) + gathered
	self:goHome(m, m.toX, m.toY, t)
end

function World.arrive(self: World, m: March, t: number)
	local k = self.kingdoms[m.owner]
	local target = self.entities[m.targetId]
	local valid = target ~= nil and target.x == m.toX and target.y == m.toY
	if m.kind == "gather" and valid and target.kind == "node" and not target.gatherer then
		local rate = Balance.NODES[target.res].rateBase
			* (1 + (target.level - 1) * 0.5)
			* (1 + Economy.researchBonus(k.data, "gather") + Economy.heroBonus(m.hero, m.heroLevel, "gather", nil))
		local amount = math.min(Army.load(k.data, m.troops, m.hero, m.heroLevel), target.amount)
		target.gatherer = m.id
		target.gathererName = k.name
		self:touch(target)
		m.phase = "work"
		m.res = target.res
		m.gatherAmount = amount
		m.workStart = t
		m.workEndAt = t + math.max(1, math.ceil(amount / rate * 60))
		m.leg = { ax = m.toX, ay = m.toY, bx = m.toX, by = m.toY, t0 = t, t1 = m.workEndAt }
		self.marchesDirty = true
		return
	elseif m.kind == "hunt" and valid and target.kind == "monster" then
		self:resolveHunt(m, k, target, t)
	elseif m.kind == "attack" and valid and target.kind == "castle" then
		self:resolveAttack(m, k, target, t)
	elseif m.kind == "scout" and valid and target.kind == "castle" then
		self:resolveScout(m, k, target, t)
	else
		self:report(m.owner, { kind = "lost", x = m.toX, y = m.toY }, t)
	end
	self:goHome(m, m.toX, m.toY, t)
end

function World.resolveHunt(self: World, m: March, k: Kingdom, monster: any, t: number)
	local damage = math.min(monster.hp, Combat.huntDamage(k.data, m.troops, m.hero, m.heroLevel))
	monster.hp -= damage
	local killed = monster.hp <= 0
	local rewards = Combat.huntRewards(monster.monster, monster.level, damage, monster.maxHp, killed)
	Army.add(m.cargo, rewards)
	local xp = math.floor(Balance.MONSTERS[monster.monster].heroXp * monster.level * (if killed then 1.5 else 1))
	local levels = City.giveHeroXp(k.data, m.hero, xp)
	k.data.stats.hunts += 1
	if killed then
		self:removeEntity(monster.id)
	else
		self:touch(monster)
	end
	self:report(m.owner, {
		kind = "hunt",
		monster = monster.monster,
		level = monster.level,
		damage = damage,
		killed = killed,
		hpLeft = math.max(0, monster.hp),
		maxHp = monster.maxHp,
		rewards = rewards,
		hero = m.hero,
		heroXp = xp,
		heroLevels = levels,
		x = m.toX,
		y = m.toY,
	}, t)
end

function World.resolveAttack(self: World, m: March, k: Kingdom, castle: any, t: number)
	local enemy = self.kingdoms[castle.kid]
	if not enemy then
		return
	end
	self:settleKingdom(enemy, t)
	if City.isShielded(enemy.data, t) then
		self:report(m.owner, { kind = "shielded", name = enemy.name, x = m.toX, y = m.toY }, t)
		return
	end
	local result = Combat.battle({
		data = k.data,
		troops = m.troops,
		hero = m.hero,
		heroLevel = m.heroLevel,
	}, {
		data = enemy.data,
		troops = enemy.data.troops,
		wallBonus = Economy.level(enemy.data, "wall") * Balance.EFFECTS.wallDefensePerLevel,
	})

	-- Attacker: part of the fallen are wounded and carried home if their infirmary has room.
	local aRoom = Army.infirmaryCap(k.data) - Army.total(k.data.wounded)
	local aDead, aWounded = Combat.splitLosses(result.attacker.lost, 1 - Balance.ATTACKER_DEAD_SHARE, aRoom)
	Army.add(k.data.wounded, aWounded)
	m.troops = result.attacker.survivors

	-- Defender: every loss is a wound while the infirmary has room.
	local dRoom = Army.infirmaryCap(enemy.data) - Army.total(enemy.data.wounded)
	local dDead, dWounded = Combat.splitLosses(result.defender.lost, 1, dRoom)
	Army.add(enemy.data.wounded, dWounded)
	enemy.data.troops = result.defender.survivors

	local loot = {}
	if result.attackerWon then
		local capacity = Army.load(k.data, m.troops, m.hero, m.heroLevel)
		local protected = Economy.protected(enemy.data)
		local available = {}
		local total = 0
		for _, res in Balance.RESOURCES do
			local amount = math.floor(math.max(0, (enemy.data.resources[res] or 0) - protected) * Balance.LOOT_SHARE)
			available[res] = amount
			total += amount
		end
		local share = if total > 0 then math.min(1, capacity / total) else 0
		for res, amount in available do
			local take = math.floor(amount * share)
			if take > 0 then
				loot[res] = take
				enemy.data.resources[res] -= take
			end
		end
		Army.add(m.cargo, loot)
		k.data.stats.battlesWon += 1
		-- A short shield after a defeat keeps one kingdom from being farmed over and over.
		enemy.data.shieldUntil = t + Balance.ATTACK_SHIELD_SECONDS
		self:touch(castle)
	else
		enemy.data.stats.battlesWon += 1
	end
	local xp = 30 + math.floor(result.defender.powerLost * 2)
	City.giveHeroXp(k.data, m.hero, xp)

	local base = {
		attacker = k.name,
		defender = enemy.name,
		attackerWon = result.attackerWon,
		rounds = result.rounds,
		wallBonus = result.wallBonus,
		attackerBefore = result.attacker.before,
		attackerDead = aDead,
		attackerWounded = aWounded,
		defenderBefore = result.defender.before,
		defenderDead = dDead,
		defenderWounded = dWounded,
		loot = loot,
		hero = m.hero,
		x = m.toX,
		y = m.toY,
	}
	local mine = table.clone(base)
	mine.kind = "attack"
	self:report(k.id, mine, t)
	local theirs = table.clone(base)
	theirs.kind = "defend"
	self:report(enemy.id, theirs, t)
	self:toast(enemy.id, if result.attackerWon then "toast.defeated" else "toast.defended", { name = k.name })
	self.dirtyKingdoms[enemy.id] = true
	self.rankingAt = -math.huge
end

function World.resolveScout(self: World, m: March, k: Kingdom, castle: any, t: number)
	local enemy = self.kingdoms[castle.kid]
	if not enemy then
		return
	end
	self:settleKingdom(enemy, t)
	-- Without a watchtower the numbers are rounded, so a scout gives a picture, not an exact count.
	local exact = Economy.level(k.data, "watchtower") >= Balance.EFFECTS.watchtowerDetailLevel
	local troops = {}
	for id, count in enemy.data.troops do
		troops[id] = if exact then count else math.max(10, math.floor(count / 50 + 0.5) * 50)
	end
	local protected = Economy.protected(enemy.data)
	local resources = {}
	for _, res in Balance.RESOURCES do
		resources[res] = math.floor(math.max(0, (enemy.data.resources[res] or 0) - protected))
	end
	self:report(k.id, {
		kind = "scout",
		name = enemy.name,
		exact = exact,
		troops = troops,
		resources = resources,
		wall = Economy.level(enemy.data, "wall"),
		keep = Economy.level(enemy.data, "keep"),
		power = self:power(enemy),
		shielded = City.isShielded(enemy.data, t),
		x = m.toX,
		y = m.toY,
	}, t)
	self:report(enemy.id, { kind = "scouted", name = k.name, x = castle.x, y = castle.y }, t)
end

function World.arriveHome(self: World, m: March, t: number)
	self.marches[m.id] = nil
	self.marchesDirty = true
	local k = self.kingdoms[m.owner]
	if not k then
		return
	end
	Army.add(k.data.troops, m.troops)
	Army.add(k.data.resources, m.cargo)
	if m.kind == "gather" then
		local gathered = m.cargo[m.res or ""] or 0
		k.data.stats.gathered += gathered
		City.giveHeroXp(k.data, m.hero, math.floor(gathered / 100))
		self:report(m.owner, { kind = "gather", res = m.res, amount = gathered, x = m.toX, y = m.toY }, t)
	end
	self.dirtyKingdoms[m.owner] = true
end

-- Advances one march through every phase that has ended by `now`, at the exact time each phase ended.
function World.advanceMarch(self: World, m: March, now: number)
	for _ = 1, 4 do
		if m.phase == "out" and m.leg.t1 <= now then
			self:arrive(m, m.leg.t1)
		elseif m.phase == "work" and m.workEndAt <= now then
			self:endGathering(m, m.gatherAmount, m.workEndAt)
		elseif m.phase == "back" and m.leg.t1 <= now then
			self:arriveHome(m, m.leg.t1)
			return
		else
			return
		end
	end
end

-- Guilds --------------------------------------------------------------------------------------------------------------

function World.newGuild(self: World, adj: number, noun: number, leader: string?): any
	self.nextGuild += 1
	local a, n = Balance.GUILD_ADJECTIVES[adj], Balance.GUILD_NOUNS[noun]
	local g = {
		id = self.nextGuild,
		adj = adj,
		noun = noun,
		name = a .. " " .. n,
		tag = string.upper(string.sub(a, 1, 1) .. string.sub(n, 1, 2)),
		leader = leader,
		members = {},
		count = 0,
		helps = {},
	}
	self.guilds[g.id] = g
	return g
end

function World.joinGuild(self: World, k: Kingdom, g: any)
	g.members[k.id] = true
	g.count += 1
	g.leader = g.leader or k.id
	k.guild = g.id
	k.data.stats.guild = 1
	self:touch(self:castleOf(k))
	for kid in g.members do
		self.dirtyKingdoms[kid] = true
	end
end

function World.leaveGuild(self: World, k: Kingdom)
	local g = self.guilds[k.guild]
	k.guild = nil
	self:touch(self:castleOf(k))
	if not g then
		return
	end
	g.members[k.id] = nil
	g.count -= 1
	for helpKey, help in g.helps do
		if help.kid == k.id then
			g.helps[helpKey] = nil
		end
	end
	if g.leader == k.id then
		g.leader = next(g.members)
	end
	-- Player guilds disappear with their last member; the three realm guilds always stay open.
	if g.count <= 0 and g.id > #Balance.BOT_GUILDS then
		self.guilds[g.id] = nil
	end
	for kid in g.members do
		self.dirtyKingdoms[kid] = true
	end
end

function World.addHelp(self: World, k: Kingdom, job: any, labelKind: string, label: string)
	local g = k.guild and self.guilds[k.guild]
	if not g then
		return
	end
	g.helps[k.id .. ":" .. job.id] = {
		kid = k.id,
		job = job.id,
		labelKind = labelKind,
		label = label,
		level = job.level,
		given = 0,
		max = Balance.EFFECTS.embassyHelpBase + Economy.level(k.data, "embassy"),
		helpers = {},
	}
	for kid in g.members do
		self.dirtyKingdoms[kid] = true
	end
end

-- Helps every open request of the guild once; each help takes a little time off the job.
function World.helpAll(self: World, k: Kingdom, now: number): number
	local g = k.guild and self.guilds[k.guild]
	if not g then
		return 0
	end
	local count = 0
	for helpKey, help in g.helps do
		local owner = self.kingdoms[help.kid]
		if help.kid ~= k.id and not help.helpers[k.id] and owner then
			local job = City.findJob(owner.data, help.job)
			if job then
				local cut =
					math.max(Balance.GUILD_HELP_MIN_SECONDS, (job.endAt - job.startAt) * Balance.GUILD_HELP_SHARE)
				job.endAt -= cut
				help.given += 1
				help.helpers[k.id] = true
				count += 1
				self.dirtyKingdoms[help.kid] = true
				self:settleKingdom(owner, now)
			end
			if not job or help.given >= help.max then
				g.helps[helpKey] = nil
			end
		end
	end
	if count > 0 then
		for kid in g.members do
			self.dirtyKingdoms[kid] = true
		end
	end
	return count
end

function World.pruneHelps(self: World)
	for _, g in self.guilds do
		for helpKey, help in g.helps do
			local owner = self.kingdoms[help.kid]
			if not owner or not City.findJob(owner.data, help.job) then
				g.helps[helpKey] = nil
				for kid in g.members do
					self.dirtyKingdoms[kid] = true
				end
			end
		end
	end
end

-- Step ----------------------------------------------------------------------------------------------------------------

function World.step(self: World, now: number)
	self.lastNow = now
	local ids = {}
	for id in self.marches do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local m = self.marches[id]
		if m then
			self:advanceMarch(m, now)
		end
	end
	for _, k in self.kingdoms do
		self:settleKingdom(k, now)
	end
	self:pruneHelps()
	if now - self.lastRespawn >= Balance.RESPAWN_SECONDS then
		self:respawn(now, false)
	end
end

function World.drain(self: World): any
	local out = {
		kingdoms = self.dirtyKingdoms,
		chunks = self.dirtyChunks,
		marches = self.marchesDirty,
		castles = self.castlesDirty,
		toasts = self.toasts,
	}
	self.dirtyKingdoms = {}
	self.dirtyChunks = {}
	self.marchesDirty = false
	self.castlesDirty = false
	self.toasts = {}
	return out
end

-- Views: what one player may see --------------------------------------------------------------------------------------

function World.rankings(self: World, now: number): { any }
	if now - self.rankingAt < 5 then
		return self.ranking
	end
	local list = {}
	for _, k in self.kingdoms do
		local g = k.guild and self.guilds[k.guild]
		table.insert(list, {
			kid = k.id,
			name = k.name,
			power = self:power(k),
			isBot = k.isBot,
			tag = if g then g.tag else nil,
			color = k.color,
		})
	end
	table.sort(list, function(a, b)
		if a.power ~= b.power then
			return a.power > b.power
		end
		return a.kid < b.kid
	end)
	self.ranking = list
	self.rankingAt = now
	return list
end

local function publicMarch(self: World, m: March): any
	local k = self.kingdoms[m.owner]
	return {
		id = m.id,
		kid = m.owner,
		name = if k then k.name else "?",
		color = if k then k.color else "#ffffff",
		kind = m.kind,
		phase = m.phase,
		targetKid = m.targetKid,
		leg = m.leg,
		size = Army.total(m.troops),
	}
end

function World.marchList(self: World): { any }
	local out = {}
	for _, m in self.marches do
		table.insert(out, publicMarch(self, m))
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

-- Every castle's place and colour, for the minimap.
function World.castleList(self: World): { any }
	local out = {}
	for _, k in self.kingdoms do
		local c = self.entities[k.castle]
		if c then
			table.insert(out, { kid = k.id, x = c.x, y = c.y, color = k.color })
		end
	end
	table.sort(out, function(a, b)
		return a.kid < b.kid
	end)
	return out
end

function World.chunkView(self: World, chunk: number): { any }
	local out = {}
	local ids = self.chunks[chunk]
	if not ids then
		return out
	end
	local now = self.lastNow or 0
	for id in ids do
		local e = self.entities[id]
		if e.kind == "castle" then
			local k = self.kingdoms[e.kid]
			if k then
				local g = k.guild and self.guilds[k.guild]
				table.insert(out, {
					id = id,
					k = "c",
					x = e.x,
					y = e.y,
					kid = k.id,
					n = k.name,
					col = k.color,
					lv = Economy.level(k.data, "keep"),
					g = if g then g.tag else nil,
					gid = k.guild,
					bot = k.isBot,
					sh = City.isShielded(k.data, now),
				})
			end
		elseif e.kind == "node" then
			table.insert(out, {
				id = id,
				k = "n",
				x = e.x,
				y = e.y,
				r = e.res,
				lv = e.level,
				a = math.floor(e.amount),
				am = e.maxAmount,
				busy = e.gatherer ~= nil,
				by = if e.gatherer then e.gathererName else nil,
			})
		else
			table.insert(out, {
				id = id,
				k = "m",
				x = e.x,
				y = e.y,
				m = e.monster,
				lv = e.level,
				hp = e.hp,
				mhp = e.maxHp,
			})
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

function World.guildView(self: World, k: Kingdom): any
	local g = k.guild and self.guilds[k.guild]
	if not g then
		return nil
	end
	local members = {}
	for kid in g.members do
		local m = self.kingdoms[kid]
		if m then
			table.insert(members, {
				kid = kid,
				name = m.name,
				power = self:power(m),
				isBot = m.isBot,
				leader = g.leader == kid,
				keep = Economy.level(m.data, "keep"),
			})
		end
	end
	table.sort(members, function(a, b)
		return a.power > b.power
	end)
	local helps = {}
	for _, help in g.helps do
		local owner = self.kingdoms[help.kid]
		if owner then
			table.insert(helps, {
				name = owner.name,
				mine = help.kid == k.id,
				labelKind = help.labelKind,
				label = help.label,
				level = help.level,
				given = help.given,
				max = help.max,
				helped = help.helpers[k.id] == true,
			})
		end
	end
	table.sort(helps, function(a, b)
		return a.name < b.name
	end)
	return { id = g.id, name = g.name, tag = g.tag, count = g.count, members = members, helps = helps }
end

function World.guildList(self: World): { any }
	local out = {}
	for _, g in self.guilds do
		local power = 0
		for kid in g.members do
			local m = self.kingdoms[kid]
			if m then
				power += self:power(m)
			end
		end
		table.insert(out, { id = g.id, name = g.name, tag = g.tag, count = g.count, power = power })
	end
	table.sort(out, function(a, b)
		return a.power > b.power
	end)
	return out
end

-- Everything one player sees about their own kingdom. Other kingdoms appear only through the map, ranking and reports.
function World.view(self: World, kid: string, now: number): any
	local k = self.kingdoms[kid]
	if not k then
		return nil
	end
	local data = k.data
	local castle = self:castleOf(k)
	local ranking = self:rankings(now)
	local rank = 0
	for i, row in ranking do
		if row.kid == kid then
			rank = i
			break
		end
	end
	local questDef, questProgress, questDone = City.quest(data)
	local incoming = {}
	local mine = {}
	for _, m in self.marches do
		if m.owner == kid then
			local row = publicMarch(self, m)
			row.troops = m.troops
			row.hero = m.hero
			row.cargo = m.cargo
			row.workEndAt = m.workEndAt
			row.toX, row.toY = m.toX, m.toY
			table.insert(mine, row)
		elseif m.targetKid == kid and m.phase == "out" and (m.kind == "attack" or m.kind == "scout") then
			local row = publicMarch(self, m)
			-- Details of an attack only with a watchtower; otherwise just that something is coming.
			if Economy.level(data, "watchtower") >= 1 then
				row.size = Army.total(m.troops)
			else
				row.size = nil
			end
			table.insert(incoming, row)
		end
	end
	table.sort(mine, function(a, b)
		return a.id < b.id
	end)
	local unread = 0
	for _, r in data.reports do
		if not r.read then
			unread += 1
		end
	end
	local top = {}
	for i = 1, math.min(10, #ranking) do
		top[i] = ranking[i]
	end
	return {
		now = now,
		kid = kid,
		name = k.name,
		color = k.color,
		seed = self.seed,
		resources = data.resources,
		rates = Economy.production(data),
		cap = Economy.storageCap(data),
		protected = Economy.protected(data),
		buildings = data.buildings,
		builds = data.builds,
		queueSlots = City.queueSlots(data),
		training = data.training,
		researching = data.researching,
		research = data.research,
		troops = data.troops,
		wounded = data.wounded,
		infirmaryCap = Army.infirmaryCap(data),
		batchSize = Army.batchSize(data),
		marchSize = Army.marchSize(data),
		marchSlots = Army.marchSlots(data),
		heroes = data.heroes,
		stamina = data.stamina,
		staminaAt = data.staminaAt,
		staminaSeconds = City.staminaSeconds(data),
		power = self:power(k),
		rank = rank,
		kingdoms = self.kingdomCount,
		castle = { x = castle.x, y = castle.y },
		shielded = City.isShielded(data, now),
		shieldUntil = data.shieldUntil,
		beginner = Economy.level(data, "keep") < Balance.BEGINNER_KEEP and not data.peaceBroken,
		quest = if questDef
			then {
				id = questDef.id,
				progress = questProgress,
				goal = questDef.amount,
				done = questDone,
				reward = questDef.reward,
			}
			else nil,
		guild = self:guildView(k),
		guilds = if k.guild then nil else self:guildList(),
		marches = mine,
		incoming = incoming,
		reports = data.reports,
		unread = unread,
		top = top,
	}
end

return World
