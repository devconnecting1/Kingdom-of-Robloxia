--!strict
-- The whole interface as one function of the client state: top bar, side panel, the active screen, the bottom
-- navigation, modals and toasts. The boot script re-renders it on every change and on a timer for countdowns.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Rules.Balance)
local Format = require(Shared.Rules.Format)

local C = require(script.Parent.Components)
local Kit = require(script.Parent.Parent.Kit)
local Live = require(script.Parent.Live)
local Theme = require(script.Parent.Theme)

local Screens = script.Parent.Screens
local ScreenModules = {
	city = require(Screens.City),
	map = require(Screens.Map),
	army = require(Screens.Army),
	heroes = require(Screens.Heroes),
	academy = require(Screens.Academy),
	guild = require(Screens.Guild),
	reports = require(Screens.Reports),
}
local Modals = require(Screens.Modals)

local e = C.e
local t = C.t
local px = Theme.px

local App = {}

App.NAV = {
	{ id = "city", icon = "🏰" },
	{ id = "map", icon = "🗺️" },
	{ id = "army", icon = "⚔️" },
	{ id = "heroes", icon = "🦸" },
	{ id = "academy", icon = "📜" },
	{ id = "guild", icon = "🤝" },
	{ id = "reports", icon = "📨" },
}

local TOP = 70
local NAV = 78
local SIDE = 300

local function resourcePill(res: string, amount: number, rate: number, cap: number, order: number): Kit.Element
	local full = amount >= cap and res ~= "gold"
	return C.panel({
		Size = UDim2.fromOffset(px(if Theme.compact then 96 else 132), px(48)),
		LayoutOrder = order,
	}, {
		icon = C.text({
			text = Balance.RESOURCE_ICONS[res],
			size = 22,
			align = "Center",
			Position = UDim2.fromOffset(px(4), 0),
			Size = UDim2.new(0, px(34), 1, 0),
		}),
		amount = C.text({
			text = Format.short(amount),
			size = 18,
			font = "title",
			color = if full then "orange" else "text",
			Position = UDim2.fromOffset(px(40), px(4)),
			Size = UDim2.new(1, -px(44), 0, px(22)),
		}),
		rate = C.text({
			text = if rate > 0 then "+" .. t("ui.perHour", { v = Format.short(rate) }) else t("res." .. res),
			size = 12,
			color = if full then "orange" else "green",
			font = "bold",
			Position = UDim2.fromOffset(px(40), px(25)),
			Size = UDim2.new(1, -px(44), 0, px(16)),
			Visible = not Theme.compact,
		}),
	}, "flat")
end

