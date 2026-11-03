--!strict
-- Hand-drawn icon set: every icon is built from plain GUI shapes (circles, rounded bars,
-- rotated squares) in one flat sticker style: solid fills, one dark outline, a small shine.
-- Icons are drawn in a square box (0..1 coordinates) and scale with whatever size they get.

local Icons = {}

local OUTLINE = Color3.fromRGB(28, 22, 48)

local C = {
	Gold = Color3.fromRGB(255, 201, 60),
	GoldDark = Color3.fromRGB(232, 150, 28),
	Gem = Color3.fromRGB(79, 216, 255),
	GemDark = Color3.fromRGB(40, 150, 230),
	Red = Color3.fromRGB(240, 70, 80),
	Green = Color3.fromRGB(110, 214, 90),
	GreenDark = Color3.fromRGB(60, 160, 70),
	Blue = Color3.fromRGB(70, 140, 255),
	Purple = Color3.fromRGB(170, 100, 255),
	Pink = Color3.fromRGB(255, 110, 190),
	White = Color3.fromRGB(255, 255, 255),
	Paper = Color3.fromRGB(255, 248, 232),
	Wood = Color3.fromRGB(205, 140, 80),
	WoodDark = Color3.fromRGB(150, 95, 55),
	Steel = Color3.fromRGB(170, 180, 200),
	Ink = Color3.fromRGB(28, 22, 48),
}

type Opts = {
	Rotation: number?,
	Radius: number?, -- corner radius as a fraction of the shape (0.5 = circle/pill)
	Stroke: number?, -- outline thickness in pixels (0 = none)
	StrokeColor: Color3?,
	Transparency: number?,
	Z: number?,
	Ring: boolean?, -- only the outline (for handles, shackles, loops)
}

-- One shape centered at (x, y) with size (w, h), all in 0..1 of the icon box.
local function shape(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, opts: Opts?): Frame
	local o: Opts = opts or {}
	local frame = Instance.new("Frame")
	frame.Name = "Shape"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(x, y)
	frame.Size = UDim2.fromScale(w, h)
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = if o.Ring then 1 else (o.Transparency or 0)
	frame.Rotation = o.Rotation or 0
	frame.ZIndex = o.Z or 2
	local radius = o.Radius or 0.18
	if radius > 0 then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(radius, 0)
		corner.Parent = frame
	end
	local thickness = o.Stroke or 2.5
	if thickness > 0 then
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = thickness
		stroke.Color = o.StrokeColor or OUTLINE
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Parent = frame
	end
	frame.Parent = parent
	return frame
end

-- A loop (handle, shackle, arrow ring) with a dark outline on both edges.
local function ring(
	parent: Instance,
	x: number,
	y: number,
	w: number,
	h: number,
	color: Color3,
	thickness: number,
	z: number?
)
	local base = z or 2
	shape(
		parent,
		x,
		y,
		w,
		h,
		OUTLINE,
		{ Radius = 0.5, Ring = true, Stroke = thickness + 4, StrokeColor = OUTLINE, Z = base }
	)
	shape(
		parent,
		x,
		y,
		w,
		h,
		color,
		{ Radius = 0.5, Ring = true, Stroke = thickness, StrokeColor = color, Z = base + 1 }
	)
end

local function shine(parent: Instance, x: number, y: number, w: number, h: number)
	shape(parent, x, y, w, h, C.White, { Radius = 0.5, Stroke = 0, Transparency = 0.35, Z = 6 })
end

local function glyph(parent: Instance, text: string, x: number, y: number, size: number, color: Color3)
	local label = Instance.new("TextLabel")
	label.Name = "Glyph"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(x, y)
	label.Size = UDim2.fromScale(size, size)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color
	label.ZIndex = 7
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = OUTLINE
	stroke.Parent = label
	label.Parent = parent
end

-- Thick "^" made of two bars; points up at (x, y) before rotation of the whole group.
local function chevron(
	parent: Instance,
	x: number,
	y: number,
	size: number,
	color: Color3,
	rotation: number,
	z: number?
)
	local rad = math.rad(rotation)
	local function rotated(dx: number, dy: number): (number, number)
		return x + dx * math.cos(rad) - dy * math.sin(rad), y + dx * math.sin(rad) + dy * math.cos(rad)
	end
	local ax, ay = rotated(-size * 0.2, size * 0.18)
	local bx, by = rotated(size * 0.2, size * 0.18)
	shape(parent, ax, ay, size * 0.62, size * 0.24, color, { Rotation = rotation - 45, Radius = 0.5, Z = z })
	shape(parent, bx, by, size * 0.62, size * 0.24, color, { Rotation = rotation + 45, Radius = 0.5, Z = z })
