--!strict
-- Runs the realm on this server: up to 20 players plus 30 bots on one 96×96 map. It owns the World, steps it four
-- times a second, executes orders from RemoteFunction calls and pushes only what changed, to whom it concerns.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Rules.Balance)
local Bot = require(Shared.Rules.Bot)
local MapGen = require(Shared.Rules.MapGen)
local Protocol = require(Shared.Rules.Protocol)
local Rng = require(Shared.Rules.Rng)
local Schema = require(Shared.Rules.Schema)
local World = require(Shared.Rules.World)

local Profiles = require(script.Parent.Profiles)
local RateLimiter = require(script.Parent.RateLimiter)

local Realm = {}

local STEP_SECONDS = 0.25
local AUTOSAVE_SECONDS = 90
local BOT_TICK_SECONDS = 10
local MARCH_PUSH_SECONDS = 0.5

local world: any
local rng: Rng.Rng
local limiter = RateLimiter.new(Balance.COMMANDS_PER_SECOND, Balance.COMMAND_BURST)
local pushRemote: RemoteEvent
local commandRemote: RemoteFunction

-- Per player: their kingdom id and the map chunks they are looking at.
local sessions: { [Player]: { kid: string, chunks: { [number]: boolean }, joinedAt: number } } = {}
local playerOf: { [string]: Player } = {}
local botIds: { string } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function kidOf(player: Player): string
	return "u" .. player.UserId
end

local function createRemotes()
	local folder = Instance.new("Folder")
	folder.Name = "KoRNet"
	commandRemote = Instance.new("RemoteFunction")
	commandRemote.Name = Protocol.REMOTE_COMMAND
	commandRemote.Parent = folder
	pushRemote = Instance.new("RemoteEvent")
	pushRemote.Name = Protocol.REMOTE_PUSH
	pushRemote.Parent = folder
	folder.Parent = ReplicatedStorage
end

local function spawnBots(t: number)
	local taken = {}
	for i = 1, Balance.BOT_COUNT do
		local name = Bot.newName(rng, taken)
		taken[name] = true
		local data = Schema.new(name, t)
		Bot.prepare(data, rng)
		local kid = "b" .. i
		local k = world:addKingdom(kid, data, true, t)
		if k then
			k.personality = Bot.PERSONALITIES[(i - 1) % #Bot.PERSONALITIES + 1]
			table.insert(botIds, kid)
		end
	end
end

-- Sends what changed since the last flush. Views are per player; chunks only to players watching them.
local lastMarchPush = 0
local marchesPending = false
local function flush(t: number)
	local changes = world:drain()
	for kid in changes.kingdoms do
		local player = playerOf[kid]
		if player then
			pushRemote:FireClient(player, "view", world:view(kid, t))
		end
	end
	if next(changes.chunks) then
		for player, session in sessions do
			for chunk in changes.chunks do
				if session.chunks[chunk] then
					pushRemote:FireClient(player, "chunk", chunk, world:chunkView(chunk))
				end
			end
		end
	end
	for _, toast in changes.toasts do
		local player = playerOf[toast.kid]
		if player then
			pushRemote:FireClient(player, "toast", toast.key, toast.params)
		end
	end
	if changes.castles then
		pushRemote:FireAllClients("castles", world:castleList())
	end
	-- Marches move on a timeline the client interpolates, so the list is only sent when one starts, turns or ends.
	marchesPending = marchesPending or changes.marches
	if marchesPending and t - lastMarchPush >= MARCH_PUSH_SECONDS then
		marchesPending = false
		lastMarchPush = t
		pushRemote:FireAllClients("marches", world:marchList())
	end
end

local function onCommand(player: Player, name: any, payload: any): any
	local session = sessions[player]
	local t = now()
	if not session then
		return { ok = false, err = "err.offline" }
	end
	if not limiter:allow(player.UserId, os.clock()) then
		return { ok = false, err = "err.rate" }
	end
	if name == "hello" then
		return {
			ok = true,
			view = world:view(session.kid, t),
			marches = world:marchList(),
			castles = world:castleList(),
			now = t,
		}
	end
	if name == "watch" then
		local clean = Protocol.validate("watch", payload)
		if not clean then
			return { ok = false, err = "err.unknown" }
		end
		local chunks = {}
		local out = {}
		for _, chunk in clean.chunks do
			if chunk >= 0 and chunk < MapGen.chunkCount() then
				chunks[chunk] = true
				-- A list, not a table keyed by chunk id: remotes mangle sparse number keys.
				table.insert(out, { chunk = chunk, list = world:chunkView(chunk) })
			end
		end
		session.chunks = chunks
		return { ok = true, chunks = out }
	end
	local ok, result = world:command(session.kid, name, payload, t)
	flush(t)
	if ok then
		return { ok = true, result = if type(result) == "table" then nil else result }
	end
	return { ok = false, err = if type(result) == "string" and string.sub(result, 1, 4) == "err." then result else "err.unknown" }
end

local function onPlayerAdded(player: Player)
	local t = now()
	local data, problem = Profiles.load(player.UserId, player.DisplayName, t)
	if not player.Parent then
		if data then
			Profiles.save(player.UserId, data, now(), true)
		end
		return
	end
	if not data then
		player:Kick(problem or "Could not load your kingdom.")
		return
	end
	local kid = kidOf(player)
	local k = world:addKingdom(kid, data, false, now())
	if not k then
		Profiles.save(player.UserId, data, now(), true)
		player:Kick("The realm is full. Please try another server.")
		return
	end
	sessions[player] = { kid = kid, chunks = {}, joinedAt = t }
	playerOf[kid] = player
	flush(now())
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	playerOf[session.kid] = nil
	limiter:forget(player.UserId)
	local data = world:removeKingdom(session.kid, now())
	flush(now())
	if data then
		Profiles.save(player.UserId, data, now(), true)
	end
end

local function autosave()
	for player, session in sessions do
		local k = world.kingdoms[session.kid]
		if k then
			task.spawn(Profiles.save, player.UserId, k.data, now(), false)
		end
	end
end

function Realm.start()
	local seed = tonumber(string.sub(string.gsub(HttpService:GenerateGUID(false), "%D", ""), 1, 9)) or os.time()
	rng = Rng.new(seed)
	local t = now()
	world = World.new(seed, t)
	spawnBots(t)
	createRemotes()
	commandRemote.OnServerInvoke = onCommand

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	game:BindToClose(function()
		local threads = 0
		for player, session in sessions do
			local k = world.kingdoms[session.kid]
			if k then
				threads += 1
				task.spawn(function()
					Profiles.save(player.UserId, k.data, now(), true)
					threads -= 1
				end)
			end
		end
		local deadline = os.clock() + 25
		while threads > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	-- Bots act every BOT_TICK_SECONDS, spread over the interval so no single step does all thirty.
	local accumulator = 0
	local stepCount = 0
	local lastSave = os.clock()
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < STEP_SECONDS then
			return
		end
		accumulator = 0
		stepCount += 1
		local tNow = now()
		world:step(tNow)
		local stepsPerTick = math.max(1, math.floor(BOT_TICK_SECONDS / STEP_SECONDS))
		for i, kid in botIds do
			if (stepCount + i) % stepsPerTick == 0 then
				Bot.tick(world, kid, tNow, rng)
			end
		end
		flush(tNow)
		if os.clock() - lastSave >= AUTOSAVE_SECONDS then
			lastSave = os.clock()
			autosave()
		end
	end)
end

return Realm
