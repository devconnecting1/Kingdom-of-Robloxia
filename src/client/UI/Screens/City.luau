--!strict
-- The kingdom seen from above: a 2D board of building plots around the Keep. Each plot shows its level, a ⬆ when an
-- upgrade is affordable, a timer while it builds, and a lock until the Keep unlocks it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Rules.Balance)
local Economy = require(Shared.Rules.Economy)
local Format = require(Shared.Rules.Format)

local C = require(script.Parent.Parent.Components)
local Kit = require(script.Parent.Parent.Parent.Kit)
local Live = require(script.Parent.Parent.Live)
local Theme = require(script.Parent.Parent.Theme)

local e = C.e
local t = C.t
local px = Theme.px

local City = {}

-- Plot positions on a 6×4 board (column, row, width, height): the Keep in the middle, the Wall as its gate, and
-- the fields along the top. Empty cells get scenery.
local LAYOUT = {
	farm = { 0, 0, 1, 1 },
	sawmill = { 1, 0, 1, 1 },
	quarry = { 2, 0, 1, 1 },
	mine = { 3, 0, 1, 1 },
	manor = { 4, 0, 1, 1 },
	vault = { 5, 0, 1, 1 },
	barracks = { 0, 1, 1, 1 },
	academy = { 1, 1, 1, 1 },
	keep = { 2, 1, 2, 2 },
	embassy = { 4, 1, 1, 1 },
	warhall = { 5, 1, 1, 1 },
	infirmary = { 0, 2, 1, 1 },
	watchtower = { 5, 2, 1, 1 },
	wall = { 2, 3, 2, 1 },
}
local SCENERY = {
	{ x = 1, y = 2, icon = "🌳" },
	{ x = 4, y = 2, icon = "⛲" },
	{ x = 0, y = 3, icon = "🌲" },
	{ x = 1, y = 3, icon = "🌻" },
	{ x = 4, y = 3, icon = "🐑" },
	{ x = 5, y = 3, icon = "🌲" },
}

local function plot(state: any, actions: any, id: string, cell: number, gap: number): Kit.Element
	local view = state.view
	local def = Balance.BUILDINGS[id]
	local level = view.buildings[id] or 0
	local keep = view.buildings.keep or 1
	local locked = id ~= "keep" and keep < math.max(1, def.unlockKeep)
	local job = Live.buildingJob(view, id)
	local resources = Live.resources(view, state.now)
	local canUpgrade = false
	if not locked and not job and level < def.maxLevel and (id == "keep" or level < keep) then
		canUpgrade = Economy.canAfford(resources, Economy.buildingCost(id, level + 1))
	end
	local place = LAYOUT[id]
	local big = id == "keep"
	local w, h = place[3] * cell + (place[3] - 1) * gap, place[4] * cell + (place[4] - 1) * gap

	local kids: { [any]: any } = {
		_corner = C.corner(16),
		_gradient = if locked
			then C.gradient("#2A3150", "#1A1F36")
			elseif big then C.gradient("#6C5BD6", "#3B2F8A")
			else C.gradient("#3B6E4A", "#244A33"),
		_stroke = C.stroke(
			if job then "blue" elseif canUpgrade then "gold" else "line",
			if canUpgrade or job then 2.5 else 1.5,
			if locked then 0.6 else 0
		),
		icon = C.text({
			text = if locked then "🔒" else def.icon,
			size = if big then 76 else 40,
			align = "Center",
			Position = UDim2.fromOffset(0, px(if big then 18 else 8)),
			Size = UDim2.new(1, 0, 0, px(if big then 90 else 50)),
			TextTransparency = if locked then 0.3 else 0,
		}),
		name = C.text({
			text = t("b." .. id),
			size = if big then 22 else 14,
			font = "title",
			align = "Center",
			color = if locked then "faint" else "text",
			Position = UDim2.new(0, 0, 1, -px(if big then 62 else 44)),
			Size = UDim2.new(1, 0, 0, px(if big then 26 else 18)),
		}),
		sub = C.text({
			text = if locked
				then t("ui.locked", { level = def.unlockKeep })
				elseif job then "⏳ " .. Format.duration(Live.left(job, state.now))
				else t("ui.level", { level = level }),
			size = if big then 15 else 12,
			font = "bold",
			align = "Center",
			color = if locked then "faint" elseif job then "blue" else "gold",
			Position = UDim2.new(0, 0, 1, -px(if big then 34 else 24)),
			Size = UDim2.new(1, 0, 0, px(if big then 20 else 16)),
		}),
	}
	if level > 0 and not locked then
		kids.level = C.badge(tostring(level), if level >= def.maxLevel then "goldDeep" else "panelHi", {
			Position = UDim2.fromOffset(px(8), px(8)),
			TextSize = px(14),
		})
	end
	if canUpgrade then
		kids.arrow = C.badge("⬆", "greenDeep", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -px(8), 0, px(8)),
			TextSize = px(14),
		})
	end
	if job then
		kids.bar = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -px(6)),
			Size = UDim2.new(1, -px(20), 0, px(6)),
			BackgroundTransparency = 1,
		}, { bar = C.progress(Live.fraction(job, state.now), "blue", 6) })
	end

	return e("TextButton", {
		Position = UDim2.fromOffset(px(place[1] * (cell + gap)), px(place[2] * (cell + gap))),
		Size = UDim2.fromOffset(px(w), px(h)),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		Text = "",
		AutoButtonColor = not locked,
		onActivated = function()
			actions.openBuilding(id)
		end,
	}, kids)
