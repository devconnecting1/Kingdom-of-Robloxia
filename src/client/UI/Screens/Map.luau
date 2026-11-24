--!strict
-- The realm map: a 96×96 grid drawn only around the camera. Terrain comes from the seed (no network), entities from
-- the chunks the client watches, marches from their timelines. Drag, arrow keys or WASD to pan, wheel or ± to zoom,
-- tap a tile to act. Panning itself is handled in the boot script with UserInputService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Rules.Balance)
local Format = require(Shared.Rules.Format)
local MapGen = require(Shared.Rules.MapGen)
local Rng = require(Shared.Rules.Rng)

local C = require(script.Parent.Parent.Components)
local Kit = require(script.Parent.Parent.Parent.Kit)
local Live = require(script.Parent.Parent.Live)
local Theme = require(script.Parent.Parent.Theme)

local e = C.e
local t = C.t
local px = Theme.px

local Map = {}

Map.BASE_TILE = 58
local SIZE = Balance.MAP_SIZE
local TOP, NAV = 70, 78
local MARCH_ICONS = { gather = "⛏️", hunt = "🏹", attack = "⚔️", scout = "👁️" }

function Map.tileSize(state: any): number
	return math.floor(Map.BASE_TILE * state.map.zoom)
end

-- The camera centre, kept far enough from the edges that the view never shows outside the realm.
function Map.camera(state: any): (number, number)
	local dw, dh = Theme.designSize()
	local tile = Map.tileSize(state)
	local halfX, halfY = dw / tile / 2, (dh - TOP - NAV) / tile / 2
	local function clamp(v: number, half: number): number
		local lo, hi = half - 0.5, SIZE - half - 0.5
		if lo > hi then
			return (SIZE - 1) / 2
		end
		return math.clamp(v, lo, hi)
	end
	return clamp(state.map.x, halfX), clamp(state.map.y, halfY)
end

-- Visible tile range for the camera, with a one-tile margin.
function Map.range(state: any): (number, number, number, number)
	local dw, dh = Theme.designSize()
	local h = dh - TOP - NAV
	local tile = Map.tileSize(state)
	local cx, cy = Map.camera(state)
	local halfX, halfY = dw / tile / 2, h / tile / 2
	local x0 = math.max(0, math.floor(cx - halfX) - 1)
	local y0 = math.max(0, math.floor(cy - halfY) - 1)
	local x1 = math.min(SIZE - 1, math.ceil(cx + halfX) + 1)
	local y1 = math.min(SIZE - 1, math.ceil(cy + halfY) + 1)
	return x0, y0, x1, y1
end

function Map.visibleChunks(state: any): { number }
	local x0, y0, x1, y1 = Map.range(state)
	local seen, out = {}, {}
	for y = y0 - 8, y1 + 8, Balance.CHUNK_SIZE // 2 do
		for x = x0 - 8, x1 + 8, Balance.CHUNK_SIZE // 2 do
			local cx, cy = math.clamp(x, 0, SIZE - 1), math.clamp(y, 0, SIZE - 1)
			local c = MapGen.chunkOf(cx, cy)
			if not seen[c] then
				seen[c] = true
				table.insert(out, c)
			end
		end
	end
	table.sort(out)
	return out
end

local DECOR = {
	forest = { icon = "🌲", chance = 0.55 },
	hills = { icon = "⛰️", chance = 0.45 },
	lake = { icon = "🌊", chance = 0.2 },
	crown = { icon = "✨", chance = 0.12 },
	meadow = { icon = "🌼", chance = 0.06 },
}

