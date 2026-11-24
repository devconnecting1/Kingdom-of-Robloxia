return function(test, expect, load)
	local Army = load("shared/Rules/Army")
	local Balance = load("shared/Rules/Balance")
	local MapGen = load("shared/Rules/MapGen")
	local Schema = load("shared/Rules/Schema")
	local World = load("shared/Rules/World")

	local function setup(seed)
		local world = World.new(seed or 7, 0)
		local a = world:addKingdom("u1", Schema.new("Alice", 0), false, 0)
		local b = world:addKingdom("u2", Schema.new("Bruno", 0), false, 0)
		return world, a, b
	end

	local function run(world, from, to)
		local t = from
		while t < to do
			t = math.min(to, t + 1)
			world:step(t)
		end
		return t
	end

	local function find(world, kind)
		for _, e in world.entities do
			if e.kind == kind and not e.gatherer then
				return e
			end
		end
		return nil
	end

	test("a new realm is filled with fields and monsters", function()
		local world = World.new(1, 0)
		expect.eq(world.nodeCount, Balance.NODE_TARGET)
		expect.eq(world.monsterCount, Balance.MONSTER_TARGET)
		for id, e in world.entities do
			expect.eq(world.tiles[e.x + e.y * Balance.MAP_SIZE], id)
			expect.truthy(MapGen.inBounds(e.x, e.y))
			expect.truthy(MapGen.biome(world.seed, e.x, e.y) ~= "lake", "nothing spawns on water")
		end
	end)

	test("the same seed builds the same realm", function()
		local a = World.new(99, 0)
		local b = World.new(99, 0)
		expect.same(a:chunkView(10), b:chunkView(10))
		local c = World.new(100, 0)
		expect.truthy(#a:chunkView(0) ~= #c:chunkView(0) or a:chunkView(0)[1].x ~= c:chunkView(0)[1].x)
	end)

	test("castles are placed apart in the outer zone", function()
		local world = World.new(3, 0)
		for i = 1, 50 do
			expect.truthy(world:addKingdom("k" .. i, Schema.new("K" .. i, 0), true, 0), "placed " .. i)
		end
		local castles = {}
		for _, k in world.kingdoms do
			table.insert(castles, world:castleOf(k))
		end
		for i = 1, #castles do
			for j = i + 1, #castles do
				local a, b = castles[i], castles[j]
				expect.truthy(math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) >= Balance.CASTLE_SPACING)
			end
		end
	end)

	test("a gathering march goes, works, comes back with the load", function()
		local world, a = setup()
		local node = find(world, "node")
		local troops = { inf1 = 50 }
		local ok, marchId = world:command("u1", "march", { kind = "gather", x = node.x, y = node.y, troops = troops }, 0)
		expect.truthy(ok, tostring(marchId))
		expect.eq(a.data.troops.inf1, Balance.START_TROOPS.inf1 - 50)
		local m = world.marches[marchId]
		run(world, 0, m.leg.t1)
		expect.eq(m.phase, "work")
		expect.eq(node.gatherer, marchId)
		local before = a.data.resources[node.res]
		run(world, m.leg.t1, 3600)
		expect.eq(world.marches[marchId], nil)
		expect.eq(a.data.troops.inf1, Balance.START_TROOPS.inf1)
		local load = Army.load(a.data, troops)
		expect.truthy(a.data.resources[node.res] >= before + math.min(load, node.maxAmount) - 1)
		expect.eq(a.data.stats.gathered, math.min(load, node.maxAmount))
		expect.eq(a.data.reports[1].kind, "gather")
	end)

	test("a field being gathered cannot take a second march", function()
		local world = setup()
		local node = find(world, "node")
		local ok1 = world:command("u1", "march", { kind = "gather", x = node.x, y = node.y, troops = { inf1 = 10 } }, 0)
		run(world, 0, 120)
		expect.truthy(ok1)
		if node.gatherer then
			local ok2, err = world:command("u2", "march", { kind = "gather", x = node.x, y = node.y, troops = { inf1 = 10 } }, 120)
			expect.errorKey(ok2, err, "err.occupied")
		end
	end)

	test("hunting spends stamina and wounds the monster", function()
		local world, a = setup()
		local monster = find(world, "monster")
		local hp = monster.hp
		local ok, id = world:command("u1", "march", { kind = "hunt", x = monster.x, y = monster.y, troops = { inf1 = 100 }, hero = "aldric" }, 0)
		expect.truthy(ok, tostring(id))
		expect.eq(a.data.stamina, Balance.STAMINA_MAX - Balance.HUNT_STAMINA)
		local okBusy, err = world:command("u1", "march", { kind = "hunt", x = monster.x, y = monster.y, troops = { inf1 = 10 }, hero = "aldric" }, 0)
		expect.errorKey(okBusy, err, "err.heroBusy")
		run(world, 0, 3600)
		expect.truthy(monster.hp < hp or world.entities[monster.id] == nil)
		expect.eq(a.data.stats.hunts, 1)
		expect.eq(a.data.reports[1].kind, "hunt")
		expect.truthy(a.data.heroes.aldric.xp > 0 or a.data.heroes.aldric.level > 1)
	end)

	test("beginners cannot be attacked; others can, and both get a report", function()
		local world, a, b = setup()
		local castle = world:castleOf(b)
		local ok, err = world:command("u1", "march", { kind = "attack", x = castle.x, y = castle.y, troops = { inf1 = 100 } }, 0)
		expect.errorKey(ok, err, "err.shielded")
		b.data.peaceBroken = true
		b.data.buildings.infirmary = 2
		a.data.troops.cav1 = 2000
		a.data.buildings.warhall = 10
		local ok2, id = world:command("u1", "march", { kind = "attack", x = castle.x, y = castle.y, troops = { cav1 = 2000 } }, 0)
		expect.truthy(ok2, tostring(id))
		expect.truthy(a.data.peaceBroken, "attacking ends beginner protection")
		local view = world:view("u2", 0)
		expect.eq(#view.incoming, 1)
		expect.eq(view.incoming[1].size, nil, "no watchtower, no numbers")
		run(world, 0, 3600)
		expect.eq(a.data.reports[1].kind, "attack")
		expect.eq(b.data.reports[1].kind, "defend")
		expect.truthy(a.data.reports[1].attackerWon)
		expect.truthy(b.data.shieldUntil > 0, "a defeat gives a short shield")
		expect.truthy(Army.total(b.data.wounded) > 0, "defender losses become wounded")
	end)

	test("guild mates cannot attack each other", function()
		local world, a, b = setup()
		b.data.peaceBroken = true
		expect.truthy(world:command("u1", "guildJoin", { guild = 1 }, 0))
		expect.truthy(world:command("u2", "guildJoin", { guild = 1 }, 0))
		local castle = world:castleOf(b)
		local ok, err = world:command("u1", "march", { kind = "attack", x = castle.x, y = castle.y, troops = { inf1 = 10 } }, 0)
		expect.errorKey(ok, err, "err.ally")
	end)

	test("guild help takes time off a mate's job", function()
		local world, a, b = setup()
		world:command("u1", "guildJoin", { guild = 2 }, 0)
		world:command("u2", "guildJoin", { guild = 2 }, 0)
		local ok, job = world:command("u1", "upgrade", { building = "farm" }, 0)
		expect.truthy(ok, tostring(job))
		local endAt = job.endAt
		local okHelp, n = world:command("u2", "guildHelp", {}, 1)
		expect.truthy(okHelp)
		expect.eq(n, 1)
		expect.eq(job.endAt, endAt - Balance.GUILD_HELP_MIN_SECONDS)
		local again, err = world:command("u2", "guildHelp", {}, 2)
		expect.errorKey(again, err, "err.nothing")
		local view = world:view("u1", 2)
		expect.eq(view.guild.name, world.guilds[2].name)
	end)

	test("recalling brings troops home early", function()
		local world, a = setup()
		local node = find(world, "node")
		local _, id = world:command("u1", "march", { kind = "gather", x = node.x, y = node.y, troops = { rng1 = 30 } }, 0)
		local m = world.marches[id]
		local half = m.leg.t1 / 2
		run(world, 0, half)
		expect.truthy(world:command("u1", "recall", { march = id }, half))
		expect.eq(m.phase, "back")
		run(world, half, half * 3)
		expect.eq(world.marches[id], nil)
		expect.eq(a.data.troops.rng1, Balance.START_TROOPS.rng1)
	end)

	test("march limits: slots, size and troops at home", function()
		local world, a = setup()
		local nodes = {}
		for _, e in world.entities do
			if e.kind == "node" then
				table.insert(nodes, e)
			end
		end
		local function go(i, troops)
			return world:command("u1", "march", { kind = "gather", x = nodes[i].x, y = nodes[i].y, troops = troops }, 0)
		end
		local ok, err = go(1, { inf1 = 99999 })
		expect.errorKey(ok, err, "err.noTroops")
		a.data.troops.inf1 = 5000
		ok, err = go(1, { inf1 = Army.marchSize(a.data) + 1 })
		expect.errorKey(ok, err, "err.marchSize")
		for i = 1, Army.marchSlots(a.data) do
			expect.truthy(go(i, { inf1 = 1 }))
		end
		ok, err = go(10, { inf1 = 1 })
		expect.errorKey(ok, err, "err.noSlot")
	end)

	test("a leaving kingdom takes its armies home and frees its tile", function()
		local world, a = setup()
		local node = find(world, "node")
		world:command("u1", "march", { kind = "gather", x = node.x, y = node.y, troops = { inf1 = 40 } }, 0)
		local castle = world:castleOf(a)
		local data = world:removeKingdom("u1", 5)
		expect.eq(data.troops.inf1, Balance.START_TROOPS.inf1)
		expect.eq(world:entityAt(castle.x, castle.y), nil)
		expect.eq(#world:marchesOf("u1"), 0)
		expect.eq(world.kingdomCount, 1)
	end)

	test("relocating needs gold, a free tile and the right zone", function()
		local world, a = setup()
		local ok, err = world:command("u1", "relocate", { x = 48, y = 48 }, 0)
		expect.errorKey(ok, err, "err.zoneLocked")
		local x, y
		for tx = 0, Balance.MAP_SIZE - 1 do
			if world:castleSpotFree(tx, 1) and MapGen.zone(tx, 1) == 1 then
				x, y = tx, 1
				break
			end
		end
		a.data.resources.gold = 0
		ok, err = world:command("u1", "relocate", { x = x, y = y }, 0)
		expect.errorKey(ok, err, "err.notEnough")
		a.data.resources.gold = Balance.RELOCATE_GOLD
		expect.truthy(world:command("u1", "relocate", { x = x, y = y }, 0))
		expect.eq(world:castleOf(a).x, x)
	end)

	test("a player's view never holds another kingdom's troops or resources", function()
		local world = setup()
		local view = world:view("u1", 0)
		expect.eq(view.name, "Alice")
		for _, row in view.top do
			expect.eq(row.troops, nil)
			expect.eq(row.resources, nil)
		end
		for c = 0, 35 do
			for _, e in world:chunkView(c) do
				expect.eq(e.troops, nil)
				expect.eq(e.resources, nil)
			end
		end
	end)

	test("invalid orders change nothing", function()
		local world, a = setup()
		local before = Army.total(a.data.troops)
		local ok = world:command("u1", "march", { kind = "gather", x = -1, y = 999, troops = { inf1 = 1 } }, 0)
		expect.falsy(ok)
		ok = world:command("u1", "march", { kind = "nuke", x = 1, y = 1, troops = { inf1 = 1 } }, 0)
		expect.falsy(ok)
		ok = world:command("nobody", "heal", {}, 0)
		expect.falsy(ok)
		expect.eq(Army.total(a.data.troops), before)
	end)
end
