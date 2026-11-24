--!strict
-- Every number of the game lives here. The server, the bots, the UI and the Lune tests all read this one table, so a
-- balance change is a data edit and never a second copy of a rule.

local Balance = {}

-- World ---------------------------------------------------------------------------------------------------------------

-- 96×96 tiles: room for 50 castles at least 3 tiles apart plus about 550 resource fields and monsters, while a march
-- across the whole map still takes under eight minutes for infantry.
Balance.MAP_SIZE = 96
Balance.CHUNK_SIZE = 16
Balance.MAX_REAL_PLAYERS = 20
Balance.BOT_COUNT = 30
Balance.CASTLE_SPACING = 3

-- Zones are rings around the Crown Lands in the centre; the inner ones hold richer fields and stronger monsters.
-- A ring is chosen by the Chebyshev distance from the centre.
Balance.ZONES = {
	{ level = 1, minDist = 36 },
	{ level = 2, minDist = 24 },
	{ level = 3, minDist = 12 },
	{ level = 4, minDist = 0 },
}
Balance.NODE_TARGET = 420
Balance.MONSTER_TARGET = 110
Balance.RESPAWN_SECONDS = 45
Balance.RELOCATE_GOLD = 200

-- Resources -----------------------------------------------------------------------------------------------------------

Balance.RESOURCES = { "food", "wood", "stone", "ore", "gold" }
Balance.RESOURCE_ICONS = { food = "🌾", wood = "🪵", stone = "🪨", ore = "⛓️", gold = "🪙" }

Balance.START_RESOURCES = { food = 4000, wood = 4000, stone = 1500, ore = 600, gold = 300 }
Balance.STORAGE_BASE = 12000
Balance.STORAGE_GROWTH = 1.45

-- Buildings -----------------------------------------------------------------------------------------------------------

export type BuildingDef = {
	order: number,
	icon: string,
	maxLevel: number,
	unlockKeep: number,
	baseCost: { [string]: number },
	baseTime: number,
	power: number,
	produces: string?,
	baseRate: number?,
}

Balance.COST_GROWTH = 1.6
Balance.TIME_GROWTH = 1.5
Balance.RATE_EXPONENT = 1.2
Balance.KEEP_MAX = 15

Balance.BUILDINGS = {
	keep = {
		order = 1,
		icon = "🏰",
		maxLevel = 15,
		unlockKeep = 0,
		baseCost = { food = 400, wood = 400, stone = 150 },
		baseTime = 12,
		power = 60,
	},
	farm = {
		order = 2,
		icon = "🌾",
		maxLevel = 15,
		unlockKeep = 0,
		baseCost = { wood = 120 },
		baseTime = 6,
		power = 10,
		produces = "food",
		baseRate = 900,
	},
	sawmill = {
		order = 3,
		icon = "🪵",
		maxLevel = 15,
		unlockKeep = 0,
		baseCost = { food = 120 },
		baseTime = 6,
		power = 10,
		produces = "wood",
		baseRate = 900,
	},
	quarry = {
		order = 4,
		icon = "🪨",
		maxLevel = 15,
		unlockKeep = 2,
		baseCost = { food = 160, wood = 160 },
		baseTime = 8,
		power = 12,
		produces = "stone",
		baseRate = 600,
	},
	mine = {
		order = 5,
		icon = "⛏️",
		maxLevel = 15,
		unlockKeep = 4,
		baseCost = { food = 220, wood = 220, stone = 120 },
		baseTime = 10,
		power = 14,
		produces = "ore",
		baseRate = 450,
	},
	manor = {
		order = 6,
		icon = "🏛️",
		maxLevel = 15,
		unlockKeep = 3,
		baseCost = { food = 260, wood = 260, stone = 160 },
		baseTime = 10,
		power = 14,
		produces = "gold",
		baseRate = 120,
	},
	barracks = {
		order = 7,
		icon = "⚔️",
		maxLevel = 15,
		unlockKeep = 1,
		baseCost = { food = 180, wood = 220 },
		baseTime = 8,
		power = 16,
	},
	wall = {
		order = 8,
		icon = "🧱",
		maxLevel = 15,
		unlockKeep = 1,
		baseCost = { wood = 200, stone = 200 },
		baseTime = 9,
		power = 18,
	},
	infirmary = {
		order = 9,
		icon = "⛑️",
		maxLevel = 15,
		unlockKeep = 2,
		baseCost = { food = 200, wood = 180 },
		baseTime = 8,
		power = 10,
	},
	vault = {
		order = 10,
		icon = "🔐",
		maxLevel = 15,
		unlockKeep = 2,
		baseCost = { wood = 220, stone = 180 },
		baseTime = 8,
		power = 10,
	},
	academy = {
		order = 11,
		icon = "📜",
		maxLevel = 15,
		unlockKeep = 3,
		baseCost = { food = 300, wood = 300, stone = 200 },
		baseTime = 12,
		power = 16,
	},
	embassy = {
		order = 12,
		icon = "🤝",
		maxLevel = 15,
		unlockKeep = 3,
		baseCost = { food = 250, wood = 250 },
		baseTime = 10,
		power = 10,
	},
	warhall = {
		order = 13,
		icon = "🚩",
		maxLevel = 15,
		unlockKeep = 4,
		baseCost = { food = 400, wood = 300, stone = 300 },
		baseTime = 12,
		power = 20,
	},
	watchtower = {
		order = 14,
		icon = "🔭",
		maxLevel = 15,
		unlockKeep = 5,
		baseCost = { wood = 400, stone = 400, ore = 100 },
		baseTime = 12,
		power = 14,
	},
} :: { [string]: BuildingDef }

