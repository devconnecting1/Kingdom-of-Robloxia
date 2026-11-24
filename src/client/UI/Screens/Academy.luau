--!strict
-- Research in three branches. Each card shows the level, the bonus it gives now and the next cost.

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

local Academy = {}

local BRANCHES = { "economy", "military", "logistics" }
local BRANCH_COLOR = { economy = "green", military = "red", logistics = "blue" }

local function techCard(state: any, actions: any, id: string, order: number): Kit.Element
	local view = state.view
	local def = Balance.RESEARCH[id]
	local level = view.research[id] or 0
	local academy = view.buildings.academy or 0
	local nextLevel = level + 1
	local maxed = level >= def.maxLevel
	local running = view.researching and view.researching.tech == id
	local resources = Live.resources(view, state.now)
	local cost = if maxed then {} else Economy.researchCost(id, nextLevel)
	local blocked = academy < 1 or nextLevel > academy or view.researching ~= nil
	local afford = Economy.canAfford(resources, cost)
	local data = { buildings = view.buildings, research = view.research }

	local status
	if maxed then
		status = C.text({ text = "⭐ " .. t("ui.maxed"), size = 13, font = "bold", color = "gold", LayoutOrder = 4 })
	elseif running then
		status = e("Frame", { Size = UDim2.new(1, 0, 0, px(18)), BackgroundTransparency = 1, LayoutOrder = 4 }, {
			bar = C.progress(Live.fraction(view.researching, state.now), "purple", 18, Format.duration(Live.left(view.researching, state.now))),
		})
	else
		status = e("Frame", { Size = UDim2.new(1, 0, 0, px(34)), BackgroundTransparency = 1, LayoutOrder = 4 }, {
			cost = e("Frame", { Size = UDim2.new(1, -px(92), 1, 0), BackgroundTransparency = 1 }, { row = C.costRow(cost, resources) }),
			go = C.button({
				text = "⏱ " .. Format.duration(Economy.researchTime(data, id, nextLevel)),
				variant = "blue",
				disabled = blocked or not afford,
				textSize = 12,
				size = UDim2.fromOffset(px(88), px(30)),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				onClick = function()
					actions.research(id)
				end,
			}),
		})
	end

	return C.panel({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order }, {
		_pad = C.padding(12),
		_list = C.list("y", 6),
		head = e("Frame", { Size = UDim2.new(1, 0, 0, px(28)), BackgroundTransparency = 1, LayoutOrder = 1 }, {
			icon = C.text({ text = def.icon, size = 22, Size = UDim2.fromOffset(px(30), px(28)) }),
			name = C.text({ text = t("tech." .. id), size = 17, font = "title", Position = UDim2.fromOffset(px(32), 0), Size = UDim2.new(1, -px(90), 1, 0) }),
			level = C.badge(level .. "/" .. def.maxLevel, if maxed then "goldDeep" else "panelHi", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				TextSize = px(12),
			}),
		}),
		bonus = C.text({
			text = t("stat." .. def.stat, { v = Format.percent(def.perLevel * math.max(level, 1)) }) .. (if level == 0 then " (" .. t("ui.level", { level = 1 }) .. ")" else ""),
			size = 13,
			color = if level > 0 then "green" else "muted",
			font = "bold",
			LayoutOrder = 2,
		}),
		dots = e("Frame", { Size = UDim2.new(1, 0, 0, px(8)), BackgroundTransparency = 1, LayoutOrder = 3 }, (function()
			local dots: { [any]: any } = { _list = C.list("x", 4) }
			for i = 1, def.maxLevel do
				dots[i] = e("Frame", {
					Size = UDim2.new(1 / def.maxLevel, -px(4), 1, 0),
					BackgroundColor3 = Theme.color(if i <= level then "purple" else "bg"),
					BorderSizePixel = 0,
				}, { _corner = C.round() })
			end
			return dots
		end)()),
		status = status,
	}, if running then "hi" else nil)
end

function Academy.render(state: any, actions: any): Kit.Element
	local view = state.view
	local academy = view.buildings.academy or 0
	local columns: { [any]: any } = {}
	for i, branch in BRANCHES do
		local kids: { [any]: any } = {
			_list = C.list("y", 10),
			title = C.badge(t("branch." .. branch), BRANCH_COLOR[branch] .. "Deep", {
				Size = UDim2.fromOffset(0, px(30)),
				TextSize = px(16),
				Font = Theme.fonts.title,
				LayoutOrder = 0,
			}),
		}
		for _, id in Balance.RESEARCH_ORDER do
			local def = Balance.RESEARCH[id]
			if def.branch == branch then
				kids[id] = techCard(state, actions, id, def.order)
			end
		end
		columns[branch] = C.scroll({
			Position = UDim2.new((i - 1) / 3, px(4), 0, 0),
			Size = UDim2.new(1 / 3, -px(12), 1, 0),
		}, kids)
	end
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		_pad = C.padding(18),
		title = C.text({
			text = "📜 " .. t("b.academy") .. " · " .. t("ui.level", { level = academy }),
			size = 26,
			font = "title",
			color = "gold",
			Size = UDim2.new(1, 0, 0, px(34)),
		}),
		sub = C.text({
			text = if academy < 1 then t("ui.locked", { level = Balance.BUILDINGS.academy.unlockKeep }) else t("ui.academyHint"),
			size = 14,
			color = "muted",
			Position = UDim2.fromOffset(0, px(36)),
		}),
		cols = e("Frame", { Position = UDim2.fromOffset(0, px(68)), Size = UDim2.new(1, 0, 1, -px(68)), BackgroundTransparency = 1 }, columns),
	})
end

return Academy
