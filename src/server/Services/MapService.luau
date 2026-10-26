--!strict
-- Builds the whole world in code: home plaza, runway, 7 themed zones, speed gates, nests.
-- Layout numbers come from MapLayout/Config; decorations use a fixed seed so every server matches.
-- Trees, rocks, statues etc. use the AI-generated meshes (MeshLibrary) with part-built fallbacks.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local MapLayout = require(Shared.MapLayout)
local Build = require(Shared.Build)
local Format = require(Shared.Format)
local MeshLibrary = require(Shared.MeshLibrary)

local MapService = {}

MapService.Root = nil :: Folder?
MapService.Nests = {} :: { { Zone: number, Index: number, Part: BasePart, Position: Vector3 } }
MapService.Gates = {} :: { { Zone: number, Part: BasePart } }

local GROUND_Y = 0
local WORLD_WIDTH = 1400 -- ground reaches the horizon so no other color shows past a zone

local function v3(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

-- Decorations ---------------------------------------------------------------
type Rng = { NextNumber: (Rng, number?, number?) -> number, NextInteger: (Rng, number, number) -> number }

-- Size of each decoration mesh at scale 1 (the box it was generated for).
local DECOR_BOX: { [string]: Vector3 } = {
	Decor_RoundTree = Vector3.new(10, 14, 10),
	Decor_Pine = Vector3.new(8, 16, 8),
	Decor_SnowPine = Vector3.new(8, 16, 8),
	Decor_Cactus = Vector3.new(6, 10, 6),
	Decor_Mushroom = Vector3.new(7, 8, 7),
	Decor_Crystals = Vector3.new(7, 10, 7),
	Decor_LavaRock = Vector3.new(7, 5, 6),
	Decor_Bush = Vector3.new(5, 3.5, 5),
	Decor_Rock = Vector3.new(6, 4, 5),
	Decor_Bench = Vector3.new(7, 3.5, 3),
	Decor_Lamp = Vector3.new(2.4, 11, 2.4),
	Decor_SlimeStatue = Vector3.new(6, 12, 6),
}

-- Places a decoration mesh; returns false when the mesh isn't loaded (caller builds parts).
local function meshDecor(parent: Instance, key: string, pos: Vector3, scale: number, yaw: number): boolean
	local box = DECOR_BOX[key] or Vector3.new(6, 6, 6)
	local part = MeshLibrary.Place(key, box * scale, CFrame.new(pos) * CFrame.Angles(0, yaw, 0), parent)
	return part ~= nil
end

local function tree(parent: Instance, pos: Vector3, scale: number, trunkColor: string, leafColor: string)
	local trunkHeight = 8 * scale
	Build.Part({
		Name = "Trunk",
		Size = v3(1.6 * scale, trunkHeight, 1.6 * scale),
		Position = pos + v3(0, trunkHeight / 2, 0),
		Color = trunkColor,
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	for i = 0, 2 do
		local size = (7 - i * 1.6) * scale
		Build.Part({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = v3(size, size, size),
			Position = pos + v3((i - 1) * 0.6 * scale, trunkHeight + i * 2.4 * scale, 0),
			Color = leafColor,
			Material = Enum.Material.Grass,
			CanCollide = false,
			Parent = parent,
		})
	end
end

local function pine(parent: Instance, pos: Vector3, scale: number, leafColor: string, tipColor: string?)
	Build.Part({
		Name = "Trunk",
		Size = v3(1.2 * scale, 4 * scale, 1.2 * scale),
		Position = pos + v3(0, 2 * scale, 0),
		Color = "#6D4C41",
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	for i = 0, 3 do
		local width = (8 - i * 1.8) * scale
		Build.Part({
			Name = "Layer",
			Shape = Enum.PartType.Cylinder,
			Size = v3(2.2 * scale, width, width),
			CFrame = CFrame.new(pos + v3(0, (4.5 + i * 2.6) * scale, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = if i == 3 and tipColor then tipColor else leafColor,
			Material = Enum.Material.Grass,
			CanCollide = false,
			Parent = parent,
		})
	end
end

local function rock(parent: Instance, pos: Vector3, size: number, color: string, rng: Rng)
	Build.Part({
		Name = "Rock",
		Size = v3(size, size * 0.7, size * 0.9),
		CFrame = CFrame.new(pos + v3(0, size * 0.3, 0))
			* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6.28), rng:NextNumber(-0.3, 0.3)),
		Color = color,
		Material = Enum.Material.Slate,
		Parent = parent,
	})
end

local function crystal(parent: Instance, pos: Vector3, height: number, color: string, rng: Rng, neon: boolean)
	Build.Part({
		Name = "Crystal",
		Size = v3(height * 0.3, height, height * 0.3),
		CFrame = CFrame.new(pos + v3(0, height * 0.45, 0))
			* CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, 6.28), rng:NextNumber(-0.35, 0.35)),
		Color = color,
		Material = if neon then Enum.Material.Neon else Enum.Material.Glass,
		Transparency = if neon then 0.1 else 0.25,
		CanCollide = false,
		Parent = parent,
	})
end

local function cactus(parent: Instance, pos: Vector3, scale: number)
	local h = 7 * scale
	Build.Part({
		Name = "Cactus",
		Size = v3(1.8 * scale, h, 1.8 * scale),
		Position = pos + v3(0, h / 2, 0),
		Color = "#3FA34D",
		Material = Enum.Material.Grass,
		Parent = parent,
	})
	for _, side in { -1, 1 } do
		Build.Part({
			Name = "Arm",
			Size = v3(2.5 * scale, 1.2 * scale, 1.2 * scale),
			Position = pos + v3(side * 1.6 * scale, h * 0.55, 0),
			Color = "#3FA34D",
			Material = Enum.Material.Grass,
			Parent = parent,
		})
		Build.Part({
			Name = "ArmUp",
			Size = v3(1.2 * scale, 2.6 * scale, 1.2 * scale),
			Position = pos + v3(side * 2.4 * scale, h * 0.55 + 1.3 * scale, 0),
			Color = "#3FA34D",
			Material = Enum.Material.Grass,
			Parent = parent,
		})
	end
end

local function pyramid(parent: Instance, pos: Vector3, base: number)
	for i = 0, 5 do
		local w = base * (1 - i / 6)
		Build.Part({
			Name = "Step",
			Size = v3(w, base / 8, w),
			Position = pos + v3(0, base / 16 + i * base / 8, 0),
			Color = "#D8B46A",
			Material = Enum.Material.Sandstone,
			Parent = parent,
		})
	end
end

local function mushroom(parent: Instance, pos: Vector3, scale: number)
	Build.Part({
		Name = "Stem",
		Shape = Enum.PartType.Cylinder,
		Size = v3(4 * scale, 1.4 * scale, 1.4 * scale),
		CFrame = CFrame.new(pos + v3(0, 2 * scale, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = "#F5ECD7",
		Parent = parent,
	})
	Build.Ellipsoid({
		Name = "Cap",
		Size = v3(5 * scale, 2.4 * scale, 5 * scale),
		Position = pos + v3(0, 4.2 * scale, 0),
		Color = "#E53935",
		CanCollide = false,
		Parent = parent,
	})
end

local function flower(parent: Instance, pos: Vector3, color: string)
	Build.Part({
		Name = "Flower",
		Shape = Enum.PartType.Ball,
		Size = v3(1.2, 1.2, 1.2),
		Position = pos + v3(0, 0.8, 0),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = parent,
	})
end

local function lavaPool(parent: Instance, pos: Vector3, size: number)
	Build.Part({
		Name = "Lava",
		Shape = Enum.PartType.Cylinder,
		Size = v3(0.4, size, size),
		CFrame = CFrame.new(pos + v3(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = "#FF5722",
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = parent,
	})
end

local function star(parent: Instance, pos: Vector3, size: number, color: string)
	Build.Part({
		Name = "Star",
		Shape = Enum.PartType.Ball,
		Size = v3(size, size, size),
		Position = pos,
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = parent,
	})
end

local function planet(parent: Instance, pos: Vector3, size: number, color: string)
	Build.Part({
		Name = "Planet",
		Shape = Enum.PartType.Ball,
		Size = v3(size, size, size),
		Position = pos,
		Color = color,
		CanCollide = false,
		Parent = parent,
	})
	Build.Part({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = v3(0.4, size * 1.8, size * 1.8),
		CFrame = CFrame.new(pos) * CFrame.Angles(0.4, 0, math.rad(90)),
		Color = "#B388FF",
		Material = Enum.Material.Neon,
		Transparency = 0.4,
		CanCollide = false,
		Parent = parent,
	})
end

local DECOR: { [string]: (Instance, Vector3, Rng) -> () } = {
	Meadow = function(parent, pos, rng)
		local roll = rng:NextNumber()
		local scale, yaw = rng:NextNumber(0.9, 1.4), rng:NextNumber(0, 6.28)
		if roll < 0.45 then
			if not meshDecor(parent, "Decor_RoundTree", pos, scale, yaw) then
				tree(parent, pos, scale, "#8D6E63", "#66BB6A")
			end
		elseif roll < 0.8 and meshDecor(parent, "Decor_Bush", pos, scale, yaw) then
			return
		elseif roll < 0.8 then
			for _ = 1, 4 do
				local colors = { "#FF8AD8", "#FFE066", "#FFFFFF", "#80D8FF" }
				flower(parent, pos + v3(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4)), colors[rng:NextInteger(1, 4)])
			end
		elseif not meshDecor(parent, "Decor_Rock", pos, scale * 0.8, yaw) then
			rock(parent, pos, rng:NextNumber(2, 4), "#9E9E9E", rng)
		end
	end,
	Forest = function(parent, pos, rng)
		local roll = rng:NextNumber()
		local yaw = rng:NextNumber(0, 6.28)
		if roll < 0.55 then
			local scale = rng:NextNumber(1, 1.6)
			if not meshDecor(parent, "Decor_Pine", pos, scale, yaw) then
				pine(parent, pos, scale, "#2E7D32")
			end
		elseif roll < 0.85 then
			local scale = rng:NextNumber(0.8, 1.6)
			if not meshDecor(parent, "Decor_Mushroom", pos, scale, yaw) then
				mushroom(parent, pos, scale)
			end
		else
			local scale = rng:NextNumber(1.2, 1.6)
			if not meshDecor(parent, "Decor_RoundTree", pos, scale, yaw) then
				tree(parent, pos, scale, "#5D4037", "#388E3C")
			end
		end
	end,
	Desert = function(parent, pos, rng)
		local roll = rng:NextNumber()
		if roll < 0.55 then
			local scale = rng:NextNumber(0.8, 1.4)
			if not meshDecor(parent, "Decor_Cactus", pos, scale, rng:NextNumber(0, 6.28)) then
				cactus(parent, pos, scale)
			end
		elseif roll < 0.7 then
			pyramid(parent, pos, rng:NextNumber(14, 26))
		else
			rock(parent, pos, rng:NextNumber(2, 5), "#C9A86A", rng)
		end
	end,
	Snow = function(parent, pos, rng)
		local roll = rng:NextNumber()
		if roll < 0.6 then
			local scale = rng:NextNumber(1, 1.6)
			if not meshDecor(parent, "Decor_SnowPine", pos, scale, rng:NextNumber(0, 6.28)) then
				pine(parent, pos, scale, "#2E7D32", "#FFFFFF")
			end
		elseif roll < 0.85 then
			crystal(parent, pos, rng:NextNumber(5, 10), "#9BE7FF", rng, false)
		else
			rock(parent, pos, rng:NextNumber(3, 5), "#ECEFF1", rng)
		end
	end,
	Volcano = function(parent, pos, rng)
		local roll = rng:NextNumber()
		if roll < 0.5 then
			local size = rng:NextNumber(3, 7)
			if not meshDecor(parent, "Decor_LavaRock", pos, size / 4, rng:NextNumber(0, 6.28)) then
				rock(parent, pos, size, "#3E2723", rng)
			end
		elseif roll < 0.85 then
			lavaPool(parent, pos, rng:NextNumber(5, 10))
		else
			crystal(parent, pos, rng:NextNumber(4, 8), "#FF7043", rng, true)
		end
	end,
	Crystal = function(parent, pos, rng)
		local roll = rng:NextNumber()
		local colors = { "#CE93D8", "#80DEEA", "#B39DDB", "#F48FB1" }
		if
			roll < 0.75 and meshDecor(parent, "Decor_Crystals", pos, rng:NextNumber(0.9, 1.7), rng:NextNumber(0, 6.28))
		then
			return
		elseif roll < 0.75 then
			for _ = 1, 3 do
				crystal(
					parent,
					pos + v3(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3)),
					rng:NextNumber(5, 14),
					colors[rng:NextInteger(1, 4)],
					rng,
					rng:NextNumber() < 0.4
				)
			end
		else
			rock(parent, pos, rng:NextNumber(3, 6), "#4A3B63", rng)
		end
	end,
	Void = function(parent, pos, rng)
		local roll = rng:NextNumber()
		if roll < 0.6 then
			star(parent, pos + v3(0, rng:NextNumber(8, 40), 0), rng:NextNumber(0.6, 2), "#FFFFFF")
		elseif roll < 0.8 then
			planet(parent, pos + v3(0, rng:NextNumber(25, 60), 0), rng:NextNumber(6, 14), "#7C4DFF")
		elseif not meshDecor(parent, "Decor_Crystals", pos, rng:NextNumber(0.8, 1.4), rng:NextNumber(0, 6.28)) then
			crystal(parent, pos, rng:NextNumber(6, 12), "#B388FF", rng, true)
		end
	end,
}

-- Builders ----------------------------------------------------------------------

-- Statues, lamps, benches and bushes on the home plaza, plus the big runway arch.
local function buildPlazaDecor(home: Instance, roadStart: number, homeEnd: number)
	local decor = Build.Folder("PlazaDecor", home)
	local edge = Config.Map.RoadWidth / 2 - 3
	local spawnZ = Config.Map.SpawnZ
	-- golden slime statues around the spawn
	for _, side in { -1, 1 } do
		for _, dz in { -26, 26 } do
			local pos = v3(side * edge, GROUND_Y, spawnZ + dz)
			if not meshDecor(decor, "Decor_SlimeStatue", pos, 1, if side < 0 then math.pi / 2 else -math.pi / 2) then
				Build.Part({
					Name = "StatuePillar",
					Size = v3(4, 6, 4),
					Position = pos + v3(0, 3, 0),
					Color = "#FFFFFF",
					Material = Enum.Material.Marble,
					Parent = decor,
				})
			end
		end
	end
	-- lamps and benches along both curbs
	local z = roadStart + 20
	local index = 0
	while z < homeEnd - 10 do
		index += 1
		for _, side in { -1, 1 } do
			local pos = v3(side * (edge + 1), GROUND_Y, z)
			if math.abs(z - spawnZ) > 34 then
				if index % 2 == 0 then
					meshDecor(decor, "Decor_Lamp", pos, 1, 0)
				else
					meshDecor(decor, "Decor_Bench", pos, 1, if side < 0 then -math.pi / 2 else math.pi / 2)
				end
			end
			meshDecor(decor, "Decor_Bush", v3(side * (edge + 1.5), GROUND_Y, z + 10), 0.7, z)
		end
		z += 24
	end
	for _, lamp in decor:GetChildren() do
		if lamp.Name == "Decor_Lamp" and lamp:IsA("BasePart") then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 214, 140)
			light.Range = 18
			light.Brightness = 1.2
			light.Parent = lamp
		end
	end

	-- Big arch over the runway start
	local width = Config.Map.RoadWidth
	for _, side in { -1, 1 } do
		Build.Part({
			Name = "ArchPillar",
			Shape = Enum.PartType.Cylinder,
			Size = v3(26, 6, 6),
			CFrame = CFrame.new(side * (width / 2 + 3), 13, homeEnd) * CFrame.Angles(0, 0, math.rad(90)),
			Color = "#FFB300",
			Parent = decor,
		})
		Build.Part({
			Name = "ArchBall",
			Shape = Enum.PartType.Ball,
			Size = v3(8, 8, 8),
			Position = v3(side * (width / 2 + 3), 30, homeEnd),
			Color = "#FF4FA3",
			Material = Enum.Material.Neon,
			Parent = decor,
		})
	end
	local banner = Build.Part({
		Name = "ArchBanner",
		Size = v3(width + 6, 9, 2),
		Position = v3(0, 24, homeEnd),
		Color = "#4DA6FF",
		Parent = decor,
	})
	Build.SurfaceText(banner, Enum.NormalId.Back, "STEAL A SLIME!", Color3.new(1, 1, 1))
	Build.SurfaceText(banner, Enum.NormalId.Front, "GO HOME FAST!", Color3.new(1, 1, 1))
end

-- Trees, bushes and rocks around the bases so the home area never looks like an empty field.
local function buildHomeForest(home: Instance, roadStart: number, homeEnd: number, halfWidth: number)
	local forest = Build.Folder("Forest", home)
	local rng = (Random.new(4242) :: any) :: Rng
	local keys = { "Decor_RoundTree", "Decor_RoundTree", "Decor_Pine", "Decor_Bush", "Decor_Rock" }
	local z = roadStart - 30
	while z < homeEnd do
		for _, side in { -1, 1 } do
			for _ = 1, 2 do
				local key = keys[rng:NextInteger(1, #keys)]
				local pos =
					v3(side * rng:NextNumber(halfWidth + 10, halfWidth + 90), GROUND_Y, z + rng:NextNumber(-8, 8))
				if not meshDecor(forest, key, pos, rng:NextNumber(0.9, 1.6), rng:NextNumber(0, 6.28)) then
					tree(forest, pos, 1.2, "#8D6E63", "#66BB6A")
				end
			end
		end
		z += 22
	end
	-- a row behind the last bases
	for x = -halfWidth - 60, halfWidth + 60, 20 do
		local pos = v3(x + rng:NextNumber(-6, 6), GROUND_Y, roadStart - rng:NextNumber(14, 50))
		if not meshDecor(forest, "Decor_Pine", pos, rng:NextNumber(1, 1.7), rng:NextNumber(0, 6.28)) then
			pine(forest, pos, 1.3, "#2E7D32")
		end
	end
end

local function buildHome(root: Instance)
	local home = Build.Folder("Home", root)
	local roadStart = MapLayout.RoadStartZ
	local homeEnd = Config.Map.FirstZoneStart - Config.Map.GateGap / 2 -- where zone 1's ground begins
	local homeLength = homeEnd - roadStart
	local centerZ = roadStart + homeLength / 2
	local halfWidth = MapLayout.HomeHalfWidth

	Build.Part({
		Name = "Ground",
		Size = v3(WORLD_WIDTH, 2, homeLength),
		Position = v3(0, GROUND_Y - 1, centerZ),
		Color = "#7CCB5B",
		Material = Enum.Material.Grass,
		Parent = home,
	})
	-- Checkered plaza floor (cream / warm yellow tiles)
	local tile = 12
	local columns = math.floor(Config.Map.RoadWidth / tile)
	local rows = math.ceil(homeLength / tile)
	local tileWidth = Config.Map.RoadWidth / columns
	local tileLength = homeLength / rows
	local plaza = Build.Folder("Plaza", home)
	for row = 0, rows - 1 do
		for column = 0, columns - 1 do
			Build.Part({
				Name = "Tile",
				Size = v3(tileWidth, 0.2, tileLength),
				Position = v3(
					-Config.Map.RoadWidth / 2 + tileWidth * (column + 0.5),
					GROUND_Y + 0.1,
					roadStart + tileLength * (row + 0.5)
				),
				Color = if (row + column) % 2 == 0 then "#FFF4DC" else "#FFD37A",
				Material = Enum.Material.SmoothPlastic,
				CastShadow = false,
				Parent = plaza,
			})
		end
	end
	-- Curbs along the plaza
	for _, side in { -1, 1 } do
		Build.Part({
			Name = "Curb",
			Size = v3(1.6, 0.8, homeLength),
			Position = v3(side * (Config.Map.RoadWidth / 2 + 0.8), GROUND_Y + 0.4, centerZ),
			Color = "#FFFFFF",
			Parent = plaza,
		})
	end
	buildPlazaDecor(home, roadStart, homeEnd)
	buildHomeForest(home, roadStart, homeEnd, halfWidth)

	-- invisible boundary walls around the home area
	local wallHeight = Config.Map.RoadWallHeight
	for _, side in { -1, 1 } do
		Build.Part({
			Name = "BoundaryWall",
			Size = v3(2, wallHeight, homeLength),
			Position = v3(side * (halfWidth + 1), wallHeight / 2, centerZ),
			Transparency = 1,
			Parent = home,
		})
	end
	Build.Part({
		Name = "BackWall",
		Size = v3(halfWidth * 2, wallHeight, 2),
		Position = v3(0, wallHeight / 2, roadStart - 1),
		Transparency = 1,
		Parent = home,
	})
	-- front fences beside the runway entrance (keep players on the road when leaving home)
	local frontZ = homeEnd
	local fenceWidth = halfWidth - MapLayout.HalfRoad
	for _, side in { -1, 1 } do
		Build.Part({
			Name = "FrontWall",
			Size = v3(fenceWidth, wallHeight, 2),
			Position = v3(side * (MapLayout.HalfRoad + fenceWidth / 2), wallHeight / 2, frontZ),
			Transparency = 1,
			Parent = home,
		})
		Build.Part({
			Name = "Hedge",
			Size = v3(fenceWidth, 4, 3),
			Position = v3(side * (MapLayout.HalfRoad + fenceWidth / 2), 2, frontZ),
			Color = "#2E7D32",
			Material = Enum.Material.Grass,
			Parent = home,
		})
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Shape = Enum.PartType.Cylinder
	spawn.Size = v3(1, 14, 14)
	spawn.CFrame = CFrame.new(0, GROUND_Y + 0.5, Config.Map.SpawnZ) * CFrame.Angles(0, 0, math.rad(90))
	spawn.Color = Build.Hex("#4DA6FF")
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.15
	spawn.Parent = home
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	local _ = Format
end

local function buildGate(parent: Instance, zoneIndex: number)
	local def = Config.Zones[zoneIndex]
	local layout = MapLayout.Zones[zoneIndex]
	local width = Config.Map.RoadWidth
	local height = 30
	local locked = def.GateSpeed > 0 or def.RebirthsRequired > 0

	-- arch pillars
	for _, side in { -1, 1 } do
		Build.Part({
			Name = "Pillar",
			Size = v3(4, height + 6, 4),
			Position = v3(side * (width / 2 + 2), (height + 6) / 2, layout.GateZ),
			Color = def.AccentColor,
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
	end
	for _, side in { -1, 1 } do
		Build.Part({
			Name = "PillarCap",
			Shape = Enum.PartType.Ball,
			Size = v3(7, 7, 7),
			Position = v3(side * (width / 2 + 2), height + 8, layout.GateZ),
			Color = def.AccentColor,
			Material = Enum.Material.Neon,
			Parent = parent,
		})
	end
	local top = Build.Part({
		Name = "ArchTop",
		Size = v3(width + 8, 6, 4),
		Position = v3(0, height + 3, layout.GateZ),
		Color = def.AccentColor,
		Parent = parent,
	})
	local title = string.upper(def.Name)
	Build.SurfaceText(top, Enum.NormalId.Front, title, Color3.new(1, 1, 1))
	Build.SurfaceText(top, Enum.NormalId.Back, title, Color3.new(1, 1, 1))

	if locked then
		local barrier = Build.Part({
			Name = "Gate",
			Size = v3(width, height, 1),
			Position = v3(0, height / 2, layout.GateZ),
			Color = def.AccentColor,
			Material = Enum.Material.ForceField,
			Transparency = 0.35,
			Parent = parent,
		})
		barrier:SetAttribute("Zone", zoneIndex)
		barrier:SetAttribute("GateSpeed", def.GateSpeed)
		barrier:SetAttribute("RebirthsRequired", def.RebirthsRequired)
		barrier:AddTag("SpeedGate")
		local need = "Need " .. Format.Number(def.GateSpeed) .. " Speed"
		if def.RebirthsRequired > 0 then
			need ..= "\n+ " .. def.RebirthsRequired .. " Rebirths"
		end
		Build.SurfaceText(barrier, Enum.NormalId.Front, need, Color3.new(1, 1, 1))
		table.insert(MapService.Gates, { Zone = zoneIndex, Part = barrier })
	end
end

local function buildNest(parent: Instance, zoneIndex: number, nestIndex: number, point: MapLayout.Point)
	local def = Config.Zones[zoneIndex]
	local egg = Config.Eggs[def.Egg]
	local model = Build.Model("Nest_" .. nestIndex, parent)
	local nestMesh = MeshLibrary.Place(
		"Nest",
		v3(8, 2.6, 8),
		CFrame.new(point.X, GROUND_Y, point.Z) * CFrame.Angles(0, nestIndex, 0),
		model
	)
	local base = Build.Part({
		Name = "Base",
		Shape = Enum.PartType.Cylinder,
		Size = v3(1.2, 7, 7),
		CFrame = CFrame.new(point.X, GROUND_Y + 0.6, point.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = "#8D6E63",
		Material = Enum.Material.Wood,
		Transparency = if nestMesh then 1 else 0,
		Parent = model,
	})
	Build.Part({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = v3(0.5, 7.6, 7.6),
		CFrame = CFrame.new(point.X, GROUND_Y + 1.3, point.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = egg.SpotColor,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = model,
	})
	model.PrimaryPart = base
	model:SetAttribute("Zone", zoneIndex)
	model:SetAttribute("Egg", def.Egg)
	model:SetAttribute("NestIndex", nestIndex)
	model:AddTag("Nest")
	table.insert(MapService.Nests, {
		Zone = zoneIndex,
		Index = nestIndex,
		Part = base,
		Position = v3(point.X, GROUND_Y + 1.2, point.Z),
	})
end

local function buildZone(root: Instance, zoneIndex: number, rng: Rng)
	local def = Config.Zones[zoneIndex]
	local layout = MapLayout.Zones[zoneIndex]
	local folder = Build.Folder(def.Id, root)
	local length = layout.EndZ - layout.StartZ + Config.Map.GateGap
	local centerZ = (layout.StartZ + layout.EndZ) / 2
	local halfRoad = MapLayout.HalfRoad
	local sideWidth = Config.Map.ZoneSideWidth
	local fullWidth = (halfRoad + sideWidth) * 2

	local _ = fullWidth
	Build.Part({
		Name = "Ground",
		Size = v3(WORLD_WIDTH, 2, length),
		Position = v3(0, GROUND_Y - 1, centerZ),
		Color = Build.Shade(Build.Hex(def.GroundColor), -0.15),
		Material = if def.Decor == "Snow"
			then Enum.Material.Snow
			elseif def.Decor == "Desert" then Enum.Material.Sand
			elseif def.Decor == "Volcano" then Enum.Material.Basalt
			elseif def.Decor == "Void" then Enum.Material.SmoothPlastic
			elseif def.Decor == "Crystal" then Enum.Material.Slate
			else Enum.Material.Grass,
		Parent = folder,
	})
	-- Runway in alternating bands so it reads like a race track
	local bands = math.max(1, math.floor(length / 20))
	local bandLength = length / bands
	local roadColor = Build.Hex(def.GroundColor)
	for band = 0, bands - 1 do
		Build.Part({
			Name = "Road",
			Size = v3(Config.Map.RoadWidth, 0.2, bandLength),
			Position = v3(0, GROUND_Y + 0.1, centerZ - length / 2 + bandLength * (band + 0.5)),
			Color = if band % 2 == 0 then roadColor else Build.Shade(roadColor, 0.18),
			Material = Enum.Material.SmoothPlastic,
			CastShadow = false,
			Parent = folder,
		})
	end
	for _, side in { -1, 1 } do
		Build.Part({
			Name = "Edge",
			Size = v3(1.5, 1, length),
			Position = v3(side * (halfRoad + 0.75), GROUND_Y + 0.5, centerZ),
			Color = def.AccentColor,
			Material = Enum.Material.Neon,
			Parent = folder,
		})
		Build.Part({
			Name = "RoadWall",
			Size = v3(2, Config.Map.RoadWallHeight, length),
			Position = v3(side * (halfRoad + 2), Config.Map.RoadWallHeight / 2, centerZ),
			Transparency = 1,
			Parent = folder,
		})
	end

	-- Decor on both sides
	local decor = Build.Folder("Decor", folder)
	local builder = DECOR[def.Decor] or DECOR.Meadow
	local zMin = layout.StartZ - Config.Map.GateGap / 2 + 4
	local zMax = layout.EndZ + Config.Map.GateGap / 2 - 4
	local count = math.floor(length / 8)
	for _ = 1, count do
		for _, side in { -1, 1 } do
			local x = side * rng:NextNumber(halfRoad + 8, halfRoad + sideWidth - 6)
			builder(decor, v3(x, GROUND_Y, rng:NextNumber(zMin, zMax)), rng)
		end
	end
	-- Colored ground patches (flower beds, dunes, snow drifts, lava cracks...) break up flat ground
	local ground = Build.Hex(def.GroundColor)
	local patchColor = if def.Decor == "Volcano"
		then Build.Hex("#FF6A1A")
		elseif def.Decor == "Void" or def.Decor == "Crystal" then Build.Hex(def.AccentColor)
		else Build.Shade(ground, 0.2)
	local patchNeon = def.Decor == "Volcano" or def.Decor == "Void" or def.Decor == "Crystal"
	for _ = 1, math.floor(length / 30) do
		for _, side in { -1, 1 } do
			local size = rng:NextNumber(10, 26) * (if patchNeon then 0.45 else 1)
			Build.Part({
				Name = "Patch",
				Shape = Enum.PartType.Cylinder,
				Size = v3(0.3, size, size * rng:NextNumber(0.6, 1)),
				CFrame = CFrame.new(
					side * rng:NextNumber(halfRoad + 6, halfRoad + sideWidth + 40),
					GROUND_Y + 0.05,
					rng:NextNumber(zMin, zMax)
				) * CFrame.Angles(0, rng:NextNumber(0, 6.28), math.rad(90)),
				Color = patchColor,
				Material = if patchNeon then Enum.Material.Neon else Enum.Material.SmoothPlastic,
				Transparency = if patchNeon then 0.35 else 0,
				CanCollide = false,
				CastShadow = false,
				Parent = decor,
			})
		end
	end
	-- Rolling hills on the horizon
	for _ = 1, math.max(2, math.floor(length / 70)) do
		for _, side in { -1, 1 } do
			local size = rng:NextNumber(70, 140)
			Build.Part({
				Name = "Hill",
				Shape = Enum.PartType.Ball,
				Size = v3(size, size, size),
				Position = v3(
					side * rng:NextNumber(halfRoad + sideWidth + 70, halfRoad + sideWidth + 160),
					-size * 0.3,
					rng:NextNumber(zMin, zMax)
				),
				Color = Build.Shade(ground, rng:NextNumber(-0.25, 0.05)),
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				CastShadow = false,
				Parent = decor,
			})
		end
	end

	buildGate(folder, zoneIndex)

	local nests = Build.Folder("Nests", folder)
	for nestIndex, point in layout.Nests do
		buildNest(nests, zoneIndex, nestIndex, point)
	end

	-- Zone sign at the entrance
	local sign = Build.Part({
		Name = "ZoneSign",
		Size = v3(16, 6, 1),
		Position = v3(-(halfRoad + 10), 8, layout.StartZ + 6),
		Color = def.AccentColor,
		Parent = folder,
	})
	Build.SurfaceText(sign, Enum.NormalId.Front, def.Name .. "\n" .. Config.Eggs[def.Egg].Name, Color3.new(1, 1, 1))
	Build.Part({
		Name = "SignPost",
		Size = v3(1, 6, 1),
		Position = v3(-(halfRoad + 10), 2.5, layout.StartZ + 6),
		Color = "#5D4037",
		Parent = folder,
	})
end

local function buildEnd(root: Instance)
	local last = MapLayout.Zones[#MapLayout.Zones]
	Build.Part({
		Name = "EndWall",
		Size = v3(Config.Map.RoadWidth + 10, Config.Map.RoadWallHeight, 2),
		Position = v3(0, Config.Map.RoadWallHeight / 2, MapLayout.RoadEndZ),
		Transparency = 1,
		Parent = root,
	})
	Build.Part({
		Name = "EndGround",
		Size = v3((MapLayout.HalfRoad + Config.Map.ZoneSideWidth) * 2, 2, MapLayout.RoadEndZ - last.EndZ + 10),
		Position = v3(0, GROUND_Y - 1, (last.EndZ + MapLayout.RoadEndZ) / 2),
		Color = "#140C24",
		Parent = root,
	})
end

-- Returns the Lighting child with this name, creating it once.
local function effect(className: string, name: string): any
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local created = Instance.new(className :: any)
	created.Name = name
	created.Parent = Lighting
	return created
end

-- Bright, saturated cartoon look. The client tweens these per zone (Config.Zones[i].Ambience).
local function setupLighting()
	local ambience = Config.Zones[1].Ambience
	Lighting.ClockTime = ambience.ClockTime
	Lighting.Brightness = ambience.Brightness
	Lighting.Ambient = Color3.fromRGB(120, 115, 140)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 170)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.ExposureCompensation = 0
	Lighting.GlobalShadows = true
	-- drop effects we don't manage (e.g. Studio's default ColorGrading)
	local keep = { Atmosphere = true, Sky = true, Bloom = true, ColorCorrection = true, SunRays = true }
	for _, child in Lighting:GetChildren() do
		local isEffect = child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky")
		if isEffect and not keep[child.Name] then
			child:Destroy()
		end
	end
	local atmosphere = effect("Atmosphere", "Atmosphere")
	atmosphere.Density = ambience.Density
	atmosphere.Haze = ambience.Haze
	atmosphere.Color = Build.Hex(ambience.Atmosphere)
	atmosphere.Decay = Color3.fromRGB(120, 170, 255)
	atmosphere.Glare = 0.2
	atmosphere.Offset = 0.1
	local sky = effect("Sky", "Sky")
	sky.StarCount = 3000
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 9
	local bloom = effect("BloomEffect", "Bloom")
	bloom.Intensity = 0.55
	bloom.Size = 28
	bloom.Threshold = 1.4
	local grading = effect("ColorCorrectionEffect", "ColorCorrection")
	grading.Saturation = 0.28
	grading.Contrast = 0.1
	grading.Brightness = 0.02
	grading.TintColor = Build.Hex(ambience.Tint)
	local rays = effect("SunRaysEffect", "SunRays")
	rays.Intensity = 0.05
	rays.Spread = 0.6
end

function MapService.Init()
	MeshLibrary.LoadAll(20)
	local existing = Workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end
	local root = Build.Folder("Map")
	MapService.Root = root
	table.clear(MapService.Nests)
	table.clear(MapService.Gates)

	local rng = (Random.new(1337) :: any) :: Rng
	-- Big ground under everything so no void shows past the play area.
	local totalLength = MapLayout.RoadEndZ - MapLayout.RoadStartZ + 400
	Build.Part({
		Name = "Baseplate",
		Size = Vector3.new(1400, 2, totalLength),
		Position = Vector3.new(0, GROUND_Y - 1.6, (MapLayout.RoadEndZ + MapLayout.RoadStartZ) / 2),
		Color = "#4C8C3F",
		Material = Enum.Material.Grass,
		Parent = root,
	})
	buildHome(root)
	local zonesFolder = Build.Folder("Zones", root)
	for zoneIndex = 1, #Config.Zones do
		buildZone(zonesFolder, zoneIndex, rng)
	end
	buildEnd(root)
	Build.Folder("Plots", root)
	Build.Folder("Eggs", root)
	root.Parent = Workspace
	setupLighting()
end

function MapService.Start() end

return MapService
