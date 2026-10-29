--!strict
-- Treadmill visuals: moving belt stripes, the character runs in place while on an owned
-- treadmill, and labels / buy prompts show what this player owns. Speed is decided on the server.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local StateController = require(script.Parent.StateController)

local TreadmillController = {}

local player = Players.LocalPlayer
local STRIPES = 4
local BELT_SPEED = 6 -- studs per second (visual only)

type Belt = { Part: BasePart, Stripes: { BasePart } }
local belts: { Belt } = {}
local runTrack: AnimationTrack? = nil

local function addBelt(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local stripes: { BasePart } = {}
	for i = 1, STRIPES do
		local stripe = Instance.new("Part")
		stripe.Name = "BeltStripe"
		stripe.Anchored = true
		stripe.CanCollide = false
		stripe.CanQuery = false
		stripe.CanTouch = false
		stripe.CastShadow = false
		stripe.Material = Enum.Material.Neon
		stripe.Color = Color3.fromRGB(255, 255, 255)
		stripe.Transparency = 0.6
		stripe.Size = Vector3.new(part.Size.X - 0.4, 0.05, 0.5)
		stripe:SetAttribute("Offset", (i - 1) / STRIPES)
		stripe.Parent = part
		table.insert(stripes, stripe)
	end
	table.insert(belts, { Part = part, Stripes = stripes })
end

local function animateBelts(t: number)
	for _, belt in belts do
		local part = belt.Part
		local length = part.Size.Z
		for _, stripe in belt.Stripes do
			local offset = (stripe:GetAttribute("Offset") :: number?) or 0
			-- stripes travel toward -Z (runners face +Z, toward the console)
			local u = ((t * BELT_SPEED / length) + offset) % 1
			local z = length / 2 - u * length
			stripe.CFrame = part.CFrame * CFrame.new(0, part.Size.Y / 2 + 0.03, z)
		end
	end
end

local function setRunning(on: boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if on then
		if runTrack or not humanoid or not character then
			return
		end
		local animate = character:FindFirstChild("Animate")
		local run = animate and animate:FindFirstChild("run")
		local animation = run and run:FindFirstChildOfClass("Animation")
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animation and animator then
			local ok, track = pcall(function()
				return animator:LoadAnimation(animation)
			end)
			if ok and track then
				track.Looped = true
				track:Play(0.2)
				track:AdjustSpeed(1.4)
				runTrack = track
			end
		end
	elseif runTrack then
		runTrack:Stop(0.2)
		runTrack = nil
	end
end

local function refreshLabels(state: any)
	local owned = state.Data.Treadmills or {}
	local passes = state.Passes or {}
	for _, model in CollectionService:GetTagged("TreadmillBelt") do
		local id = model:GetAttribute("TreadmillId")
		local def = if type(id) == "string" then Config.Treadmills[id] else nil
		local treadmill = model.Parent
		if def and treadmill then
			local mine = Formulas.OwnsTreadmill(id :: string, owned, passes)
			local console = treadmill:FindFirstChild("Console")
			local billboard = console and console:FindFirstChild("TreadmillLabel")
			local label = billboard and billboard:FindFirstChild("Label") :: TextLabel?
			if label then
				local lockText = if def.RequiresPass
					then "Pass only"
					elseif def.Rebirths and (state.Data.Rebirths or 0) < def.Rebirths then "$" .. Format.Number(
						def.Cost
					) .. " + " .. def.Rebirths .. " Rebirths"
					else "$" .. Format.Number(def.Cost)
				label.Text = def.Name
					.. "\nx"
					.. def.Multiplier
					.. " Speed"
					.. (if mine then "" else "  🔒 " .. lockText)
			end
			local prompt = console and console:FindFirstChild("BuyPrompt") :: ProximityPrompt?
			if prompt then
				prompt.Enabled = not mine
			end
		end
	end
end

function TreadmillController.Init()
	for _, part in CollectionService:GetTagged("TreadmillBelt") do
		addBelt(part)
	end
	CollectionService:GetInstanceAddedSignal("TreadmillBelt"):Connect(addBelt)
end

function TreadmillController.Start()
	RunService.RenderStepped:Connect(function()
		animateBelts(os.clock())
	end)
	StateController.Changed:Connect(function(state: any)
		refreshLabels(state)
		setRunning((state.TreadmillMultiplier or 1) > 1)
	end)
	player.CharacterAdded:Connect(function()
		runTrack = nil
	end)
end

return TreadmillController
