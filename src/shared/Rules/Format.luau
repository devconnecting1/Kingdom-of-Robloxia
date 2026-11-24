--!strict
-- Number and time formatting shared by the UI and the reports.

local Format = {}

-- 950 → "950", 12_400 → "12.4K", 3_250_000 → "3.25M".
function Format.short(n: number): string
	local sign = if n < 0 then "-" else ""
	local a = math.abs(n)
	if a < 1000 then
		return sign .. tostring(math.floor(a))
	elseif a < 1e6 then
		return sign .. Format.trim(string.format("%.1f", a / 1e3)) .. "K"
	elseif a < 1e9 then
		return sign .. Format.trim(string.format("%.2f", a / 1e6)) .. "M"
	end
	return sign .. Format.trim(string.format("%.2f", a / 1e9)) .. "B"
end

function Format.trim(s: string): string
	local out = string.gsub(s, "%.?0+$", "")
	return out
end

-- 1234567 → "1,234,567".
function Format.thousands(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return (if n < 0 then "-" else "") .. out
end

-- 45 → "45s", 125 → "2m 05s", 3725 → "1h 02m", 90000 → "1d 01h".
function Format.duration(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	if s < 60 then
		return string.format("%ds", s)
	elseif s < 3600 then
		return string.format("%dm %02ds", s // 60, s % 60)
	elseif s < 86400 then
		return string.format("%dh %02dm", s // 3600, (s % 3600) // 60)
	end
	return string.format("%dd %02dh", s // 86400, (s % 86400) // 3600)
end

function Format.percent(fraction: number): string
	return Format.trim(string.format("%.1f", fraction * 100)) .. "%"
end

return Format
