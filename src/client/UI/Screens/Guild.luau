--!strict
-- Guilds: join one of the realm's guilds or found your own from a list of words (no typed names, so nothing to
-- moderate). Inside a guild: members, help requests and one button to help everyone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Rules.Balance)
local Format = require(Shared.Rules.Format)

local C = require(script.Parent.Parent.Components)
local Kit = require(script.Parent.Parent.Parent.Kit)
local Live = require(script.Parent.Parent.Live)
local Theme = require(script.Parent.Parent.Theme)

local e = C.e
local t = C.t
local px = Theme.px

local Guild = {}

local function row(order: number, height: number, kids: { [any]: any }): Kit.Element
	return C.panel({ Size = UDim2.new(1, 0, 0, px(height)), LayoutOrder = order }, kids, "flat")
end

local function inGuild(state: any, actions: any): Kit.Element
	local g = state.view.guild
	local members: { [any]: any } = { _list = C.list("y", 6) }
	for i, m in g.members do
		members[i] = row(i, 46, {
			rank = C.text({
				text = "#" .. i,
				size = 14,
				font = "bold",
				color = "faint",
				align = "Center",
				Size = UDim2.fromOffset(px(40), px(46)),
			}),
			name = C.text({
				text = (if m.leader then "👑 " else "") .. m.name .. (if m.isBot then "  🤖" else "") .. (if m.kid
						== state.view.kid
					then "  ⭐"
					else ""),
				size = 15,
				font = "bold",
				color = if m.kid == state.view.kid then "gold" else "text",
				Position = UDim2.fromOffset(px(40), 0),
				Size = UDim2.new(0.6, -px(40), 1, 0),
			}),
			keep = C.text({
				text = "🏰 " .. m.keep,
				size = 14,
				color = "muted",
				Position = UDim2.fromScale(0.6, 0),
				Size = UDim2.new(0.15, 0, 1, 0),
			}),
			power = C.text({
				text = "⚔ " .. Format.short(m.power),
				size = 14,
				font = "bold",
				color = "gold",
				align = "Right",
				Position = UDim2.fromScale(0.75, 0),
				Size = UDim2.new(0.25, -px(12), 1, 0),
			}),
		})
	end

	local helps: { [any]: any } = { _list = C.list("y", 6) }
	local open = 0
	for i, h in g.helps do
		if not h.mine and not h.helped then
			open += 1
		end
		local label = if h.labelKind == "building" then t("b." .. h.label) else t("tech." .. h.label)
		helps[i] = row(i, 58, {
			_pad = C.padding(8, 12, 8, 12),
			who = C.text({
				text = h.name .. (if h.mine then " (" .. t("ui.you") .. ")" else ""),
				size = 14,
				font = "bold",
				Size = UDim2.new(1, 0, 0, px(20)),
			}),
			what = C.text({
				text = label .. " → " .. t("ui.level", { level = h.level }) .. "  ·  " .. t(
					"ui.helpProgress",
					{ given = h.given, max = h.max }
				),
				size = 13,
				color = if h.helped then "green" else "muted",
				Position = UDim2.fromOffset(0, px(22)),
				Size = UDim2.new(1, 0, 0, px(18)),
			}),
		})
	end
	if #g.helps == 0 then
		helps.empty = C.text({
			text = t("ui.noHelp"),
			size = 14,
			color = "muted",
			wrap = true,
			Size = UDim2.new(1, 0, 0, px(40)),
		})
	end

	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		title = C.text({
			text = "🤝 [" .. g.tag .. "] " .. g.name,
			size = 26,
			font = "title",
			color = "gold",
			Size = UDim2.new(1, 0, 0, px(34)),
		}),
		sub = C.text({
			text = t("ui.members", { n = g.count, max = Balance.GUILD_MAX_MEMBERS }),
			size = 14,
			color = "muted",
			Position = UDim2.fromOffset(0, px(36)),
		}),
		leave = C.button({
			text = t("ui.leave"),
			variant = "red",
			textSize = 14,
			size = UDim2.fromOffset(px(150), px(38)),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			onClick = actions.guildLeave,
		}),
		members = C.scroll(
			{ Position = UDim2.fromOffset(0, px(70)), Size = UDim2.new(0.55, -px(10), 1, -px(70)) },
			members
		),
		helpBox = C.panel({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, px(70)),
			Size = UDim2.new(0.45, -px(10), 1, -px(70)),
		}, {
			_pad = C.padding(14),
			title = C.text({
				text = "🔨 " .. t("ui.guildHelp"),
				size = 18,
				font = "title",
				color = "gold",
				Size = UDim2.new(1, 0, 0, px(26)),
			}),
			list = C.scroll({ Position = UDim2.fromOffset(0, px(34)), Size = UDim2.new(1, 0, 1, -px(34 + 60)) }, helps),
			help = C.button({
				text = "🤝 " .. t("ui.helpAll") .. (if open > 0 then " (" .. open .. ")" else ""),
				variant = "green",
				disabled = open == 0,
				size = UDim2.new(1, 0, 0, px(48)),
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				onClick = actions.guildHelp,
			}),
		}, "hi"),
	})