Balance.BUILDING_ORDER = {
	"keep",
	"farm",
	"sawmill",
	"quarry",
	"mine",
	"manor",
	"barracks",
	"wall",
	"infirmary",
	"vault",
	"academy",
	"embassy",
	"warhall",
	"watchtower",
}

Balance.START_BUILDINGS = { keep = 2, farm = 1, sawmill = 1, barracks = 1, wall = 1 }

-- A task with this many seconds or fewer left can be finished at once for free.
Balance.FREE_FINISH_SECONDS = 30
-- Gold per started minute to finish anything else at once.
Balance.GOLD_PER_MINUTE = 3

-- Effects of buildings, in the order the UI lists them.
Balance.EFFECTS = {
	barracksBatchBase = 100,
	barracksBatchPerLevel = 120,
	tier2Barracks = 4,
	tier3Barracks = 8,
	infirmaryPerLevel = 250,
	vaultBase = 1500,
	vaultExponent = 1.35,
	wallDefensePerLevel = 0.05,
	marchSizeBase = 600,
	marchSizePerLevel = 400,
	marchSlotsEvery = 4,
	marchSlotsMax = 5,
	embassyHelpBase = 3,
	academySpeedPerLevel = 0.03,
	manorBuilderLevel = 5,
	watchtowerDetailLevel = 3,
}

-- Troops --------------------------------------------------------------------------------------------------------------

export type TroopDef = {
	class: string,
	tier: number,
	icon: string,
	atk: number,
	def: number,
	hp: number,
	load: number,
	speed: number, -- tiles per minute
	power: number,
	time: number, -- seconds per unit
	cost: { [string]: number },
}

Balance.TROOP_CLASSES = { "infantry", "ranged", "cavalry", "siege" }
Balance.CLASS_ICONS = { infantry = "🛡️", ranged = "🏹", cavalry = "🐎", siege = "🪃" }

-- Infantry holds cavalry, cavalry runs down archers, archers shoot infantry; siege breaks walls.
Balance.COUNTER_BONUS = 1.3
Balance.COUNTER_MALUS = 0.8
Balance.COUNTERS = {
	infantry = { strong = "cavalry", weak = "ranged" },
	ranged = { strong = "infantry", weak = "cavalry" },
	cavalry = { strong = "ranged", weak = "infantry" },
	siege = {},
}