end

local DRAW: { [string]: (Frame) -> () } = {}

DRAW.Coin = function(f)
	shape(f, 0.5, 0.54, 0.84, 0.84, C.GoldDark, { Radius = 0.5 })
	shape(f, 0.5, 0.48, 0.84, 0.84, C.Gold, { Radius = 0.5, Z = 3 })
	shape(f, 0.5, 0.48, 0.58, 0.58, C.GoldDark, { Radius = 0.5, Stroke = 0, Transparency = 0.55, Z = 4 })
	glyph(f, "$", 0.5, 0.49, 0.5, C.White)
	shine(f, 0.32, 0.27, 0.16, 0.1)
end

DRAW.Gem = function(f)
	shape(f, 0.5, 0.52, 0.6, 0.6, C.GemDark, { Rotation = 45, Radius = 0.12 })
	shape(f, 0.5, 0.45, 0.44, 0.44, C.Gem, { Rotation = 45, Radius = 0.12, Stroke = 0, Z = 3 })
	shine(f, 0.42, 0.34, 0.12, 0.12)
end

DRAW.Shop = function(f)
	ring(f, 0.5, 0.36, 0.4, 0.44, C.White, 4, 2)
	shape(f, 0.5, 0.64, 0.74, 0.58, C.Pink, { Radius = 0.16, Z = 4 })
	shape(f, 0.5, 0.42, 0.74, 0.1, C.Red, { Radius = 0.3, Stroke = 0, Z = 5 })
	shine(f, 0.3, 0.56, 0.1, 0.22)
end

DRAW.Rebirth = function(f)
	ring(f, 0.5, 0.5, 0.62, 0.62, C.White, 6, 2)
	-- arrowheads riding the loop (top-right points down, bottom-left points up)
	chevron(f, 0.81, 0.5, 0.46, C.White, 180, 5)
	chevron(f, 0.19, 0.5, 0.46, C.White, 0, 5)
end

DRAW.Upgrade = function(f)
	shape(f, 0.5, 0.64, 0.24, 0.5, C.White, { Radius = 0.4 })
	chevron(f, 0.5, 0.36, 0.72, C.White, 0, 3)
	shine(f, 0.45, 0.6, 0.06, 0.2)
end

DRAW.Slime = function(f)
	shape(f, 0.5, 0.82, 0.92, 0.22, C.GreenDark, { Radius = 0.5 })
	shape(f, 0.5, 0.58, 0.8, 0.62, C.Green, { Radius = 0.48, Z = 3 })
	for _, x in { 0.38, 0.62 } do
		shape(f, x, 0.56, 0.13, 0.17, C.Ink, { Radius = 0.5, Stroke = 0, Z = 5 })
		shape(f, x - 0.02, 0.52, 0.05, 0.05, C.White, { Radius = 0.5, Stroke = 0, Z = 6 })
	end
	shape(f, 0.5, 0.7, 0.14, 0.05, C.Ink, { Radius = 0.5, Stroke = 0, Z = 5 })
	shine(f, 0.3, 0.4, 0.12, 0.08)
end

DRAW.Index = function(f)
	shape(f, 0.5, 0.56, 0.86, 0.66, C.Purple, { Radius = 0.12 })
	shape(f, 0.31, 0.52, 0.36, 0.58, C.Paper, { Radius = 0.1, Rotation = -6, Z = 3 })
	shape(f, 0.69, 0.52, 0.36, 0.58, C.Paper, { Radius = 0.1, Rotation = 6, Z = 3 })
	for i = 0, 2 do
		shape(f, 0.31, 0.4 + i * 0.1, 0.22, 0.04, C.Steel, { Radius = 0.5, Stroke = 0, Rotation = -6, Z = 4 })
		shape(f, 0.69, 0.4 + i * 0.1, 0.22, 0.04, C.Steel, { Radius = 0.5, Stroke = 0, Rotation = 6, Z = 4 })
	end
end

