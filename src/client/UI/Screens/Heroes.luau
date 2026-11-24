--!strict
-- Hero roster: owned heroes with level, XP and their bonus; others can be recruited for gold.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Rules.Balance)
local City = require(Shared.Rules.City)
local Economy = require(Shared.Rules.Economy)
local Format = require(Shared.Rules.Format)

local C = require(script.Parent.Parent.Components)
local Kit = require(script.Parent.Parent.Parent.Kit)
local Live = require(script.Parent.Parent.Live)
local Theme = require(script.Parent.Parent.Theme)

local e = C.e
local t = C.t
local px = Theme.px

local Heroes = {}

function Heroes.bonusText(id: string, level: number): string
	local def = Balance.HEROES[id]
	local value = Format.percent(Economy.heroBonus(id, level, def.stat, def.class))
	if def.class and def.stat == "atk" then
		return t("stat.atkClass", { v = value, class = t("class." .. def.class) })
	elseif def.class and def.stat == "def" then
		return t("stat.defClass", { v = value, class = t("class." .. def.class) })
	end
	return t("stat." .. def.stat, { v = value })
end

local function busyHeroes(view: any): { [string]: boolean }
	local out = {}
	for _, m in view.marches do
		if m.hero then
			out[m.hero] = true
		end
	end
	return out
end

local function card(state: any, actions: any, id: string, order: number, busy: boolean): Kit.Element
	local view = state.view
	local def = Balance.HEROES[id]
	local hero = view.heroes[id]
	local owned = hero ~= nil
	local level = if hero then hero.level else 1
	local selected = state.selected.hero == id
	local resources = Live.resources(view, state.now)
	local kids: { [any]: any } = {
		_corner = C.corner(16),
		_gradient = if owned
			then C.gradient(Theme.colors[def.rarity], "panel", 90)
			else C.gradient("#2A3150", "#1A1F36"),
		_stroke = C.stroke(
			if selected then "gold" else def.rarity,
			if selected then 3 else 2,
			if owned then 0 else 0.4
		),
		portrait = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, px(14)),
			Size = UDim2.fromOffset(px(96), px(96)),
			BackgroundColor3 = Theme.color("bg"),
			BackgroundTransparency = 0.3,
		}, {
			_corner = C.round(),
			_stroke = C.stroke(def.rarity, 3),
			icon = C.text({
				text = def.icon,
				size = 52,
				align = "Center",
				Size = UDim2.fromScale(1, 1),
				TextTransparency = if owned then 0 else 0.5,
			}),
		}),
		rarity = C.badge(
			t("rarity." .. def.rarity),
			def.rarity,
			{ Position = UDim2.fromOffset(px(8), px(8)), TextSize = px(11), Size = UDim2.fromOffset(0, px(20)) }
		),
		name = C.text({
			text = t("hero." .. id),
			size = 16,
			font = "title",
			align = "Center",
			Position = UDim2.fromOffset(px(6), px(116)),
			Size = UDim2.new(1, -px(12), 0, px(22)),
		}),
		bonus = C.text({
			text = Heroes.bonusText(id, level),
			size = 12,
			font = "bold",
			align = "Center",
			color = "green",
			wrap = true,
			Position = UDim2.fromOffset(px(8), px(140)),
			Size = UDim2.new(1, -px(16), 0, px(32)),
		}),
	}
	if owned then
		local next = City.heroXpToNext(level)
		kids.level = C.badge(t("ui.level", { level = level }), "goldDeep", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -px(8), 0, px(8)),
			TextSize = px(12),
			Size = UDim2.fromOffset(0, px(20)),
		})
		kids.xp = e(
			"Frame",
			{
				Position = UDim2.new(0, px(12), 1, -px(52)),
				Size = UDim2.new(1, -px(24), 0, px(14)),
				BackgroundTransparency = 1,
			},
			{
				bar = C.progress(
					if level >= Balance.HERO_MAX_LEVEL then 1 else hero.xp / next,
					"purple",
					14,
					t("ui.xp", { xp = Format.short(hero.xp), next = Format.short(next) })
				),
			}
		)
		kids.status = C.text({
			text = if busy then "🚩 " .. t("ui.busy") else "✅ " .. t("ui.ready"),
			size = 13,
			font = "bold",
			align = "Center",
			color = if busy then "orange" else "green",
			Position = UDim2.new(0, 0, 1, -px(32)),
			Size = UDim2.new(1, 0, 0, px(22)),
		})
	else
		kids.recruit = C.button({
			text = if def.recruitGold > 0 then t("ui.recruit", { gold = def.recruitGold }) else t("ui.recruitFree"),
			variant = "gold",
			disabled = (resources.gold or 0) < def.recruitGold,
			textSize = 14,
			size = UDim2.new(1, -px(24), 0, px(38)),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -px(10)),
			onClick = function()
				actions.recruit(id)
			end,
		})
	end
	return e("TextButton", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		Text = "",
		LayoutOrder = order,
		onActivated = function()
			actions.selectHero(id)
		end,
	}, kids)
end

function Heroes.render(state: any, actions: any): Kit.Element
	local busy = busyHeroes(state.view)
	local kids: { [any]: any } = { _grid = C.grid(196, 238, 14) }
	for i, id in Balance.HERO_ORDER do
		kids[id] = card(state, actions, id, i, busy[id] == true)
	end
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		_pad = C.padding(18),
		title = C.text({
			text = "🦸 " .. t("nav.heroes"),
			size = 26,
			font = "title",
			color = "gold",
			Size = UDim2.new(1, 0, 0, px(34)),
		}),
		sub = C.text({ text = t("ui.heroHint"), size = 14, color = "muted", Position = UDim2.fromOffset(0, px(36)) }),
		grid = C.scroll({ Position = UDim2.fromOffset(0, px(68)), Size = UDim2.new(1, 0, 1, -px(68)) }, kids),
	})
end

return Heroes