Balance.TROOPS = {
	inf1 = {
		class = "infantry",
		tier = 1,
		icon = "🛡️",
		atk = 8,
		def = 12,
		hp = 40,
		load = 12,
		speed = 12,
		power = 1,
		time = 1.2,
		cost = { food = 50, wood = 30 },
	},
	inf2 = {
		class = "infantry",
		tier = 2,
		icon = "🛡️",
		atk = 18,
		def = 27,
		hp = 88,
		load = 26,
		speed = 12,
		power = 3,
		time = 3,
		cost = { food = 120, wood = 70, ore = 20 },
	},
	inf3 = {
		class = "infantry",
		tier = 3,
		icon = "🛡️",
		atk = 36,
		def = 54,
		hp = 180,
		load = 52,
		speed = 12,
		power = 7,
		time = 7,
		cost = { food = 260, wood = 150, ore = 80, gold = 3 },
	},
	rng1 = {
		class = "ranged",
		tier = 1,
		icon = "🏹",
		atk = 12,
		def = 6,
		hp = 30,
		load = 10,
		speed = 12,
		power = 1,
		time = 1.2,
		cost = { food = 40, wood = 50 },
	},
	rng2 = {
		class = "ranged",
		tier = 2,
		icon = "🏹",
		atk = 27,
		def = 13,
		hp = 66,
		load = 22,
		speed = 12,
		power = 3,
		time = 3,
		cost = { food = 90, wood = 110, ore = 20 },
	},
	rng3 = {
		class = "ranged",
		tier = 3,
		icon = "🏹",
		atk = 54,
		def = 27,
		hp = 135,
		load = 44,
		speed = 12,
		power = 7,
		time = 7,
		cost = { food = 200, wood = 230, ore = 80, gold = 3 },
	},
	cav1 = {
		class = "cavalry",
		tier = 1,
		icon = "🐎",
		atk = 11,
		def = 8,
		hp = 38,
		load = 8,
		speed = 20,
		power = 1,
		time = 1.5,
		cost = { food = 60, wood = 20, stone = 20 },
	},
	cav2 = {
		class = "cavalry",
		tier = 2,
		icon = "🐎",
		atk = 24,
		def = 18,
		hp = 84,
		load = 18,
		speed = 20,
		power = 3,
		time = 3.6,
		cost = { food = 140, wood = 40, ore = 40 },
	},
	cav3 = {
		class = "cavalry",
		tier = 3,
		icon = "🐎",
		atk = 50,
		def = 36,
		hp = 170,
		load = 36,
		speed = 20,
		power = 7,
		time = 8,
		cost = { food = 300, wood = 90, ore = 120, gold = 3 },
	},
	sie1 = {
		class = "siege",
		tier = 1,
		icon = "🪃",
		atk = 18,
		def = 4,
		hp = 30,
		load = 20,
		speed = 6,
		power = 1,
		time = 2,
		cost = { wood = 70, stone = 40 },
	},
	sie2 = {
		class = "siege",
		tier = 2,
		icon = "🪃",
		atk = 40,
		def = 9,
		hp = 66,
		load = 44,
		speed = 6,
		power = 3,
		time = 4.5,
		cost = { wood = 160, stone = 90, ore = 30 },
	},
	sie3 = {
		class = "siege",
		tier = 3,
		icon = "🪃",
		atk = 80,
		def = 18,
		hp = 135,
		load = 88,
		speed = 6,
		power = 7,
		time = 10,
		cost = { wood = 330, stone = 200, ore = 100, gold = 3 },
	},
} :: { [string]: TroopDef }

Balance.TROOP_ORDER = { "inf1", "rng1", "cav1", "sie1", "inf2", "rng2", "cav2", "sie2", "inf3", "rng3", "cav3", "sie3" }

Balance.START_TROOPS = { inf1 = 120, rng1 = 80, cav1 = 40 }

-- Healing a wounded unit costs this share of its training cost and happens at once.
Balance.HEAL_COST_SHARE = 0.25

-- Combat --------------------------------------------------------------------------------------------------------------

