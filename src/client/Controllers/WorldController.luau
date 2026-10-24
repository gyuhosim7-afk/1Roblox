--!strict
-- Client-side world polish: speed gates open locally, incubator countdowns, per-player prompt
-- visibility, bouncing / rainbow slimes, the guide beam, the nest odds panel and per-zone sky.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local MapLayout = require(Shared.MapLayout)
local StateController = require(script.Parent.StateController)
local Popups = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Popups"))

local WorldController = {}

local player = Players.LocalPlayer

-- Speed gates ---------------------------------------------------------------------
local function refreshGates(state: any)
	local data = state.Data
	for _, gate in CollectionService:GetTagged("SpeedGate") do
		if gate:IsA("BasePart") then
			local need = gate:GetAttribute("GateSpeed") or 0
			local rebirths = gate:GetAttribute("RebirthsRequired") or 0
			local open = data.Speed >= need and data.Rebirths >= rebirths
			gate.CanCollide = not open
			gate.Transparency = if open then 0.9 else 0.35
			local gui = gate:FindFirstChildWhichIsA("SurfaceGui")
			local label = gui and gui:FindFirstChildWhichIsA("TextLabel")
			if label then
				if open then
					label.Text = "OPEN"
				else
					local text = "Need " .. Format.Number(need) .. " Speed"
					if rebirths > 0 then
						text ..= "\n+ " .. rebirths .. " Rebirths"
					end
					label.Text = text
				end
			end
		end
	end
end

-- Incubators ------------------------------------------------------------------------
local function myPlotModel(): Model?
	for _, plot in CollectionService:GetTagged("Plot") do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			return plot :: Model
		end
	end
	return nil
end

local function applyPromptRule(prompt: ProximityPrompt, part: BasePart)
	local owner = part:GetAttribute("OwnerUserId")
	local isMine = owner == player.UserId
	local kind = prompt:GetAttribute("PromptKind")
	local hide = (kind == "Steal" and isMine) or (kind == "Hatch" and not isMine)
	if kind == "Steal" and not isMine then
		local plot = part.Parent
		local lockedUntil = plot and plot:GetAttribute("LockedUntil") or 0
		if type(lockedUntil) == "number" and lockedUntil > StateController.Now() then
			hide = true
		end
	end
	-- Same rule the server uses (egg present, not being stolen), plus who may see it.
	local eggId = part:GetAttribute("Egg")
	local hasEgg = type(eggId) == "string" and eggId ~= ""
	local desired = hasEgg and part:GetAttribute("Reserved") ~= true and not hide
	if prompt.Enabled ~= desired then
		prompt.Enabled = desired
	end
end

local function watchIncubator(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	for _, child in part:GetChildren() do
		if child:IsA("ProximityPrompt") then
			child:GetPropertyChangedSignal("Enabled"):Connect(function()
				applyPromptRule(child, part)
			end)
			applyPromptRule(child, part)
		end
	end
	part:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		for _, child in part:GetChildren() do
			if child:IsA("ProximityPrompt") then
				applyPromptRule(child, part)
			end
		end
	end)
end

local function updateIncubatorLabels()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local now = StateController.Now()
	for _, part in CollectionService:GetTagged("Incubator") do
		if part:IsA("BasePart") and (part.Position - camera.CFrame.Position).Magnitude < 120 then
			local billboard = part:FindFirstChild("Billboard")
			local label = billboard and billboard:FindFirstChild("Label") :: TextLabel?
			if label then
				local eggId = part:GetAttribute("Egg")
				if type(eggId) ~= "string" or eggId == "" or not Config.Eggs[eggId] then
					label.Text = ""
				elseif part:GetAttribute("Reserved") then
					label.Text = "⚠ BEING STOLEN!"
				else
					local remaining = (part:GetAttribute("HatchAt") or 0) - now
					label.Text = Config.Eggs[eggId].Name
						.. "\n"
						.. (if remaining > 0 then Format.Clock(remaining) else "Hatching...")
				end
			end
			-- owner's hatch prompt shows the gem price
			local hatchPrompt = part:FindFirstChild("HatchPrompt") :: ProximityPrompt?
			if hatchPrompt then
				local remaining = (part:GetAttribute("HatchAt") or 0) - now
				hatchPrompt.ObjectText = Formulas.SkipCost(remaining) .. " Gems"
			end
		end
	end
end

-- Slime animation ------------------------------------------------------------------
type Animated = { Model: Model, Base: CFrame, Phase: number, Body: BasePart? }
local animated: { [Model]: Animated } = {}

local function trackSlime(model: Instance)
	if not model:IsA("Model") then
		return
	end
	animated[model] = {
		Model = model,
		Base = model:GetPivot(),
		Phase = math.random() * 6,
		Body = model:FindFirstChild("Body") :: BasePart?,
	}
end

