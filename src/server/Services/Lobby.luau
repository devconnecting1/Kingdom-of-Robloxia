--!strict
-- Public servers are the lobby. Each player is sent to their home realm; a new player is given the newest open
-- realm, and when every realm is closed the lobby reserves a server and opens the next one.

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Realms = require(Shared.Rules.Realms)

local Stores = require(script.Parent.Stores)

local Lobby = {}

local RETRY_SECONDS = 15

local function status(player: Player, key: string, realm: number?)
	player:SetAttribute("KoRStatus", key)
	if realm then
		player:SetAttribute("KoRRealm", realm)
	end
end

local function now(): number
	return workspace:GetServerTimeNow()
end

-- The realm entry for this player, creating their membership (and a new realm) when needed.
local function homeFor(player: Player): Realms.RealmEntry?
	local ok, home = Stores.homeRealm(player.UserId)
	if not ok then
		return nil
	end
	local registry = Stores.registry()
	if not registry then
		return nil
	end
	if home then
		return Realms.find(registry, home)
	end
	if not Realms.pickForNewPlayer(registry) then
		local reserved, code, psid = pcall(function()
			return TeleportService:ReserveServer(game.PlaceId)
		end)
		if not reserved then
			warn("[Lobby] ReserveServer failed: " .. tostring(code))
			return nil
		end
		Stores.updateRegistry(function(reg)
			-- Another lobby may have opened one meanwhile; then this reservation is simply not used.
			if not Realms.pickForNewPlayer(reg) then
				Realms.addRealm(reg, code, psid, now())
			end
		end)
	end
	local chosen: Realms.RealmEntry? = nil
	Stores.updateRegistry(function(reg)
		local pick = Realms.pickForNewPlayer(reg)
		if pick and Realms.addMember(reg, pick.id) then
			chosen = table.clone(pick)
		end
	end)
	if chosen then
		Stores.setHomeRealm(player.UserId, (chosen :: Realms.RealmEntry).id)
	end
	return chosen
end

local function send(player: Player)
	while player.Parent do
		status(player, "lobby.finding")
		local entry = homeFor(player)
		if entry then
			status(player, "lobby.teleporting", entry.id)
			local options = Instance.new("TeleportOptions")
			options.ReservedServerAccessCode = entry.code
			options:SetTeleportData({ realm = entry.id })
			local ok, err = pcall(function()
				TeleportService:TeleportAsync(game.PlaceId, { player }, options)
			end)
			if ok then
				return
			end
			warn("[Lobby] teleport failed: " .. tostring(err))
		end
		status(player, "lobby.error")
		task.wait(RETRY_SECONDS)
	end
end

function Lobby.start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(send, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(send, player)
	end
	-- A failed teleport (full realm server, network) puts the player back in the queue.
	TeleportService.TeleportInitFailed:Connect(function(player, _result, message)
		warn("[Lobby] teleport init failed: " .. tostring(message))
		status(player, "lobby.full")
		task.delay(RETRY_SECONDS, send, player)
	end)
end

return Lobby
