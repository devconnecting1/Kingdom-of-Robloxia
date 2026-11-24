return function(test, expect, load)
	local Balance = load("shared/Rules/Balance")
	local City = load("shared/Rules/City")
	local Economy = load("shared/Rules/Economy")
	local Schema = load("shared/Rules/Schema")

	local function rich(data)
		for _, res in Balance.RESOURCES do
			data.resources[res] = 1e7
		end
		return data
	end

	test("an upgrade pays, waits and then levels up", function()
		local data = Schema.new("A", 0)
		local before = data.resources.wood
		local err, job = City.startUpgrade(data, "farm", 0)
		expect.eq(err, nil)
		expect.eq(data.resources.wood, before - Economy.buildingCost("farm", 2).wood)
		expect.eq(job.endAt, Economy.buildingTime("farm", 2))
		City.settle(data, job.endAt - 1)
		expect.eq(data.buildings.farm, 1)
		local events = City.settle(data, job.endAt)
		expect.eq(data.buildings.farm, 2)
		expect.eq(events[1].kind, "built")
	end)

	test("one builder until the Manor reaches level 5", function()
		local data = rich(Schema.new("A", 0))
		expect.eq(City.startUpgrade(data, "farm", 0), nil)
		expect.eq(City.startUpgrade(data, "sawmill", 0), "err.queueFull")
		expect.eq(City.startUpgrade(data, "farm", 0), "err.alreadyBuilding")
		data.buildings.manor = 5
		expect.eq(City.queueSlots(data), 2)
	end)

	test("buildings cannot pass the Keep and the Keep needs the Wall", function()
		local data = rich(Schema.new("A", 0))
		expect.eq(City.startUpgrade(data, "farm", 0), nil)
		City.settle(data, 1e6)
		expect.eq(City.checkUpgrade(data, "farm"), "err.needKeep")
		expect.eq(City.checkUpgrade(data, "academy"), "err.locked")
		expect.eq(City.checkUpgrade(data, "keep"), "err.needWall")
		data.buildings.wall = 2
		expect.eq(City.checkUpgrade(data, "keep"), nil)
	end)

	test("an unaffordable upgrade is refused and costs nothing", function()
		local data = Schema.new("A", 0)
		data.resources.wood = 0
		local err = City.startUpgrade(data, "farm", 0)
		expect.eq(err, "err.notEnough")
		expect.eq(data.resources.wood, 0)
		expect.eq(#data.builds, 0)
	end)

	test("production stops at the storage cap", function()
		local data = Schema.new("A", 0)
		local cap = Economy.storageCap(data)
		City.settle(data, 3600 * 1000)
		expect.eq(data.resources.food, cap)
		-- Over the cap (from loot) is kept, not cut.
		data.resources.food = cap * 3
		City.settle(data, 3600 * 1001)
		expect.eq(data.resources.food, cap * 3)
	end)

	test("training respects tiers, batch size and one batch at a time", function()
		local data = rich(Schema.new("A", 0))
		expect.eq(City.startTraining(data, "inf2", 10, 0), "err.locked")
		expect.eq(City.startTraining(data, "inf1", 0, 0), "err.batch")
		expect.eq(City.startTraining(data, "inf1", 1e6, 0), "err.batch")
		local err, job = City.startTraining(data, "inf1", 100, 0)
		expect.eq(err, nil)
		expect.eq(City.startTraining(data, "rng1", 10, 0), "err.queueFull")
		local home = data.troops.inf1
		City.settle(data, job.endAt)
		expect.eq(data.troops.inf1, home + 100)
		expect.eq(data.stats.trained, 100)
	end)

	test("research needs the Academy and its level", function()
		local data = rich(Schema.new("A", 0))
		expect.eq(City.startResearch(data, "forging", 0), "err.locked")
		data.buildings.academy = 1
		local err, job = City.startResearch(data, "forging", 0)
		expect.eq(err, nil)
		City.settle(data, job.endAt)
		expect.eq(data.research.forging, 1)
		expect.eq(City.checkResearch(data, "forging"), "err.needAcademy")
	end)

	test("finishing early costs gold except in the last seconds", function()
		local data = rich(Schema.new("A", 0))
		local _, job = City.startUpgrade(data, "farm", 0)
		local gold = data.resources.gold
		local at = job.endAt - 5
		expect.eq(City.finishJob(data, job.id, at), nil)
		expect.eq(data.resources.gold, gold)
		City.settle(data, at)
		expect.eq(data.buildings.farm, 2)
		data.buildings.keep = 10
		data.buildings.wall = 10
		local _, job2 = City.startUpgrade(data, "keep", 100)
		local price = Economy.finishGold(job2.endAt - 100)
		expect.truthy(price > 0)
		expect.eq(City.finishJob(data, job2.id, 100), nil)
		expect.eq(data.resources.gold, gold - price)
	end)

	test("heroes level up from XP and stop at the cap", function()
		local data = Schema.new("A", 0)
		expect.eq(City.giveHeroXp(data, "aldric", City.heroXpToNext(1)), 1)
		expect.eq(data.heroes.aldric.level, 2)
		City.giveHeroXp(data, "aldric", 1e9)
		expect.eq(data.heroes.aldric.level, Balance.HERO_MAX_LEVEL)
		expect.eq(City.giveHeroXp(data, "kaela", 100), 0)
	end)

	test("recruiting a hero costs gold once", function()
		local data = Schema.new("A", 0)
		data.resources.gold = 1000
		expect.eq(City.recruitHero(data, "kaela"), nil)
		expect.eq(data.resources.gold, 1000 - Balance.HEROES.kaela.recruitGold)
		expect.eq(City.recruitHero(data, "kaela"), "err.owned")
		expect.eq(City.recruitHero(data, "nobody"), "err.unknown")
	end)

	test("the quest chain pays out in order", function()
		local data = Schema.new("A", 0)
		expect.eq(City.claimQuest(data), "err.notDone")
		data.buildings.farm = 2
		local food = data.resources.food
		expect.eq(City.claimQuest(data), nil)
		expect.eq(data.resources.food, food + Balance.QUESTS[1].reward.food)
		expect.eq(data.questIndex, 2)
		data.questIndex = #Balance.QUESTS + 1
		expect.eq(City.claimQuest(data), "err.nothing")
	end)

	test("healing brings the wounded back for a share of their cost", function()
		local data = rich(Schema.new("A", 0))
		expect.eq(City.heal(data), "err.nothing")
		data.wounded = { inf1 = 10 }
		local food = data.resources.food
		local home = data.troops.inf1
		expect.eq(City.heal(data), nil)
		expect.eq(data.troops.inf1, home + 10)
		expect.eq(data.resources.food, food - math.ceil(50 * 10 * Balance.HEAL_COST_SHARE))
	end)

	test("beginners are shielded until they attack or grow", function()
		local data = Schema.new("A", 0)
		expect.truthy(City.isShielded(data, 0))
		data.peaceBroken = true
		expect.falsy(City.isShielded(data, 0))
		data.shieldUntil = 50
		expect.truthy(City.isShielded(data, 10))
		expect.falsy(City.isShielded(data, 60))
	end)

	test("stamina regenerates up to the maximum", function()
		local data = Schema.new("A", 0)
		data.stamina = 0
		data.staminaAt = 0
		City.settle(data, Balance.STAMINA_SECONDS * 5 + 1)
		expect.eq(data.stamina, 5)
		City.settle(data, 1e7)
		expect.eq(data.stamina, Balance.STAMINA_MAX)
	end)

	test("reports keep only the newest", function()
		local data = Schema.new("A", 0)
		for i = 1, Balance.REPORTS_KEPT + 5 do
			City.addReport(data, { kind = "lost", n = i }, i)
		end
		expect.eq(#data.reports, Balance.REPORTS_KEPT)
		expect.eq(data.reports[1].n, Balance.REPORTS_KEPT + 5)
	end)
end
