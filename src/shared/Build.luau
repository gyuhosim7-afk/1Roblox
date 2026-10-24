--!strict
-- Small helpers for building parts and labels in code (we never use Toolbox models).

local Build = {}

export type PartProps = {
	Name: string?,
	Size: Vector3?,
	CFrame: CFrame?,
	Position: Vector3?,
	Color: (Color3 | string)?,
	Material: Enum.Material?,
	Shape: Enum.PartType?,
	Transparency: number?,
	Anchored: boolean?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	CanTouch: boolean?,
	CastShadow: boolean?,
	Reflectance: number?,
	Parent: Instance?,
}

local colorCache: { [string]: Color3 } = {}

function Build.Hex(hex: string): Color3
	local cached = colorCache[hex]
	if cached then
		return cached
	end
	local clean = hex:gsub("#", "")
	local r = tonumber(clean:sub(1, 2), 16) or 255
	local g = tonumber(clean:sub(3, 4), 16) or 255
	local b = tonumber(clean:sub(5, 6), 16) or 255
	local color = Color3.fromRGB(r, g, b)
	colorCache[hex] = color
	return color
end

function Build.Color(value: (Color3 | string)?): Color3
	if value == nil then
		return Color3.fromRGB(200, 200, 200)
	end
	if type(value) == "string" then
		return Build.Hex(value)
	end
	return value :: Color3
end

-- Lighter / darker version of a color (amount -1..1).
function Build.Shade(color: Color3, amount: number): Color3
	if amount >= 0 then
		return color:Lerp(Color3.new(1, 1, 1), amount)
	end
	return color:Lerp(Color3.new(0, 0, 0), -amount)
end

function Build.Part(props: PartProps): BasePart
	local part = Instance.new("Part")
	part.Name = props.Name or "Part"
	part.Anchored = if props.Anchored == nil then true else props.Anchored
	part.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	if props.CanQuery ~= nil then
		part.CanQuery = props.CanQuery
	end
	if props.CanTouch ~= nil then
		part.CanTouch = props.CanTouch
	end
	part.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	if props.Shape then
		part.Shape = props.Shape
	end
	part.Size = props.Size or Vector3.new(4, 1, 4)
	if props.CFrame then
		part.CFrame = props.CFrame
	elseif props.Position then
		part.CFrame = CFrame.new(props.Position)
	end
	part.Color = Build.Color(props.Color)
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Transparency = props.Transparency or 0
	part.Reflectance = props.Reflectance or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if props.Parent then
		part.Parent = props.Parent
	end
	return part :: BasePart
end

-- An ellipsoid (egg / slime body) using a built-in sphere mesh.
function Build.Ellipsoid(props: PartProps): BasePart
	local part = Build.Part(props)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

function Build.Model(name: string, parent: Instance?): Model
	local model = Instance.new("Model")
	model.Name = name
	if parent then
		model.Parent = parent
	end
	return model
end

function Build.Folder(name: string, parent: Instance?): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	if parent then
		folder.Parent = parent
	end
	return folder
end

function Build.Weld(a: BasePart, b: BasePart): WeldConstraint
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = a
	weld.Part1 = b
	weld.Parent = a
	return weld
end

function Build.Corner(parent: Instance, radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius or 0.2, 0)
	corner.Parent = parent
	return corner
end

function Build.Stroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or 2
	stroke.Color = color or Color3.new(0, 0, 0)
	stroke.Parent = parent
	return stroke
end

-- Text label filling a container, scaled, with an outline.
function Build.Label(parent: Instance, text: string, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 1
	label.RichText = true
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(28, 22, 48)
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	label.Parent = parent
	return label
end

-- Text on a part face.
function Build.SurfaceText(part: BasePart, face: Enum.NormalId, text: string, color: Color3?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SurfaceGui_" .. face.Name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = part
	Build.Label(gui, text, color)
	return gui
end

-- Floating label above a part.
function Build.Billboard(
	adornee: BasePart,
	text: string,
	size: UDim2?,
	offset: Vector3?,
	maxDistance: number?
): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "Billboard"
	gui.Adornee = adornee
	gui.Size = size or UDim2.fromScale(8, 2)
	gui.StudsOffset = offset or Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance or 120
	gui.Parent = adornee
	Build.Label(gui, text)
	return gui
end

return Build