local function topBar(state: any, actions: any): Kit.Element
	local view = state.view
	local resources = Live.resources(view, state.now)
	local pills: { [any]: any } = { _list = C.list("x", 8, "Right", "Center") }
	for i, res in Balance.RESOURCES do
		pills[res] = resourcePill(res, resources[res], view.rates[res] or 0, view.cap, i)
	end
	local stamina = Live.stamina(view, state.now)
	pills.stamina = C.panel(
		{ Size = UDim2.fromOffset(px(if Theme.compact then 70 else 92), px(48)), LayoutOrder = 10 },
		{
			icon = C.text({ text = "⚡", size = 20, align = "Center", Size = UDim2.new(0, px(30), 1, 0) }),
			amount = C.text({
				text = tostring(stamina),
				size = 18,
				font = "title",
				color = "gold",
				Position = UDim2.fromOffset(px(30), 0),
				Size = UDim2.new(1, -px(32), 1, 0),
			}),
		},
		"flat"
	)

	local shield = nil
	if view.shielded then
		shield = C.badge(
			if view.beginner
				then "🛡 " .. t("ui.beginner", { level = Balance.BEGINNER_KEEP })
				else "🛡 " .. t("ui.shield", { time = Format.duration(view.shieldUntil - state.now) }),
			"blueDeep",
			{
				Position = UDim2.fromOffset(px(Theme.safeLeft + 84), px(52)),
				Size = UDim2.fromOffset(0, px(20)),
				TextSize = px(11),
				Visible = not Theme.compact,
			}
		)
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, px(TOP)),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 10,
	}, {
		_gradient = C.gradient("bg2", "bg"),
		_line = e("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, px(2)),
			BackgroundColor3 = Theme.color("goldDeep"),
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
		}),
		avatar = e("TextButton", {
			Position = UDim2.fromOffset(px(Theme.safeLeft + 12), px(9)),
			Size = UDim2.fromOffset(px(52), px(52)),
			BackgroundColor3 = Theme.color(view.color),
			Text = string.upper(string.sub(view.name, 1, 1)),
			TextSize = px(26),
			Font = Theme.fonts.title,
			TextColor3 = Theme.color("text"),
			onActivated = actions.openRanking,
		}, { _corner = C.round(), _stroke = C.stroke("gold", 2.5) }),
		name = C.text({
			text = view.name,
			size = 20,
			font = "title",
			Position = UDim2.fromOffset(px(Theme.safeLeft + 74), px(8)),
			Size = UDim2.fromOffset(px(220), px(24)),
		}),
		power = e("TextButton", {
			Position = UDim2.fromOffset(px(Theme.safeLeft + 74), px(32)),
			Size = UDim2.fromOffset(px(220), px(20)),
			BackgroundTransparency = 1,
			Text = "⚔ " .. Format.thousands(view.power) .. "   🏆 " .. t(
				"ui.rank",
				{ rank = view.rank, total = view.kingdoms }
			),
			TextSize = px(14),
			Font = Theme.fonts.bold,
			TextColor3 = Theme.color("gold"),
			TextXAlignment = Enum.TextXAlignment.Left,
			onActivated = actions.openRanking,
		}),
		shield = shield,
		pills = e("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -px(12), 0.5, 0),
			Size = UDim2.new(1, -px(Theme.safeLeft + 320), 0, px(48)),
			BackgroundTransparency = 1,
		}, pills),
	})
end

local function jobRow(
	icon: string,
	title: string,
	job: any,
	now: number,
	color: string,
	actions: any,
	order: number
): Kit.Element
	local left = Live.left(job, now)
	local free = left <= Balance.FREE_FINISH_SECONDS
	return e("Frame", { Size = UDim2.new(1, 0, 0, px(58)), BackgroundTransparency = 1, LayoutOrder = order }, {
		icon = C.text({ text = icon, size = 22, align = "Center", Size = UDim2.fromOffset(px(30), px(30)) }),
		title = C.text({
			text = title,
			size = 14,
			font = "bold",
			Position = UDim2.fromOffset(px(34), 0),
			Size = UDim2.new(1, -px(110), 0, px(20)),
		}),
		bar = e("Frame", {
			Position = UDim2.fromOffset(px(34), px(26)),
			Size = UDim2.new(1, -px(110), 0, px(18)),
			BackgroundTransparency = 1,
		}, { bar = C.progress(Live.fraction(job, now), color, 18, Format.duration(left)) }),
		finish = C.button({
			text = if free then t("ui.finishFree") else "⏩",
			variant = if free then "green" else "ghost",
			size = UDim2.fromOffset(px(66), px(34)),
			textSize = 14,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, px(6)),
			onClick = function()
				actions.finish(job.id)
			end,
		}),
	})
end