end

function City.render(state: any, actions: any): Kit.Element
	local dw, dh = Theme.designSize()
	local sideW = if Theme.compact then 0 else 300
	local availW = dw - sideW - 48
	local availH = dh - 70 - 78 - 90
	local gap = 14
	local cell = math.floor(math.min((availW - 5 * gap - 40) / 6, (availH - 3 * gap - 40) / 4))
	local boardW = 6 * cell + 5 * gap
	local boardH = 4 * cell + 3 * gap

	local plots: { [any]: any } = {}
	for _, id in Balance.BUILDING_ORDER do
		plots[id] = plot(state, actions, id, cell, gap)
	end
	for i, deco in SCENERY do
		plots["deco" .. i] = C.text({
			text = deco.icon,
			size = math.floor(cell * 0.45),
			align = "Center",
			Position = UDim2.fromOffset(px(deco.x * (cell + gap)), px(deco.y * (cell + gap))),
			Size = UDim2.fromOffset(px(cell), px(cell)),
			TextTransparency = 0.15,
		})
	end

	local view = state.view
	local rates = view.rates
	local header = e("Frame", {
		Position = UDim2.fromOffset(px(24), px(14)),
		Size = UDim2.new(1, -px(48), 0, px(56)),
		BackgroundTransparency = 1,
	}, {
		title = C.text({
			text = "🏰 " .. view.name,
			size = 28,
			font = "title",
			color = "gold",
			Size = UDim2.new(0.5, 0, 0, px(34)),
		}),
		sub = C.text({
			text = t("ui.storage", { v = Format.short(view.cap) })
				.. "   ·   "
				.. t("ui.protected", { v = Format.short(view.protected) }),
			size = 14,
			color = "muted",
			Position = UDim2.fromOffset(0, px(34)),
			Size = UDim2.new(0.6, 0, 0, px(20)),
		}),
		prod = C.text({
			text = "📈 "
				.. t("ui.production")
				.. ": 🌾 "
				.. Format.short(rates.food)
				.. "  🪵 "
				.. Format.short(rates.wood)
				.. "  🪨 "
				.. Format.short(rates.stone)
				.. "  ⛓️ "
				.. Format.short(rates.ore)
				.. "  🪙 "
				.. Format.short(rates.gold),
			size = 14,
			font = "bold",
			color = "green",
			align = "Right",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, px(6)),
			Size = UDim2.new(0.5, 0, 0, px(22)),
			Visible = not Theme.compact,
		}),
	})

	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		header = header,
		board = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -px(16)),
			Size = UDim2.fromOffset(px(boardW + 40), px(boardH + 40)),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BorderSizePixel = 0,
		}, {
			_corner = C.corner(26),
			_gradient = C.gradient("grass", "grassDeep"),
			_stroke = C.stroke("#7A5A2E", 5),
			plots = e("Frame", {
				Position = UDim2.fromOffset(px(20), px(20)),
				Size = UDim2.new(1, -px(40), 1, -px(40)),
				BackgroundTransparency = 1,
			}, plots),
		}),
	})
end

return City
