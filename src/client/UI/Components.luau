--!strict
-- Building blocks shared by every screen: panels, buttons, bars, pills and modals in the game's style.

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Rules.Balance)
local Format = require(Shared.Rules.Format)
local Locale = require(Shared.Locale)

local e = Kit.e
local px = Theme.px
local C = {}

-- Static lookups: indexing an Enum with a runtime string is unsafe for the type checker.
local HALIGN = {
	Left = Enum.HorizontalAlignment.Left,
	Center = Enum.HorizontalAlignment.Center,
	Right = Enum.HorizontalAlignment.Right,
}
local VALIGN = {
	Top = Enum.VerticalAlignment.Top,
	Center = Enum.VerticalAlignment.Center,
	Bottom = Enum.VerticalAlignment.Bottom,
}
local TEXT_X =
	{ Left = Enum.TextXAlignment.Left, Center = Enum.TextXAlignment.Center, Right = Enum.TextXAlignment.Right }
local TEXT_Y =
	{ Top = Enum.TextYAlignment.Top, Center = Enum.TextYAlignment.Center, Bottom = Enum.TextYAlignment.Bottom }

C.e = e
C.t = Locale.t

function C.merge(...: { [string]: any }?): { [string]: any }
	local out = {}
	for i = 1, select("#", ...) do
		local t = select(i, ...)
		if t then
			for k, v in t do
				out[k] = v
			end
		end
	end
	return out
end

-- Layout decorations ----------------------------------------------------------------------------------------------------

function C.corner(r: number?): Kit.Element
	return e("UICorner", { CornerRadius = UDim.new(0, px(r or 12)) })
end

function C.round(): Kit.Element
	return e("UICorner", { CornerRadius = UDim.new(1, 0) })
end

