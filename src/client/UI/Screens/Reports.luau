--!strict
-- Battle, hunt, gathering and scouting reports. Each side of a battle gets its own copy from the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Army = require(Shared.Rules.Army)
local Balance = require(Shared.Rules.Balance)
local Format = require(Shared.Rules.Format)

local C = require(script.Parent.Parent.Components)
local Kit = require(script.Parent.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)

local e = C.e
local t = C.t
local px = Theme.px

local Reports = {}

function Reports.summary(r: any): (string, string, string)
	if r.kind == "attack" then
		return if r.attackerWon then "🏆" else "💀", t(if r.attackerWon then "rep.attackWon" else "rep.attackLost", { name = r.defender }), if r.attackerWon then "green" else "red"
	elseif r.kind == "defend" then
		return if r.attackerWon then "🔥" else "🛡️", t(if r.attackerWon then "rep.defendLost" else "rep.defendWon", { name = r.attacker }), if r.attackerWon then "red" else "green"
	elseif r.kind == "hunt" then
		local name = t("mon." .. r.monster)
		return Balance.MONSTERS[r.monster].icon, t(if r.killed then "rep.huntKilled" else "rep.hunt", { monster = name, level = r.level }), "gold"
	elseif r.kind == "gather" then
		return Balance.RESOURCE_ICONS[r.res] or "⛏️", t("rep.gather", { amount = Format.short(r.amount), res = t("res." .. (r.res or "food")) }), "green"
	elseif r.kind == "scout" then
		return "👁️", t("rep.scout", { name = r.name }), "blue"
	elseif r.kind == "scouted" then
		return "👁️", t("rep.scouted", { name = r.name }), "orange"
	elseif r.kind == "shielded" then
		return "🛡️", t("rep.shielded", { name = r.name }), "muted"
	end
	return "❔", t("rep.lost"), "muted"
end

local function troopTable(columns: { { string } }, rows: { [string]: { number } }): Kit.Element
	local kids: { [any]: any } = { _list = C.list("y", 2) }
	local header: { [any]: any } = { _list = C.list("x", 0) }
	header.name = C.text({ text = "", size = 13, Size = UDim2.new(0.34, 0, 0, px(22)), LayoutOrder = 0 })
	for i, col in columns do
		header[i] = C.text({ text = col[1], size = 13, font = "bold", color = col[2], align = "Right", Size = UDim2.new(0.22, 0, 0, px(22)), LayoutOrder = i })
	end
	kids.header = e("Frame", { Size = UDim2.new(1, 0, 0, px(22)), BackgroundTransparency = 1, LayoutOrder = 0 }, header)
	for order, id in Balance.TROOP_ORDER do
		local values = rows[id]
		if values then
			local line: { [any]: any } = { _list = C.list("x", 0) }
			line.name = C.text({ text = Balance.TROOPS[id].icon .. " " .. t("t." .. id), size = 13, Size = UDim2.new(0.34, 0, 0, px(22)), LayoutOrder = 0 })
			for i, v in values do
				line[i] = C.text({
					text = if v > 0 then Format.thousands(v) else "–",
					size = 13,
					font = "bold",
					color = columns[i][2],
					align = "Right",
					Size = UDim2.new(0.22, 0, 0, px(22)),
					LayoutOrder = i,
				})
			end
			kids[id] = e("Frame", { Size = UDim2.new(1, 0, 0, px(22)), BackgroundTransparency = 1, LayoutOrder = order }, line)
		end
	end
	return e("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, kids)
end

local function battleSide(title: string, before: any, dead: any, wounded: any, order: number): Kit.Element
	local rows = {}
	for id, n in before do
		rows[id] = { n, dead[id] or 0, wounded[id] or 0 }
	end
	return C.panel({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order }, {
		_pad = C.padding(12),
		_list = C.list("y", 6),
		title = C.text({ text = title, size = 16, font = "title", color = "gold", LayoutOrder = 0 }),
		table = e("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1 }, {
			t = troopTable({ { t("rep.before"), "text" }, { t("rep.dead"), "red" }, { t("rep.woundedCol"), "orange" } }, rows),
		}),
	}, "flat")
end

