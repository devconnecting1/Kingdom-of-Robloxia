--!strict
-- Everything the game keeps between servers:
--   KoR_Registry_v1   "registry"     the list of realms (Realms.Registry)
--   KoR_Realms_v1     "realm_<id>"   one realm's whole state (World.snapshot)
--   KoR_Players_v1    "u_<userId>"   a player's home realm
--   MemoryStore hash  "KoR_RealmLease" which server holds each realm right now
-- Every call retries with backoff. Without DataStore access (Studio with API access off) it falls back to memory, so
-- the game still runs for development, and says so in the output.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Realms = require(Shared.Rules.Realms)

local Stores = {}

local RETRIES = 5
local memory: { [string]: any } = {}
local available: boolean? = nil

local function retry<T>(label: string, fn: () -> T): (boolean, any)
	local last: any = nil
	for attempt = 1, RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		last = result
		warn(string.format("[Stores] %s failed (try %d): %s", label, attempt, tostring(result)))
		task.wait(math.min(2 ^ attempt, 15))
	end
	return false, last
end

local function store(name: string): DataStore?
	if available == false then
		return nil
	end
	local ok, result = pcall(function()
		local ds = DataStoreService:GetDataStore(name)
		-- A cheap read proves API access; it fails at once in Studio when access is off.
		ds:GetAsync("__probe")
		return ds
	end)
	if not ok then
		if available == nil then
			warn("[Stores] DataStore unavailable, realms live in memory only: " .. tostring(result))
		end
		available = false
		return nil
	end
	available = true
	return result
end

-- Read-modify-write of one key. `fn` gets the current value and returns the new one (or nil to keep it).
local function update(storeName: string, key: string, fn: (any) -> any): (boolean, any)
	local ds = store(storeName)
	if not ds then
		local value = fn(memory[storeName .. "/" .. key])
		if value ~= nil then
			memory[storeName .. "/" .. key] = value
		end
		return true, memory[storeName .. "/" .. key]
	end
	return retry("update " .. storeName .. "/" .. key, function()
		return ds:UpdateAsync(key, function(old)
			return fn(old)
		end)
	end)
end

local function get(storeName: string, key: string): (boolean, any)
	local ds = store(storeName)
	if not ds then
		return true, memory[storeName .. "/" .. key]
	end
	return retry("get " .. storeName .. "/" .. key, function()
		return ds:GetAsync(key)
	end)
end

function Stores.persistent(): boolean
	store("KoR_Registry_v1")
	return available == true
end

-- Registry ------------------------------------------------------------------------------------------------------------

function Stores.registry(): Realms.Registry?
	local ok, value = get("KoR_Registry_v1", "registry")
	if not ok then
		return nil
	end
	return Realms.normalize(value)
end

function Stores.updateRegistry(fn: (Realms.Registry) -> ()): Realms.Registry?
	local ok, value = update("KoR_Registry_v1", "registry", function(old)
		local registry = Realms.normalize(old)
		fn(registry)
		return registry
	end)
	return if ok then Realms.normalize(value) else nil
end

-- Players -------------------------------------------------------------------------------------------------------------

function Stores.homeRealm(userId: number): (boolean, number?)
	local ok, value = get("KoR_Players_v1", "u_" .. userId)
	if not ok then
		return false, nil
	end
	return true, if type(value) == "table" then value.home else nil
end

function Stores.setHomeRealm(userId: number, realm: number)
	update("KoR_Players_v1", "u_" .. userId, function(old)
		local profile = if type(old) == "table" then old else {}
		profile.home = realm
		return profile
	end)
end

-- Realm state ---------------------------------------------------------------------------------------------------------

function Stores.loadRealm(id: number): (boolean, any)
	return get("KoR_Realms_v1", "realm_" .. id)
end

-- Returns the size of the saved JSON, so the host can trim before it nears the 4 MB DataStore limit.
function Stores.saveRealm(id: number, snapshot: any): (boolean, number)
	local size = #HttpService:JSONEncode(snapshot)
	local ok = update("KoR_Realms_v1", "realm_" .. id, function()
		return snapshot
	end)
	return ok, size
end

-- Lease -----------------------------------------------------------------------------------------------------------------

local leaseMap: MemoryStoreHashMap? = nil
local leaseMemory: { [string]: Realms.Lease } = {}

local function leases(): MemoryStoreHashMap?
	if leaseMap then
		return leaseMap
	end
	local ok, map = pcall(function()
		return MemoryStoreService:GetHashMap("KoR_RealmLease")
	end)
	if ok then
		leaseMap = map
	end
	return leaseMap
end

-- Takes or renews the lease on a realm for this server. False while another live server holds it.
function Stores.holdLease(id: number, now: number): boolean
	local key = "realm_" .. id
	local map = leases()
	if not map or not Stores.persistent() then
		local current = leaseMemory[key]
		if not Realms.canHold(current, game.JobId, now) then
			return false
		end
		leaseMemory[key] = Realms.lease(game.JobId, now)
		return true
	end
	local held = false
	local ok = pcall(function()
		map:UpdateAsync(key, function(current: any)
			if not Realms.canHold(current, game.JobId, now) then
				held = false
				return nil
			end
			held = true
			return Realms.lease(game.JobId, now)
		end, Realms.LEASE_SECONDS)
	end)
	return ok and held
end

function Stores.releaseLease(id: number)
	local key = "realm_" .. id
	leaseMemory[key] = nil
	local map = leases()
	if map and Stores.persistent() then
		pcall(function()
			map:UpdateAsync(key, function(current: any)
				if current and current.job == game.JobId then
					return { job = "", untilAt = 0 }
				end
				return nil
			end, 5)
		end)
	end
end

return Stores
