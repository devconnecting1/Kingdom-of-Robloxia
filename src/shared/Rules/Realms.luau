--!strict
-- Persistent realms on Roblox. A realm is one map that lives forever: its state is saved in a DataStore and it runs
-- in a reserved server whenever someone is in it. Public servers are only the lobby that sends each player to their
-- home realm. New players fill the newest realm until it is full, then a new realm opens on its own, the way kingdom
-- games open new servers as players arrive.
--
-- Everything here is pure (no Roblox API) so the assignment, lease and bot rules are tested under Lune.

local Realms = {}

-- A realm takes newcomers until it has this many human members, then it closes to newcomers.
Realms.OPEN_MEMBERS = 60
-- Hard cap of human members per realm (room for friends who follow someone in after it closed).
Realms.MAX_MEMBERS = 70
-- Players online in one realm at once: one Roblox server.
Realms.MAX_ONLINE = 20
-- Bots fill the map while it is young and give way as humans arrive, never below this many.
Realms.BOTS_MAX = 30
Realms.BOTS_MIN = 10
-- A realm server holds a lease so a second server for the same realm cannot also write its state.
Realms.LEASE_SECONDS = 90
Realms.LEASE_RENEW_SECONDS = 25

export type RealmEntry = {
	id: number,
	code: string, -- reserved server access code
	psid: string, -- PrivateServerId of that reserved server
	members: number,
	open: boolean,
	createdAt: number,
}

export type Registry = {
	nextId: number,
	realms: { RealmEntry },
}

function Realms.newRegistry(): Registry
	return { nextId = 1, realms = {} }
end

function Realms.normalize(raw: any): Registry
	if type(raw) ~= "table" or type(raw.realms) ~= "table" then
		return Realms.newRegistry()
	end
	return raw :: Registry
end

function Realms.find(registry: Registry, id: number): RealmEntry?
	for _, realm in registry.realms do
		if realm.id == id then
			return realm
		end
	end
	return nil
end

function Realms.findByServer(registry: Registry, psid: string): RealmEntry?
	for _, realm in registry.realms do
		if realm.psid == psid then
			return realm
		end
	end
	return nil
end

-- The realm a brand-new player should join: the newest one still open. nil means a new realm must be created.
function Realms.pickForNewPlayer(registry: Registry): RealmEntry?
	local best: RealmEntry? = nil
	for _, realm in registry.realms do
		if realm.open and realm.members < Realms.OPEN_MEMBERS then
			if best == nil or realm.id > (best :: RealmEntry).id then
				best = realm
			end
		end
	end
	return best
end

function Realms.addRealm(registry: Registry, code: string, psid: string, now: number): RealmEntry
	local realm: RealmEntry = {
		id = registry.nextId,
		code = code,
		psid = psid,
		members = 0,
		open = true,
		createdAt = now,
	}
	registry.nextId += 1
	table.insert(registry.realms, realm)
	-- Only the newest realm takes newcomers, so players are never spread thin over many half-empty realms.
	for _, other in registry.realms do
		if other.id ~= realm.id then
			other.open = false
		end
	end
	return realm
end

-- Counts a new member; returns false when the realm cannot take more.
function Realms.addMember(registry: Registry, id: number): boolean
	local realm = Realms.find(registry, id)
	if not realm or realm.members >= Realms.MAX_MEMBERS then
		return false
	end
	realm.members += 1
	if realm.members >= Realms.OPEN_MEMBERS then
		realm.open = false
	end
	return true
end

function Realms.botTarget(humans: number): number
	return math.clamp(Realms.BOTS_MAX - humans // 2, Realms.BOTS_MIN, Realms.BOTS_MAX)
end

export type Lease = { job: string, untilAt: number }

-- Whether server `job` may hold the realm at `now`, given the lease currently stored (or nil).
function Realms.canHold(current: Lease?, job: string, now: number): boolean
	return current == nil or current.job == job or current.untilAt <= now
end

function Realms.lease(job: string, now: number): Lease
	return { job = job, untilAt = now + Realms.LEASE_SECONDS }
end

return Realms
