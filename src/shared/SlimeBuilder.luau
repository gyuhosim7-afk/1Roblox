--!strict
-- Builds a slime model. Uses the AI-generated mesh for the kind when MeshLibrary has it,
-- otherwise builds it from parts: squishy body, eyes, cheeks and accessories.
-- Front of the slime is local -Z. All parts are anchored (static display).

local Config = require(script.Parent.Config)
local Build = require(script.Parent.Build)
local MeshLibrary = require(script.Parent.MeshLibrary)
local ModelAssets = require(script.Parent.ModelAssets)

local SlimeBuilder = {}

local RARITY_SCALE = { Common = 1, Uncommon = 1.05, Rare = 1.1, Epic = 1.2, Legendary = 1.3, Mythic = 1.45 }
local GOLD = Build.Hex("#FFD54F")

type Ctx = { model: Model, body: BasePart, scale: number, color: Color3, origin: CFrame }

local function add(ctx: Ctx, props: Build.PartProps, offset: CFrame, ellipsoid: boolean?): BasePart
	props.CFrame = ctx.origin * offset
	props.Parent = ctx.model
	props.CanCollide = false
	props.CastShadow = false
	local part = if ellipsoid then Build.Ellipsoid(props) else Build.Part(props)
	return part
end

local function v(ctx: Ctx, x: number, y: number, z: number): CFrame
	local s = ctx.scale
	return CFrame.new(x * s, y * s, z * s)
end

local function sz(ctx: Ctx, x: number, y: number, z: number): Vector3
	local s = ctx.scale
	return Vector3.new(x * s, y * s, z * s)
end