Balance.COMBAT_ROUNDS = 6
-- Share of the losses that die outright on each side; the rest are wounded.
Balance.ATTACKER_DEAD_SHARE = 0.4
Balance.LOOT_SHARE = 0.5
Balance.ATTACK_SHIELD_SECONDS = 600
Balance.BEGINNER_KEEP = 5

-- Research ------------------------------------------------------------------------------------------------------------

export type TechDef = {
	order: number,
	icon: string,
	branch: string,
	maxLevel: number,
	perLevel: number,
	stat: string,
	baseCost: { [string]: number },
	baseTime: number,
}

Balance.RESEARCH = {
	agriculture = {
		order = 1,
		icon = "🌾",
		branch = "economy",
		maxLevel = 5,
		perLevel = 0.06,
		stat = "food",
		baseCost = { food = 400, wood = 400 },
		baseTime = 20,
	},
	forestry = {
		order = 2,
		icon = "🪵",
		branch = "economy",
		maxLevel = 5,
		perLevel = 0.06,
		stat = "wood",
		baseCost = { food = 400, wood = 400 },
		baseTime = 20,
	},
	masonry = {
		order = 3,
		icon = "🪨",
		branch = "economy",
		maxLevel = 5,
		perLevel = 0.06,
		stat = "stone",
		baseCost = { food = 500, wood = 500 },
		baseTime = 25,
	},
	smelting = {
		order = 4,
		icon = "⛏️",
		branch = "economy",
		maxLevel = 5,
		perLevel = 0.06,
		stat = "ore",
		baseCost = { food = 600, wood = 600, stone = 300 },
		baseTime = 30,
	},
	surveying = {
		order = 5,
		icon = "🧭",
		branch = "economy",
		maxLevel = 5,
		perLevel = 0.1,
		stat = "gather",
		baseCost = { food = 600, wood = 600, stone = 300 },
		baseTime = 30,
	},
	drills = {
		order = 6,
		icon = "🥁",
		branch = "military",
		maxLevel = 5,
		perLevel = 0.08,
		stat = "trainSpeed",
		baseCost = { food = 700, wood = 500, ore = 100 },
		baseTime = 30,
	},
	forging = {
		order = 7,
		icon = "🗡️",
		branch = "military",
		maxLevel = 5,
		perLevel = 0.05,
		stat = "atk",
		baseCost = { food = 800, wood = 600, ore = 200 },
		baseTime = 40,
	},
	plating = {
		order = 8,
		icon = "🛡️",
		branch = "military",
		maxLevel = 5,
		perLevel = 0.05,
		stat = "def",
		baseCost = { food = 800, wood = 600, ore = 200 },
		baseTime = 40,
	},
	vitality = {
		order = 9,
		icon = "❤️",
		branch = "military",
		maxLevel = 5,
		perLevel = 0.05,
		stat = "hp",
		baseCost = { food = 800, wood = 600, ore = 200 },
		baseTime = 40,
	},
	roads = {
		order = 10,
		icon = "🛤️",
		branch = "logistics",
		maxLevel = 5,
		perLevel = 0.08,
		stat = "marchSpeed",
		baseCost = { food = 500, wood = 700, stone = 300 },
		baseTime = 30,
	},
	packs = {
		order = 11,
		icon = "🎒",
		branch = "logistics",
		maxLevel = 5,
		perLevel = 0.1,
		stat = "load",
		baseCost = { food = 500, wood = 700, stone = 300 },
		baseTime = 30,
	},
	stamina = {
		order = 12,
		icon = "⚡",
		branch = "logistics",
		maxLevel = 5,
		perLevel = 0.1,
		stat = "staminaRegen",
		baseCost = { food = 600, wood = 600, ore = 150 },
		baseTime = 30,
	},
} :: { [string]: TechDef }

Balance.RESEARCH_ORDER = {
	"agriculture",
	"forestry",
	"masonry",
	"smelting",
	"surveying",
	"drills",
	"forging",
	"plating",
	"vitality",
	"roads",
	"packs",
	"stamina",
}
Balance.RESEARCH_COST_GROWTH = 2
Balance.RESEARCH_TIME_GROWTH = 1.8

