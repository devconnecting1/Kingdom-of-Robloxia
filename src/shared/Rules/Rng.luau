--!strict
-- Seeded xorshift32. The world, the map and the bots draw from it instead of math.random, so a realm built from the
-- same seed is the same realm, and the tests can replay any session.

local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { state: number }, Rng))

local function mix(seed: number): number
	local s = bit32.band(math.floor(seed), 0xFFFFFFFF)
	if s == 0 then
		s = 0x9E3779B9
	end
	return s
end

function Rng.new(seed: number): Rng
	local self = setmetatable({ state = mix(seed) }, Rng)
	-- The first outputs of xorshift follow the seed closely; skip them.
	for _ = 1, 8 do
		self:nextU32()
	end
	return self
end

function Rng.nextU32(self: Rng): number
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.state = x
	return x
end

-- A float in [0, 1).
function Rng.float(self: Rng): number
	return self:nextU32() / 4294967296
end

-- An integer in [min, max], both included.
function Rng.int(self: Rng, min: number, max: number): number
	return min + math.floor(self:float() * (max - min + 1))
end

function Rng.chance(self: Rng, p: number): boolean
	return self:float() < p
end

function Rng.pick<T>(self: Rng, list: { T }): T
	return list[self:int(1, #list)]
end

-- Picks a key from a weight table; keys are visited in sorted order so the result does not depend on table layout.
function Rng.weighted(self: Rng, weights: { [string]: number }): string
	local keys = {}
	local total = 0
	for key, weight in weights do
		table.insert(keys, key)
		total += weight
	end
	table.sort(keys)
	local roll = self:float() * total
	for _, key in keys do
		roll -= weights[key]
		if roll < 0 then
			return key
		end
	end
	return keys[#keys]
end

-- 32-bit multiplication modulo 2^32, split in 16-bit halves so no product leaves the exact range of a double.
local function imul(a: number, b: number): number
	local aHi, aLo = bit32.rshift(a, 16), bit32.band(a, 0xFFFF)
	local bHi, bLo = bit32.rshift(b, 16), bit32.band(b, 0xFFFF)
	local cross = bit32.band(aHi * bLo + aLo * bHi, 0xFFFF)
	return bit32.band(aLo * bLo + cross * 65536, 0xFFFFFFFF)
end

-- A stable hash of integers in [0, 2^32), for values tied to a place (terrain) rather than to the order of draws.
function Rng.hash(a: number, b: number, c: number): number
	local h = mix(a)
	h = imul(bit32.bxor(h, bit32.band(b, 0xFFFFFFFF)), 0x85EBCA6B)
	h = imul(bit32.bxor(h, bit32.rshift(h, 13)), 0xC2B2AE35)
	h = imul(bit32.bxor(h, bit32.band(c, 0xFFFFFFFF)), 0x27D4EB2F)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / 4294967296
end

return Rng
