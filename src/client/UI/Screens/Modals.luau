--!strict
-- Dialogs on top of any screen: a building's upgrade sheet, the march composer and the realm ranking.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Army = require(Shared.Rules.Army)
local Balance = require(Shared.Rules.Balance)
local City = require(Shared.Rules.City)
local Combat = require(Shared.Rules.Combat)
local Economy = require(Shared.Rules.Economy)
local Format = require(Shared.Rules.Format)

local C = require(script.Parent.Parent.Components)
local Kit = require(script.Parent.Parent.Parent.Kit)
local Live = require(script.Parent.Parent.Live)
local Theme = require(script.Parent.Parent.Theme)

local e = C.e
local t = C.t
local px = Theme.px

local Modals = {}

-- What a building does at a level, in one line.
function Modals.effect(id: string, level: number): string
	local data = { buildings = { [id] = level }, research = {} }
	local def = Balance.BUILDINGS[id]
	if level <= 0 then
		return "–"
	end
	if def.produces and def.baseRate then
		return t(
			"eff.production",
			{
				v = Format.short(math.floor(def.baseRate * level ^ Balance.RATE_EXPONENT)),
				res = t("res." .. def.produces),
			}
		)
	elseif id == "keep" then
		return t("eff.keep", { v = Format.short(Economy.storageCap(data)), level = level })
	elseif id == "barracks" then
		local tier = if level >= Balance.EFFECTS.tier3Barracks
			then 3
			elseif level >= Balance.EFFECTS.tier2Barracks then 2
			else 1
		return t("eff.barracks", { v = Army.batchSize(data), tier = tier })
	elseif id == "wall" then
		return t("eff.wall", { v = Format.percent(level * Balance.EFFECTS.wallDefensePerLevel) })
	elseif id == "infirmary" then
		return t("eff.infirmary", { v = Format.short(Army.infirmaryCap(data)) })
	elseif id == "vault" then
		return t("eff.vault", { v = Format.short(Economy.protected(data)) })
	elseif id == "academy" then
		return t("eff.academy", { v = Format.percent(level * Balance.EFFECTS.academySpeedPerLevel), level = level })
	elseif id == "embassy" then
		return t("eff.embassy", { v = Balance.EFFECTS.embassyHelpBase + level })
	elseif id == "warhall" then
		return t("eff.warhall", { v = Format.short(Army.marchSize(data)), slots = Army.marchSlots(data) })
	elseif id == "watchtower" then
		return t(if level >= Balance.EFFECTS.watchtowerDetailLevel then "eff.watchtowerExact" else "eff.watchtower")
	end
	return ""
end