-- Heroes --------------------------------------------------------------------------------------------------------------

export type HeroDef = {
	order: number,
	icon: string,
	rarity: string,
	stat: string,
	class: string?,
	base: number,
	perLevel: number,
	recruitGold: number,
}

Balance.HERO_MAX_LEVEL = 30
Balance.HERO_XP_BASE = 100
Balance.HERO_XP_EXPONENT = 1.5

Balance.HEROES = {
	aldric = {
		order = 1,
		icon = "🛡️",
		rarity = "epic",
		stat = "def",
		class = "infantry",
		base = 0.08,
		perLevel = 0.006,
		recruitGold = 0,
	},
	mira = {
		order = 2,
		icon = "🏹",
		rarity = "epic",
		stat = "atk",
		class = "ranged",
		base = 0.08,
		perLevel = 0.006,
		recruitGold = 0,
	},
	kaela = {
		order = 3,
		icon = "🐎",
		rarity = "legendary",
		stat = "atk",
		class = "cavalry",
		base = 0.1,
		perLevel = 0.008,
		recruitGold = 600,
	},
	borin = {
		order = 4,
		icon = "🔨",
		rarity = "rare",
		stat = "load",
		base = 0.12,
		perLevel = 0.01,
		recruitGold = 250,
	},
	seren = {
		order = 5,
		icon = "🌙",
		rarity = "legendary",
		stat = "gather",
		base = 0.15,
		perLevel = 0.01,
		recruitGold = 700,
	},
	pip = {
		order = 6,
		icon = "⚙️",
		rarity = "rare",
		stat = "atk",
		class = "siege",
		base = 0.12,
		perLevel = 0.008,
		recruitGold = 300,
	},
	thorne = {
		order = 7,
		icon = "🐺",
		rarity = "epic",
		stat = "hunt",
		base = 0.15,
		perLevel = 0.01,
		recruitGold = 450,
	},
	ysolde = {
		order = 8,
		icon = "🔥",
		rarity = "legendary",
		stat = "march",
		base = 0.1,
		perLevel = 0.006,
		recruitGold = 800,
	},
} :: { [string]: HeroDef }

Balance.HERO_ORDER = { "aldric", "mira", "kaela", "borin", "seren", "pip", "thorne", "ysolde" }
Balance.START_HEROES = { "aldric", "mira" }

-- Map content ---------------------------------------------------------------------------------------------------------

Balance.NODES = {
	food = { icon = "🌾", amountBase = 18000, rateBase = 900 },
	wood = { icon = "🌲", amountBase = 18000, rateBase = 900 },
	stone = { icon = "🪨", amountBase = 12000, rateBase = 600 },
	ore = { icon = "⛏️", amountBase = 9000, rateBase = 450 },
	gold = { icon = "🪙", amountBase = 2500, rateBase = 120 },
}
Balance.NODE_WEIGHTS = { food = 30, wood = 30, stone = 20, ore = 14, gold = 6 }

export type MonsterDef = {
	order: number,
	icon: string,
	hpBase: number,
	minZone: number,
	reward: { [string]: number },
	heroXp: number,
}

Balance.MONSTERS = {
	golem = { order = 1, icon = "🗿", hpBase = 6000, minZone = 1, reward = { stone = 900, wood = 600 }, heroXp = 40 },
	wyrm = { order = 2, icon = "🐍", hpBase = 7500, minZone = 1, reward = { food = 1200, ore = 200 }, heroXp = 45 },
	troll = { order = 3, icon = "👹", hpBase = 11000, minZone = 2, reward = { ore = 600, gold = 30 }, heroXp = 70 },
	drake = { order = 4, icon = "🐉", hpBase = 16000, minZone = 3, reward = { gold = 80, ore = 900 }, heroXp = 110 },
	titan = {
		order = 5,
		icon = "🤖",
		hpBase = 24000,
		minZone = 4,
		reward = { gold = 160, stone = 2500 },
		heroXp = 160,
	},
} :: { [string]: MonsterDef }
Balance.MONSTER_ORDER = { "golem", "wyrm", "troll", "drake", "titan" }
Balance.MONSTER_HP_EXPONENT = 1.6
Balance.HUNT_STAMINA = 10
Balance.STAMINA_MAX = 100
Balance.STAMINA_SECONDS = 36
-- Kill rewards are this many times a full hit's rewards.
Balance.KILL_BONUS = 2