DRAW.Daily = function(f)
	shape(f, 0.5, 0.58, 0.78, 0.66, C.Paper, { Radius = 0.14 })
	shape(f, 0.5, 0.33, 0.78, 0.2, C.Red, { Radius = 0.3, Z = 3 })
	for _, x in { 0.33, 0.67 } do
		shape(f, x, 0.22, 0.08, 0.18, C.Steel, { Radius = 0.5, Z = 4 })
	end
	glyph(f, "1", 0.5, 0.64, 0.42, C.Red)
end

DRAW.Gift = function(f)
	for _, side in { -1, 1 } do
		shape(f, 0.5 + side * 0.13, 0.22, 0.24, 0.18, C.Gold, { Radius = 0.5, Rotation = side * 25 })
	end
	shape(f, 0.5, 0.66, 0.7, 0.48, C.Purple, { Radius = 0.12, Z = 3 })
	shape(f, 0.5, 0.39, 0.82, 0.18, C.Purple, { Radius = 0.2, Z = 4 })
	shape(f, 0.5, 0.56, 0.14, 0.7, C.Gold, { Radius = 0.2, Z = 5 })
	shine(f, 0.27, 0.56, 0.06, 0.18)
end

DRAW.Trade = function(f)
	shape(f, 0.44, 0.33, 0.54, 0.16, C.Green, { Radius = 0.5 })
	chevron(f, 0.72, 0.33, 0.38, C.Green, 90, 3)
	shape(f, 0.56, 0.67, 0.54, 0.16, C.Blue, { Radius = 0.5 })
	chevron(f, 0.28, 0.67, 0.38, C.Blue, -90, 3)
end

DRAW.Bonk = function(f)
	shape(f, 0.5, 0.55, 0.2, 0.84, C.Wood, { Radius = 0.5, Rotation = 40 })
	shape(f, 0.27, 0.8, 0.14, 0.26, C.WoodDark, { Radius = 0.5, Rotation = 40, Z = 3 })
	shape(f, 0.79, 0.21, 0.2, 0.2, C.Gold, { Radius = 0.1, Rotation = 45, Z = 4 })
	shape(f, 0.79, 0.21, 0.2, 0.2, C.Gold, { Radius = 0.1, Z = 4 })
	shine(f, 0.55, 0.4, 0.05, 0.22)
end

local function lock(f: Frame, open: boolean)
	local x = if open then 0.66 else 0.5
	local y = if open then 0.26 else 0.33
	ring(f, x, y, 0.4, 0.44, C.Steel, 5, 1)
	shape(f, 0.5, 0.66, 0.72, 0.5, C.Gold, { Radius = 0.18, Z = 3 })
	shape(f, 0.5, 0.62, 0.14, 0.14, C.Ink, { Radius = 0.5, Stroke = 0, Z = 4 })
	shape(f, 0.5, 0.72, 0.07, 0.16, C.Ink, { Radius = 0.4, Stroke = 0, Z = 4 })
	shine(f, 0.27, 0.58, 0.06, 0.16)
end

DRAW.Lock = function(f)
	lock(f, false)
end

DRAW.Unlock = function(f)
	lock(f, true)
end

DRAW.Speed = function(f)
	shape(f, 0.16, 0.34, 0.2, 0.08, C.White, { Radius = 0.5, Stroke = 2 })
	shape(f, 0.12, 0.66, 0.16, 0.08, C.White, { Radius = 0.5, Stroke = 2 })
	chevron(f, 0.48, 0.5, 0.66, C.Gold, 90, 3)
	chevron(f, 0.74, 0.5, 0.66, C.GoldDark, 90, 4)
end

DRAW.Luck = function(f)
	shape(f, 0.58, 0.82, 0.08, 0.3, C.GreenDark, { Radius = 0.5, Rotation = -25 })
	for _, p in { { 0.5, 0.28 }, { 0.72, 0.5 }, { 0.5, 0.72 }, { 0.28, 0.5 } } do
		shape(f, p[1], p[2], 0.38, 0.38, C.Green, { Radius = 0.5, Z = 3 })
	end
	shape(f, 0.5, 0.5, 0.2, 0.2, C.GreenDark, { Radius = 0.5, Stroke = 0, Z = 4 })
end

