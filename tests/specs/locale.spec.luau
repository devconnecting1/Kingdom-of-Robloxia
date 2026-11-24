return function(test, expect, load)
	local Balance = load("shared/Rules/Balance")
	local Locale = load("shared/Locale")

	local function placeholders(s: string): string
		local found = {}
		for name in string.gmatch(s, "{(%w+)}") do
			table.insert(found, name)
		end
		table.sort(found)
		return table.concat(found, ",")
	end

	test("English and Portuguese have the same keys and placeholders", function()
		local en, pt = Locale.tables.en, Locale.tables.pt
		for key, text in en do
			expect.truthy(pt[key], "pt is missing " .. key)
			expect.eq(placeholders(pt[key]), placeholders(text), "placeholders of " .. key)
		end
		for key in pt do
			expect.truthy(en[key], "en is missing " .. key)
		end
	end)

	test("every game id has a name", function()
		local en = Locale.tables.en
		for id in Balance.BUILDINGS do
			expect.truthy(en["b." .. id] and en["bd." .. id], "building " .. id)
		end
		for id in Balance.TROOPS do
			expect.truthy(en["t." .. id], "troop " .. id)
		end
		for id, def in Balance.RESEARCH do
			expect.truthy(en["tech." .. id] and en["stat." .. def.stat] and en["branch." .. def.branch], "tech " .. id)
		end
		for id, def in Balance.HEROES do
			expect.truthy(en["hero." .. id] and en["rarity." .. def.rarity], "hero " .. id)
		end
		for id in Balance.MONSTERS do
			expect.truthy(en["mon." .. id], "monster " .. id)
		end
		for _, res in Balance.RESOURCES do
			expect.truthy(en["res." .. res], "resource " .. res)
		end
	end)

	test("every error key a rule can return is translated", function()
		local en = Locale.tables.en
		for _, file in { "City", "World", "Protocol" } do
			local source = require("@lune/fs").readFile("src/shared/Rules/" .. file .. ".luau")
			for key in string.gmatch(source, '"(err%.%w+)"') do
				expect.truthy(en[key], key .. " used in " .. file)
			end
			for key in string.gmatch(source, '"(toast%.%w+)"') do
				expect.truthy(en[key], key .. " used in " .. file)
			end
		end
	end)

	test("every literal key the interface uses exists, and every quest has a text", function()
		local fs = require("@lune/fs")
		local en = Locale.tables.en
		local function scan(dir: string)
			for _, name in fs.readDir(dir) do
				local path = dir .. "/" .. name
				if fs.isDir(path) then
					scan(path)
				elseif string.match(name, "%.luau$") then
					local source = fs.readFile(path)
					for key in string.gmatch(source, '[%s%(%[{=,]t%("([%w_%.]+)"[,%)]') do
						expect.truthy(en[key], key .. " used in " .. path)
					end
				end
			end
		end
		scan("src/client")
		for _, quest in Balance.QUESTS do
			expect.truthy(en["quest." .. quest.id], "quest." .. quest.id)
		end
	end)

	test("fills placeholders and falls back to the key", function()
		Locale.set("pt")
		expect.eq(Locale.t("ui.level", { level = 3 }), "Nv. 3")
		Locale.set("en")
		expect.eq(Locale.t("ui.level", { level = 3 }), "Lv. 3")
		expect.eq(Locale.t("no.such.key"), "no.such.key")
		expect.eq(Locale.fromRobloxId("pt-br"), "pt")
		expect.eq(Locale.fromRobloxId("en-us"), "en")
	end)
end
