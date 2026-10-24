--!strict
-- Slime icon for lists: the AI-made 3D slime in a small viewport (a black silhouette while still
-- undiscovered), or a flat 2D slime when the mesh isn't loaded.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MeshLibrary = require(Shared.MeshLibrary)
local SlimeBuilder = require(Shared.SlimeBuilder)
local Theme = require(script.Parent.Theme)

local SlimeIcon = {}

local function viewportIcon(holder: Frame, kind: string, mutation: string?, hidden: boolean?)
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Viewport"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Ambient = Color3.fromRGB(200, 200, 210)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-0.4, -1, 0.6)
	if hidden then
		viewport.ImageColor3 = Color3.fromRGB(20, 18, 34)
	end
	local model = SlimeBuilder.Build(kind, if hidden then nil else mutation)
	model.Parent = viewport
	local extents = model:GetExtentsSize()
	local radius = math.max(extents.X, extents.Y, extents.Z)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local target = Vector3.new(0, extents.Y * 0.48, 0)
	-- the slime faces -Z, so look at it from the front and a little above
	camera.CFrame = CFrame.lookAt(target + Vector3.new(radius * 0.35, radius * 0.45, -radius * 2.1), target)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Parent = holder
end

function SlimeIcon.Create(parent: Instance, kind: string, mutation: string?, size: number, hidden: boolean?): Frame
	local def = Config.Slimes[kind]
	local holder = Instance.new("Frame")
	holder.Name = "SlimeIcon"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(size, size)
	if MeshLibrary.Has(kind) then
		viewportIcon(holder, kind, mutation, hidden)
		holder.Parent = parent
		return holder
	end

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.AnchorPoint = Vector2.new(0.5, 1)
	body.Position = UDim2.fromScale(0.5, 0.95)
	body.Size = UDim2.fromScale(0.9, 0.72)
	body.BorderSizePixel = 0
	local color = if def then Theme.Hex(def.Color) else Theme.Colors.Disabled
	if mutation == "Gold" then
		color = Theme.Colors.Gold
	end
	body.BackgroundColor3 = if hidden then Color3.fromRGB(40, 40, 50) else color
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = body
	Theme.Stroke(body, 2)
	if mutation == "Rainbow" and not hidden then
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 80)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 255, 120)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 160, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 80, 255)),
		})
		gradient.Parent = body
	end
	body.Parent = holder

	if not hidden then
		for _, x in { 0.32, 0.62 } do
			local eye = Instance.new("Frame")
			eye.Name = "Eye"
			eye.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
			eye.BorderSizePixel = 0
			eye.Size = UDim2.fromScale(0.13, 0.2)
			eye.Position = UDim2.fromScale(x, 0.3)
			local eyeCorner = Instance.new("UICorner")
			eyeCorner.CornerRadius = UDim.new(0.5, 0)
			eyeCorner.Parent = eye
			eye.Parent = body
		end
	else
		local q = Theme.Text(body, "?", { MaxSize = 40, Color = Theme.Colors.SubText })
		q.Size = UDim2.fromScale(1, 1)
	end
	holder.Parent = parent
	return holder
end

return SlimeIcon