-- Guilds --------------------------------------------------------------------------------------------------------------

Balance.GUILD_MAX_MEMBERS = 20
Balance.GUILD_CREATE_GOLD = 150
Balance.GUILD_HELP_MIN_SECONDS = 10
Balance.GUILD_HELP_SHARE = 0.02
-- Players pick a name from these words instead of typing one, so no player text needs filtering or moderation.
Balance.GUILD_ADJECTIVES =
	{ "Iron", "Silver", "Ember", "Crimson", "Azure", "Golden", "Storm", "Oak", "Frost", "Dawn", "Shadow", "Thunder" }
Balance.GUILD_NOUNS = {
	"Pact",
	"Oath",
	"Crown",
	"Banner",
	"Legion",
	"Wardens",
	"Hearth",
	"Vanguard",
	"Order",
	"Circle",
	"Shield",
	"Talons",
}
Balance.BOT_GUILDS = { { 1, 1 }, { 2, 2 }, { 3, 3 } }

Balance.KINGDOM_COLORS = {
	"#E85D5D",
	"#E8A33D",
	"#E8D84A",
	"#7BD35A",
	"#3DBE9A",
	"#3DAEE8",
	"#5D7BE8",
	"#9A5DE8",
	"#D85DC0",
	"#C9C9C9",
}

Balance.BOT_NAME_PREFIX =
	{ "Thorn", "Ash", "Brook", "Raven", "Stone", "Wolf", "Elder", "Mist", "Gold", "High", "Fern", "Duskh" }
Balance.BOT_NAME_SUFFIX = { "vale", "hold", "mere", "watch", "ford", "crest", "haven", "march", "spire", "wick" }

-- Quests: a guided chain that teaches one system at a time ------------------------------------------------------------

export type QuestDef = {
	id: string,
	kind: string,
	target: string?,
	amount: number,
	reward: { [string]: number },
}

Balance.QUESTS = {
	{ id = "farm2", kind = "building", target = "farm", amount = 2, reward = { food = 1500, wood = 1500 } },
	{ id = "sawmill2", kind = "building", target = "sawmill", amount = 2, reward = { food = 1500, wood = 1500 } },
	{ id = "train50", kind = "trained", amount = 50, reward = { food = 2000, gold = 50 } },
	{ id = "wall2", kind = "building", target = "wall", amount = 2, reward = { wood = 2000, stone = 1500 } },
	{ id = "hunt1", kind = "hunts", amount = 1, reward = { ore = 800, gold = 50 } },
	{ id = "gather3k", kind = "gathered", amount = 3000, reward = { food = 3000, wood = 3000 } },
	{
		id = "keep3",
		kind = "building",
		target = "keep",
		amount = 3,
		reward = { food = 4000, wood = 4000, stone = 2000 },
	},
	{ id = "research1", kind = "researched", amount = 1, reward = { gold = 120 } },
	{ id = "guild", kind = "guild", amount = 1, reward = { gold = 150 } },
	{
		id = "keep5",
		kind = "building",
		target = "keep",
		amount = 5,
		reward = { food = 10000, wood = 10000, stone = 5000, ore = 2000, gold = 300 },
	},
	{ id = "win1", kind = "battlesWon", amount = 1, reward = { gold = 200 } },
	{
		id = "keep8",
		kind = "building",
		target = "keep",
		amount = 8,
		reward = { food = 30000, wood = 30000, stone = 15000, ore = 8000, gold = 600 },
	},
} :: { QuestDef }

-- Network -------------------------------------------------------------------------------------------------------------

Balance.COMMANDS_PER_SECOND = 8
Balance.COMMAND_BURST = 20
Balance.REPORTS_KEPT = 25

return Balance
