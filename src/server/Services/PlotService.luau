--!strict
-- Player bases: builds the 8 plots, assigns one per player, spawns players at home,
-- and offers position helpers (is this point inside a plot?).

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local MapLayout = require(Shared.MapLayout)
local Build = require(Shared.Build)
local Signal = require(Shared.Signal)
local Formulas = require(Shared.Formulas)
local MapService = require(script.Parent.MapService)
local PlayerService = require(script.Parent.PlayerService)
local BoostService = require(script.Parent.BoostService)

export type Slot = { Index: number, Part: BasePart, Anchor: CFrame, Label: TextLabel? }
export type PlotState = {
	Index: number,
	Layout: MapLayout.PlotLayout,
	CFrame: CFrame, -- plot center at ground level, LookVector faces the road
	Model: Model,
	Owner: Player?,
	Incubators: { Slot },
	Pedestals: { Slot },
	CollectPad: BasePart,
	LockPad: BasePart,
	Barrier: BasePart,
	SignLabel: TextLabel,
	BankLabel: TextLabel,
	LockedUntil: number,
}

local PlotService = {}

PlotService.PlotAssigned = Signal.new() -- (player, plot)
PlotService.PlotReleased = Signal.new() -- (player, plot)

local plots: { PlotState } = {}
local byPlayer: { [Player]: PlotState } = {}

local FLOOR_COLORS = { "#FFC46B", "#8EDB8E", "#7FC4FF", "#FF9EC7", "#B9A2FF", "#FFE45C", "#6EE0E8", "#FF9F80" }

local function localCFrame(plotCFrame: CFrame, lx: number, ly: number, lz: number): CFrame
	return plotCFrame * CFrame.new(lx, ly, lz)
end