DRAW.Star = function(f)
	shape(f, 0.5, 0.5, 0.56, 0.56, C.Gold, { Radius = 0.12 })
	shape(f, 0.5, 0.5, 0.56, 0.56, C.Gold, { Radius = 0.12, Rotation = 45, Z = 3 })
	shape(f, 0.5, 0.5, 0.3, 0.3, C.White, { Radius = 0.5, Stroke = 0, Transparency = 0.5, Z = 4 })
end

DRAW.Crown = function(f)
	for i, x in { 0.24, 0.5, 0.76 } do
		shape(f, x, if i == 2 then 0.38 else 0.44, 0.26, 0.26, C.Gold, { Rotation = 45, Radius = 0.1 })
		shape(f, x, if i == 2 then 0.22 else 0.28, 0.1, 0.1, C.Red, { Radius = 0.5, Z = 4 })
	end
	shape(f, 0.5, 0.64, 0.76, 0.3, C.Gold, { Radius = 0.15, Z = 3 })
	shape(f, 0.5, 0.64, 0.12, 0.12, C.Red, { Radius = 0.5, Z = 4 })
end

DRAW.Cash = function(f)
	shape(f, 0.54, 0.58, 0.8, 0.46, C.GreenDark, { Radius = 0.12, Rotation = -8 })
	shape(f, 0.46, 0.46, 0.8, 0.46, C.Green, { Radius = 0.12, Rotation = -8, Z = 3 })
	shape(f, 0.46, 0.46, 0.22, 0.22, C.GreenDark, { Radius = 0.5, Stroke = 0, Z = 4 })
	glyph(f, "$", 0.46, 0.47, 0.24, C.White)
end

DRAW.Egg = function(f)
	shape(f, 0.5, 0.54, 0.62, 0.8, C.Paper, { Radius = 0.5 })
	for _, p in { { 0.4, 0.42, 0.14 }, { 0.62, 0.58, 0.18 }, { 0.42, 0.72, 0.1 } } do
		shape(f, p[1], p[2], p[3], p[3], C.Pink, { Radius = 0.5, Stroke = 0, Z = 3 })
	end
	shine(f, 0.36, 0.3, 0.08, 0.14)
end

DRAW.Pedestal = function(f)
	shape(f, 0.5, 0.82, 0.82, 0.18, C.Steel, { Radius = 0.3 })
	shape(f, 0.5, 0.58, 0.46, 0.34, C.Paper, { Radius = 0.12, Z = 3 })
	shape(f, 0.5, 0.36, 0.66, 0.14, C.Steel, { Radius = 0.3, Z = 4 })
	shape(f, 0.5, 0.2, 0.26, 0.2, C.Green, { Radius = 0.5, Z = 5 })
end

DRAW.Hatch = function(f)
	chevron(f, 0.36, 0.5, 0.62, C.Blue, 90)
	chevron(f, 0.66, 0.5, 0.62, C.Blue, 90, 3)
end

DRAW.Trophy = function(f)
	shape(f, 0.5, 0.86, 0.56, 0.14, C.WoodDark, { Radius = 0.3 })
	shape(f, 0.5, 0.72, 0.12, 0.2, C.GoldDark, { Radius = 0.3 })
	for _, side in { -1, 1 } do
		ring(f, 0.5 + side * 0.3, 0.36, 0.2, 0.24, C.Gold, 3, 1)
	end
	shape(f, 0.5, 0.4, 0.5, 0.46, C.Gold, { Radius = 0.3, Z = 3 })
	shine(f, 0.38, 0.34, 0.06, 0.18)
end

-- Old names used around the UI.
DRAW.Coins = DRAW.Coin
DRAW.Gems = DRAW.Gem
DRAW.Training = DRAW.Speed
DRAW.Pedestals = DRAW.Pedestal
DRAW.Incubators = DRAW.Egg

function Icons.Has(key: string): boolean
	return DRAW[key] ~= nil
end

-- Draws icon `key` into a new square frame. Size/position/anchor work like any GuiObject.
function Icons.Draw(parent: Instance, key: string, size: UDim2?, position: UDim2?, anchor: Vector2?): Frame
	local box = Instance.new("Frame")
	box.Name = "Icon"
	box.BackgroundTransparency = 1
	box.Size = size or UDim2.fromOffset(40, 40)
	box.Position = position or UDim2.new()
	box.AnchorPoint = anchor or Vector2.zero
	box.ZIndex = 2
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = box
	local draw = DRAW[key] or DRAW.Star
	draw(box)
	box.Parent = parent
	return box
end

return Icons