function C.stroke(color: string?, thickness: number?, transparency: number?): Kit.Element
	return e("UIStroke", {
		Color = Theme.color(color or "line"),
		Thickness = math.max(1, px(thickness or 1.5)),
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function C.padding(t: number, r: number?, b: number?, l: number?): Kit.Element
	return e("UIPadding", {
		PaddingTop = UDim.new(0, px(t)),
		PaddingRight = UDim.new(0, px(r or t)),
		PaddingBottom = UDim.new(0, px(b or t)),
		PaddingLeft = UDim.new(0, px(l or r or t)),
	})
end

function C.list(direction: string?, gap: number?, halign: string?, valign: string?): Kit.Element
	return e("UIListLayout", {
		FillDirection = if direction == "x" then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, px(gap or 8)),
		HorizontalAlignment = HALIGN[halign or "Left"],
		VerticalAlignment = VALIGN[valign or "Top"],
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function C.grid(w: number, h: number, gap: number?): Kit.Element
	return e("UIGridLayout", {
		CellSize = UDim2.fromOffset(px(w), px(h)),
		CellPadding = UDim2.fromOffset(px(gap or 10), px(gap or 10)),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	})
end

function C.gradient(top: string, bottom: string, rotation: number?): Kit.Element
	return e("UIGradient", {
		Color = ColorSequence.new(Theme.color(top), Theme.color(bottom)),
		Rotation = rotation or 90,
	})
end

-- Text ------------------------------------------------------------------------------------------------------------------

export type TextProps = {
	text: string,
	size: number?,
	color: string?,
	font: string?,
	align: string?,
	valign: string?,
	wrap: boolean?,
	[string]: any,
}

function C.text(p: TextProps): Kit.Element
	local props = {
		BackgroundTransparency = 1,
		Text = p.text,
		TextSize = px(p.size or 16),
		TextColor3 = Theme.color(p.color or "text"),
		Font = Theme.fonts[p.font or "body"],
		TextXAlignment = TEXT_X[p.align or "Left"],
		TextYAlignment = TEXT_Y[p.valign or "Center"],
		TextWrapped = p.wrap or false,
		TextTruncate = if p.wrap then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, px((p.size or 16) + 6)),
	}
	for k, v in p :: any do
		if string.match(k, "^%u") then
			props[k] = v
		end
	end
	return e("TextLabel", props)
end

-- Surfaces --------------------------------------------------------------------------------------------------------------

function C.panel(props: { [string]: any }?, children: { [any]: any }?, style: string?): Kit.Element
	local kids = C.merge(children)
	kids._corner = C.corner(14)
	kids._stroke = C.stroke(if style == "hi" then "gold" else "line", 1.5, if style == "hi" then 0.2 else 0.35)
	if style ~= "flat" then
		kids._gradient = if style == "hi" then C.gradient("panelHi", "panel") else C.gradient("panel2", "panel")
	end
	-- A flat panel has no gradient to tint, so it takes the panel colour directly.
	local background = if style == "flat" then Theme.color("panel2") else Color3.fromRGB(255, 255, 255)
	return e("Frame", C.merge({ BackgroundColor3 = background, BorderSizePixel = 0 }, props), kids)
end

local VARIANTS = {
	gold = { "gold", "goldDeep", "#3A2600" },
	green = { "green", "greenDeep", "#082A14" },
	blue = { "blue", "blueDeep", "#FFFFFF" },
	red = { "red", "redDeep", "#FFFFFF" },
	ghost = { "panelHi", "panel2", "text" },
	dark = { "bg2", "bg", "muted" },
}

export type ButtonProps = {
	text: string,
	variant: string?,
	size: UDim2?,
	disabled: boolean?,
	onClick: (() -> ())?,
	textSize: number?,
	[string]: any,
}

function C.button(p: ButtonProps): Kit.Element
	local v = VARIANTS[if p.disabled then "dark" else p.variant or "gold"]
	local props = {
		Size = p.size or UDim2.fromOffset(px(140), px(44)),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		AutoButtonColor = not p.disabled,
		Text = p.text,
		TextSize = px(p.textSize or 17),
		TextColor3 = Theme.color(v[3]),
		Font = Theme.fonts.title,
		BorderSizePixel = 0,
		onActivated = if p.disabled then nil else p.onClick,
	}
	for k, val in p :: any do
		if string.match(k, "^%u") then
			props[k] = val
		end
	end
	return e("TextButton", props, {
		_corner = C.corner(12),
		_gradient = C.gradient(v[1], v[2]),
		_stroke = C.stroke(if p.disabled then "line" else v[2], 2, if p.disabled then 0.5 else 0),
	})
end

function C.iconButton(
	icon: string,
	label: string,
	onClick: (() -> ())?,
	size: number?,
	props: { [string]: any }?
): Kit.Element
	local s = size or 44
	return e(
		"TextButton",
		C.merge({
			Size = UDim2.fromOffset(px(s), px(s)),
			BackgroundColor3 = Theme.color("panel2"),
			Text = icon,
			TextSize = px(s * 0.5),
			Font = Theme.fonts.bold,
			TextColor3 = Theme.color("text"),
			AutoButtonColor = true,
			onActivated = onClick,
			-- Icon-only: the accessible name lives in the instance name used by screen readers and tests.
			Name = label,
		}, props),
		{ _corner = C.corner(12), _stroke = C.stroke("line", 1.5, 0.3) }
	)
end

function C.progress(fraction: number, color: string?, height: number?, label: string?): Kit.Element
	local f = math.clamp(fraction, 0, 1)
	local base = color or "green"
	local deep = if Theme.colors[base .. "Deep"] then base .. "Deep" else base
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, px(height or 10)),
		BackgroundColor3 = Theme.color("bg"),
		BorderSizePixel = 0,
	}, {
		_corner = C.round(),
		fill = e("Frame", {
			Size = UDim2.new(f, 0, 1, 0),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BorderSizePixel = 0,
			Visible = f > 0,
		}, {
			_corner = C.round(),
			_gradient = C.gradient(base, deep, 0),
		}),
		label = if label
			then C.text({
				text = label,
				size = math.max(11, (height or 10) - 6),
				font = "bold",
				align = "Center",
				Size = UDim2.fromScale(1, 1),
				ZIndex = 2,
			})
			else nil,
	})