local ACCESSORIES: { [string]: (Ctx) -> () } = {
	Ears = function(ctx)
		for _, side in { -1, 1 } do
			add(ctx, {
				Name = "Ear",
				Size = sz(ctx, 0.7, 0.9, 0.5),
				Color = Build.Shade(ctx.color, -0.15),
			}, v(ctx, side * 0.85, 1.25, 0) * CFrame.Angles(0, 0, side * -0.35), true)
		end
	end,
	Flower = function(ctx)
		add(
			ctx,
			{ Name = "FlowerCenter", Shape = Enum.PartType.Ball, Size = sz(ctx, 0.5, 0.5, 0.5), Color = "#FFC107" },
			v(ctx, 0, 1.35, 0)
		)
		for i = 1, 5 do
			local a = i / 5 * math.pi * 2
			add(ctx, {
				Name = "Petal",
				Shape = Enum.PartType.Ball,
				Size = sz(ctx, 0.45, 0.45, 0.45),
				Color = "#FF80AB",
			}, v(ctx, math.cos(a) * 0.4, 1.3, math.sin(a) * 0.4))
		end
	end,
	Leaf = function(ctx)
		add(ctx, { Name = "Stem", Size = sz(ctx, 0.12, 0.5, 0.12), Color = "#33691E" }, v(ctx, 0, 1.35, 0))
		add(ctx, {
			Name = "Leaf",
			Size = sz(ctx, 1.1, 0.12, 0.6),
			Color = "#7CB342",
		}, v(ctx, 0.4, 1.6, 0) * CFrame.Angles(0, 0, 0.4), true)
	end,
	Cap = function(ctx)
		add(ctx, { Name = "Cap", Size = sz(ctx, 3.2, 1.3, 3.2), Color = "#E53935" }, v(ctx, 0, 1.05, 0), true)
		for i = 1, 4 do
			local a = i / 4 * math.pi * 2 + 0.4
			add(ctx, {
				Name = "Dot",
				Shape = Enum.PartType.Ball,
				Size = sz(ctx, 0.4, 0.4, 0.4),
				Color = "#FFFFFF",
			}, v(ctx, math.cos(a) * 0.9, 1.45, math.sin(a) * 0.9))
		end
	end,
	Spikes = function(ctx)
		for i = -2, 2 do
			add(
				ctx,
				{
					Name = "Spike",
					Size = sz(ctx, 0.35, 0.8, 0.35),
					Color = Build.Shade(ctx.color, -0.3),
				},
				v(ctx, 0, 1.15 - math.abs(i) * 0.12, i * 0.45)
					* CFrame.Angles(i * 0.25, 0, 0)
					* CFrame.Angles(0, math.pi / 4, 0)
			)
		end
	end,
	Horns = function(ctx)
		for _, side in { -1, 1 } do
			add(ctx, {
				Name = "Horn",
				Size = sz(ctx, 0.3, 1.0, 0.3),
				Color = "#EFEBE9",
			}, v(ctx, side * 0.7, 1.35, -0.2) * CFrame.Angles(-0.2, 0, side * -0.5))
			add(ctx, {
				Name = "HornTip",
				Size = sz(ctx, 0.22, 0.5, 0.22),
				Color = "#BCAAA4",
			}, v(ctx, side * 1.0, 1.85, -0.3) * CFrame.Angles(-0.2, 0, side * -0.9))
		end
	end,
	Crown = function(ctx)
		add(ctx, {
			Name = "CrownBand",
			Shape = Enum.PartType.Cylinder,
			Size = sz(ctx, 0.45, 1.4, 1.4),
			Color = GOLD,
			Material = Enum.Material.Metal,
		}, v(ctx, 0, 1.3, 0) * CFrame.Angles(0, 0, math.pi / 2))
		for i = 1, 5 do
			local a = i / 5 * math.pi * 2
			add(ctx, {
				Name = "CrownSpike",
				Size = sz(ctx, 0.22, 0.45, 0.22),
				Color = GOLD,
				Material = Enum.Material.Metal,
			}, v(ctx, math.cos(a) * 0.6, 1.7, math.sin(a) * 0.6))
		end
		add(ctx, {
			Name = "Gem",
			Shape = Enum.PartType.Ball,
			Size = sz(ctx, 0.3, 0.3, 0.3),
			Color = "#E91E63",
			Material = Enum.Material.Neon,
		}, v(ctx, 0, 1.3, -0.7))
	end,
	Halo = function(ctx)
		add(ctx, {
			Name = "Halo",
			Shape = Enum.PartType.Cylinder,
			Size = sz(ctx, 0.15, 1.6, 1.6),
			Color = "#FFF59D",
			Material = Enum.Material.Neon,
			Transparency = 0.1,
		}, v(ctx, 0, 2.1, 0) * CFrame.Angles(0, 0, math.pi / 2))
	end,
	Wings = function(ctx)
		for _, side in { -1, 1 } do
			add(ctx, {
				Name = "Wing",
				Size = sz(ctx, 1.8, 1.1, 0.15),
				Color = "#FFFFFF",
				Transparency = 0.25,
			}, v(ctx, side * 1.5, 0.6, 0.7) * CFrame.Angles(0, side * 0.5, side * 0.35), true)
		end
	end,
	Star = function(ctx)
		for i = 0, 1 do
			add(ctx, {
				Name = "Star",
				Size = sz(ctx, 0.75, 0.75, 0.15),
				Color = "#FFEB3B",
				Material = Enum.Material.Neon,
			}, v(ctx, 0, 1.75, 0) * CFrame.Angles(0, 0, math.pi / 4 * i))
		end
	end,
	Antenna = function(ctx)
		for _, side in { -1, 1 } do
			add(ctx, {
				Name = "Antenna",
				Size = sz(ctx, 0.1, 0.9, 0.1),
				Color = "#212121",
			}, v(ctx, side * 0.35, 1.5, -0.2) * CFrame.Angles(0, 0, side * -0.3))
			add(ctx, {
				Name = "AntennaTip",
				Shape = Enum.PartType.Ball,
				Size = sz(ctx, 0.3, 0.3, 0.3),
				Color = "#FFEB3B",
				Material = Enum.Material.Neon,
			}, v(ctx, side * 0.5, 1.95, -0.2))
		end
	end,
	Bandage = function(ctx)
		for i = 0, 2 do
			add(ctx, {
				Name = "Bandage",
				Shape = Enum.PartType.Cylinder,
				Size = sz(ctx, 0.25, 3.05 - i * 0.35, 3.05 - i * 0.35),
				Color = "#FAFAFA",
			}, v(ctx, 0, -0.4 + i * 0.55, 0) * CFrame.Angles(0.15 * (i - 1), 0, math.pi / 2))
		end
	end,
	Belly = function(ctx)
		add(ctx, { Name = "Belly", Size = sz(ctx, 1.6, 1.4, 0.6), Color = "#FAFAFA" }, v(ctx, 0, -0.35, -1.15), true)
	end,
	Tusks = function(ctx)
		for _, side in { -1, 1 } do
			add(ctx, {
				Name = "Tusk",
				Size = sz(ctx, 0.25, 0.9, 0.25),
				Color = "#FFFDE7",
			}, v(ctx, side * 0.55, -0.65, -1.35) * CFrame.Angles(0.6, 0, side * 0.25))
		end
	end,
	Ring = function(ctx)
		add(ctx, {
			Name = "Ring",
			Shape = Enum.PartType.Cylinder,
			Size = sz(ctx, 0.1, 4.6, 4.6),
			Color = "#B388FF",
			Material = Enum.Material.Neon,
			Transparency = 0.35,
		}, v(ctx, 0, 0, 0) * CFrame.Angles(0.35, 0, math.pi / 2))
	end,
}

function SlimeBuilder.Scale(kind: string): number
	local def = Config.Slimes[kind]
	if not def then
		return 1
	end
	return (def.Size or RARITY_SCALE[def.Rarity] or 1)
end

