return function(test, expect, load)
	local Balance = load("shared/Rules/Balance")
	local Economy = load("shared/Rules/Economy")
	local Format = load("shared/Rules/Format")
	local Schema = load("shared/Rules/Schema")

	test("building costs grow with level", function()
		local l1 = Economy.buildingCost("farm", 1)
		local l2 = Economy.buildingCost("farm", 2)
		expect.eq(l1.wood, 120)
		expect.eq(l2.wood, math.floor(120 * Balance.COST_GROWTH))
		expect.truthy(Economy.buildingTime("keep", 10) > Economy.buildingTime("keep", 9))
	end)

	test("every building, troop, tech and hero has consistent data", function()
		for _, id in Balance.BUILDING_ORDER do
			expect.truthy(Balance.BUILDINGS[id], "building " .. id)
		end
		for id in Balance.BUILDINGS do
			expect.truthy(table.find(Balance.BUILDING_ORDER, id), "ordered building " .. id)
		end
		for id in Balance.TROOPS do
			expect.truthy(table.find(Balance.TROOP_ORDER, id), "ordered troop " .. id)
		end
		for id in Balance.RESEARCH do
			expect.truthy(table.find(Balance.RESEARCH_ORDER, id), "ordered tech " .. id)
		end
		for id in Balance.HEROES do
			expect.truthy(table.find(Balance.HERO_ORDER, id), "ordered hero " .. id)
		end
		for _, id in Balance.START_HEROES do
			expect.eq(Balance.HEROES[id].recruitGold, 0, "start hero is free")
		end
	end)

	test("production follows levels and research", function()
		local data = Schema.new("Test", 0)
		local base = Economy.production(data)
		expect.eq(base.food, 900)
		expect.eq(base.stone, 0)
		data.buildings.farm = 3
		expect.eq(Economy.production(data).food, math.floor(900 * 3 ^ Balance.RATE_EXPONENT))
		data.research.agriculture = 2
		expect.eq(Economy.production(data).food, math.floor(900 * 3 ^ Balance.RATE_EXPONENT * (1 + 0.06 * 2)))
	end)

	test("vault protects nothing until built", function()
		local data = Schema.new("Test", 0)
		expect.eq(Economy.protected(data), 0)
		data.buildings.vault = 2
		expect.truthy(Economy.protected(data) > Balance.EFFECTS.vaultBase)
	end)

	test("finishing is free in the last seconds", function()
		expect.eq(Economy.finishGold(Balance.FREE_FINISH_SECONDS), 0)
		expect.eq(Economy.finishGold(61), 2 * Balance.GOLD_PER_MINUTE)
	end)

	test("missing lists only what is short", function()
		expect.same(Economy.missing({ food = 10, wood = 50 }, { food = 30, wood = 20 }), { food = 20 })
		expect.eq(Economy.missing({ food = 30 }, { food = 30 }), nil)
	end)

	test("formats numbers and durations", function()
		expect.eq(Format.short(950), "950")
		expect.eq(Format.short(12400), "12.4K")
		expect.eq(Format.short(12000), "12K")
		expect.eq(Format.short(3250000), "3.25M")
		expect.eq(Format.thousands(1234567), "1,234,567")
		expect.eq(Format.thousands(999), "999")
		expect.eq(Format.duration(45), "45s")
		expect.eq(Format.duration(125), "2m 05s")
		expect.eq(Format.duration(3725), "1h 02m")
		expect.eq(Format.duration(90000), "1d 01h")
	end)

	test("migrate fills new fields and drops unknown ids", function()
		local old = {
			resources = { food = 5 },
			buildings = { keep = 3 },
			troops = { inf1 = 4, ghost = 9 },
			heroes = {},
			stats = {},
			reports = {},
		}
		local data = Schema.migrate(old, "Ana", 100)
		expect.eq(data.buildings.keep, 3)
		expect.eq(data.troops.ghost, nil)
		expect.eq(data.troops.inf1, 4)
		expect.eq(data.resources.wood, 0)
		expect.eq(data.stats.hunts, 0)
		expect.eq(data.version, Schema.VERSION)
		expect.eq(Schema.migrate(nil, "Bo", 0).name, "Bo")
	end)
end
