--!strict
-- Server entry point. Decides what this server is:
--   Studio                      → hosts realm 0 locally (no lobby, no teleports)
--   reserved server (a realm)   → hosts the realm registered for this PrivateServerId
--   VIP private server          → hosts its own realm, keyed by the private server
--   public server               → the lobby, which sends every player to their home realm
-- All game rules live in ReplicatedStorage.Shared.Rules; this only wires them to Roblox.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Realms = require(Shared.Rules.Realms)

local Lobby = require(script.Services.Lobby)
local Realm = require(script.Services.Realm)
local Stores = require(script.Services.Stores)

-- The game is pure UI: nobody needs an avatar in the 3D world.
Players.CharacterAutoLoads = false

local function hostReserved()
	-- The lobby registers the realm before teleporting anyone, but DataStore reads can lag; retry briefly.
	for _ = 1, 10 do
		local registry = Stores.registry()
		local entry = registry and Realms.findByServer(registry, game.PrivateServerId)
		if entry then
			Realm.host(entry.id)
			return
		end
		task.wait(3)
	end
	Realm.toLobby(Players:GetPlayers(), "lobby.error")
	Players.PlayerAdded:Connect(function(player)
		Realm.toLobby({ player }, "lobby.error")
	end)
end

if RunService:IsStudio() then
	Realm.host(0, { localMode = true })
elseif game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then
	hostReserved()
elseif game.PrivateServerId ~= "" then
	-- A VIP server is its own little realm, saved under a negative id derived from its owner.
	Realm.host(-game.PrivateServerOwnerId, { localMode = true })
else
	Lobby.start()
end