local function buildingModal(state: any, actions: any, id: string): Kit.Element
	local view = state.view
	local def = Balance.BUILDINGS[id]
	local level = view.buildings[id] or 0
	local nextLevel = level + 1
	local resources = Live.resources(view, state.now)
	local data = {
		buildings = view.buildings,
		builds = view.builds,
		resources = resources,
		research = view.research,
		jobSeq = 0,
	}
	local err = City.checkUpgrade(data, id)
	local maxed = level >= def.maxLevel
	local cost = if maxed then {} else Economy.buildingCost(id, nextLevel)
	local time = if maxed then 0 else Economy.buildingTime(id, nextLevel)
	local job = Live.buildingJob(view, id)

	local body: { [any]: any } = {
		_list = C.list("y", 10),
		top = e("Frame", { Size = UDim2.new(1, 0, 0, px(92)), BackgroundTransparency = 1, LayoutOrder = 1 }, {
			icon = e("Frame", { Size = UDim2.fromOffset(px(92), px(92)), BackgroundColor3 = Theme.color("bg") }, {
				_corner = C.corner(18),
				_stroke = C.stroke("gold", 2, 0.3),
				icon = C.text({ text = def.icon, size = 56, align = "Center", Size = UDim2.fromScale(1, 1) }),
			}),
			level = C.text({
				text = t("ui.level", { level = level })
					.. (if maxed then "  ⭐" else "  →  " .. t("ui.level", { level = nextLevel })),
				size = 22,
				font = "title",
				color = "gold",
				Position = UDim2.fromOffset(px(108), px(4)),
				Size = UDim2.new(1, -px(108), 0, px(28)),
			}),
			desc = C.text({
				text = t("bd." .. id),
				size = 14,
				color = "muted",
				wrap = true,
				valign = "Top",
				Position = UDim2.fromOffset(px(108), px(36)),
				Size = UDim2.new(1, -px(108), 0, px(56)),
			}),
		}),
		effect = C.panel({ Size = UDim2.new(1, 0, 0, px(62)), LayoutOrder = 2 }, {
			_pad = C.padding(10, 14, 10, 14),
			now = C.text({
				text = "📊 " .. Modals.effect(id, level),
				size = 15,
				font = "bold",
				Size = UDim2.new(1, 0, 0, px(20)),
			}),
			next = C.text({
				text = if maxed then t("ui.maxed") else "⬆ " .. Modals.effect(id, nextLevel),
				size = 15,
				font = "bold",
				color = "green",
				Position = UDim2.fromOffset(0, px(22)),
				Size = UDim2.new(1, 0, 0, px(20)),
			}),
		}, "flat"),
	}
	if not maxed then
		body.costTitle = C.text({
			text = t("ui.cost") .. "  ·  ⏱ " .. Format.duration(time),
			size = 14,
			font = "bold",
			color = "muted",
			LayoutOrder = 3,
		})
		body.cost = e(
			"Frame",
			{ Size = UDim2.new(1, 0, 0, px(28)), BackgroundTransparency = 1, LayoutOrder = 4 },
			{ row = C.costRow(cost, resources) }
		)
	end
	if job then
		body.progress = e("Frame", { Size = UDim2.new(1, 0, 0, px(22)), BackgroundTransparency = 1, LayoutOrder = 5 }, {
			bar = C.progress(
				Live.fraction(job, state.now),
				"blue",
				22,
				"⏳ " .. Format.duration(Live.left(job, state.now))
			),
		})
	elseif err and err ~= "err.notEnough" and not maxed then
		body.reason = C.text({ text = "⚠ " .. t(err), size = 14, font = "bold", color = "orange", LayoutOrder = 5 })
	end
	body.upgrade = C.button({
		text = if level == 0 then "🔨 " .. t("ui.build") else "⬆ " .. t("ui.upgrade"),
		variant = "green",
		disabled = err ~= nil,
		size = UDim2.new(1, 0, 0, px(52)),
		textSize = 20,
		LayoutOrder = 6,
		onClick = function()
			actions.upgrade(id)
		end,
	})
	return C.modal(
		t("b." .. id),
		560,
		470,
		actions.closeModal,
		{ content = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, body) }
	)
end

local KIND_TITLE = { gather = "ui.gather", hunt = "ui.hunt", attack = "ui.attack", scout = "ui.scout" }

