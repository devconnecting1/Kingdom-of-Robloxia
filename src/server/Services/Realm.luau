--!strict
-- Hosts one persistent realm in this server: up to 20 players online, every member's castle on the map (online or
-- not), and the bots. It loads the realm from the DataStore, catches it up to the present, steps it four times a
-- second, executes orders, pushes only what changed, and saves it back every minute and on shutdown. A lease in
-- MemoryStore makes sure only one server ever writes a realm.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Rules.Balance)
local Bot = require(Shared.Rules.Bot)
local MapGen = require(Shared.Rules.MapGen)
local Protocol = require(Shared.Rules.Protocol)
local Realms = require(Shared.Rules.Realms)
local Rng = require(Shared.Rules.Rng)
local Schema = require(Shared.Rules.Schema)
local World = require(Shared.Rules.World)

local RateLimiter = require(script.Parent.RateLimiter)
local Stores = require(script.Parent.Stores)

local Realm = {}

local STEP_SECONDS = 0.25
local SAVE_SECONDS = 60
local BOT_TICK_SECONDS = 10
local MARCH_PUSH_SECONDS = 0.5
-- The DataStore limit is 4 MB per key; above this the oldest reports are trimmed before saving.
local SAVE_TRIM_BYTES = 3_200_000

export type Options = {
	-- Studio and VIP servers: no lobby, no home-realm checks.
	localMode: boolean?,
}

local world: any
local realmId = 0
local options: Options = {}
local rng: Rng.Rng
local limiter = RateLimiter.new(Balance.COMMANDS_PER_SECOND, Balance.COMMAND_BURST)
local pushRemote: RemoteEvent
local commandRemote: RemoteFunction
local hosting = false

local sessions: { [Player]: { kid: string, chunks: { [number]: boolean } } } = {}
local playerOf: { [string]: Player } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function status(player: Player, key: string, realm: number?)
	player:SetAttribute("KoRStatus", key)
	player:SetAttribute("KoRRealm", realm or realmId)
end

-- Sends players back to the lobby, which places them in their home realm.
function Realm.toLobby(players: { Player }, reason: string)
	if #players == 0 then
		return
	end
	for _, player in players do
		status(player, reason)
	end
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, players)
	end)
	if not ok then
		for _, player in players do
			player:Kick("Could not reach the lobby, please rejoin. (" .. tostring(err) .. ")")
		end
	end
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

local function botIds(): { string }
	local ids = {}
	for kid, k in world.kingdoms do
		if k.isBot then
			table.insert(ids, kid)
		end
	end
	table.sort(ids)
	return ids
end

