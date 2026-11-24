--!strict
-- Deterministic battles: no dice, so the same armies always give the same report and players can learn the counters.

local Army = require(script.Parent.Army)
local Balance = require(script.Parent.Balance)
local Economy = require(script.Parent.Economy)

local Combat = {}

export type Side = {
	data: any,
	troops: Army.Troops,
	hero: string?,
	heroLevel: number?,
	wallBonus: number?,
}

export type SideResult = {
	before: Army.Troops,
	lost: Army.Troops,
	survivors: Army.Troops,
	powerLost: number,
}

export type Result = {
	attackerWon: boolean,
	rounds: number,
	wallBonus: number,
	attacker: SideResult,
	defender: SideResult,
}

type Stats = { [string]: { atk: number, def: number, hp: number, class: string } }

local function statsFor(side: Side): Stats
	local out: Stats = {}
	for id in side.troops do
		local atk, def, hp = Army.unitStats(side.data, id, side.hero, side.heroLevel)
		out[id] = { atk = atk, def = def, hp = hp, class = Balance.TROOPS[id].class }
	end
	return out
end

function Combat.counter(attackerClass: string, defenderClass: string): number
	local rule = Balance.COUNTERS[attackerClass]
	if rule.strong == defenderClass then
		return Balance.COUNTER_BONUS
	elseif rule.weak == defenderClass then
		return Balance.COUNTER_MALUS
	end
	return 1
end

-- Sorted keys keep the floating-point sums in the same order on every machine.
local function keys(t: { [string]: any }): { string }
	local out = {}
	for k in t do
		table.insert(out, k)
	end
	table.sort(out)
	return out
end

-- Units of `dst` killed by one round of fire from `src`.
local function volley(src: Army.Troops, srcStats: Stats, dst: Army.Troops, dstStats: Stats, dstWall: number): Army.Troops
	local dstTotal = Army.total(dst)
	local kills: { [string]: number } = {}
	if dstTotal <= 0 then
		return {}
	end
	for _, s in keys(src) do
		local firepower = src[s] * srcStats[s].atk / Balance.COMBAT_ROUNDS
		for _, d in keys(dst) do
			local share = dst[d] / dstTotal
			local mult = Combat.counter(srcStats[s].class, dstStats[d].class)
			local armour = 100 / (100 + dstStats[d].def * (1 + dstWall))
			kills[d] = (kills[d] or 0) + firepower * share * mult * armour / dstStats[d].hp
		end
	end
	local out: Army.Troops = {}
	for id, k in kills do
		out[id] = math.min(dst[id], math.floor(k + 0.5))
	end
	return out
end

function Combat.battle(attacker: Side, defender: Side): Result
	local a = Army.copy(attacker.troops)
	local d = Army.copy(defender.troops)
	local aStats = statsFor(attacker)
	local dStats = statsFor(defender)

	-- Siege engines tear the wall down: a fifth of the army in siege cancels half the wall bonus.
	local siege = 0
	for id, count in a do
		if Balance.TROOPS[id].class == "siege" then
			siege += count
		end
	end
	local siegeShare = if Army.total(a) > 0 then siege / Army.total(a) else 0
	local wall = (defender.wallBonus or 0) * math.max(0, 1 - siegeShare * 2.5)

	local rounds = 0
	for _ = 1, Balance.COMBAT_ROUNDS do
		if Army.total(a) <= 0 or Army.total(d) <= 0 then
			break
		end
		rounds += 1
		local dLost = volley(a, aStats, d, dStats, wall)
		local aLost = volley(d, dStats, a, aStats, 0)
		Army.remove(d, dLost)
		Army.remove(a, aLost)
	end

	local aLost = Army.copy(attacker.troops)
	Army.remove(aLost, a)
	local dLost = Army.copy(defender.troops)
	Army.remove(dLost, d)

	local aPower = Army.power(a)
	local dPower = Army.power(d)
	local attackerWon = Army.total(a) > 0 and (Army.total(d) == 0 or aPower > dPower * (1 + wall))

	return {
		attackerWon = attackerWon,
		rounds = rounds,
		wallBonus = wall,
		attacker = { before = Army.copy(attacker.troops), lost = aLost, survivors = a, powerLost = Army.power(aLost) },
		defender = { before = Army.copy(defender.troops), lost = dLost, survivors = d, powerLost = Army.power(dLost) },
	}
end

-- Splits losses into dead and wounded. Wounded only survive while the infirmary has room.
function Combat.splitLosses(lost: Army.Troops, woundedShare: number, room: number): (Army.Troops, Army.Troops)
	local dead: Army.Troops = {}
	local wounded: Army.Troops = {}
	local left = math.max(0, room)
	local ids = keys(lost)
	for _, id in ids do
		local count = lost[id]
		local w = math.min(left, math.floor(count * woundedShare))
		left -= w
		if w > 0 then
			wounded[id] = w
		end
		if count - w > 0 then
			dead[id] = count - w
		end
	end
	return dead, wounded
end

function Combat.monsterMaxHp(monster: string, level: number): number
	return math.floor(Balance.MONSTERS[monster].hpBase * level ^ Balance.MONSTER_HP_EXPONENT)
end

-- Damage a hunting army deals in one attack. Monsters do not kill troops; they cost stamina instead.
function Combat.huntDamage(data: any, troops: Army.Troops, hero: string?, heroLevel: number?): number
	local total = 0
	for _, id in keys(troops) do
		local atk = Army.unitStats(data, id, hero, heroLevel)
		total += troops[id] * atk
	end
	return math.floor(total * (1 + Economy.heroBonus(hero, heroLevel, "hunt", nil)))
end

-- Rewards for dealing `damage` to a monster with `maxHp`, plus the kill bonus when it falls.
function Combat.huntRewards(monster: string, level: number, damage: number, maxHp: number, killed: boolean): Economy.Resources
	local def = Balance.MONSTERS[monster]
	local share = math.min(1, damage / maxHp)
	local factor = level * (share + (if killed then Balance.KILL_BONUS else 0) * 0.25)
	return Economy.scale(def.reward, factor)
end

return Combat
