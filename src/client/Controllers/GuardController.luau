--!strict
-- Draws guard slimes locally and moves them with the shared server clock.
-- The server runs the same math for hit tests, so nothing is replicated per frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Build = require(Shared.Build)
local MapLayout = require(Shared.MapLayout)
local GuardMotion = require(Shared.GuardMotion)
local MeshLibrary = require(Shared.MeshLibrary)

local GuardController = {}

type Visual = { Guard: MapLayout.Guard, Model: Model?, Arm: BasePart? }

local visuals: { Visual } = {}
local folder: Folder

local function buildPatrol(guard: MapLayout.Guard): Model
	local zone = Config.Zones[guard.Zone]
	local r = guard.Radius
	local model = Instance.new("Model")
	model.Name = guard.Id
	local mesh = MeshLibrary.Get("Guard")
	if mesh then
		-- AI-made guard slime, facing -Z like the part version
		MeshLibrary.Fit(mesh, Vector3.new(r * 2.2, r * 2.2, r * 2.2))
		mesh.Name = "Body"
		mesh.CFrame = CFrame.new(0, mesh.Size.Y / 2, 0)
		mesh.Parent = model
		model.PrimaryPart = mesh
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 80, 80)
		glow.Range = r * 3
		glow.Parent = mesh
		model.WorldPivot = CFrame.new()
		model:PivotTo(CFrame.new(guard.X, 0, guard.Z)) -- start on its own path, not at the map origin
		model.Parent = folder
		return model
	end
	local color = Build.Shade(Build.Hex(zone.AccentColor), -0.35)
	local body = Build.Ellipsoid({
		Name = "Body",
		Size = Vector3.new(r * 2, r * 1.7, r * 2),
		CFrame = CFrame.new(0, r * 0.85, 0),
		Color = color,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = model,
	})
	model.PrimaryPart = body
	for _, side in { -1, 1 } do
		Build.Part({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(r * 0.35, r * 0.35, r * 0.35),
			CFrame = CFrame.new(side * r * 0.35, r * 1.05, -r * 0.88),
			Color = "#FFFFFF",
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Parent = model,
		})
		Build.Part({
			Name = "Brow",
			Size = Vector3.new(r * 0.45, r * 0.1, r * 0.1),
			CFrame = CFrame.new(side * r * 0.35, r * 1.3, -r * 0.9) * CFrame.Angles(0, 0, side * 0.45),
			Color = "#1B1B1B",
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Parent = model,
		})
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 80, 80)
	light.Range = r * 3
	light.Parent = body
	model.WorldPivot = CFrame.new() -- pivot on the ground under the guard
	model:PivotTo(CFrame.new(guard.X, 0, guard.Z)) -- start on its own path, not at the map origin
	model.Parent = folder
	return model
end

local function buildSweeper(guard: MapLayout.Guard): BasePart
	Build.Part({
		Name = guard.Id .. "_Pivot",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(6, 3, 3),
		CFrame = CFrame.new(guard.X, 3, guard.Z) * CFrame.Angles(0, 0, math.pi / 2),
		Color = "#37474F",
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = folder,
	})
	return Build.Part({
		Name = guard.Id,
		Size = Vector3.new(guard.Amplitude * 2, 1.4, guard.Radius * 2),
		CFrame = CFrame.new(guard.X, 2.2, guard.Z),
		Color = "#FF1744",
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = folder,
	})
end

function GuardController.Init()
	folder = Instance.new("Folder")
	folder.Name = "GuardsLocal"
	folder.Parent = Workspace
	for _, zone in MapLayout.Zones do
		for _, guard in zone.Guards do
			local visual: Visual = { Guard = guard, Model = nil, Arm = nil }
			if guard.Kind == "Patrol" then
				visual.Model = buildPatrol(guard)
			else
				visual.Arm = buildSweeper(guard)
			end
			table.insert(visuals, visual)
		end
	end
end

-- Meshes may arrive after the guards were first drawn: swap the part guards for mesh guards.
local function upgradeToMeshes()
	for _, visual in visuals do
		if visual.Model then
			visual.Model:Destroy()
			visual.Model = buildPatrol(visual.Guard)
		end
	end
end

function GuardController.Start()
	if not MeshLibrary.Has("Guard") then
		local connection
		connection = ReplicatedStorage.ChildAdded:Connect(function(child)
			if child.Name == "MeshTemplates" then
				connection:Disconnect()
				upgradeToMeshes()
			end
		end)
	end
	local player = Players.LocalPlayer
	RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local t = Workspace:GetServerTimeNow()
		local camZ = camera.CFrame.Position.Z
		local _ = player
		for _, visual in visuals do
			local guard = visual.Guard
			if math.abs(guard.Z - camZ) < 450 then
				if visual.Model then
					local x, z = GuardMotion.PatrolPosition(guard, t)
					local hop = math.abs(math.sin(t * 5 + guard.Phase)) * 1.2
					visual.Model:PivotTo(
						CFrame.new(x, hop, z)
							* CFrame.Angles(
								0,
								if math.cos(t * math.pi * 2 / guard.Period + guard.Phase) > 0
									then -math.pi / 2
									else math.pi / 2,
								0
							)
					)
				elseif visual.Arm then
					local angle = GuardMotion.SweeperAngle(guard, t)
					visual.Arm.CFrame = CFrame.new(guard.X, 2.2, guard.Z) * CFrame.Angles(0, -angle, 0)
				end
			end
		end
	end)
end

return GuardController