local function spawnBots(t: number, count: number)
	local taken = {}
	for _, k in world.kingdoms do
		taken[k.name] = true
	end
	local slot = 1
	for i = 1, count do
		local name = Bot.newName(rng, taken)
		taken[name] = true
		local data = Schema.new(name, t)
		Bot.prepare(data, rng)
		while world.kingdoms["b" .. slot] do
			slot += 1
		end
		local k = world:addKingdom("b" .. slot, data, true, t)
		if k then
			k.personality = Bot.PERSONALITIES[(i - 1) % #Bot.PERSONALITIES + 1]
		end
	end
end

-- Bots give way as humans join, down to Realms.BOTS_MIN.
local function balanceBots(t: number)
	local humans, bots = world:counts()
	local target = Realms.botTarget(humans)
	while bots > target do
		if not world:retireBot(t) then
			break
		end
		bots -= 1
	end
end

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
	return {
		ok = false,
		err = if type(result) == "string" and string.sub(result, 1, 4) == "err." then result else "err.unknown",
	}
end

-- Whether this player belongs here. New players without a home join this realm while it is open.
local function admit(player: Player): boolean
	if options.localMode then
		return true
	end
	local ok, home = Stores.homeRealm(player.UserId)
	if not ok then
		Realm.toLobby({ player }, "lobby.error")
		return false
	end
	if home == realmId then
		return true
	end
	if home ~= nil then
		-- Someone followed a friend into a realm that is not theirs.
		Realm.toLobby({ player }, "lobby.moving")
		return false
	end
	local accepted = false
	Stores.updateRegistry(function(registry)
		local entry = Realms.find(registry, realmId)
		accepted = entry ~= nil and entry.open and Realms.addMember(registry, realmId)
	end)
	if accepted then
		Stores.setHomeRealm(player.UserId, realmId)
		return true
	end
	Realm.toLobby({ player }, "lobby.moving")
	return false
end

local function onPlayerAdded(player: Player)
	status(player, "lobby.loading")
	if not admit(player) or not player.Parent then
		return
	end
	local kid = "u" .. player.UserId
	local t = now()
	if not world.kingdoms[kid] then
		local k = world:addKingdom(kid, Schema.new(player.DisplayName, t), false, t)
		if not k then
			Realm.toLobby({ player }, "lobby.full")
			return
		end
		balanceBots(t)
	end
	local k = world.kingdoms[kid]
	k.name = player.DisplayName
	k.data.name = player.DisplayName
	world:setOnline(kid, true, t)
	sessions[player] = { kid = kid, chunks = {} }
	playerOf[kid] = player
	status(player, "lobby.ready")
	flush(t)
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	playerOf[session.kid] = nil
	limiter:forget(player.UserId)
	-- The castle stays on the map: armies keep marching and the kingdom keeps producing.
	world:setOnline(session.kid, false, now())
	flush(now())
end

local saving = false
local function save(): boolean
	if saving then
		return false
	end
	saving = true
	local snapshot = world:snapshot(now())
	local ok, size = Stores.saveRealm(realmId, snapshot)
	if ok and size > SAVE_TRIM_BYTES then
		for _, k in snapshot.kingdoms do
			while #k.data.reports > 8 do
				table.remove(k.data.reports)
			end
		end
		ok = Stores.saveRealm(realmId, snapshot)
	end
	saving = false
	return ok
end

function Realm.host(id: number, opts: Options?): boolean
	options = opts or {}
	realmId = id
	local t = now()
	if not Stores.holdLease(id, t) then
		-- Another server is running this realm (it is full right now). Send everyone back to try again.
		Players.PlayerAdded:Connect(function(player)
			Realm.toLobby({ player }, "lobby.full")
		end)
		Realm.toLobby(Players:GetPlayers(), "lobby.full")
		return false
	end
	local loaded, snapshot = Stores.loadRealm(id)
	if not loaded then
		-- Never start an empty realm over one that merely failed to load.
		Stores.releaseLease(id)
		Realm.toLobby(Players:GetPlayers(), "lobby.error")
		return false
	end
	if snapshot then
		world = World.restore(snapshot, t)
		rng = Rng.new(world.seed + math.floor(t))
	else
		local seed = (math.abs(id) * 7919 + math.floor(t)) % 2147483647
		world = World.new(seed, t)
		rng = Rng.new(seed + 1)
		spawnBots(t, Realms.BOTS_MAX)
	end
	world.realmId = id
	balanceBots(t)
	hosting = true

	createRemotes()
	commandRemote.OnServerInvoke = onCommand
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	game:BindToClose(function()
		if not hosting then
			return
		end
		for player, session in sessions do
			world:setOnline(session.kid, false, now())
			sessions[player] = nil
		end
		save()
		Stores.releaseLease(realmId)
	end)

	local accumulator = 0
	local stepCount = 0
	local lastSave = os.clock()
	local lastLease = os.clock()
	RunService.Heartbeat:Connect(function(dt)
		if not hosting then
			return
		end
		accumulator += dt
		if accumulator < STEP_SECONDS then
			return
		end
		accumulator = 0
		stepCount += 1
		local tNow = now()
		world:step(tNow)
		-- Bots act every BOT_TICK_SECONDS, spread over the interval so no single step runs all of them.
		local stepsPerTick = math.max(1, math.floor(BOT_TICK_SECONDS / STEP_SECONDS))
		for i, kid in botIds() do
			if (stepCount + i) % stepsPerTick == 0 then
				Bot.tick(world, kid, tNow, rng)
			end
		end
		flush(tNow)
		if os.clock() - lastLease >= Realms.LEASE_RENEW_SECONDS then
			lastLease = os.clock()
			task.spawn(function()
				if not Stores.holdLease(realmId, now()) then
					-- Lost the realm (this server stalled past the lease). Stop writing and send players back.
					hosting = false
					Realm.toLobby(Players:GetPlayers(), "lobby.error")
				end
			end)
		end
		if os.clock() - lastSave >= SAVE_SECONDS then
			lastSave = os.clock()
			task.spawn(save)
		end
	end)
	return true
end

return Realm