local function terrain(
	state: any,
	actions: any,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	tile: number
): Kit.Element
	local seed = state.view.seed
	local kids: { [any]: any } = {}
	for y = y0, y1 do
		for x = x0, x1 do
			local biome = MapGen.biome(seed, x, y)
			local h = Rng.hash(seed + 31, x, y)
			local decor = DECOR[biome]
			local shade = (h - 0.5) * 0.16
			kids[x .. "_" .. y] = e("TextButton", {
				Position = UDim2.fromOffset(px(x * tile), px(y * tile)),
				Size = UDim2.fromOffset(px(tile) - 1, px(tile) - 1),
				BackgroundColor3 = Theme.shade(Theme.biomes[biome], shade),
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = if decor and h < decor.chance then decor.icon else "",
				TextSize = px(tile * 0.42),
				TextTransparency = 0.25,
				Font = Theme.fonts.bold,
				onActivated = function()
					actions.selectTile(x, y)
				end,
			})
		end
	end
	-- Zone borders: the rings get richer towards the Crown Lands in the centre.
	local center = (SIZE - 1) / 2
	for _, zone in Balance.ZONES do
		if zone.minDist > 0 then
			local d = zone.minDist - 0.5
			kids["zone" .. zone.level] = e("Frame", {
				Position = UDim2.fromOffset(px((center - d) * tile), px((center - d) * tile)),
				Size = UDim2.fromOffset(px(2 * d * tile + tile), px(2 * d * tile + tile)),
				BackgroundTransparency = 1,
				ZIndex = 2,
			}, { _stroke = C.stroke("gold", 2, 0.45) })
		end
	end
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, kids)
end

local function entityElement(state: any, ent: any, tile: number): Kit.Element
	local view = state.view
	local pos = UDim2.fromOffset(px(ent.x * tile), px(ent.y * tile))
	local size = UDim2.fromOffset(px(tile), px(tile))
	local kids: { [any]: any } = {}
	if ent.k == "c" then
		local mine = ent.kid == view.kid
		kids.ring = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromScale(0.92, 0.92),
			BackgroundColor3 = Theme.color(ent.col),
			BackgroundTransparency = 0.35,
		}, { _corner = C.round(), _stroke = C.stroke(if mine then "gold" else ent.col, if mine then 3 else 2) })
		kids.icon = C.text({ text = "🏰", size = tile * 0.6, align = "Center", Size = UDim2.fromScale(1, 0.9) })
		kids.name = C.badge((if ent.g then "[" .. ent.g .. "] " else "") .. ent.n, if mine then "goldDeep" else "bg", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, -px(10)),
			Size = UDim2.fromOffset(0, px(18)),
			TextSize = px(11),
			BackgroundTransparency = 0.15,
			ZIndex = 4,
		})
		kids.level = C.badge(
			tostring(ent.lv),
			"panelHi",
			{ Position = UDim2.fromOffset(-px(4), -px(4)), TextSize = px(11), Size = UDim2.fromOffset(px(18), px(18)) }
		)
		if ent.off and not ent.bot then
			kids.sleep = C.text({
				text = "💤",
				size = 14,
				align = "Center",
				Position = UDim2.fromOffset(px(2), px(14)),
				Size = UDim2.fromOffset(px(18), px(18)),
			})
		end
		if ent.sh then
			kids.shield = C.text({
				text = "🛡️",
				size = 14,
				align = "Center",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, px(4), 0, -px(4)),
				Size = UDim2.fromOffset(px(18), px(18)),
			})
		end
	elseif ent.k == "n" then
		kids.icon = C.text({
			text = Balance.NODES[ent.r].icon,
			size = tile * 0.46,
			align = "Center",
			Size = UDim2.fromScale(1, 0.8),
		})
		kids.level = C.badge(tostring(ent.lv), "bg", {
			Position = UDim2.fromOffset(px(2), px(2)),
			TextSize = px(10),
			Size = UDim2.fromOffset(px(16), px(16)),
			BackgroundTransparency = 0.25,
		})
		kids.bar = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -px(4)),
			Size = UDim2.new(0.7, 0, 0, px(5)),
			BackgroundTransparency = 1,
		}, { bar = C.progress(ent.a / ent.am, if ent.busy then "orange" else "gold", 5) })
		if ent.busy then
			kids.busy = C.text({
				text = "⛏️",
				size = 12,
				align = "Center",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -px(2), 0, px(2)),
				Size = UDim2.fromOffset(px(16), px(16)),
			})
		end
	else
		kids.icon = C.text({
			text = Balance.MONSTERS[ent.m].icon,
			size = tile * 0.5,
			align = "Center",
			Size = UDim2.fromScale(1, 0.85),
		})
		kids.level = C.badge(
			tostring(ent.lv),
			"redDeep",
			{ Position = UDim2.fromOffset(px(2), px(2)), TextSize = px(10), Size = UDim2.fromOffset(px(16), px(16)) }
		)
		kids.bar = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -px(4)),
			Size = UDim2.new(0.75, 0, 0, px(5)),
			BackgroundTransparency = 1,
		}, { bar = C.progress(ent.hp / ent.mhp, "red", 5) })
	end
	return e("Frame", { Position = pos, Size = size, BackgroundTransparency = 1, ZIndex = 3 }, kids)
