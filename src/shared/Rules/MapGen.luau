--!strict
-- Terrain, zones and spawning for the 96×96 realm. Terrain is a pure function of the seed and the tile, so the client
-- draws it without the server sending a single tile of it.

local Balance = require(script.Parent.Balance)
local Combat = require(script.Parent.Combat)
local Rng = require(script.Parent.Rng)

local MapGen = {}

local CENTER = (Balance.MAP_SIZE - 1) / 2

function MapGen.ring(x: number, y: number): number
	return math.max(math.abs(x - CENTER), math.abs(y - CENTER))
end

function MapGen.zone(x: number, y: number): number
	local d = MapGen.ring(x, y)
	for _, zone in Balance.ZONES do
		if d >= zone.minDist then
			return zone.level
		end
	end
	return 4
end

function MapGen.inBounds(x: number, y: number): boolean
	return x >= 0 and y >= 0 and x < Balance.MAP_SIZE and y < Balance.MAP_SIZE and x % 1 == 0 and y % 1 == 0
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- Value noise in [0, 1).
function MapGen.noise(seed: number, x: number, y: number, scale: number): number
	local fx, fy = x / scale, y / scale
	local x0, y0 = math.floor(fx), math.floor(fy)
	local tx, ty = smooth(fx - x0), smooth(fy - y0)
	local a = Rng.hash(seed, x0, y0)
	local b = Rng.hash(seed, x0 + 1, y0)
	local c = Rng.hash(seed, x0, y0 + 1)
	local d = Rng.hash(seed, x0 + 1, y0 + 1)
	local top = a + (b - a) * tx
	local bottom = c + (d - c) * tx
	return top + (bottom - top) * ty
end

-- Purely visual: terrain never changes a rule.
function MapGen.biome(seed: number, x: number, y: number): string
	if MapGen.zone(x, y) == 4 then
		return "crown"
	end
	local h = MapGen.noise(seed, x, y, 11) * 0.7 + MapGen.noise(seed + 7, x, y, 4) * 0.3
	local m = MapGen.noise(seed + 13, x, y, 9)
	if h < 0.25 then
		return "lake"
	elseif h > 0.72 then
		return "hills"
	elseif m > 0.6 then
		return "forest"
	end
	return "meadow"
end

function MapGen.newNode(rng: Rng.Rng, x: number, y: number): any
	local res = rng:weighted(Balance.NODE_WEIGHTS)
	local zone = MapGen.zone(x, y)
	local level = math.clamp(zone + (if rng:chance(0.25) then 1 else 0), 1, 5)
	local amount = math.floor(Balance.NODES[res].amountBase * (1 + (level - 1) * 0.6))
	return { kind = "node", x = x, y = y, res = res, level = level, amount = amount, maxAmount = amount }
end

function MapGen.newMonster(rng: Rng.Rng, x: number, y: number): any
	local zone = MapGen.zone(x, y)
	local options = {}
	for _, id in Balance.MONSTER_ORDER do
		if Balance.MONSTERS[id].minZone <= zone then
			table.insert(options, id)
		end
	end
	local monster = rng:pick(options)
	local level = math.clamp(zone + rng:int(0, 1), 1, 5)
	local hp = Combat.monsterMaxHp(monster, level)
	return { kind = "monster", x = x, y = y, monster = monster, level = level, hp = hp, maxHp = hp }
end

-- A random tile for which `ok(x, y)` holds, tried a bounded number of times so a full map cannot hang the server.
function MapGen.randomTile(rng: Rng.Rng, ok: (number, number) -> boolean, zone: number?): (number?, number?)
	for _ = 1, 400 do
		local x = rng:int(0, Balance.MAP_SIZE - 1)
		local y = rng:int(0, Balance.MAP_SIZE - 1)
		if (zone == nil or MapGen.zone(x, y) == zone) and ok(x, y) then
			return x, y
		end
	end
	return nil, nil
end

function MapGen.chunkOf(x: number, y: number): number
	local per = Balance.MAP_SIZE // Balance.CHUNK_SIZE
	return (y // Balance.CHUNK_SIZE) * per + (x // Balance.CHUNK_SIZE)
end

function MapGen.chunkCount(): number
	local per = Balance.MAP_SIZE // Balance.CHUNK_SIZE
	return per * per
end

return MapGen
