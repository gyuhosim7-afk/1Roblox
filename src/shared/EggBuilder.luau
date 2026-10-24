--!strict
-- Builds an egg model: the AI-generated egg mesh when loaded, otherwise an ellipsoid shell with
-- spots. Pivot is the egg's bottom.

local Config = require(script.Parent.Config)
local Build = require(script.Parent.Build)
local MeshLibrary = require(script.Parent.MeshLibrary)

local EggBuilder = {}

local SPOTS = {
	{ 0.62, 0.35, -0.6 },
	{ -0.7, 0.1, -0.45 },
	{ 0.2, -0.45, -0.85 },
	{ -0.35, 0.75, 0.6 },
	{ 0.75, -0.2, 0.5 },
	{ -0.6, -0.55, 0.55 },
}

-- eggId may be "Royal" for the Royal Egg.
function EggBuilder.Build(eggId: string, scale: number?): Model
	local s = scale or 1
	local color, spotColor
	if eggId == "Royal" then
		color, spotColor = Config.RoyalEgg.Color, Config.RoyalEgg.SpotColor
	else
		local def = Config.Eggs[eggId]
		assert(def, "Unknown egg " .. tostring(eggId))
		color, spotColor = def.Color, def.SpotColor
	end

	local model = Instance.new("Model")
	model.Name = eggId .. "Egg"
	local mesh = MeshLibrary.Get("Egg_" .. eggId)
	if mesh then
		MeshLibrary.Fit(mesh, Vector3.new(2.6, 3.2, 2.6) * s)
		mesh.Name = "Shell"
		mesh.CFrame = CFrame.new(0, mesh.Size.Y / 2, 0)
		mesh.CastShadow = false
		mesh.Parent = model
		model.PrimaryPart = mesh
		model:SetAttribute("Egg", eggId)
		model.WorldPivot = CFrame.new()
		return model
	end
	local origin = CFrame.new(0, 1.5 * s, 0)
	local shell = Build.Ellipsoid({
		Name = "Shell",
		Size = Vector3.new(2.4, 3, 2.4) * s,
		CFrame = origin,
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CastShadow = false,
		Parent = model,
	})
	model.PrimaryPart = shell
	for _, spot in SPOTS do
		Build.Ellipsoid({
			Name = "Spot",
			Size = Vector3.new(0.7, 0.7, 0.25) * s,
			CFrame = origin
				* CFrame.lookAt(Vector3.zero, Vector3.new(spot[1], spot[2] * 1.2, spot[3]))
				* CFrame.new(0, 0, -1.1 * s),
			Color = spotColor,
			Material = if eggId == "Royal"
					or eggId == "Void"
					or eggId == "Crystal"
				then Enum.Material.Neon
				else Enum.Material.SmoothPlastic,
			CanCollide = false,
			CastShadow = false,
			Parent = model,
		})
	end
	if eggId == "Royal" then
		Build.Part({
			Name = "Crown",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 1.2, 1.2) * s,
			CFrame = origin * CFrame.new(0, 1.55 * s, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color = "#FFC107",
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = model,
		})
	end
	model:SetAttribute("Egg", eggId)
	model.WorldPivot = CFrame.new()
	return model
end

-- Makes every part of a model unanchored and massless so it can be welded to a character.
function EggBuilder.MakeCarryable(model: Model)
	local primary = model.PrimaryPart
	assert(primary, "egg model needs a PrimaryPart")
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			if part ~= primary then
				Build.Weld(primary, part)
			end
		end
	end
end

return EggBuilder