end

local function entities(state: any, x0: number, y0: number, x1: number, y1: number, tile: number): Kit.Element
	local kids: { [any]: any } = {}
	for _, list in state.chunks do
		for _, ent in list do
			if ent.x >= x0 and ent.x <= x1 and ent.y >= y0 and ent.y <= y1 then
				kids[ent.id] = entityElement(state, ent, tile)
			end
		end
	end
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3 }, kids)
end

local function marches(state: any, tile: number): Kit.Element
	local kids: { [any]: any } = {}
	local me = state.view.kid
	for _, m in state.marches do
		local leg = m.leg
		local ax, ay = (leg.ax + 0.5) * tile, (leg.ay + 0.5) * tile
		local bx, by = (leg.bx + 0.5) * tile, (leg.by + 0.5) * tile
		local length = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
		local hostile = m.targetKid == me and m.kind == "attack"
		local color = if hostile then "red" elseif m.kid == me then "gold" else m.color
		if length > 1 and m.phase ~= "work" then
			kids["l" .. m.id] = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(px((ax + bx) / 2), px((ay + by) / 2)),
				Size = UDim2.fromOffset(px(length), px(if m.kid == me or hostile then 4 else 3)),
				Rotation = math.deg(math.atan2(by - ay, bx - ax)),
				BackgroundColor3 = Theme.color(color),
				BackgroundTransparency = if m.phase == "back" then 0.55 else 0.15,
				BorderSizePixel = 0,
				ZIndex = 5,
			})
		end
		local mx, my = Live.legPosition(leg, state.now)
		kids["t" .. m.id] = e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(px((mx + 0.5) * tile), px((my + 0.5) * tile)),
			Size = UDim2.fromOffset(px(30), px(30)),
			BackgroundColor3 = Theme.color(color),
			Text = MARCH_ICONS[m.kind] or "🚩",
			TextSize = px(16),
			Font = Theme.fonts.bold,
			ZIndex = 6,
		}, { _corner = C.round(), _stroke = C.stroke("bg", 2) })
	end
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5 }, kids)
end

local function minimap(state: any): Kit.Element
	local s = 170
	local scale = s / SIZE
	local kids: { [any]: any } = { _corner = C.corner(10), _stroke = C.stroke("gold", 2, 0.2) }
	local center = (SIZE - 1) / 2
	for i = #Balance.ZONES, 1, -1 do
		local zone = Balance.ZONES[i]
		local outer = if i == 1 then SIZE / 2 else Balance.ZONES[i - 1].minDist
		kids["z" .. zone.level] = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(px(outer * 2 * scale), px(outer * 2 * scale)),
			BackgroundColor3 = Theme.color(Theme.zoneTint[zone.level]),
			BorderSizePixel = 0,
			ZIndex = 2 + (5 - i),
		})
	end
	for i, c in state.castles do
		local mine = c.kid == state.view.kid
		kids["c" .. i] = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(px((c.x + 0.5) * scale), px((c.y + 0.5) * scale)),
			Size = UDim2.fromOffset(px(if mine then 9 else 5), px(if mine then 9 else 5)),
			BackgroundColor3 = Theme.color(if mine then "gold" else c.color),
			BorderSizePixel = 0,
			ZIndex = if mine then 9 else 8,
		}, { _corner = C.round(), _stroke = if mine then C.stroke("bg", 1.5) else nil })
	end
	local dw, dh = Theme.designSize()
	local tile = Map.tileSize(state)
	local vw, vh = dw / tile, (dh - TOP - NAV) / tile
	local camX, camY = Map.camera(state)
	kids.view = e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(px((camX + 0.5) * scale), px((camY + 0.5) * scale)),
		Size = UDim2.fromOffset(px(vw * scale), px(vh * scale)),
		BackgroundTransparency = 1,
		ZIndex = 10,
	}, { _stroke = C.stroke("text", 1.5) })
	kids.center = e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(px((center + 0.5) * scale), px((center + 0.5) * scale)),
		Size = UDim2.fromOffset(px(6), px(6)),
		BackgroundColor3 = Theme.color("purple"),
		ZIndex = 9,
	}, { _corner = C.round() })
	return e("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -px(14), 1, -px(14)),
		Size = UDim2.fromOffset(px(s), px(s)),
		BackgroundColor3 = Theme.color("bg"),
		ClipsDescendants = true,
		ZIndex = 20,
	}, kids)
