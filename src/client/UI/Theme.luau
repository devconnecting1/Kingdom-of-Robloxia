--!strict
-- Colours, fonts and the scale every size goes through. The UI is designed at 1280×720 and scaled to the screen;
-- small screens (phones in landscape) switch to a compact layout instead of shrinking text past readability.

local Theme = {}

Theme.colors = {
	bg = "#0F1426",
	bg2 = "#161D36",
	panel = "#1C2444",
	panel2 = "#243058",
	panelHi = "#2E3C6E",
	line = "#3C4C86",
	text = "#F2F4FF",
	muted = "#A3AED6",
	faint = "#6C79A8",
	gold = "#FFC94A",
	goldDeep = "#E09B1A",
	green = "#4CD27A",
	greenDeep = "#22A453",
	red = "#FF5D6C",
	redDeep = "#C93245",
	blue = "#4DA3FF",
	blueDeep = "#2F6FE0",
	purple = "#A579FF",
	orange = "#FF9B42",
	grass = "#3E8E4F",
	grassDeep = "#2D6B3C",
	path = "#C9A46A",
	shadow = "#05070F",
	rare = "#4DA3FF",
	epic = "#A579FF",
	legendary = "#FFB13B",
}

Theme.biomes = {
	meadow = "#5DA34E",
	forest = "#2F7A43",
	hills = "#8E8A5C",
	lake = "#3B78C2",
	crown = "#B79A4E",
}

Theme.zoneTint = { "#5DA34E", "#6EA548", "#8B9D46", "#B79A4E" }

local function hexToRgb(hex: string): (number, number, number)
	local h = string.gsub(hex, "#", "")
	return tonumber(string.sub(h, 1, 2), 16) or 0, tonumber(string.sub(h, 3, 4), 16) or 0, tonumber(string.sub(h, 5, 6), 16) or 0
end

local cache: { [string]: Color3 } = {}
function Theme.color(nameOrHex: string): Color3
	local cached = cache[nameOrHex]
	if cached then
		return cached
	end
	local hex = Theme.colors[nameOrHex] or nameOrHex
	local r, g, b = hexToRgb(hex)
	local c = Color3.fromRGB(r, g, b)
	cache[nameOrHex] = c
	return c
end

-- Mixes a colour towards black (f < 0) or white (f > 0), in hex so it works the same outside Roblox.
function Theme.shade(nameOrHex: string, f: number): Color3
	local key = nameOrHex .. "@" .. f
	local cached = cache[key]
	if cached then
		return cached
	end
	local r, g, b = hexToRgb(Theme.colors[nameOrHex] or nameOrHex)
	local function mix(v: number): number
		if f < 0 then
			return math.floor(v * (1 + f) + 0.5)
		end
		return math.floor(v + (255 - v) * f + 0.5)
	end
	local c = Color3.fromRGB(mix(r), mix(g), mix(b))
	cache[key] = c
	return c
end

Theme.fonts = {
	title = Enum.Font.FredokaOne,
	bold = Enum.Font.GothamBold,
	body = Enum.Font.GothamMedium,
	black = Enum.Font.GothamBlack,
}

-- Scale ---------------------------------------------------------------------------------------------------------------

Theme.scale = 1
Theme.compact = false
-- Design pixels on the left of the top bar taken by Roblox's own menu and chat buttons.
Theme.safeLeft = 0
Theme.width = 1280
Theme.height = 720

function Theme.setViewport(w: number, h: number)
	Theme.width, Theme.height = w, h
	local s = math.min(w / 1280, h / 720)
	Theme.compact = s < 0.75
	if Theme.compact then
		s = math.min(w / 960, h / 540)
	end
	Theme.scale = math.max(0.5, s)
end

function Theme.px(n: number): number
	return math.floor(n * Theme.scale + 0.5)
end

-- Design-space size of the screen (what px() maps onto the real screen).
function Theme.designSize(): (number, number)
	return Theme.width / Theme.scale, Theme.height / Theme.scale
end

function Theme.udim(xs: number, xo: number, ys: number, yo: number): UDim2
	return UDim2.new(xs, Theme.px(xo), ys, Theme.px(yo))
end

function Theme.size(w: number, h: number): UDim2
	return UDim2.fromOffset(Theme.px(w), Theme.px(h))
end

return Theme