local function animateSlimes(t: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local camPos = camera.CFrame.Position
	for model, info in animated do
		if model.Parent == nil then
			animated[model] = nil
			continue
		end
		if (info.Base.Position - camPos).Magnitude < 90 then
			local bounce = math.abs(math.sin(t * 2.6 + info.Phase)) * 0.45
			model:PivotTo(info.Base * CFrame.new(0, bounce, 0))
			if info.Body and model:HasTag("RainbowSlime") then
				info.Body.Color = Color3.fromHSV((t * 0.25 + info.Phase) % 1, 0.7, 1)
			end
		end
	end
end

-- Guide beam (to base while carrying, or the tutorial target) ----------------------------
local beamTargetPart: BasePart? = nil
local beam: Beam? = nil
local beamAttachment: Attachment? = nil

local function setBeamTarget(position: Vector3?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not position or not root then
		if beam then
			beam.Enabled = false
		end
		return
	end
	if not beamTargetPart then
		local part = Instance.new("Part")
		part.Name = "GuideTarget"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(1, 1, 1)
		part.Parent = Workspace
		local attachment = Instance.new("Attachment")
		attachment.Name = "Target"
		attachment.Parent = part
		beamTargetPart = part
	end
	local targetPart = beamTargetPart :: BasePart
	targetPart.Position = position + Vector3.new(0, 2, 0)
	if not beamAttachment or beamAttachment.Parent ~= root then
		local attachment = Instance.new("Attachment")
		attachment.Name = "GuideSource"
		attachment.Parent = root
		beamAttachment = attachment
		if beam then
			beam:Destroy()
		end
		local newBeam = Instance.new("Beam")
		newBeam.Attachment0 = attachment
		newBeam.Attachment1 = targetPart:FindFirstChild("Target") :: Attachment
		newBeam.Width0 = 1.2
		newBeam.Width1 = 1.2
		newBeam.FaceCamera = true
		newBeam.LightEmission = 1
		newBeam.Color = ColorSequence.new(Color3.fromRGB(255, 213, 79))
		newBeam.Transparency = NumberSequence.new(0.2)
		newBeam.Parent = targetPart
		beam = newBeam
	end
	if beam then
		beam.Enabled = true
	end
end

local function homePosition(local_: MapLayout.Point?): Vector3?
	local plotModel = myPlotModel()
	if not plotModel then
		return nil
	end
	local index = plotModel:GetAttribute("PlotIndex")
	local plot = MapLayout.Plots[if type(index) == "number" then index else 0]
	if not plot then
		return nil
	end
	local point = local_ or MapLayout.PlotLocal.Spawn
	local x, z = MapLayout.PlotToWorld(plot, point.X, point.Z)
	return Vector3.new(x, 1, z)
end

local function nearestNest(position: Vector3, zone: number?): (Model?, number)
	local best, bestDistance = nil, math.huge
	for _, nest in CollectionService:GetTagged("Nest") do
		if nest:IsA("Model") and (zone == nil or nest:GetAttribute("Zone") == zone) then
			local pivot = nest:GetPivot().Position
			local distance = (pivot - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = nest, distance
			end
		end
	end
	return best, bestDistance
end

local function updateGuide()
	local state = StateController.State
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not state or not root then
		setBeamTarget(nil)
		Popups.NestOdds(nil, nil)
		return
	end
	local carrying = player:GetAttribute("CarryingEgg")
	local step = state.Data.TutorialStep
	if type(carrying) == "string" or step == 2 then
		setBeamTarget(homePosition(nil))
	elseif step == 1 then
		local nest = nearestNest(root.Position, 1)
		setBeamTarget(if nest then nest:GetPivot().Position else nil)
	elseif step == 4 then
		setBeamTarget(homePosition(MapLayout.PlotLocal.CollectPad))
	else
		setBeamTarget(nil)
	end

	local nest, distance = nearestNest(root.Position, nil)
	if nest and distance < 30 then
		local eggId = nest:GetAttribute("Egg")
		Popups.NestOdds(if type(eggId) == "string" then eggId else nil, state)
	else
		Popups.NestOdds(nil, nil)
	end
end

-- Zone sky ------------------------------------------------------------------------
local currentAmbience = -1

local function hex(value: string): Color3
	local clean = value:gsub("#", "")
	return Color3.fromRGB(
		tonumber(clean:sub(1, 2), 16) or 255,
		tonumber(clean:sub(3, 4), 16) or 255,
		tonumber(clean:sub(5, 6), 16) or 255
	)
end

-- Tweens the sky to the look of the zone the player stands in (home uses the first zone).
local function updateAmbience()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local zoneIndex = math.max(1, MapLayout.ZoneAtZ(root.Position.Z))
	if zoneIndex == currentAmbience then
		return
	end
	currentAmbience = zoneIndex
	local ambience = Config.Zones[zoneIndex].Ambience
	local info = TweenInfo.new(2.5, Enum.EasingStyle.Sine)
	TweenService:Create(Lighting, info, { ClockTime = ambience.ClockTime, Brightness = ambience.Brightness }):Play()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		TweenService:Create(atmosphere, info, {
			Density = ambience.Density,
			Haze = ambience.Haze,
			Color = hex(ambience.Atmosphere),
		}):Play()
	end
	local grading = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if grading then
		TweenService:Create(grading, info, { TintColor = hex(ambience.Tint) }):Play()
	end
end

function WorldController.Init() end

function WorldController.Start()
	StateController.StatsChanged:Connect(refreshGates)
	CollectionService:GetInstanceAddedSignal("SpeedGate"):Connect(function()
		local state = StateController.State
		if state then
			refreshGates(state)
		end
	end)

	for _, part in CollectionService:GetTagged("Incubator") do
		watchIncubator(part)
	end
	CollectionService:GetInstanceAddedSignal("Incubator"):Connect(watchIncubator)

	for _, model in CollectionService:GetTagged("PedestalSlime") do
		trackSlime(model)
	end
	CollectionService:GetInstanceAddedSignal("PedestalSlime"):Connect(trackSlime)
	CollectionService:GetInstanceRemovedSignal("PedestalSlime"):Connect(function(model)
		animated[model :: Model] = nil
	end)

	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		if accumulator >= 1 / 30 then
			accumulator = 0
			animateSlimes(os.clock())
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			updateIncubatorLabels()
			updateGuide()
			updateAmbience()
			-- re-apply prompt rules (lock state changes over time)
			for _, part in CollectionService:GetTagged("Incubator") do
				if part:IsA("BasePart") then
					for _, child in part:GetChildren() do
						if child:IsA("ProximityPrompt") then
							applyPromptRule(child, part)
						end
					end
				end
			end
		end
	end)
end

return WorldController
