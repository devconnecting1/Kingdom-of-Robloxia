--!strict
-- Barracks: pick a troop, choose how many, see the cost and time, train. Below: the troops at home and the wounded.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Army = require(Shared.Rules.Army)
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

local ArmyScreen = {}

local function unlocked(view: any, tier: number): boolean
	return Army.tierUnlocked({ buildings = view.buildings }, tier)
end

local function troopCard(state: any, actions: any, id: string, order: number): Kit.Element
	local view = state.view
	local def = Balance.TROOPS[id]
	local open = unlocked(view, def.tier)
	local selected = state.selected.troop == id
	return e("TextButton", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		Text = "",
		LayoutOrder = order,
		AutoButtonColor = open,
		onActivated = function()
			actions.selectTroop(id)
		end,
	}, {
		_corner = C.corner(14),
		_gradient = if selected then C.gradient("panelHi", "panel2") elseif open then C.gradient("panel2", "panel") else C.gradient("#232842", "#1A1F36"),
		_stroke = C.stroke(if selected then "gold" else "line", if selected then 2.5 else 1.5, if open then 0 else 0.5),
		tier = C.badge("T" .. def.tier, if def.tier == 3 then "goldDeep" elseif def.tier == 2 then "purple" else "blueDeep", {
			Position = UDim2.fromOffset(px(8), px(8)),
			TextSize = px(12),
		}),
		icon = C.text({
			text = if open then def.icon else "🔒",
			size = 40,
			align = "Center",
			Position = UDim2.fromOffset(0, px(14)),
			Size = UDim2.new(1, 0, 0, px(50)),
		}),
		name = C.text({
			text = t("t." .. id),
			size = 14,
			font = "title",
			align = "Center",
			color = if open then "text" else "faint",
			Position = UDim2.fromOffset(0, px(68)),
			Size = UDim2.new(1, 0, 0, px(18)),
		}),
		count = C.text({
			text = "×" .. Format.short(view.troops[id] or 0),
			size = 14,
			font = "bold",
			align = "Center",
			color = "gold",
			Position = UDim2.fromOffset(0, px(88)),
			Size = UDim2.new(1, 0, 0, px(18)),
		}),
	})
end

local function detail(state: any, actions: any): Kit.Element
	local view = state.view
	local id = state.selected.troop
	local def = Balance.TROOPS[id]
	local open = unlocked(view, def.tier)
	local batch = view.batchSize
	local count = math.clamp(state.selected.count, 1, batch)
	local cost = Army.trainCost(id, count)
	local resources = Live.resources(view, state.now)
	local research = { research = view.research, buildings = view.buildings }
	local time = Army.trainTime(research, id, count)
	local afford = Economy.canAfford(resources, cost)
	local busy = view.training ~= nil
	local counter = Balance.COUNTERS[def.class]
	local function step(n: number)
		return function()
			actions.setCount(math.clamp(count + n, 1, batch))
		end
	end

	return C.panel({ Size = UDim2.fromScale(1, 1) }, {
		_pad = C.padding(18),
		_list = C.list("y", 10),
		head = e("Frame", { Size = UDim2.new(1, 0, 0, px(64)), BackgroundTransparency = 1, LayoutOrder = 1 }, {
			icon = C.text({ text = def.icon, size = 48, align = "Center", Size = UDim2.fromOffset(px(64), px(64)) }),
			name = C.text({ text = t("t." .. id), size = 26, font = "title", color = "gold", Position = UDim2.fromOffset(px(72), px(2)), Size = UDim2.new(1, -px(72), 0, px(32)) }),
			class = C.text({
				text = t("class." .. def.class) .. " · T" .. def.tier .. " · " .. t("ui.power") .. " " .. def.power,
				size = 14,
				color = "muted",
				Position = UDim2.fromOffset(px(72), px(36)),
				Size = UDim2.new(1, -px(72), 0, px(20)),
			}),
		}),
		stats = C.text({ text = t("ui.stats", { atk = def.atk, def = def.def, hp = def.hp, load = def.load }), size = 15, font = "bold", LayoutOrder = 2 }),
		counter = C.text({
			text = if counter.strong
				then "🎯 " .. t("ui.counter", { strong = t("class." .. counter.strong), weak = t("class." .. counter.weak) })
				else "🎯 " .. t("ui.siegeNote"),
			size = 14,
			color = "green",
			LayoutOrder = 3,
		}),
		qty = e("Frame", { Size = UDim2.new(1, 0, 0, px(48)), BackgroundTransparency = 1, LayoutOrder = 4 }, {
			_list = C.list("x", 8, "Left", "Center"),
			minus = C.iconButton("−", "fewer", step(-10), 44, { LayoutOrder = 1 }),
			value = e("TextLabel", {
				Size = UDim2.fromOffset(px(120), px(44)),
				BackgroundColor3 = Theme.color("bg"),
				Text = Format.thousands(count),
				TextSize = px(22),
				Font = Theme.fonts.title,
				TextColor3 = Theme.color("text"),
				LayoutOrder = 2,
			}, { _corner = C.corner(10), _stroke = C.stroke("line") }),
			plus = C.iconButton("+", "more", step(10), 44, { LayoutOrder = 3 }),
			p50 = C.button({ text = "50", variant = "ghost", size = UDim2.fromOffset(px(56), px(40)), textSize = 15, LayoutOrder = 4, onClick = function()
				actions.setCount(math.min(50, batch))
			end }),
			max = C.button({ text = t("ui.max") .. " " .. batch, variant = "ghost", size = UDim2.fromOffset(px(110), px(40)), textSize = 15, LayoutOrder = 5, onClick = function()
				actions.setCount(batch)
			end }),
		}),
		batch = C.text({ text = t("ui.batch", { v = batch }), size = 13, color = "faint", LayoutOrder = 5 }),
		costTitle = C.text({ text = t("ui.cost") .. " · ⏱ " .. Format.duration(time), size = 14, font = "bold", color = "muted", LayoutOrder = 6 }),
		cost = e("Frame", { Size = UDim2.new(1, 0, 0, px(28)), BackgroundTransparency = 1, LayoutOrder = 7 }, { row = C.costRow(cost, resources) }),
		train = C.button({
			text = if not open then t("err.locked") elseif busy then t("err.queueFull") else "⚔️ " .. t("ui.train"),
			variant = "green",
			disabled = not open or busy or not afford,
			size = UDim2.new(1, 0, 0, px(50)),
			textSize = 20,
			LayoutOrder = 8,
			onClick = function()
				actions.train(id, count)
			end,
		}),
	}, "hi")
