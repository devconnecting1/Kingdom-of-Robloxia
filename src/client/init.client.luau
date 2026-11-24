--!strict
-- Client entry point: hides the 3D world, builds one full-screen ScreenGui, connects to the server and keeps the
-- interface in sync. Everything the player sees is drawn by UI/App from the client state.

local GuiService = game:GetService("GuiService")
local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Rules.Balance)
local Locale = require(Shared.Locale)
local Protocol = require(Shared.Rules.Protocol)

local Kit = require(script.Kit)
local Store = require(script.Store)
local App = require(script.UI.App)
local Map = require(script.UI.Screens.Map)
local Theme = require(script.UI.Theme)

local player = Players.LocalPlayer

-- Pure 2D: no avatar, no backpack, a fixed camera. Chat stays, it is filtered and moderated by Roblox.
for _, coreGui in
	{ Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.EmotesMenu, Enum.CoreGuiType.PlayerList }
do
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, coreGui, false)
end
local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable
camera.CFrame = CFrame.new(0, 10000, 0)

Locale.set(Locale.fromRobloxId(LocalizationService.RobloxLocaleId))

local gui = Instance.new("ScreenGui")
gui.Name = "KingdomUI"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local net = ReplicatedStorage:WaitForChild("KoRNet")
local commandRemote = net:WaitForChild(Protocol.REMOTE_COMMAND) :: RemoteFunction
local pushRemote = net:WaitForChild(Protocol.REMOTE_PUSH) :: RemoteEvent

local state = Store.initialState()
local dirty = true
local function changed()
	dirty = true
end

local function send(name: string, payload: any): any
	local ok, reply = pcall(function()
		return commandRemote:InvokeServer(name, payload)
	end)
	if not ok then
		return { ok = false, err = "err.offline" }
	end
	return reply
end

local actions = Store.actions(state, send, changed)

-- Toast params carry ids; turn them into names in the player's language.
local PARAM_PREFIX = { building = "b.", troop = "t.", tech = "tech." }
pushRemote.OnClientEvent:Connect(function(topic: string, a: any, b: any)
	if topic == "view" then
		state.view = a
	elseif topic == "chunk" then
		Store.setChunk(state, a, b)
	elseif topic == "marches" then
		state.marches = a
	elseif topic == "castles" then
		state.castles = a
	elseif topic == "toast" then
		local params = {}
		for k, v in b or {} do
			params[k] = if PARAM_PREFIX[k] then Locale.t(PARAM_PREFIX[k] .. v) else v
		end
		actions.toast(Locale.t(a, params), if a == "toast.incoming" or a == "toast.defeated" then "warn" else "info")
	end
	changed()
end)

-- Viewport and safe area ------------------------------------------------------------------------------------------------

local function updateViewport()
	local size = camera.ViewportSize
	Theme.setViewport(size.X, size.Y)
	Theme.safeLeft = GuiService.TopbarInset.Min.X / Theme.scale
	changed()
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateViewport)
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(updateViewport)
updateViewport()

-- Map: drag, keys and wheel ---------------------------------------------------------------------------------------------

local drag: { last: Vector3, moved: number }? = nil

local function onMap(): boolean
	return state.screen == "map" and state.modal == nil and state.view ~= nil
end

UserInputService.InputBegan:Connect(function(input, _processed)
	if not onMap() then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		drag = { last = input.Position, moved = 0 }
		state.dragMoved = false
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if not onMap() then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
		actions.mapZoom(if input.Position.Z > 0 then 1 else -1)
	elseif
		drag
		and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch)
	then
		local delta = input.Position - drag.last
		drag.last = input.Position
		drag.moved += delta.Magnitude
		if drag.moved > 8 then
			state.dragMoved = true
			local tile = Theme.px(Map.tileSize(state))
			actions.mapPan(-delta.X / tile, -delta.Y / tile)
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		drag = nil
		-- Activated fires right after; keep the flag for it, then clear.
		task.defer(function()
			state.dragMoved = false
		end)
	end
end)

local KEY_PAN = {
	[Enum.KeyCode.W] = Vector2.new(0, -1),
	[Enum.KeyCode.Up] = Vector2.new(0, -1),
	[Enum.KeyCode.S] = Vector2.new(0, 1),
	[Enum.KeyCode.Down] = Vector2.new(0, 1),
	[Enum.KeyCode.A] = Vector2.new(-1, 0),
	[Enum.KeyCode.Left] = Vector2.new(-1, 0),
	[Enum.KeyCode.D] = Vector2.new(1, 0),
	[Enum.KeyCode.Right] = Vector2.new(1, 0),
}

-- Watch only the chunks around the camera, so the server pushes only what this player can see.
local watched = ""
local lastWatch = 0
local function updateWatch(now: number)
	if not onMap() or now - lastWatch < 0.3 then
		return
	end
	local chunks = Map.visibleChunks(state)
	local key = table.concat(chunks, ",")
	if key == watched then
		return
	end
	watched = key
	lastWatch = now
	task.spawn(function()
		local reply = send("watch", { chunks = chunks })
		if reply and reply.ok then
			local keep = {}
			for _, c in chunks do
				keep[c] = true
			end
			for c in state.chunks do
				if not keep[c] then
					Store.setChunk(state, c, {})
					state.chunks[c] = nil
				end
			end
			for _, item in reply.chunks do
				Store.setChunk(state, item.chunk, item.list)
			end
			changed()
		end
	end)
end

-- Connect ---------------------------------------------------------------------------------------------------------------

local root = Kit.mount(App.render(state, actions), gui, "Root")

task.spawn(function()
	while not state.view do
		local reply = send("hello", {})
		if reply and reply.ok then
			state.view = reply.view
			state.marches = reply.marches
			state.castles = reply.castles
			state.map.x, state.map.y = reply.view.castle.x, reply.view.castle.y
			changed()
		else
			task.wait(1)
		end
	end
end)

-- Render loop: on change, plus a steady tick for countdowns (faster on the map, where marches move).
local lastRender = 0
RunService.RenderStepped:Connect(function(dt)
	local now = workspace:GetServerTimeNow()
	state.now = now
	if onMap() and not UserInputService:GetFocusedTextBox() then
		local pan = Vector2.zero
		for key, dir in KEY_PAN do
			if UserInputService:IsKeyDown(key) then
				pan += dir
			end
		end
		if pan.Magnitude > 0 then
			actions.mapPan(pan.X * dt * 12, pan.Y * dt * 12)
		end
	end
	updateWatch(os.clock())
	local clock = os.clock()
	for i = #state.toasts, 1, -1 do
		if clock - state.toasts[i].at > 4 then
			table.remove(state.toasts, i)
			dirty = true
		end
	end
	local interval = if state.screen == "map" and #state.marches > 0 then 1 / 20 else 0.25
	if dirty or clock - lastRender >= interval then
		dirty = false
		lastRender = clock
		Kit.update(root, App.render(state, actions))
	end
end)

-- Keep the realm size visible in the output for whoever tests in Studio.
print(
	string.format(
		"[Kingdom of Robloxia] %d×%d realm, up to %d players and %d bots",
		Balance.MAP_SIZE,
		Balance.MAP_SIZE,
		Balance.MAX_REAL_PLAYERS,
		Balance.BOT_COUNT
	)
)