end

local function noGuild(state: any, actions: any): Kit.Element
	local list: { [any]: any } = { _list = C.list("y", 8) }
	for i, g in state.view.guilds or {} do
		local full = g.count >= Balance.GUILD_MAX_MEMBERS
		list[i] = row(i, 60, {
			tag = C.badge(g.tag, "purple", { Position = UDim2.fromOffset(px(12), px(18)), TextSize = px(13) }),
			name = C.text({
				text = g.name,
				size = 17,
				font = "title",
				Position = UDim2.fromOffset(px(70), px(8)),
				Size = UDim2.new(1, -px(230), 0, px(24)),
			}),
			info = C.text({
				text = t("ui.members", { n = g.count, max = Balance.GUILD_MAX_MEMBERS })
					.. "  ·  ⚔ "
					.. Format.short(g.power),
				size = 13,
				color = "muted",
				Position = UDim2.fromOffset(px(70), px(32)),
				Size = UDim2.new(1, -px(230), 0, px(18)),
			}),
			join = C.button({
				text = t("ui.join"),
				variant = "green",
				disabled = full,
				textSize = 15,
				size = UDim2.fromOffset(px(110), px(40)),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -px(12), 0.5, 0),
				onClick = function()
					actions.guildJoin(g.id)
				end,
			}),
		})
	end

	local pick = state.selected.guildName
	local adj = Balance.GUILD_ADJECTIVES[pick.adj]
	local noun = Balance.GUILD_NOUNS[pick.noun]
	local gold = Live.resources(state.view, state.now).gold
	local function cycle(part: string, delta: number)
		return function()
			actions.cycleGuildName(part, delta)
		end
	end
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		title = C.text({
			text = "🤝 " .. t("nav.guild"),
			size = 26,
			font = "title",
			color = "gold",
			Size = UDim2.new(1, 0, 0, px(34)),
		}),
		sub = C.text({
			text = t("ui.noGuild"),
			size = 14,
			color = "muted",
			wrap = true,
			Position = UDim2.fromOffset(0, px(36)),
			Size = UDim2.new(1, 0, 0, px(22)),
		}),
		list = C.scroll({ Position = UDim2.fromOffset(0, px(70)), Size = UDim2.new(0.58, -px(10), 1, -px(70)) }, list),
		create = C.panel({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, px(70)),
			Size = UDim2.new(0.42, -px(10), 0, px(260)),
		}, {
			_pad = C.padding(16),
			_list = C.list("y", 12, "Center"),
			title = C.text({
				text = "🏳️ " .. t("ui.pickName"),
				size = 18,
				font = "title",
				color = "gold",
				LayoutOrder = 1,
			}),
			adj = e("Frame", { Size = UDim2.new(1, 0, 0, px(44)), BackgroundTransparency = 1, LayoutOrder = 2 }, {
				prev = C.iconButton("◀", "previous word", cycle("adj", -1), 44),
				word = C.text({
					text = adj,
					size = 22,
					font = "title",
					align = "Center",
					Position = UDim2.fromOffset(px(50), 0),
					Size = UDim2.new(1, -px(100), 1, 0),
				}),
				next = C.iconButton(
					"▶",
					"next word",
					cycle("adj", 1),
					44,
					{ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0) }
				),
			}),
			noun = e("Frame", { Size = UDim2.new(1, 0, 0, px(44)), BackgroundTransparency = 1, LayoutOrder = 3 }, {
				prev = C.iconButton("◀", "previous word", cycle("noun", -1), 44),
				word = C.text({
					text = noun,
					size = 22,
					font = "title",
					align = "Center",
					Position = UDim2.fromOffset(px(50), 0),
					Size = UDim2.new(1, -px(100), 1, 0),
				}),
				next = C.iconButton(
					"▶",
					"next word",
					cycle("noun", 1),
					44,
					{ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0) }
				),
			}),
			create = C.button({
				text = t("ui.create", { gold = Balance.GUILD_CREATE_GOLD }),
				variant = "gold",
				disabled = gold < Balance.GUILD_CREATE_GOLD,
				size = UDim2.new(1, 0, 0, px(48)),
				LayoutOrder = 4,
				onClick = actions.guildCreate,
			}),
		}, "hi"),
	})
end

function Guild.render(state: any, actions: any): Kit.Element
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		_pad = C.padding(18),
		body = if state.view.guild then inGuild(state, actions) else noGuild(state, actions),
	})
end

return Guild