end

function Map.entityAt(state: any, x: number, y: number): any
	return state.tileIndex[x .. "_" .. y]
end

local function actionButton(
	text: string,
	variant: string,
	disabled: boolean,
	onClick: () -> (),
	order: number
): Kit.Element
	return C.button({
		text = text,
		variant = variant,
		disabled = disabled,
		size = UDim2.new(1, 0, 0, px(42)),
		LayoutOrder = order,
		onClick = onClick,
	})
end

local function selection(state: any, actions: any): Kit.Element?
	local sel = state.selected.tile
	if not sel then
		return nil
	end
	local view = state.view
	local x, y = sel.x, sel.y
	local ent = Map.entityAt(state, x, y)
	local zone = MapGen.zone(x, y)
	local kids: { [any]: any } = { _pad = C.padding(14), _list = C.list("y", 8) }
	local title, subtitle = "", t("ui.coords", { x = x, y = y }) .. " · " .. t("ui.zone", { z = zone })
	if not ent then
		local biome = MapGen.biome(view.seed, x, y)
		title = t("biome." .. biome)
		local maxZone = 1 + (view.buildings.keep or 1) // 4
		if biome ~= "lake" then
			kids.relocate = actionButton(
				t("ui.relocate", { gold = Balance.RELOCATE_GOLD }),
				"blue",
				zone > maxZone,
				function()
					actions.relocate(x, y)
				end,
				10
			)
			if zone > maxZone then
				kids.note = C.text({
					text = t("err.zoneLocked"),
					size = 13,
					color = "muted",
					wrap = true,
					LayoutOrder = 11,
					Size = UDim2.new(1, 0, 0, px(34)),
				})
			end
		end
	elseif ent.k == "c" then
		title = (if ent.g then "[" .. ent.g .. "] " else "") .. ent.n
		local mine = ent.kid == view.kid
		local ally = view.guild ~= nil and ent.gid == view.guild.id
		kids.info = C.text({
			text = t("b.keep") .. " " .. t("ui.level", { level = ent.lv }) .. (if ent.bot
				then " · 🤖 " .. t("ui.bot")
				elseif ent.off then " · 💤 " .. t("ui.offline")
				else "") .. (if ent.sh then " · 🛡️" else ""),
			size = 14,
			color = "muted",
			LayoutOrder = 2,
		})
		if mine then
			kids.home =
				C.text({ text = "⭐ " .. t("ui.you"), size = 16, font = "bold", color = "gold", LayoutOrder = 3 })
		else
			kids.scout = actionButton("👁️ " .. t("ui.scout"), "blue", ally, function()
				actions.openMarch("scout", x, y)
			end, 10)
			kids.attack = actionButton("⚔️ " .. t("ui.attack"), "red", ally or ent.sh, function()
				actions.openMarch("attack", x, y)
			end, 11)
			if ent.sh or ally then
				kids.note = C.text({
					text = if ally then t("err.ally") else t("err.shielded"),
					size = 13,
					color = "muted",
					LayoutOrder = 12,
				})
			end
		end
	elseif ent.k == "n" then
		title = t("node." .. ent.r) .. " · " .. t("ui.level", { level = ent.lv })
		kids.amount = C.text({
			text = Balance.RESOURCE_ICONS[ent.r] .. " " .. t("ui.remaining", { v = Format.thousands(ent.a) }),
			size = 15,
			font = "bold",
			LayoutOrder = 2,
		})
		if ent.busy then
			kids.by = C.text({
				text = t("ui.gatheredBy", { name = ent.by or "?" }),
				size = 14,
				color = "orange",
				LayoutOrder = 3,
			})
		end
		kids.gather = actionButton("⛏️ " .. t("ui.gather"), "green", ent.busy, function()
			actions.openMarch("gather", x, y)
		end, 10)
	else
		title = t("mon." .. ent.m) .. " · " .. t("ui.level", { level = ent.lv })
		kids.hp = e("Frame", { Size = UDim2.new(1, 0, 0, px(18)), BackgroundTransparency = 1, LayoutOrder = 2 }, {
			bar = C.progress(
				ent.hp / ent.mhp,
				"red",
				18,
				t("ui.hp", { v = Format.short(ent.hp), max = Format.short(ent.mhp) })
			),
		})
		kids.note = C.text({
			text = t("ui.monsterHint", { v = Balance.HUNT_STAMINA }),
			size = 13,
			color = "muted",
			wrap = true,
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 0, px(34)),
		})
		kids.hunt = actionButton(
			"🏹 " .. t("ui.hunt"),
			"gold",
			Live.stamina(view, state.now) < Balance.HUNT_STAMINA,
			function()
				actions.openMarch("hunt", x, y)
			end,
			10
		)
	end
	kids.title = C.text({ text = title, size = 20, font = "title", color = "gold", LayoutOrder = 0 })
	kids.sub = C.text({ text = subtitle, size = 13, color = "faint", LayoutOrder = 1 })
	return C.panel({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -px(14), 0, px(14)),
		Size = UDim2.fromOffset(px(270), 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 20,
	}, kids, "hi")
