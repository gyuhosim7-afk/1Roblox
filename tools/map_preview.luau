-- Top-down render of the generated map (parts as rectangles) to an HTML/SVG file.
-- Usage: lune run tools/map_preview <minZ> <maxZ> <out.html>
local fs = require("@lune/fs")
local process = require("@lune/process")
local World = require("../tests/harness/World")

local minZ = tonumber(process.args[1]) or -300
local maxZ = tonumber(process.args[2]) or 900
local outPath = process.args[3] or "build/map.html"

local world = World.new()
world:StartServer()
local MapLayout = world:Require("ReplicatedStorage/Shared/MapLayout")
local map = world.workspace:FindFirstChild("Map")

local halfWidth = 160
local scale = 900 / (maxZ - minZ)
local width = math.floor(halfWidth * 2 * scale)
local height = 900
local parts = {}
for _, d in map:GetDescendants() do
	if d:IsA("BasePart") and d.Transparency < 1 then
		table.insert(parts, d)
	end
end
-- draw low parts first
table.sort(parts, function(a, b)
	return (a.Position.Y + a.Size.Y / 2) < (b.Position.Y + b.Size.Y / 2)
end)

local out = {
	string.format(
		"<!doctype html><html><body style='margin:0;background:#222'><svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d'>",
		width,
		height
	),
}
local function tx(x)
	return (x + halfWidth) * scale
end
local function tz(z)
	return height - (z - minZ) * scale
end
for _, p in parts do
	local pos, size = p.Position, p.Size
	local cf = p.CFrame
	-- approximate rotated footprint with axis-aligned extents
	local right, look = cf.RightVector, cf.LookVector
	local ex = math.abs(right.X) * size.X + math.abs(look.X) * size.Z
	local ez = math.abs(right.Z) * size.X + math.abs(look.Z) * size.Z
	if pos.Z + ez / 2 >= minZ and pos.Z - ez / 2 <= maxZ then
		local c = p.Color
		table.insert(
			out,
			string.format(
				"<rect x='%.1f' y='%.1f' width='%.1f' height='%.1f' fill='rgb(%d,%d,%d)' fill-opacity='%.2f'/>",
				tx(pos.X - ex / 2),
				tz(pos.Z + ez / 2),
				math.max(ex * scale, 0.5),
				math.max(ez * scale, 0.5),
				c.R * 255,
				c.G * 255,
				c.B * 255,
				1 - p.Transparency
			)
		)
	end
end
-- guards (red) and nests (yellow dots)
for _, zone in MapLayout.Zones do
	for _, g in zone.Guards do
		if g.Z >= minZ and g.Z <= maxZ then
			if g.Kind == "Patrol" then
				table.insert(out, string.format("<line x1='%.1f' y1='%.1f' x2='%.1f' y2='%.1f' stroke='red' stroke-width='2'/>", tx(-g.Amplitude), tz(g.Z), tx(g.Amplitude), tz(g.Z)))
			else
				table.insert(out, string.format("<circle cx='%.1f' cy='%.1f' r='%.1f' fill='none' stroke='orange' stroke-width='2'/>", tx(g.X), tz(g.Z), g.Amplitude * scale))
			end
		end
	end
end
table.insert(out, "</svg></body></html>")
fs.writeFile(outPath, table.concat(out, "\n"))
print("wrote", outPath, width, height)
