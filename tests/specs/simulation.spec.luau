-- A full realm at capacity: 20 kingdoms that stand in for players plus 30 bots, run for two hours of game time.
-- It checks the invariants every rule must keep and that one server step stays cheap with 50 kingdoms.

return function(test, expect, load)
	local Army = load("shared/Rules/Army")
	local Balance = load("shared/Rules/Balance")
	local Bot = load("shared/Rules/Bot")
	local Rng = load("shared/Rules/Rng")
	local Schema = load("shared/Rules/Schema")
	local World = load("shared/Rules/World")

	local function simulate(seed: number, seconds: number)
		local world = World.new(seed, 0)
		local rng = Rng.new(seed + 1)
		local taken = {}
		local ids = {}
		for i = 1, Balance.MAX_REAL_PLAYERS + Balance.BOT_COUNT do
			local name = Bot.newName(rng, taken)
			taken[name] = true
			local data = Schema.new(name, 0)
			local isBot = i > Balance.MAX_REAL_PLAYERS
			if isBot then
				Bot.prepare(data, rng)
			end
			local kid = (if isBot then "b" else "u") .. i
			local k = world:addKingdom(kid, data, isBot, 0)
			expect.truthy(k, "room for kingdom " .. i)
			k.personality = Bot.PERSONALITIES[(i - 1) % #Bot.PERSONALITIES + 1]
			table.insert(ids, kid)
		end
		local stepTime, steps, worst = 0, 0, 0
		local t = 0
		while t < seconds do
			t += 1
			local t0 = os.clock()
			world:step(t)
			-- Every kingdom acts every 10 s, spread over the seconds like the server does it.
			for i, kid in ids do
				if (t + i) % 10 == 0 then
					Bot.tick(world, kid, t, rng)
				end
			end
			world:drain()
			local dt = os.clock() - t0
			stepTime += dt
			worst = math.max(worst, dt)
			steps += 1
		end
		return world, stepTime / steps, worst
	end

	test("50 kingdoms play two hours without breaking an invariant", function()
		local world, avg, worst = simulate(2024, 7200)
		print(
			string.format(
				"    avg step %.2f ms, worst %.2f ms, %d marches out, %d entities",
				avg * 1000,
				worst * 1000,
				#world:marchList(),
				world.nodeCount + world.monsterCount
			)
		)
		expect.eq(world.kingdomCount, 50)
		local attacks, hunts, gathers, built = 0, 0, 0, 0
		for _, k in world.kingdoms do
			for res, amount in k.data.resources do
				expect.truthy(amount >= 0, k.name .. " " .. res .. " = " .. amount)
			end
			for id, count in k.data.troops do
				expect.truthy(count >= 0 and count % 1 == 0, k.name .. " " .. id)
			end
			for id, count in k.data.wounded do
				expect.truthy(count >= 0, k.name .. " wounded " .. id)
			end
			expect.truthy(Army.total(k.data.wounded) <= Army.infirmaryCap(k.data) + 1, k.name .. " infirmary")
			expect.truthy(k.data.stamina >= 0 and k.data.stamina <= Balance.STAMINA_MAX)
			hunts += k.data.stats.hunts
			gathers += k.data.stats.gathered
			attacks += k.data.stats.battlesWon
			built += k.data.buildings.keep
		end
		expect.truthy(hunts > 50, "bots hunt: " .. hunts)
		expect.truthy(gathers > 100000, "bots gather: " .. gathers)
		expect.truthy(built > 50 * 2, "kingdoms grow")
		expect.truthy(attacks >= 0)
		-- Tile index and chunk index agree with the entities.
		local counted = 0
		for id, e in world.entities do
			counted += 1
			expect.eq(world.tiles[e.x + e.y * Balance.MAP_SIZE], id)
		end
		local tiles = 0
		for _ in world.tiles do
			tiles += 1
		end
		expect.eq(tiles, counted)
		-- No hero is on two marches.
		local heroes = {}
		for _, m in world.marches do
			if m.hero then
				local key = m.owner .. m.hero
				expect.falsy(heroes[key], "hero twice: " .. key)
				heroes[key] = true
			end
		end
		-- Budget: the server steps 4 times a second; a step must stay far below that.
		expect.truthy(avg < 0.01, string.format("average step %.2f ms", avg * 1000))
	end)

	test("the same seed plays out the same way", function()
		local a = simulate(77, 900)
		local b = simulate(77, 900)
		local ra, rb = a:rankings(900), b:rankings(900)
		for i = 1, #ra do
			expect.eq(ra[i].kid, rb[i].kid)
			expect.eq(ra[i].power, rb[i].power)
		end
	end)
end