-- Mesh version: one textured MeshPart named Body (Gold = shiny gold statue, Rainbow = recolored).
local function buildFromMesh(model: Model, body: MeshPart, kind: string, mutation: string?, scale: number)
	MeshLibrary.Fit(body, Vector3.new(3.6, 3.4, 3.6) * scale)
	body.Name = "Body"
	local yaw = ModelAssets[kind] and ModelAssets[kind].Yaw or 0
	body.CFrame = CFrame.new(0, body.Size.Y / 2, 0) * CFrame.Angles(0, math.rad(yaw), 0)
	body.Anchored = true
	body.CanCollide = false
	body.CastShadow = false
	if mutation == "Gold" then
		body.TextureID = ""
		body.Color = GOLD
		body.Material = Enum.Material.Foil
		body.Reflectance = 0.2
	elseif mutation == "Rainbow" then
		body.TextureID = ""
		body.Material = Enum.Material.SmoothPlastic
	end
	body.Parent = model
	model.PrimaryPart = body
end

-- Returns a Model whose pivot is the bottom-center of the slime.
function SlimeBuilder.Build(kind: string, mutation: string?, extraScale: number?): Model
	local def = Config.Slimes[kind]
	assert(def, "Unknown slime " .. tostring(kind))
	local scale = SlimeBuilder.Scale(kind) * (extraScale or 1)
	local model = Instance.new("Model")
	model.Name = kind

	local mesh = MeshLibrary.Get(kind)
	if mesh then
		buildFromMesh(model, mesh, kind, mutation, scale)
		SlimeBuilder.Decorate(model, mesh, kind, mutation, scale)
		return model
	end

	local baseColor = Build.Hex(def.Color)
	local color = if mutation == "Gold" then GOLD else baseColor
	local origin = CFrame.new(0, 1.2 * scale, 0)

	local material = Enum.Material.SmoothPlastic
	if def.Material == "Glass" then
		material = Enum.Material.Glass
	elseif def.Material == "Neon" then
		material = Enum.Material.Neon
	end
	if mutation == "Gold" then
		material = Enum.Material.Metal
	end

	local body = Build.Ellipsoid({
		Name = "Body",
		Size = Vector3.new(3, 2.4, 3) * scale,
		CFrame = origin,
		Color = color,
		Material = material,
		Transparency = if material == Enum.Material.Glass then 0.2 else 0.05,
		Reflectance = if mutation == "Gold" then 0.25 else 0,
		CanCollide = false,
		Parent = model,
	})
	model.PrimaryPart = body

	local ctx: Ctx = { model = model, body = body, scale = scale, color = color, origin = origin }

	-- Face
	for _, side in { -1, 1 } do
		add(
			ctx,
			{ Name = "Eye", Shape = Enum.PartType.Ball, Size = sz(ctx, 0.55, 0.55, 0.55), Color = "#1B1B1B" },
			v(ctx, side * 0.55, 0.25, -1.25)
		)
		add(ctx, {
			Name = "Shine",
			Shape = Enum.PartType.Ball,
			Size = sz(ctx, 0.2, 0.2, 0.2),
			Color = "#FFFFFF",
			Material = Enum.Material.Neon,
		}, v(ctx, side * 0.5, 0.35, -1.48))
		add(ctx, {
			Name = "Cheek",
			Size = sz(ctx, 0.5, 0.25, 0.1),
			Color = "#FF8A80",
			Transparency = 0.25,
		}, v(ctx, side * 0.95, -0.05, -1.12), true)
	end
	add(ctx, { Name = "Mouth", Size = sz(ctx, 0.45, 0.12, 0.1), Color = "#3E2723" }, v(ctx, 0, -0.25, -1.43))

	local accessories: { string } = def.Accessory or {}
	for _, accessory in accessories do
		local builder = ACCESSORIES[accessory]
		if builder then
			builder(ctx)
		end
	end

	SlimeBuilder.Decorate(model, body, kind, mutation, scale)
	return model
end

-- Glow, sparkles and attributes shared by both builders.
function SlimeBuilder.Decorate(model: Model, body: BasePart, kind: string, mutation: string?, scale: number)
	local def = Config.Slimes[kind]
	local baseColor = Build.Hex(def.Color)
	if def.Glow or mutation == "Rainbow" then
		local light = Instance.new("PointLight")
		light.Color = baseColor
		light.Range = 10 * scale
		light.Brightness = 1.5
		light.Parent = body
	end
	if def.Sparkles or mutation == "Gold" or mutation == "Rainbow" then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Sparkles"
		emitter.Rate = 6
		emitter.Lifetime = NumberRange.new(0.8, 1.4)
		emitter.Speed = NumberRange.new(1, 2)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Size = NumberSequence.new(0.3 * scale, 0)
		emitter.LightEmission = 1
		emitter.Color = ColorSequence.new(if mutation == "Gold" then GOLD else baseColor)
		emitter.Parent = body
	end

	model:SetAttribute("Kind", kind)
	model:SetAttribute("Mutation", mutation or "None")
	model:SetAttribute("Rarity", def.Rarity)
	if mutation == "Rainbow" then
		model:AddTag("RainbowSlime")
	end
	model.WorldPivot = CFrame.new()
end

return SlimeBuilder