local function sidebar(state: any, actions: any): Kit.Element
	local view = state.view
	local now = state.now
	local kids: { [any]: any } = { _list = C.list("y", 10), _pad = C.padding(12) }

	-- Quest
	local q = view.quest
	if q then
		local questKids: { [any]: any } = {
			_pad = C.padding(12),
			_list = C.list("y", 6),
			title = C.text({
				text = "📜 " .. t("ui.quest"),
				size = 14,
				font = "bold",
				color = "gold",
				LayoutOrder = 1,
			}),
			body = C.text({
				text = t("quest." .. q.id),
				size = 15,
				font = "bold",
				wrap = true,
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, px(40)),
			}),
			bar = e("Frame", { Size = UDim2.new(1, 0, 0, px(16)), BackgroundTransparency = 1, LayoutOrder = 3 }, {
				bar = C.progress(
					q.progress / q.goal,
					"gold",
					16,
					Format.short(q.progress) .. " / " .. Format.short(q.goal)
				),
			}),
			reward = e("Frame", { Size = UDim2.new(1, 0, 0, px(28)), BackgroundTransparency = 1, LayoutOrder = 4 }, {
				row = C.costRow(q.reward),
			}),
		}
		if q.done then
			questKids.claim = C.button({
				text = t("ui.claim"),
				variant = "green",
				size = UDim2.new(1, 0, 0, px(38)),
				LayoutOrder = 5,
				onClick = actions.claimQuest,
			})
		end
		kids.quest = C.panel(
			{ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 },
			questKids,
			if q.done then "hi" else nil
		)
	end

	-- Queues
	local queue: { [any]: any } = {
		_pad = C.padding(12),
		_list = C.list("y", 6),
		title = C.text({
			text = "🔨 " .. t("ui.builders") .. " " .. #view.builds .. "/" .. view.queueSlots,
			size = 14,
			font = "bold",
			color = "gold",
			LayoutOrder = 0,
		}),
	}
	for i, job in view.builds do
		queue["b" .. i] = jobRow(
			Balance.BUILDINGS[job.building].icon,
			t("b." .. job.building) .. " → " .. job.level,
			job,
			now,
			"blue",
			actions,
			i
		)
	end
	if #view.builds < view.queueSlots then
		queue.idle = C.text({
			text = t("ui.queueEmpty"),
			size = 13,
			color = "muted",
			wrap = true,
			LayoutOrder = 9,
			Size = UDim2.new(1, 0, 0, px(34)),
		})
	end
	if view.training then
		local tr = view.training
		queue.training = jobRow(
			Balance.TROOPS[tr.troop].icon,
			t("ui.training") .. ": " .. tr.count .. " " .. t("t." .. tr.troop),
			tr,
			now,
			"orange",
			actions,
			10
		)
	end
	if view.researching then
		local r = view.researching
		queue.research = jobRow(
			Balance.RESEARCH[r.tech].icon,
			t("tech." .. r.tech) .. " → " .. r.level,
			r,
			now,
			"purple",
			actions,
			11
		)
	end
	kids.queue = C.panel({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 }, queue)

	-- Marches out
	if #view.marches > 0 or #view.incoming > 0 then
		local marches: { [any]: any } = {
			_pad = C.padding(12),
			_list = C.list("y", 6),
			title = C.text({
				text = "🚩 " .. t("ui.marches", { used = #view.marches, max = view.marchSlots }),
				size = 14,
				font = "bold",
				color = "gold",
				LayoutOrder = 0,
			}),
		}
		for i, m in view.incoming do
			marches["in" .. i] = C.text({
				text = "⚠ " .. (if m.size
					then t("ui.incomingSize", { name = m.name, size = m.size })
					else t("ui.incoming", { name = m.name })),
				size = 13,
				font = "bold",
				color = "red",
				wrap = true,
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, px(32)),
			})
		end
		for i, m in view.marches do
			local leg = m.leg
			local ends = if m.phase == "work" then m.workEndAt else leg.t1
			marches["m" .. i] = e(
				"Frame",
				{ Size = UDim2.new(1, 0, 0, px(34)), BackgroundTransparency = 1, LayoutOrder = 10 + i },
				{
					label = C.text({
						text = t("march." .. m.kind) .. " · " .. t("phase." .. m.phase) .. " " .. Format.duration(
							ends - now
						),
						size = 13,
						font = "bold",
						Size = UDim2.new(1, -px(78), 1, 0),
					}),
					recall = if m.phase ~= "back"
						then C.button({
							text = t("ui.recall"),
							variant = "red",
							textSize = 12,
							size = UDim2.fromOffset(px(72), px(28)),
							AnchorPoint = Vector2.new(1, 0.5),
							Position = UDim2.new(1, 0, 0.5, 0),
							onClick = function()
								actions.recall(m.id)
							end,
						})
						else nil,
				}
			)
		end
		kids.marches =
			C.panel({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3 }, marches)
	end

	return C.scroll({
		Position = UDim2.fromOffset(0, px(TOP)),
		Size = UDim2.new(0, px(SIDE), 1, -px(TOP + NAV)),
		ScrollBarThickness = px(4),
	}, kids)
end

local function bottomNav(state: any, actions: any): Kit.Element
	local kids: { [any]: any } = { _list = C.list("x", if Theme.compact then 4 else 8, "Center", "Center") }
	local badges = {
		reports = state.view.unread,
		guild = if state.view.guild then #state.view.guild.helps else 0,
	}
	for i, item in App.NAV do
		local active = state.screen == item.id
		local count = badges[item.id] or 0
		kids[item.id] = e("TextButton", {
			Size = UDim2.fromOffset(px(if Theme.compact then 78 else 112), px(62)),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			Text = "",
			LayoutOrder = i,
			AutoButtonColor = true,
			onActivated = function()
				actions.navigate(item.id)
			end,
		}, {
			_corner = C.corner(14),
			_gradient = if active then C.gradient("gold", "goldDeep") else C.gradient("panel2", "panel"),
			_stroke = C.stroke(if active then "gold" else "line", 1.5, if active then 0 else 0.4),
			icon = C.text({
				text = item.icon,
				size = 24,
				align = "Center",
				Position = UDim2.fromOffset(0, px(4)),
				Size = UDim2.new(1, 0, 0, px(30)),
			}),
			label = C.text({
				text = t("nav." .. item.id),
				size = 13,
				font = "bold",
				align = "Center",
				color = if active then "#3A2600" else "muted",
				Position = UDim2.fromOffset(0, px(36)),
				Size = UDim2.new(1, 0, 0, px(18)),
			}),
			badge = if count > 0
				then C.badge(
					tostring(count),
					"red",
					{ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, px(4), 0, -px(6)) }
				)
				else nil,
		})
	end
	return e("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, px(NAV)),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 10,
	}, C.merge({ _gradient = C.gradient("bg", "bg2"), _pad = C.padding(8) }, kids))
