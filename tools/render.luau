-- Renders the real interface code to JSON scenes for the screenshot pipeline: `lune run tools/render.luau`.
--
-- It plays a short realm with the real rules (50 kingdoms, bots acting), takes one kingdom's view, runs UI/App on
-- it with stand-ins for Roblox's UDim2, Color3 and Enum, and writes each element tree to preview/public/scenes/.
-- The web previewer then lays the tree out with Roblox's rules (UDim2, anchors, list and grid layouts, padding,
-- corners, strokes, gradients) and Playwright saves the PNGs. Nothing is drawn by hand for the screenshots.

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Loader = require("../tests/lib/Loader")

-- Roblox datatype stand-ins ---------------------------------------------------------------------------------------------

local function tagged(t: string, fields: { [string]: any }): any
	fields.__t = t
	return fields
end

local UDim = {
	new = function(s: number, o: number)
		return tagged("UDim", { s = s, o = o })
	end,
}
local UDim2 = {
	new = function(xs: number, xo: number, ys: number, yo: number)
		return tagged("UDim2", { xs = xs, xo = xo, ys = ys, yo = yo })
	end,
	fromScale = function(x: number, y: number)
		return tagged("UDim2", { xs = x, xo = 0, ys = y, yo = 0 })
	end,
	fromOffset = function(x: number, y: number)
		return tagged("UDim2", { xs = 0, xo = x, ys = 0, yo = y })
	end,
}
local Vector2 = {
	new = function(x: number, y: number)
		return tagged("Vector2", { x = x, y = y })
	end,
}
Vector2.zero = Vector2.new(0, 0)
local Color3 = {
	fromRGB = function(r: number, g: number, b: number)
		return tagged("Color3", { r = r, g = g, b = b })
	end,
	new = function(r: number, g: number, b: number)
		return tagged("Color3", { r = r * 255, g = g * 255, b = b * 255 })
	end,
}
local ColorSequence = {
	new = function(a: any, b: any?)
		return tagged("ColorSequence", { a = a, b = b or a })
	end,
}
local Enum = setmetatable({}, {
	__index = function(_, enumName: string)
		return setmetatable({}, {
			__index = function(_, item: string)
				return tagged("Enum", { e = enumName, v = item })
			end,
		})
	end,
})

local nodeShared = Loader.node("src/shared")
local ReplicatedStorage = {
	Shared = nodeShared,
	WaitForChild = function(self: any, name: string)
		return self[name]
	end,
}
local game = {
	GetService = function(_self: any, name: string): any
		if name == "ReplicatedStorage" then
			return ReplicatedStorage
		end
		error("render: no service " .. name)
	end,
}

Loader.setGlobals({
	UDim = UDim,
	UDim2 = UDim2,
	Vector2 = Vector2,
	Color3 = Color3,
	ColorSequence = ColorSequence,
	Enum = Enum,
	game = game,
})

local function load(path: string): any
	return Loader.load("src/" .. path)
end

local Army = load("shared/Rules/Army")
local Balance = load("shared/Rules/Balance")
local Bot = load("shared/Rules/Bot")
local Locale = load("shared/Locale")
local MapGen = load("shared/Rules/MapGen")
local Rng = load("shared/Rules/Rng")
local Schema = load("shared/Rules/Schema")
local World = load("shared/Rules/World")
local App = load("client/UI/App")
local Map = load("client/UI/Screens/Map")
local Store = load("client/Store")
local Theme = load("client/UI/Theme")

-- A realm to photograph ---------------------------------------------------------------------------------------------

