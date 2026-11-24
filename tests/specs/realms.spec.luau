-- Persistent realms: assignment of players, opening new realms, bots giving way, the single-writer lease, and a
-- realm that is saved, left alone for hours and loaded again.

return function(test, expect, load)
	local Army = load("shared/Rules/Army")
	local Balance = load("shared/Rules/Balance")
	local Bot = load("shared/Rules/Bot")
	local Realms = load("shared/Rules/Realms")
	local Rng = load("shared/Rules/Rng")
	local Schema = load("shared/Rules/Schema")
	local World = load("shared/Rules/World")

	test("new players fill the newest open realm, then a new realm opens", function()
		local registry = Realms.newRegistry()
		expect.eq(Realms.pickForNewPlayer(registry), nil, "no realm yet")
		local first = Realms.addRealm(registry, "code1", "ps1", 0)
		expect.eq(first.id, 1)
		for _ = 1, Realms.OPEN_MEMBERS do
			local pick = Realms.pickForNewPlayer(registry)
			expect.eq(pick and pick.id, 1)
			expect.truthy(Realms.addMember(registry, 1))
		end
		expect.falsy(first.open, "a full realm closes to newcomers")
		expect.eq(Realms.pickForNewPlayer(registry), nil)
		local second = Realms.addRealm(registry, "code2", "ps2", 10)
		expect.eq(second.id, 2)
		expect.eq(Realms.pickForNewPlayer(registry).id, 2)
		-- Friends can still be added to a closed realm up to the hard cap.
		while first.members < Realms.MAX_MEMBERS do
			expect.truthy(Realms.addMember(registry, 1))
		end
		expect.falsy(Realms.addMember(registry, 1))
		expect.eq(Realms.findByServer(registry, "ps2").id, 2)
		expect.eq(Realms.find(registry, 99), nil)
	end)

	test("opening a realm closes the older ones to newcomers", function()
		local registry = Realms.newRegistry()
		Realms.addRealm(registry, "a", "pa", 0)
		Realms.addRealm(registry, "b", "pb", 0)
		expect.falsy(Realms.find(registry, 1).open)
		expect.truthy(Realms.find(registry, 2).open)
		expect.same(Realms.normalize(nil), Realms.newRegistry())
	end)

	test("bots give way to humans, down to a floor", function()
		expect.eq(Realms.botTarget(0), Realms.BOTS_MAX)
		expect.eq(Realms.botTarget(10), Realms.BOTS_MAX - 5)
		expect.eq(Realms.botTarget(Realms.MAX_MEMBERS), Realms.BOTS_MIN)
		local world = World.new(5, 0)
		local rng = Rng.new(5)
		for i = 1, 12 do
			local data = Schema.new("Bot" .. i, 0)
			Bot.prepare(data, rng)
			world:addKingdom("b" .. i, data, true, 0)
		end
		local retired = world:retireBot(0)
		expect.truthy(retired)
		expect.eq(world.kingdoms[retired], nil)
		local _, bots = world:counts()
		expect.eq(bots, 11)
	end)

	test("only one server holds a realm at a time", function()
		local lease = Realms.lease("jobA", 100)
		expect.truthy(Realms.canHold(nil, "jobA", 100))
		expect.truthy(Realms.canHold(lease, "jobA", 150), "renewing your own lease")
		expect.falsy(Realms.canHold(lease, "jobB", 150), "a second server is refused")
		expect.truthy(Realms.canHold(lease, "jobB", 100 + Realms.LEASE_SECONDS), "an expired lease is free")
	end)

	local function realm()
		local world = World.new(11, 0)
		world.realmId = 3
		local a = world:addKingdom("u1", Schema.new("Ana", 0), false, 0)
		local b = world:addKingdom("u2", Schema.new("Bia", 0), false, 0)
		world:setOnline("u1", true, 0)
		return world, a, b
	end

	test("a castle stays on the map when its player leaves", function()
		local world, a = realm()
		local castle = world:castleOf(a)
		world:setOnline("u1", false, 10)
		expect.truthy(world:entityAt(castle.x, castle.y), "castle still there")
		expect.falsy(a.online)
		local offline
		local MapGen = load("shared/Rules/MapGen")
		for _, e in world:chunkView(MapGen.chunkOf(castle.x, castle.y)) do
			if e.kid == "u1" then
				offline = e.off
			end
		end
		expect.truthy(offline, "the map shows it as offline")
		-- Offline kingdoms can still be attacked once out of beginner protection.
		a.data.peaceBroken = true
		local b = world.kingdoms.u2
		b.data.troops.cav1 = 500
		local ok =
			world:command("u2", "march", { kind = "attack", x = castle.x, y = castle.y, troops = { cav1 = 500 } }, 20)
		expect.truthy(ok)
	end)

	test("a saved realm comes back identical and catches up while nobody was there", function()
		local world, a = realm()
		a.data.peaceBroken = true
		world:command("u1", "guildJoin", { guild = 2 }, 0)
		local node
		for _, e in world.entities do
			if e.kind == "node" and (node == nil or e.id < node.id) then
				node = e
			end
		end
		local ok, marchId =
			world:command("u1", "march", { kind = "gather", x = node.x, y = node.y, troops = { inf1 = 60 } }, 0)
		expect.truthy(ok, tostring(marchId))
		local _, job = world:command("u1", "upgrade", { building = "farm" }, 0)
		world:step(5)
		world:setOnline("u1", false, 5)
		local food = a.data.resources.food

		-- Through JSON, as the DataStore stores it.
		local serde = require("@lune/serde")
		local snap = serde.decode("json", serde.encode("json", world:snapshot(5)))
		local back = World.restore(snap, 5)
		expect.eq(back.realmId, 3)
		expect.eq(back.kingdomCount, world.kingdomCount)
		expect.eq(back.nodeCount, world.nodeCount)
		expect.eq(back.monsterCount, world.monsterCount)
		expect.same(back:chunkView(0), world:chunkView(0))
		expect.eq(back.kingdoms.u1.guild, 2)
		expect.truthy(back.marches[marchId], "the march survives the save")
		expect.falsy(back.kingdoms.u1.online, "nobody is online after a restart")

		-- Six hours later: the job finished, the march came home with its load, production capped at storage.
		local later = World.restore(snap, 5 + 6 * 3600)
		local k = later.kingdoms.u1
		expect.eq(k.data.buildings.farm, 2)
		expect.eq(later.marches[marchId], nil)
		expect.eq(k.data.troops.inf1, Balance.START_TROOPS.inf1)
		expect.truthy(k.data.stats.gathered > 0)
		expect.truthy(k.data.resources.food > food)
		expect.truthy(job.endAt < 6 * 3600)
		expect.eq(Army.total(k.data.wounded), 0)
		-- Ids keep counting from where they were, so nothing collides after a restart.
		expect.eq(later.nextMarch, world.nextMarch)
		expect.eq(later.nextEntity >= world.nextEntity, true)
	end)

	test("bots write no reports, so the saved realm stays small", function()
		local world = World.new(3, 0)
		local rng = Rng.new(3)
		local data = Schema.new("Botty", 0)
		Bot.prepare(data, rng)
		world:addKingdom("b1", data, true, 0)
		world:report("b1", { kind = "lost" }, 0)
		expect.eq(#world.kingdoms.b1.data.reports, 0)
	end)
end