end

local function toasts(state: any): Kit.Element?
	if #state.toasts == 0 then
		return nil
	end
	local kids: { [any]: any } = { _list = C.list("y", 6, "Center") }
	for i, toast in state.toasts do
		kids[i] = C.badge(
			toast.text,
			if toast.kind == "error" then "redDeep" elseif toast.kind == "warn" then "orange" else "greenDeep",
			{
				Size = UDim2.fromOffset(0, px(34)),
				TextSize = px(16),
				Font = Theme.fonts.bold,
			}
		)
	end
	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, px(TOP + 10)),
		Size = UDim2.fromOffset(px(600), px(200)),
		BackgroundTransparency = 1,
		ZIndex = 60,
	}, kids)
end

function App.render(state: any, actions: any): Kit.Element
	if not state.view then
		return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.color("bg"), BorderSizePixel = 0 }, {
			title = C.text({
				text = "🏰 " .. t("game.title"),
				size = 40,
				font = "title",
				color = "gold",
				align = "Center",
				Size = UDim2.fromScale(1, 0.5),
			}),
			sub = C.text({
				text = t("err.offline"),
				size = 18,
				color = "muted",
				align = "Center",
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.new(1, 0, 0, px(30)),
			}),
		})
	end
	local screen = ScreenModules[state.screen] or ScreenModules.city
	local fullBleed = state.screen == "map"
	local showSide = not Theme.compact and not fullBleed
	local content = e("Frame", {
		Position = UDim2.fromOffset(if showSide then px(SIDE) else 0, px(TOP)),
		Size = UDim2.new(1, if showSide then -px(SIDE) else 0, 1, -px(TOP + NAV)),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, { screen = screen.render(state, actions) })

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.color("bg"),
		BorderSizePixel = 0,
	}, {
		_gradient = C.gradient("bg2", "bg"),
		content = content,
		side = if showSide then sidebar(state, actions) else nil,
		top = topBar(state, actions),
		nav = bottomNav(state, actions),
		modal = Modals.render(state, actions),
		toasts = toasts(state),
	})
end

return App
