--!strict
-- Builds the whole world in code: home area, runway, 7 themed zones, speed gates, nests.
-- Layout numbers come from MapLayout/Config; decorations use a fixed seed so every server matches.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local MapLayout = require(Shared.MapLayout)
local Build = require(Shared.Build)
local Format = require(Shared.Format)

local MapService = {}

MapService.Root = nil :: Folder?
MapService.Nests = {} :: { { Zone: number, Index: number, Part: BasePart, Position: Vector3 } }
MapService.Gates = {} :: { { Zone: number, Part: BasePart } }

local GROUND_Y = 0

local function v3(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

-- Decorations ---------------------------------------------------------------
type Rng = { NextNumber: (Rng, number?, number?) -> number, NextInteger: (Rng, number, number) -> number }

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
		if roll < 0.45 then
			tree(parent, pos, rng:NextNumber(0.8, 1.3), "#8D6E63", "#66BB6A")
		elseif roll < 0.8 then
			for _ = 1, 4 do
				local colors = { "#FF8AD8", "#FFE066", "#FFFFFF", "#80D8FF" }
				flower(parent, pos + v3(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4)), colors[rng:NextInteger(1, 4)])
			end
		else
			rock(parent, pos, rng:NextNumber(2, 4), "#9E9E9E", rng)
		end
	end,
	Forest = function(parent, pos, rng)
		local roll = rng:NextNumber()
		if roll < 0.55 then
			pine(parent, pos, rng:NextNumber(1, 1.6), "#2E7D32")
		elseif roll < 0.85 then
			mushroom(parent, pos, rng:NextNumber(0.8, 1.6))
		else
			tree(parent, pos, rng:NextNumber(1.2, 1.6), "#5D4037", "#388E3C")
		end
	end,
	Desert = function(parent, pos, rng)
		local roll = rng:NextNumber()
		if roll < 0.55 then
			cactus(parent, pos, rng:NextNumber(0.8, 1.4))
		elseif roll < 0.7 then
			pyramid(parent, pos, rng:NextNumber(14, 26))
		else
			rock(parent, pos, rng:NextNumber(2, 5), "#C9A86A", rng)
		end
	end,
	Snow = function(parent, pos, rng)
		local roll = rng:NextNumber()
		if roll < 0.6 then
			pine(parent, pos, rng:NextNumber(1, 1.6), "#2E7D32", "#FFFFFF")
		elseif roll < 0.85 then
			crystal(parent, pos, rng:NextNumber(5, 10), "#9BE7FF", rng, false)
		else
			rock(parent, pos, rng:NextNumber(3, 5), "#ECEFF1", rng)
		end
	end,
	Volcano = function(parent, pos, rng)
		local roll = rng:NextNumber()
		if roll < 0.5 then
			rock(parent, pos, rng:NextNumber(3, 7), "#3E2723", rng)
		elseif roll < 0.85 then
			lavaPool(parent, pos, rng:NextNumber(5, 10))
		else
			crystal(parent, pos, rng:NextNumber(4, 8), "#FF7043", rng, true)
		end
	end,
	Crystal = function(parent, pos, rng)
		local roll = rng:NextNumber()
		local colors = { "#CE93D8", "#80DEEA", "#B39DDB", "#F48FB1" }
		if roll < 0.75 then
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
		else
			crystal(parent, pos, rng:NextNumber(6, 12), "#B388FF", rng, true)
		end
	end,
}

-- Builders ----------------------------------------------------------------------
local function buildHome(root: Instance)
	local home = Build.Folder("Home", root)
	local roadStart = MapLayout.RoadStartZ
	local homeEnd = Config.Map.FirstZoneStart - Config.Map.GateGap / 2 -- where zone 1's ground begins
	local homeLength = homeEnd - roadStart
	local centerZ = roadStart + homeLength / 2
	local halfWidth = MapLayout.HomeHalfWidth

	Build.Part({
		Name = "Ground",
		Size = v3(halfWidth * 2, 2, homeLength),
		Position = v3(0, GROUND_Y - 1, centerZ),
		Color = "#7CCB5B",
		Material = Enum.Material.Grass,
		Parent = home,
	})
	Build.Part({
		Name = "Road",
		Size = v3(Config.Map.RoadWidth, 0.2, homeLength),
		Position = v3(0, GROUND_Y + 0.1, centerZ),
		Color = "#5C6670",
		Material = Enum.Material.Concrete,
		Parent = home,
	})
	-- lane dashes
	local dashZ = roadStart + 6
	while dashZ < roadStart + homeLength - 6 do
		Build.Part({
			Name = "Dash",
			Size = v3(1, 0.22, 6),
			Position = v3(0, GROUND_Y + 0.12, dashZ),
			Color = "#FFFFFF",
			CanCollide = false,
			Parent = home,
		})
		dashZ += 14
	end

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
	spawn.Size = v3(12, 1, 12)
	spawn.CFrame = CFrame.new(0, GROUND_Y + 0.5, Config.Map.SpawnZ)
	spawn.Color = Build.Hex("#4DA6FF")
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.3
	spawn.Parent = home
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
	local base = Build.Part({
		Name = "Base",
		Shape = Enum.PartType.Cylinder,
		Size = v3(1.2, 7, 7),
		CFrame = CFrame.new(point.X, GROUND_Y + 0.6, point.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = "#8D6E63",
		Material = Enum.Material.Wood,
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

	Build.Part({
		Name = "Ground",
		Size = v3(fullWidth, 2, length),
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
	Build.Part({
		Name = "Road",
		Size = v3(Config.Map.RoadWidth, 0.2, length),
		Position = v3(0, GROUND_Y + 0.1, centerZ),
		Color = def.GroundColor,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
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
	local count = math.floor(length / 22)
	for _ = 1, count do
		for _, side in { -1, 1 } do
			local x = side * rng:NextNumber(halfRoad + 8, halfRoad + sideWidth - 6)
			local z = rng:NextNumber(layout.StartZ - Config.Map.GateGap / 2 + 4, layout.EndZ + Config.Map.GateGap / 2 - 4)
			builder(decor, v3(x, GROUND_Y, z), rng)
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

local function setupLighting()
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(110, 110, 120)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 150)
	Lighting.GlobalShadows = true
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.25
		atmosphere.Haze = 1
		atmosphere.Color = Color3.fromRGB(200, 220, 255)
		atmosphere.Parent = Lighting
	end
end

function MapService.Init()
	local existing = Workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end
	local root = Build.Folder("Map")
	MapService.Root = root
	table.clear(MapService.Nests)
	table.clear(MapService.Gates)

	local rng = (Random.new(1337) :: any) :: Rng
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