local function detail(state: any, r: any): Kit.Element
	local icon, title, color = Reports.summary(r)
	local kids: { [any]: any } = {
		_list = C.list("y", 10),
		head = C.text({ text = icon .. "  " .. title, size = 24, font = "title", color = color, LayoutOrder = 0, Size = UDim2.new(1, 0, 0, px(32)) }),
		where = C.text({ text = "📍 " .. t("ui.coords", { x = r.x or 0, y = r.y or 0 }) .. "  ·  " .. t("ui.ago", { time = Format.duration(state.now - r.t) }), size = 13, color = "faint", LayoutOrder = 1 }),
	}
	if r.kind == "attack" or r.kind == "defend" then
		local mineAttacker = r.kind == "attack"
		kids.wall = C.text({ text = "🧱 " .. t("rep.wall", { v = Format.percent(r.wallBonus) }), size = 13, color = "muted", LayoutOrder = 2 })
		kids.a = battleSide((if mineAttacker then t("rep.you") else t("rep.enemy")) .. " · " .. r.attacker, r.attackerBefore, r.attackerDead, r.attackerWounded, 3)
		kids.d = battleSide((if mineAttacker then t("rep.enemy") else t("rep.you")) .. " · " .. r.defender, r.defenderBefore, r.defenderDead, r.defenderWounded, 4)
		if next(r.loot) then
			kids.lootTitle = C.text({ text = "💰 " .. t("rep.loot"), size = 15, font = "bold", color = "gold", LayoutOrder = 5 })
			kids.loot = e("Frame", { Size = UDim2.new(1, 0, 0, px(28)), BackgroundTransparency = 1, LayoutOrder = 6 }, { row = C.costRow(r.loot) })
		end
	elseif r.kind == "hunt" then
		kids.damage = e("Frame", { Size = UDim2.new(1, 0, 0, px(20)), BackgroundTransparency = 1, LayoutOrder = 2 }, {
			bar = C.progress(r.hpLeft / r.maxHp, "red", 20, t("ui.damage", { v = Format.thousands(r.damage) }) .. "  ·  " .. t("ui.hp", { v = Format.short(r.hpLeft), max = Format.short(r.maxHp) })),
		})
		kids.rewardsTitle = C.text({ text = "🎁 " .. t("rep.rewards"), size = 15, font = "bold", color = "gold", LayoutOrder = 3 })
		kids.rewards = e("Frame", { Size = UDim2.new(1, 0, 0, px(28)), BackgroundTransparency = 1, LayoutOrder = 4 }, { row = C.costRow(r.rewards) })
		if r.hero then
			kids.hero = C.text({ text = "🦸 " .. t("hero." .. r.hero) .. "  +" .. r.heroXp .. " XP", size = 14, color = "purple", font = "bold", LayoutOrder = 5 })
		end
	elseif r.kind == "scout" then
		kids.info = C.text({
			text = "🏰 " .. t("b.keep") .. " " .. r.keep .. "  ·  🧱 " .. t("b.wall") .. " " .. r.wall .. "  ·  ⚔ " .. Format.thousands(r.power) .. (if r.shielded then "  ·  🛡️" else ""),
			size = 14,
			font = "bold",
			LayoutOrder = 2,
		})
		kids.exact = C.text({ text = if r.exact then t("rep.exact") else t("rep.approx"), size = 12, color = "muted", wrap = true, LayoutOrder = 3, Size = UDim2.new(1, 0, 0, px(30)) })
		local rows = {}
		for id, n in r.troops do
			rows[id] = { n }
		end
		kids.troops = C.panel({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4 }, {
			_pad = C.padding(12),
			t = troopTable({ { t("ui.troops"), "text" } }, rows),
		}, "flat")
		kids.res = e("Frame", { Size = UDim2.new(1, 0, 0, px(28)), BackgroundTransparency = 1, LayoutOrder = 5 }, { row = C.costRow(r.resources) })
	end
	return C.scroll({ Size = UDim2.fromScale(1, 1) }, kids)
end

function Reports.render(state: any, actions: any): Kit.Element
	local reports = state.view.reports
	local list: { [any]: any } = { _list = C.list("y", 6) }
	local selected = nil
	for i, r in reports do
		if r.id == state.selected.report then
			selected = r
		end
		local icon, title, color = Reports.summary(r)
		list[i] = e("TextButton", {
			Size = UDim2.new(1, -px(8), 0, px(56)),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			Text = "",
			LayoutOrder = i,
			onActivated = function()
				actions.openReport(r.id)
			end,
		}, {
			_corner = C.corner(12),
			_gradient = if r.id == state.selected.report then C.gradient("panelHi", "panel2") else C.gradient("panel2", "panel"),
			_stroke = C.stroke(if r.read then "line" else color, 1.5, if r.read then 0.5 else 0),
			icon = C.text({ text = icon, size = 24, align = "Center", Size = UDim2.fromOffset(px(50), px(56)) }),
			title = C.text({ text = title, size = 14, font = "bold", color = color, Position = UDim2.fromOffset(px(50), px(8)), Size = UDim2.new(1, -px(60), 0, px(20)) }),
			time = C.text({ text = t("ui.ago", { time = Format.duration(state.now - r.t) }), size = 12, color = "faint", Position = UDim2.fromOffset(px(50), px(30)), Size = UDim2.new(1, -px(60), 0, px(16)) }),
			dot = if r.read then nil else e("Frame", { Position = UDim2.fromOffset(px(6), px(6)), Size = UDim2.fromOffset(px(10), px(10)), BackgroundColor3 = Theme.color("red") }, { _corner = C.round() }),
		})
	end
	if #reports == 0 then
		list.empty = C.text({ text = t("ui.noReports"), size = 15, color = "muted", wrap = true, Size = UDim2.new(1, 0, 0, px(60)) })
	end
	selected = selected or reports[1]
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		_pad = C.padding(18),
		title = C.text({ text = "📨 " .. t("nav.reports"), size = 26, font = "title", color = "gold", Size = UDim2.new(0.5, 0, 0, px(34)) }),
		read = if state.view.unread > 0
			then C.button({
				text = "✔ " .. t("ui.markRead"),
				variant = "ghost",
				textSize = 14,
				size = UDim2.fromOffset(px(170), px(36)),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				onClick = actions.readReports,
			})
			else nil,
		list = C.scroll({ Position = UDim2.fromOffset(0, px(48)), Size = UDim2.new(0.42, -px(8), 1, -px(48)) }, list),
		detail = if selected
			then C.panel({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, px(48)), Size = UDim2.new(0.58, -px(8), 1, -px(48)) }, {
				_pad = C.padding(16),
				body = detail(state, selected),
			}, "hi")
			else nil,
	})
end

-- Totals used by tests and the battle summary.
function Reports.lost(r: any): number
	return Army.total(r.attackerDead or {}) + Army.total(r.defenderDead or {})
end

return Reports