end

function Map.render(state: any, actions: any): Kit.Element
	local dw, dh = Theme.designSize()
	local h = dh - TOP - NAV
	local tile = Map.tileSize(state)
	local x0, y0, x1, y1 = Map.range(state)
	local camX, camY = Map.camera(state)
	local rangeKey = table.concat({ x0, y0, x1, y1, tile, state.view.seed, Theme.scale }, ",")
	local canvas = e("Frame", {
		Position = UDim2.fromOffset(px(dw / 2 - (camX + 0.5) * tile), px(h / 2 - (camY + 0.5) * tile)),
		Size = UDim2.fromOffset(px(SIZE * tile), px(SIZE * tile)),
		BackgroundColor3 = Theme.color("#2C5A2E"),
		BorderSizePixel = 0,
	}, {
		terrain = Kit.memo("map.terrain", rangeKey, function()
			return terrain(state, actions, x0, y0, x1, y1, tile)
		end),
		entities = Kit.memo("map.entities", rangeKey .. "|" .. state.chunksVersion, function()
			return entities(state, x0, y0, x1, y1, tile)
		end),
		marches = marches(state, tile),
		selected = if state.selected.tile
			then e("Frame", {
				Position = UDim2.fromOffset(px(state.selected.tile.x * tile), px(state.selected.tile.y * tile)),
				Size = UDim2.fromOffset(px(tile), px(tile)),
				BackgroundTransparency = 1,
				ZIndex = 7,
			}, { _stroke = C.stroke("gold", 3), _corner = C.corner(6) })
			else nil,
	})

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.color("#1E3A20"),
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, {
		canvas = canvas,
		coords = C.panel(
			{ Position = UDim2.fromOffset(px(14), px(14)), Size = UDim2.fromOffset(px(214), px(52)), ZIndex = 20 },
			{
				label = C.text({
					text = "📍 "
						.. t("ui.coords", { x = math.floor(camX + 0.5), y = math.floor(camY + 0.5) }),
					size = 15,
					font = "bold",
					Position = UDim2.fromOffset(px(12), px(4)),
					Size = UDim2.new(1, -px(12), 0, px(22)),
				}),
				zone = C.text({
					text = t(
						"ui.zone",
						{ z = MapGen.zone(math.floor(camX + 0.5), math.floor(camY + 0.5)) }
					) .. " · " .. t("ui.marches", { used = #state.view.marches, max = state.view.marchSlots }),
					size = 12,
					color = "muted",
					Position = UDim2.fromOffset(px(12), px(26)),
					Size = UDim2.new(1, -px(12), 0, px(18)),
				}),
			},
			"flat"
		),
		tools = e("Frame", {
			Position = UDim2.fromOffset(px(14), px(76)),
			Size = UDim2.fromOffset(px(44), px(150)),
			BackgroundTransparency = 1,
			ZIndex = 20,
		}, {
			_list = C.list("y", 8),
			home = C.iconButton("🏠", t("ui.home"), actions.mapHome, 44, { LayoutOrder = 1 }),
			zoomIn = C.iconButton("＋", "zoom in", function()
				actions.mapZoom(1)
			end, 44, { LayoutOrder = 2 }),
			zoomOut = C.iconButton("－", "zoom out", function()
				actions.mapZoom(-1)
			end, 44, { LayoutOrder = 3 }),
		}),
		selection = selection(state, actions),
		minimap = if Theme.compact then nil else minimap(state),
	})
end

return Map