local function buildPlot(parent: Instance, layout: MapLayout.PlotLayout): PlotState
	local center = Vector3.new(layout.X, 0, layout.Z)
	local plotCFrame = CFrame.lookAt(center, center + Vector3.new(-layout.Side, 0, 0))
	local half = MapLayout.PlotLocal.Half
	local size = Config.Map.PlotSize
	local wallHeight = Config.Map.PlotWallHeight
	local floorColor = Build.Hex(FLOOR_COLORS[layout.Index] or "#FFFFFF")

	local model = Build.Model("Plot" .. layout.Index, parent)
	local floor = Build.Part({
		Name = "Floor",
		Size = Vector3.new(size, 1, size),
		CFrame = localCFrame(plotCFrame, 0, 0.5, 0),
		Color = floorColor,
		Parent = model,
	})
	floor.TopSurface = Enum.SurfaceType.Studs
	model.PrimaryPart = floor

	-- Walls: back and both sides (front stays open toward the road)
	local wallColor = Build.Shade(floorColor, -0.25)
	Build.Part({
		Name = "BackWall",
		Size = Vector3.new(size, wallHeight, 1),
		CFrame = localCFrame(plotCFrame, 0, 1 + wallHeight / 2, half - 0.5),
		Color = wallColor,
		Parent = model,
	})
	for _, side in { -1, 1 } do
		Build.Part({
			Name = "SideWall",
			Size = Vector3.new(1, wallHeight, size),
			CFrame = localCFrame(plotCFrame, side * (half - 0.5), 1 + wallHeight / 2, 0),
			Color = wallColor,
			Parent = model,
		})
		Build.Part({
			Name = "WallTrim",
			Size = Vector3.new(2, 1, size + 1),
			CFrame = localCFrame(plotCFrame, side * (half - 0.5), 1 + wallHeight + 0.5, 0),
			Color = "#FFFFFF",
			Parent = model,
		})
	end
	Build.Part({
		Name = "WallTrim",
		Size = Vector3.new(size + 1, 1, 2),
		CFrame = localCFrame(plotCFrame, 0, 1 + wallHeight + 0.5, half - 0.5),
		Color = "#FFFFFF",
		Parent = model,
	})

	-- Sign
	local sign = Build.Part({
		Name = "Sign",
		Size = Vector3.new(24, 6, 1),
		CFrame = localCFrame(plotCFrame, 0, wallHeight + 5, half - 0.5),
		Color = Build.Shade(floorColor, -0.4),
		Parent = model,
	})
	local signGui = Build.SurfaceText(sign, Enum.NormalId.Front, "Empty Base", Color3.new(1, 1, 1))
	local signLabel = signGui:FindFirstChild("Label") :: TextLabel

	-- Incubators
	local incubators: { Slot } = {}
	for index, point in MapLayout.PlotLocal.Incubators do
		local base = Build.Part({
			Name = "Incubator" .. index,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1, 4.4, 4.4),
			CFrame = localCFrame(plotCFrame, point.X, 1.5, point.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = "#90A4AE",
			Material = Enum.Material.Metal,
			Parent = model,
		})
		Build.Part({
			Name = "Glow",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 4.8, 4.8),
			CFrame = localCFrame(plotCFrame, point.X, 1.9, point.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = "#FFD54F",
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = base,
		})
		local billboard = Build.Billboard(base, "", UDim2.fromScale(5, 1.4), Vector3.new(0, 5.5, 0), 70)
		local label = billboard:FindFirstChild("Label") :: TextLabel
		base:SetAttribute("Slot", index)
		base:SetAttribute("Plot", layout.Index)
		base:AddTag("Incubator")
		table.insert(incubators, {
			Index = index,
			Part = base,
			Anchor = localCFrame(plotCFrame, point.X, 3.6, point.Z),
			Label = label,
		})
	end

	-- Pedestals
	local pedestals: { Slot } = {}
	for index, point in MapLayout.PlotLocal.Pedestals do
		local pedestal = Build.Part({
			Name = "Pedestal" .. index,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.2, 4.6, 4.6),
			CFrame = localCFrame(plotCFrame, point.X, 1.6, point.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = "#F5F5FA",
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
		-- glowing rim: green = slime on it, white = free, red = locked (needs Pedestals upgrade)
		Build.Part({
			Name = "Glow",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 5.2, 5.2),
			CFrame = localCFrame(plotCFrame, point.X, 1.3, point.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = "#FFFFFF",
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = pedestal,
		})
		pedestal:SetAttribute("Slot", index)
		pedestal:SetAttribute("Plot", layout.Index)
		table.insert(pedestals, {
			Index = index,
			Part = pedestal,
			Anchor = localCFrame(plotCFrame, point.X, 2.2, point.Z),
		})
	end

	-- Collect pad
	local cp = MapLayout.PlotLocal.CollectPad
	local collectPad = Build.Part({
		Name = "CollectPad",
		Size = Vector3.new(cp.Size, 0.6, cp.Size),
		CFrame = localCFrame(plotCFrame, cp.X, 1.3, cp.Z),
		Color = "#43A047",
		Material = Enum.Material.Neon,
		Parent = model,
	})
	local bankGui = Build.Billboard(collectPad, "COLLECT\n$0", UDim2.fromScale(7, 3), Vector3.new(0, 4, 0), 90)
	local bankLabel = bankGui:FindFirstChild("Label") :: TextLabel
	bankLabel.TextColor3 = Build.Hex("#B9F6CA")

	-- Lock pad
	local lp = MapLayout.PlotLocal.LockPad
	local lockPad = Build.Part({
		Name = "LockPad",
		Size = Vector3.new(lp.Size, 0.6, lp.Size),
		CFrame = localCFrame(plotCFrame, lp.X, 1.3, lp.Z),
		Color = "#E53935",
		Material = Enum.Material.Neon,
		Parent = model,
	})
	Build.Billboard(lockPad, "LOCK BASE", UDim2.fromScale(7, 1.6), Vector3.new(0, 3, 0), 70)

	-- Barrier across the entrance (visible only while locked)
	local barrier = Build.Part({
		Name = "Barrier",
		Size = Vector3.new(size - 2, 12, 0.6),
		CFrame = localCFrame(plotCFrame, 0, 7, -half),
		Color = "#FF1744",
		Material = Enum.Material.ForceField,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Parent = model,
	})

	-- Spawn marker
	local sp = MapLayout.PlotLocal.Spawn
	local spawnPart = Build.Part({
		Name = "SpawnPoint",
		Size = Vector3.new(4, 0.2, 4),
		CFrame = localCFrame(plotCFrame, sp.X, 1.1, sp.Z),
		Color = "#FFFFFF",
		Transparency = 0.6,
		CanCollide = false,
		Parent = model,
	})
	local _ = spawnPart

	model:SetAttribute("PlotIndex", layout.Index)
	model:SetAttribute("OwnerUserId", 0)
	model:SetAttribute("LockedUntil", 0)
	model:AddTag("Plot")

	return {
		Index = layout.Index,
		Layout = layout,
		CFrame = plotCFrame,
		Model = model,
		Owner = nil,
		Incubators = incubators,
		Pedestals = pedestals,
		CollectPad = collectPad,
		LockPad = lockPad,
		Barrier = barrier,
		SignLabel = signLabel,
		BankLabel = bankLabel,
		LockedUntil = 0,
	}
end

function PlotService.Get(player: Player): PlotState?
	return byPlayer[player]
end

function PlotService.GetByIndex(index: number): PlotState?
	return plots[index]
end

function PlotService.GetByUserId(userId: number): PlotState?
	for player, plot in byPlayer do
		if player.UserId == userId then
			return plot
		end
	end
	return nil
end

function PlotService.All(): { PlotState }
	return plots
end

function PlotService.Contains(plot: PlotState, position: Vector3, margin: number?): boolean
	return position.Y < 40 and MapLayout.IsInPlot(plot.Layout, position.X, position.Z, margin)
end

function PlotService.PlotAtPosition(position: Vector3): PlotState?
	for _, plot in plots do
		if PlotService.Contains(plot, position) then
			return plot
		end
	end
	return nil
end

function PlotService.SpawnCFrame(plot: PlotState): CFrame
	local sp = MapLayout.PlotLocal.Spawn
	return localCFrame(plot.CFrame, sp.X, 4, sp.Z) * CFrame.Angles(0, math.pi, 0)
end

function PlotService.TeleportHome(player: Player)
	local plot = byPlayer[player]
	local character = player.Character
	if plot and character then
		character:PivotTo(PlotService.SpawnCFrame(plot))
	end
end

-- Moves a character to just outside a plot's entrance.
function PlotService.PushOut(player: Player, plot: PlotState)
	local character = player.Character
	if not character then
		return
	end
	local x, z = MapLayout.PlotEntrance(plot.Layout, 10)
	character:PivotTo(CFrame.new(x, 4, z))
end

function PlotService.IsLocked(plot: PlotState): boolean
	return plot.LockedUntil > os.time()
end

-- Shows which incubator/pedestal slots the owner has unlocked.
function PlotService.RefreshSlots(plot: PlotState)
	local owner = plot.Owner
	local incubatorCount, pedestalCount = 0, 0
	if owner then
		local session = PlayerService.Get(owner)
		if session then
			local hasPass = BoostService.HasPass(owner, "ExtraIncubators")
			incubatorCount = Formulas.IncubatorCount(session.Data.IncubatorLevel, hasPass)
			pedestalCount = Formulas.PedestalCount(session.Data.PedestalLevel)
		end
	end
	for _, slot in plot.Incubators do
		local unlocked = slot.Index <= incubatorCount
		slot.Part.Transparency = if unlocked then 0 else 0.75
		slot.Part:SetAttribute("Unlocked", unlocked)
		local glow = slot.Part:FindFirstChild("Glow") :: BasePart?
		if glow then
			glow.Transparency = if unlocked then 0 else 1
		end
	end
	for _, slot in plot.Pedestals do
		local unlocked = slot.Index <= pedestalCount
		slot.Part.Transparency = if unlocked then 0 else 0.75
		slot.Part:SetAttribute("Unlocked", unlocked)
	end
end

local function assign(player: Player)
	if byPlayer[player] then
		return
	end
	for _, plot in plots do
		if plot.Owner == nil then
			plot.Owner = player
			plot.LockedUntil = 0
			byPlayer[player] = plot
			plot.Model:SetAttribute("OwnerUserId", player.UserId)
			plot.Model:SetAttribute("OwnerName", player.DisplayName)
			plot.Model:SetAttribute("LockedUntil", 0)
			plot.SignLabel.Text = player.DisplayName .. "'s Base"
			plot.BankLabel.Text = "COLLECT\n$0"
			PlotService.RefreshSlots(plot)
			PlotService.PlotAssigned:Fire(player, plot)
			return
		end
	end
	player:Kick("This server is full. Please join another server!")
end

local function release(player: Player)
	local plot = byPlayer[player]
	if not plot then
		return
	end
	byPlayer[player] = nil
	PlotService.PlotReleased:Fire(player, plot)
	plot.Owner = nil
	plot.LockedUntil = 0
	plot.Model:SetAttribute("OwnerUserId", 0)
	plot.Model:SetAttribute("OwnerName", "")
	plot.Model:SetAttribute("LockedUntil", 0)
	plot.Barrier.Transparency = 1
	plot.SignLabel.Text = "Empty Base"
	plot.BankLabel.Text = "COLLECT\n$0"
	PlotService.RefreshSlots(plot)
end

function PlotService.Init()
	local root = MapService.Root
	assert(root, "MapService must build the map first")
	local folder = root:FindFirstChild("Plots") :: Folder
	for _, layout in MapLayout.Plots do
		plots[layout.Index] = buildPlot(folder, layout)
	end

	PlayerService.RegisterState("Plot", function(session)
		local plot = byPlayer[session.Player]
		return plot and plot.Index or 0
	end)
	PlayerService.RegisterState("LockedUntil", function(session)
		local plot = byPlayer[session.Player]
		return plot and plot.LockedUntil or 0
	end)
end

function PlotService.Start()
	PlayerService.PlayerReady:Connect(function(player: Player)
		assign(player)
		local function onCharacter(character: Model)
			task.defer(function()
				if character.Parent and byPlayer[player] then
					character:PivotTo(PlotService.SpawnCFrame(byPlayer[player]))
				end
			end)
		end
		player.CharacterAdded:Connect(onCharacter)
		if player.Character then
			onCharacter(player.Character)
		end
	end)
	PlayerService.PlayerLeaving:Connect(function(player: Player)
		release(player)
	end)
	BoostService.PassesChanged:Connect(function(player: Player)
		local plot = byPlayer[player]
		if plot then
			PlotService.RefreshSlots(plot)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		release(player)
	end)
end

return PlotService