end

function C.badge(text: string, color: string?, props: { [string]: any }?): Kit.Element
	return e(
		"TextLabel",
		C.merge({
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(px(22), px(22)),
			BackgroundColor3 = Theme.color(color or "red"),
			Text = text,
			TextSize = px(13),
			Font = Theme.fonts.black,
			TextColor3 = Theme.color("text"),
			BorderSizePixel = 0,
		}, props),
		{ _corner = C.round(), _pad = C.padding(0, 6, 0, 6) }
	)
end

-- A resource amount with its icon, red when there is not enough.
function C.costItem(res: string, amount: number, have: number?): Kit.Element
	local short = have ~= nil and have < amount
	return e("Frame", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, px(28)),
		BackgroundColor3 = Theme.color(if short then "redDeep" else "bg2"),
		BackgroundTransparency = if short then 0.55 else 0.2,
		BorderSizePixel = 0,
	}, {
		_corner = C.corner(8),
		_pad = C.padding(0, 8, 0, 6),
		_list = C.list("x", 4, "Left", "Center"),
		icon = C.text({
			text = Balance.RESOURCE_ICONS[res],
			size = 15,
			Size = UDim2.fromOffset(px(20), px(26)),
			align = "Center",
		}),
		amount = C.text({
			text = Format.short(amount),
			size = 15,
			font = "bold",
			color = if short then "red" else "text",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, px(26)),
		}),
	})
end

function C.costRow(cost: { [string]: number }, resources: { [string]: number }?): Kit.Element
	local kids: { [any]: any } = { _list = C.list("x", 6, "Left", "Center") }
	for i, res in Balance.RESOURCES do
		if cost[res] and cost[res] > 0 then
			kids[i] = C.costItem(res, cost[res], if resources then resources[res] else nil)
		end
	end
	return e("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, px(28)) }, kids)
end

-- A centred dialog over a dimmed backdrop. Clicking the backdrop or ✕ closes it.
function C.modal(title: string, w: number, h: number, onClose: () -> (), body: { [any]: any }): Kit.Element
	local dw, dh = Theme.designSize()
	local width = math.min(w, dw - 24)
	local height = math.min(h, dh - 24)
	return e("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.color("shadow"),
		BackgroundTransparency = 0.35,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 50,
		onActivated = onClose,
	}, {
		dialog = C.panel({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(px(width), px(height)),
			ZIndex = 51,
			Active = true,
		}, {
			header = e("Frame", {
				Size = UDim2.new(1, 0, 0, px(56)),
				BackgroundColor3 = Theme.color("panelHi"),
				BorderSizePixel = 0,
				ZIndex = 52,
			}, {
				_corner = C.corner(14),
				_gradient = C.gradient("panelHi", "panel2"),
				title = C.text({
					text = title,
					size = 24,
					font = "title",
					color = "gold",
					Position = UDim2.fromOffset(px(20), 0),
					Size = UDim2.new(1, -px(80), 1, 0),
					ZIndex = 53,
				}),
				close = C.iconButton("✕", C.t("ui.close"), onClose, 38, {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -px(10), 0.5, 0),
					ZIndex = 53,
				}),
			}),
			body = e("Frame", {
				Position = UDim2.fromOffset(0, px(56)),
				Size = UDim2.new(1, 0, 1, -px(56)),
				BackgroundTransparency = 1,
				ZIndex = 52,
			}, C.merge({ _pad = C.padding(16, 20, 18, 20) }, body)),
		}, "hi"),
	})
end

function C.spacer(h: number): Kit.Element
	return e("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, px(h)) })
end

function C.scroll(props: { [string]: any }, children: { [any]: any }): Kit.Element
	return e(
		"ScrollingFrame",
		C.merge({
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = px(6),
			ScrollBarImageColor3 = Theme.color("line"),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			ScrollingDirection = Enum.ScrollingDirection.Y,
		}, props),
		children
	)
end

return C