local function marchModal(state: any, actions: any, modal: any): Kit.Element
	local view = state.view
	local troops = modal.troops
	local total = Army.total(troops)
	local data = { buildings = view.buildings, research = view.research }
	local hero = modal.hero
	local heroLevel = if hero and view.heroes[hero] then view.heroes[hero].level else nil
	local castle = view.castle
	local scouting = modal.march == "scout"

	local rows: { [any]: any } = { _list = C.list("y", 6) }
	for order, id in Balance.TROOP_ORDER do
		local have = view.troops[id] or 0
		if have > 0 and not scouting then
			local n = troops[id] or 0
			local function set(v: number)
				return function()
					actions.setMarchTroop(id, math.clamp(v, 0, have))
				end
			end
			rows[id] = C.panel({ Size = UDim2.new(1, -px(8), 0, px(48)), LayoutOrder = order }, {
				icon = C.text({
					text = Balance.TROOPS[id].icon,
					size = 22,
					align = "Center",
					Size = UDim2.fromOffset(px(44), px(48)),
				}),
				name = C.text({
					text = t("t." .. id),
					size = 14,
					font = "bold",
					Position = UDim2.fromOffset(px(44), px(4)),
					Size = UDim2.new(0.4, 0, 0, px(20)),
				}),
				have = C.text({
					text = "/ " .. Format.thousands(have),
					size = 12,
					color = "faint",
					Position = UDim2.fromOffset(px(44), px(24)),
					Size = UDim2.new(0.4, 0, 0, px(18)),
				}),
				controls = e("Frame", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -px(8), 0.5, 0),
					Size = UDim2.fromOffset(px(230), px(36)),
					BackgroundTransparency = 1,
				}, {
					_list = C.list("x", 6, "Right", "Center"),
					none = C.button({
						text = "0",
						variant = "ghost",
						textSize = 13,
						size = UDim2.fromOffset(px(36), px(34)),
						LayoutOrder = 1,
						onClick = set(0),
					}),
					minus = C.iconButton("−", "fewer", set(n - 10), 34, { LayoutOrder = 2 }),
					value = C.text({
						text = Format.thousands(n),
						size = 16,
						font = "title",
						align = "Center",
						color = if n > 0 then "gold" else "muted",
						Size = UDim2.fromOffset(px(60), px(34)),
						LayoutOrder = 3,
					}),
					plus = C.iconButton("+", "more", set(n + 10), 34, { LayoutOrder = 4 }),
					all = C.button({
						text = t("ui.max"),
						variant = "ghost",
						textSize = 13,
						size = UDim2.fromOffset(px(44), px(34)),
						LayoutOrder = 5,
						onClick = set(have),
					}),
				}),
			}, "flat")
		end
	end
	if scouting then
		rows.note = C.text({
			text = "👁️ " .. t("ui.scoutFree"),
			size = 15,
			color = "muted",
			wrap = true,
			Size = UDim2.new(1, 0, 0, px(40)),
		})
	end

	local heroes: { [any]: any } = { _list = C.list("x", 6, "Left", "Center") }
	if not scouting then
		heroes.none = C.button({
			text = t("ui.noHero"),
			variant = if hero == nil then "gold" else "ghost",
			textSize = 12,
			size = UDim2.fromOffset(px(86), px(36)),
			LayoutOrder = 0,
			onClick = function()
				actions.setMarchHero(nil)
			end,
		})
		local busy = {}
		for _, m in view.marches do
			if m.hero then
				busy[m.hero] = true
			end
		end
		for order, id in Balance.HERO_ORDER do
			if view.heroes[id] and not busy[id] then
				heroes[id] = C.button({
					text = Balance.HEROES[id].icon .. " " .. view.heroes[id].level,
					variant = if hero == id then "gold" else "ghost",
					textSize = 13,
					size = UDim2.fromOffset(px(64), px(36)),
					LayoutOrder = order,
					onClick = function()
						actions.setMarchHero(id)
					end,
				})
			end
		end
	end

	local travel = if scouting
		then math.max(3, math.ceil(Army.distance(castle.x, castle.y, modal.x, modal.y) / 30 * 60))
		elseif total > 0 then Army.travelSeconds(
			data,
			troops,
			hero,
			heroLevel,
			castle.x,
			castle.y,
			modal.x,
			modal.y
		)
		else 0
	local summary = "🚶 "
		.. Format.thousands(total)
		.. " / "
		.. Format.thousands(view.marchSize)
		.. "   ·   ⏱ "
		.. t("ui.travel", { time = Format.duration(travel) })
	if modal.march == "gather" and total > 0 then
		summary ..= "   ·   🎒 " .. t("ui.load", { v = Format.short(Army.load(data, troops, hero, heroLevel)) })
	elseif modal.march == "hunt" and total > 0 then
		summary ..= "   ·   💥 " .. t(
			"ui.damage",
			{ v = Format.short(Combat.huntDamage(data, troops, hero, heroLevel)) }
		)
	end
	local over = total > view.marchSize
	local ok = scouting or (total > 0 and not over)

	return C.modal(
		t(KIND_TITLE[modal.march]) .. " · " .. t("ui.coords", { x = modal.x, y = modal.y }),
		640,
		560,
		actions.closeModal,
		{
			title = C.text({
				text = t("ui.selectTroops"),
				size = 15,
				font = "bold",
				color = "muted",
				Size = UDim2.new(1, 0, 0, px(20)),
			}),
			rows = C.scroll({ Position = UDim2.fromOffset(0, px(26)), Size = UDim2.new(1, 0, 1, -px(26 + 160)) }, rows),
			heroTitle = C.text({
				text = "🦸 " .. t("ui.hero"),
				size = 14,
				font = "bold",
				color = "muted",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 0, 1, -px(128)),
				Visible = not scouting,
			}),
			heroes = e(
				"Frame",
				{
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 0, 1, -px(86)),
					Size = UDim2.new(1, 0, 0, px(38)),
					BackgroundTransparency = 1,
				},
				heroes
			),
			summary = C.text({
				text = summary,
				size = 14,
				font = "bold",
				color = if over then "red" else "text",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 0, 1, -px(60)),
			}),
			send = C.button({
				text = "🚩 " .. t("ui.send"),
				variant = if modal.march == "attack" then "red" else "green",
				disabled = not ok,
				size = UDim2.new(1, 0, 0, px(50)),
				textSize = 20,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				onClick = actions.sendMarch,
			}),
		}
	)
