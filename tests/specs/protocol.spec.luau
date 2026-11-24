return function(test, expect, load)
	local Protocol = load("shared/Rules/Protocol")

	test("accepts a well-formed order", function()
		local clean, err = Protocol.validate("march", { kind = "gather", x = 3, y = 4, troops = { inf1 = 10 } })
		expect.eq(err, nil)
		expect.same(clean, { kind = "gather", x = 3, y = 4, troops = { inf1 = 10 } })
		expect.truthy(Protocol.validate("heal", nil))
	end)

	test("rejects what an exploit would send", function()
		local nan = 0 / 0
		local cases = {
			{ "upgrade", { building = 5 } },
			{ "upgrade", { building = string.rep("a", 100) } },
			{ "upgrade", { building = "farm; drop" } },
			{ "upgrade", { building = "farm", extra = true } },
			{ "upgrade", {} },
			{ "train", { troop = "inf1", count = nan } },
			{ "train", { troop = "inf1", count = math.huge } },
			{ "train", { troop = "inf1", count = 1.5 } },
			{ "march", { kind = "gather", x = 1, y = 1, troops = { inf1 = -5 } } },
			{ "march", { kind = "gather", x = 1, y = 1, troops = { ghost = 5 } } },
			{ "march", { kind = "gather", x = 1, y = 1, troops = "lots" } },
			{ "watch", { chunks = { 1, 2, "x" } } },
			{ "nope", {} },
			{ 42, {} },
			{ "heal", "x" },
		}
		for i, case in cases do
			local clean = Protocol.validate(case[1], case[2])
			expect.eq(clean, nil, "case " .. i)
		end
	end)

	test("zero-count troops are dropped and an empty army is optional", function()
		local clean = Protocol.validate("march", { kind = "scout", x = 1, y = 1 })
		expect.eq(clean.troops, nil)
		local clean2 = Protocol.validate("march", { kind = "gather", x = 1, y = 1, troops = { inf1 = 0 } })
		expect.eq(clean2, nil)
	end)
end
