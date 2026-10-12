--!strict
-- Number / time formatting for UI.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- 1234 -> "1.23K", 15 -> "15", 1.5e9 -> "1.5B"
function Format.Number(n: number): string
	if n ~= n then
		return "0"
	end
	local negative = n < 0
	local value = math.abs(n)
	if value < 1000 then
		local text
		if value == math.floor(value) then
			text = tostring(math.floor(value))
		else
			text = string.format("%.1f", value):gsub("%.0$", "")
		end
		return (negative and "-" or "") .. text
	end
	local index = 1
	while value >= 1000 and index < #SUFFIXES do
		value /= 1000
		index += 1
	end
	local text
	if value >= 100 then
		text = string.format("%d", math.floor(value))
	elseif value >= 10 then
		text = string.format("%.1f", math.floor(value * 10) / 10)
	else
		text = string.format("%.2f", math.floor(value * 100) / 100)
	end
	if text:find("%.") then
		text = text:gsub("0+$", ""):gsub("%.$", "")
	end
	return (negative and "-" or "") .. text .. SUFFIXES[index]
end

-- 1234567 -> "1,234,567"
function Format.Commas(n: number): string
	local text = tostring(math.floor(math.abs(n)))
	local result = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if result:sub(1, 1) == "," then
		result = result:sub(2)
	end
	return (n < 0 and "-" or "") .. result
end

-- 65 -> "1:05", 3725 -> "1:02:05"
function Format.Clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	local h = s // 3600
	local m = (s % 3600) // 60
	local sec = s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, sec)
	end
	return string.format("%d:%02d", m, sec)
end

-- 65 -> "1m 5s", 3725 -> "1h 2m", 20 -> "20s"
function Format.Duration(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	if s < 60 then
		return string.format("%ds", s)
	elseif s < 3600 then
		local m = s // 60
		local r = s % 60
		return r > 0 and string.format("%dm %ds", m, r) or string.format("%dm", m)
	end
	local h = s // 3600
	local m = (s % 3600) // 60
	return m > 0 and string.format("%dh %dm", h, m) or string.format("%dh", h)
end

-- Probability (0..1) to percent text. Small values keep 4 significant digits past the first non-zero.
-- 0.6 -> "60%", 0.018 -> "1.8%", 0.0005 -> "0.05%", 0.000123456 -> "0.01235%"
function Format.Percent(p: number): string
	local percent = p * 100
	if percent <= 0 then
		return "0%"
	end
	if percent >= 100 then
		return "100%"
	end
	local text
	if percent >= 10 then
		text = string.format("%.2f", percent)
	elseif percent >= 1 then
		text = string.format("%.3f", percent)
	else
		-- digits after the decimal point needed to show 4 significant digits
		local magnitude = math.floor(math.log10(percent))
		local decimals = math.clamp(-magnitude + 3, 1, 10)
		text = string.format("%." .. decimals .. "f", percent)
	end
	if text:find("%.") then
		text = text:gsub("0+$", ""):gsub("%.$", "")
	end
	return text .. "%"
end

return Format
