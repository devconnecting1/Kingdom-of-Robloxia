--!strict
-- Server entry point. All game rules live in ReplicatedStorage.Shared.Rules; this script only wires them to Roblox.

local Players = game:GetService("Players")

local Realm = require(script.Services.Realm)

-- The game is pure UI: nobody needs an avatar in the 3D world.
Players.CharacterAutoLoads = false

Realm.start()
