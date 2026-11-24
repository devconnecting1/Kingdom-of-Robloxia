--!strict
-- Kingdom saves in a DataStore with a session lock: a server writes its JobId into the save while the player is
-- there, so two servers can never both load and then overwrite the same kingdom (the classic item-duplication bug).

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Schema = require(Shared.Rules.Schema)

local Profiles = {}

local STORE_NAME = "KoR_Kingdoms_v1"
-- A lock older than this belongs to a server that crashed without releasing it.
local LOCK_EXPIRY = 600
local RETRIES = 5

local store: DataStore? = nil
local memoryOnly = false

local function getStore(): DataStore?
	if store or memoryOnly then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		-- Studio without API access: play from memory so development still works.
		warn("[Profiles] DataStore unavailable, saves are disabled: " .. tostring(result))
		memoryOnly = true
	end
	return store
end

local function keyFor(userId: number): string
	return "u_" .. userId
end

local function withRetries<T>(label: string, fn: () -> T): (boolean, T | string)
	local lastErr = ""
	for attempt = 1, RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = tostring(result)
		warn(string.format("[Profiles] %s failed (try %d): %s", label, attempt, lastErr))
		task.wait(math.min(2 ^ attempt, 15))
	end
	return false, lastErr
end

-- Loads and locks a kingdom. Returns nil and a message when the save is locked by another live server.
function Profiles.load(userId: number, name: string, now: number): (any, string?)
	local ds = getStore()
	if not ds then
		return Schema.new(name, now), nil
	end
	local lockedBy: string? = nil
	local ok, result = withRetries("load " .. userId, function()
		lockedBy = nil
		return ds:UpdateAsync(keyFor(userId), function(saved: any)
			saved = if type(saved) == "table" then saved else {}
			local lock = saved.lock
			if lock and lock.job ~= game.JobId and now - (lock.at or 0) < LOCK_EXPIRY then
				lockedBy = lock.job
				return nil -- keep the save untouched
			end
			saved.lock = { job = game.JobId, at = now }
			saved.data = Schema.migrate(saved.data, name, now)
			return saved
		end)
	end)
	if not ok then
		return nil, "Could not load your kingdom. Please rejoin."
	end
	if lockedBy then
		return nil, "Your kingdom is still open on another server. Please wait a minute and rejoin."
	end
	return (result :: any).data, nil
end

-- Saves a kingdom; `release` drops the lock when the player leaves.
function Profiles.save(userId: number, data: any, now: number, release: boolean): boolean
	local ds = getStore()
	if not ds then
		return true
	end
	local ok = withRetries("save " .. userId, function()
		return ds:UpdateAsync(keyFor(userId), function(saved: any)
			saved = if type(saved) == "table" then saved else {}
			if saved.lock and saved.lock.job ~= game.JobId then
				-- Another server took over after our lock expired; its copy is newer.
				return nil
			end
			saved.data = data
			saved.savedAt = now
			saved.lock = if release then nil else { job = game.JobId, at = now }
			return saved
		end)
	end)
	return ok
end

function Profiles.isStudio(): boolean
	return RunService:IsStudio()
end

return Profiles