end

local function rankingModal(state: any, actions: any): Kit.Element
	local rows: { [any]: any } = { _list = C.list("y", 6) }
	for i, r in state.view.top do
		local me = r.kid == state.view.kid
		rows[i] = C.panel({ Size = UDim2.new(1, -px(8), 0, px(44)), LayoutOrder = i }, {
			rank = C.text({
				text = if i <= 3 then ({ "🥇", "🥈", "🥉" })[i] else "#" .. i,
				size = 18,
				font = "title",
				align = "Center",
				Size = UDim2.fromOffset(px(50), px(44)),
			}),
			swatch = e(
				"Frame",
				{
					Position = UDim2.fromOffset(px(52), px(14)),
					Size = UDim2.fromOffset(px(16), px(16)),
					BackgroundColor3 = Theme.color(r.color),
				},
				{ _corner = C.round() }
			),
			name = C.text({
				text = (if r.tag then "[" .. r.tag .. "] " else "") .. r.name .. (if r.isBot then "  🤖" else ""),
				size = 15,
				font = "bold",
				color = if me then "gold" else "text",
				Position = UDim2.fromOffset(px(76), 0),
				Size = UDim2.new(0.62, -px(76), 1, 0),
			}),
			power = C.text({
				text = "⚔ " .. Format.thousands(r.power),
				size = 15,
				font = "bold",
				color = "gold",
				align = "Right",
				Position = UDim2.fromScale(0.62, 0),
				Size = UDim2.new(0.38, -px(14), 1, 0),
			}),
		}, if me then "hi" else "flat")
	end
	return C.modal("🏆 " .. t("ui.top"), 560, 600, actions.closeModal, {
		you = C.text({
			text = t("ui.rank", { rank = state.view.rank, total = state.view.kingdoms })
				.. "  ·  ⚔ "
				.. Format.thousands(state.view.power),
			size = 15,
			font = "bold",
			color = "muted",
		}),
		list = C.scroll({ Position = UDim2.fromOffset(0, px(30)), Size = UDim2.new(1, 0, 1, -px(30)) }, rows),
	})
end

function Modals.render(state: any, actions: any): Kit.Element?
	local modal = state.modal
	if not modal then
		return nil
	end
	if modal.kind == "building" then
		return buildingModal(state, actions, modal.id)
	elseif modal.kind == "march" then
		return marchModal(state, actions, modal)
	elseif modal.kind == "ranking" then
		return rankingModal(state, actions)
	end
	return nil
end

return Modals