end

function ArmyScreen.render(state: any, actions: any): Kit.Element
	local view = state.view
	local cards: { [any]: any } = { _grid = C.grid(118, 112, 10) }
	for i, id in Balance.TROOP_ORDER do
		cards[id] = troopCard(state, actions, id, i)
	end
	local wounded = Army.total(view.wounded)
	local home = Army.total(view.troops)
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		_pad = C.padding(18),
		left = e("Frame", { Size = UDim2.new(0.56, -px(10), 1, 0), BackgroundTransparency = 1 }, {
			title = C.text({ text = "⚔️ " .. t("b.barracks") .. " · " .. t("ui.level", { level = view.buildings.barracks or 0 }), size = 26, font = "title", color = "gold", Size = UDim2.new(1, 0, 0, px(34)) }),
			sub = C.text({
				text = t("ui.atHome") .. ": " .. Format.thousands(home) .. "   ·   " .. t("ui.marchSize", { v = Format.thousands(view.marchSize) }),
				size = 14,
				color = "muted",
				Position = UDim2.fromOffset(0, px(36)),
			}),
			grid = C.scroll({ Position = UDim2.fromOffset(0, px(66)), Size = UDim2.new(1, 0, 1, -px(66 + 74)) }, cards),
			infirmary = C.panel({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, px(64)) }, {
				icon = C.text({ text = "⛑️", size = 28, align = "Center", Size = UDim2.fromOffset(px(56), px(64)) }),
				label = C.text({
					text = t("ui.wounded") .. ": " .. Format.thousands(wounded) .. "  ·  " .. t("ui.infirmary", { used = Format.short(wounded), cap = Format.short(view.infirmaryCap) }),
					size = 15,
					font = "bold",
					Position = UDim2.fromOffset(px(56), 0),
					Size = UDim2.new(1, -px(220), 1, 0),
				}),
				heal = C.button({
					text = "💊 " .. t("ui.heal"),
					variant = "blue",
					disabled = wounded == 0,
					size = UDim2.fromOffset(px(150), px(44)),
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -px(10), 0.5, 0),
					onClick = actions.heal,
				}),
			}, "flat"),
		}),
		right = e("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0.44, -px(10), 1, 0),
			BackgroundTransparency = 1,
		}, { detail = detail(state, actions) }),
	})
end

return ArmyScreen