local SEED = 20261124
local world = World.new(SEED, 0)
local rng = Rng.new(SEED)
local taken = {}
local others = {}
for i = 1, Balance.BOT_COUNT + Balance.MAX_REAL_PLAYERS - 1 do
	local name = Bot.newName(rng, taken)
	taken[name] = true
	local data = Schema.new(name, 0)
	Bot.prepare(data, rng)
	local isBot = i <= Balance.BOT_COUNT
	local kid = (if isBot then "b" else "u") .. i
	local k = world:addKingdom(kid, data, isBot, 0)
	k.personality = Bot.PERSONALITIES[(i - 1) % #Bot.PERSONALITIES + 1]
	table.insert(others, kid)
end

-- The kingdom on camera: a few days into the game.
local me = Schema.new("Aurelia", 0)
for id, level in {
	keep = 9,
	farm = 9,
	sawmill = 9,
	quarry = 8,
	mine = 7,
	manor = 6,
	barracks = 8,
	wall = 8,
	infirmary = 6,
	vault = 5,
	academy = 5,
	embassy = 4,
	warhall = 6,
	watchtower = 3,
} do
	me.buildings[id] = level
end
me.troops = { inf1 = 2400, rng1 = 1900, cav1 = 1200, sie1 = 300, inf2 = 900, rng2 = 650, cav2 = 420, inf3 = 120 }
me.research = { agriculture = 4, forestry = 3, masonry = 2, surveying = 3, forging = 2, plating = 2, roads = 1, packs = 2 }
me.heroes.kaela = { level = 14, xp = 820 }
me.heroes.seren = { level = 9, xp = 300 }
me.heroes.aldric = { level = 17, xp = 1500 }
me.heroes.mira = { level = 12, xp = 200 }
for _, res in Balance.RESOURCES do
	me.resources[res] = ({ food = 182400, wood = 151300, stone = 96200, ore = 44800, gold = 2350 })[res]
end
me.peaceBroken = true
me.questIndex = 9
me.stats.gathered = 48000
local mine = world:addKingdom("u0", me, false, 0)
world:command("u0", "guildJoin", { guild = 1 }, 0)

local function nearestCastle(filter: (any) -> boolean): any
	local castle = world:castleOf(mine)
	return world:nearest(castle.x, castle.y, 200, function(e)
		return e.kind == "castle" and e.kid ~= "u0" and filter(world.kingdoms[e.kid])
	end)
end

local t = 0
local function advance(to: number)
	while t < to do
		t += 1
		world:step(t)
		for i, kid in others do
			if (t + i) % 10 == 0 then
				Bot.tick(world, kid, t, rng)
			end
		end
	end
end

advance(600)
-- Scripted moves for the reports and the map.
local castle = world:castleOf(mine)
local monster = world:nearest(castle.x, castle.y, 40, function(e)
	return e.kind == "monster"
end)
if monster then
	world:command("u0", "march", { kind = "hunt", x = monster.x, y = monster.y, troops = { inf2 = 600, rng2 = 500, cav1 = 400 }, hero = "kaela" }, t)
end
local node = world:nearest(castle.x, castle.y, 40, function(e)
	return e.kind == "node" and not e.gatherer and e.res == "ore"
end)
if node then
	world:command("u0", "march", { kind = "gather", x = node.x, y = node.y, troops = { inf1 = 900 }, hero = "seren" }, t)
end
local target = nearestCastle(function(k)
	return k.guild ~= mine.guild and k.data.buildings.keep >= 5 and k.data.shieldUntil <= t
end)
if target then
	world.kingdoms[target.kid].data.peaceBroken = true
	world:command("u0", "march", { kind = "attack", x = target.x, y = target.y, troops = { cav2 = 420, cav1 = 800, inf2 = 300, sie1 = 300 }, hero = "aldric" }, t)
end
advance(t + 900)
local scoutTarget = nearestCastle(function(k)
	return k.guild ~= mine.guild
end)
if scoutTarget then
	world:command("u0", "march", { kind = "scout", x = scoutTarget.x, y = scoutTarget.y }, t)
end
advance(t + 400)
-- Something in every queue, and armies out on the map.
world:command("u0", "upgrade", { building = "academy" }, t)
world:command("u0", "train", { troop = "rng2", count = 600 }, t)
world:command("u0", "research", { tech = "vitality" }, t)
local second = world:nearest(castle.x, castle.y, 40, function(e)
	return e.kind == "node" and not e.gatherer and e.res == "food"
end)
if second then
	world:command("u0", "march", { kind = "gather", x = second.x, y = second.y, troops = { inf1 = 800 } }, t)
end
local hunt = world:nearest(castle.x, castle.y, 40, function(e)
	return e.kind == "monster" and (monster == nil or e.id ~= monster.id)
end)
if hunt then
	world:command("u0", "march", { kind = "hunt", x = hunt.x, y = hunt.y, troops = { rng1 = 800, cav1 = 300 }, hero = "mira" }, t)
end
advance(t + 25)
mine.data.resources.gold = 2350
for i, r in mine.data.reports do
	r.read = i > 2
end

-- Client state for the scenes --------------------------------------------------------------------------------------

local function freshState(): any
	local state = Store.initialState()
	state.view = world:view("u0", t)
	state.now = t
	state.marches = world:marchList()
	state.castles = world:castleList()
	state.map.x, state.map.y = castle.x + 1.5, castle.y + 0.5
	return state
end

local function fillChunks(state: any)
	for _, c in Map.visibleChunks(state) do
		Store.setChunk(state, c, world:chunkView(c))
	end
end

local noop = setmetatable({}, {
	__index = function()
		return function() end
	end,
})

-- Serialisation -----------------------------------------------------------------------------------------------------

local function encodeValue(v: any): any
	local kind = type(v)
	if kind == "function" then
		return nil
	elseif kind == "table" then
		if v.__t then
			local out = {}
			for k, x in v do
				out[k] = encodeValue(x)
			end
			return out
		end
		return nil
	end
	return v
end

local function encode(element: any, key: any): any
	local props = {}
	for k, v in element.props do
		if k ~= "ref" and not (string.sub(k, 1, 2) == "on" and #k > 2 and string.match(string.sub(k, 3, 3), "%u")) then
			local value = encodeValue(v)
			if value ~= nil then
				props[k] = value
			end
		end
	end
	if type(key) == "number" and props.LayoutOrder == nil then
		props.LayoutOrder = key
	end
	local children = {}
	if element.children then
		local keys = {}
		for k, child in element.children do
			if child then
				table.insert(keys, k)
			end
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		for _, k in keys do
			local child = encode(element.children[k], k)
			child.name = if type(k) == "number" then string.format("%04d", k) else tostring(k)
			table.insert(children, child)
		end
	end
	return { class = element.class, props = props, children = children }
end

-- Scenes ------------------------------------------------------------------------------------------------------------

local DESKTOP = { 1600, 900 }
local PHONE = { 844, 390 }

local scenes = {
	{ name = "01-kingdom", lang = "pt", size = DESKTOP, screen = "city" },
	{ name = "02-realm-map", lang = "pt", size = DESKTOP, screen = "map", select = "monster" },
	{ name = "03-march", lang = "pt", size = DESKTOP, screen = "map", march = "gather" },
	{ name = "04-army", lang = "pt", size = DESKTOP, screen = "army", troop = "cav2" },
	{ name = "05-heroes", lang = "pt", size = DESKTOP, screen = "heroes" },
	{ name = "06-academy", lang = "pt", size = DESKTOP, screen = "academy" },
	{ name = "07-guild", lang = "pt", size = DESKTOP, screen = "guild" },
	{ name = "08-reports", lang = "pt", size = DESKTOP, screen = "reports", report = "attack" },
	{ name = "09-building", lang = "pt", size = DESKTOP, screen = "city", modal = { kind = "building", id = "keep" } },
	{ name = "10-ranking", lang = "pt", size = DESKTOP, screen = "city", modal = { kind = "ranking" } },
	{ name = "11-kingdom-en", lang = "en", size = DESKTOP, screen = "city" },
	{ name = "12-phone-kingdom", lang = "pt", size = PHONE, screen = "city", scale = 2 },
	{ name = "13-phone-map", lang = "pt", size = PHONE, screen = "map", scale = 2 },
}

fs.writeDir("preview/public/scenes")
local index = {}
for _, scene in scenes do
	Locale.set(scene.lang)
	Theme.setViewport(scene.size[1], scene.size[2])
	local state = freshState()
	state.screen = scene.screen
	state.modal = scene.modal
	if scene.troop then
		state.selected.troop = scene.troop
		state.selected.count = 250
	end
	if scene.screen == "map" then
		fillChunks(state)
	end
	if scene.select == "monster" then
		local m = world:nearest(castle.x, castle.y, 10, function(e)
			return e.kind == "monster"
		end)
		if m then
			state.selected.tile = { x = m.x, y = m.y }
		end
	end
	if scene.march then
		local n = world:nearest(castle.x, castle.y, 12, function(e)
			return e.kind == "node" and not e.gatherer
		end)
		local actions = Store.actions(state, function()
			return { ok = true }
		end, function() end)
		if n then
			actions.openMarch(scene.march, n.x, n.y)
		end
	end
	if scene.report then
		for _, r in state.view.reports do
			if r.kind == scene.report then
				state.selected.report = r.id
				break
			end
		end
	end
	local tree = App.render(state, noop)
	local file = "preview/public/scenes/" .. scene.name .. ".json"
	fs.writeFile(file, serde.encode("json", { width = scene.size[1], height = scene.size[2], root = encode(tree, "Root") }))
	table.insert(index, { name = scene.name, width = scene.size[1], height = scene.size[2], scale = scene.scale or 1 })
	print(string.format("  scene %-18s %dx%d", scene.name, scene.size[1], scene.size[2]))
end
fs.writeFile("preview/public/scenes/index.json", serde.encode("json", index, true))

-- A few numbers from the photographed realm, for the README.
local marchCount = #world:marchList()
print(string.format(
	"realm: %d kingdoms, %d marches, %d fields, %d monsters, Aurelia power %d (rank %d), troops at home %d",
	world.kingdomCount,
	marchCount,
	world.nodeCount,
	world.monsterCount,
	world:power(mine),
	world:view("u0", t).rank,
	Army.total(mine.data.troops)
))
assert(MapGen.zone(castle.x, castle.y) >= 1)
