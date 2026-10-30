--!strict
-- Treadmill visuals: the belt carries blobs of its satisfying texture (slime, squishy, butter,
-- 왁뿌볼...) that squish or crunch under your feet, the character runs in place while on an owned
-- treadmill, and labels / buy prompts show what this player owns. Speed is decided on the server.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local StateController = require(script.Parent.StateController)

local TreadmillController = {}

local player = Players.LocalPlayer
local ROWS = 6 -- blob rows riding the belt
local PER_ROW = 3
local BELT_SPEED = 6 -- studs per second (visual only)
local ANIMATE_DISTANCE = 140 -- only animate belts this close to the camera
local STEP_SECONDS = 0.32 -- one squish / crunch per footstep while running

type Blob = { Part: BasePart, Offset: number, X: number }
type Belt = { Part: BasePart, Blobs: { Blob } }
local belts: { Belt } = {}
local runTrack: AnimationTrack? = nil

-- Mesh shape and size (x, y, z as a fraction of a blob cell) for each kind of texture.
local SHAPES: { [string]: { Mesh: Enum.MeshType, Scale: Vector3, Transparency: number } } = {
	Slime = { Mesh = Enum.MeshType.Sphere, Scale = Vector3.new(0.95, 0.25, 0.85), Transparency = 0.2 },
	Squishy = { Mesh = Enum.MeshType.Sphere, Scale = Vector3.new(0.8, 0.55, 0.8), Transparency = 0 },
	Crunch = { Mesh = Enum.MeshType.Sphere, Scale = Vector3.new(0.85, 0.4, 0.85), Transparency = 0 },
	Click = { Mesh = Enum.MeshType.Brick, Scale = Vector3.new(0.75, 0.35, 0.75), Transparency = 0 },
	Wax = { Mesh = Enum.MeshType.Sphere, Scale = Vector3.new(0.8, 0.8, 0.8), Transparency = 0 },
}

local function addBelt(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local id = part:GetAttribute("TreadmillId")
	local def = if type(id) == "string" then Config.Treadmills[id] else nil
	if not def then
		return
	end
	local texture = def.Texture
	local shape = SHAPES[texture.Kind] or SHAPES.Squishy
	local material = (Enum.Material :: any)[texture.Material] or Enum.Material.SmoothPlastic
	local cell = math.min((part.Size.X - 0.6) / PER_ROW, part.Size.Z / ROWS)
	local blobs: { Blob } = {}
	for row = 1, ROWS do
		for column = 1, PER_ROW do
			local blob = Instance.new("Part")
			blob.Name = "Blob"
			blob.Anchored = true
			blob.CanCollide = false
			blob.CanQuery = false
			blob.CanTouch = false
			blob.CastShadow = false
			blob.Size = Vector3.new(cell, cell, cell)
			blob.Material = material
			blob.Transparency = shape.Transparency
			-- every few blobs uses the accent color, like the swirl in a butter or wax ball
			local accent = (row + column) % 3 == 0
			blob.Color = Color3.fromHex(if accent then texture.Accent else texture.Base)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = shape.Mesh
			mesh.Scale = shape.Scale
			mesh.Parent = blob
			blob.Parent = part
			local x = (column - (PER_ROW + 1) / 2) * cell
			table.insert(blobs, { Part = blob :: BasePart, Offset = (row - 1) / ROWS, X = x })
		end
	end
	table.insert(belts, { Part = part, Blobs = blobs })
end

local function animateBelts(t: number)
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	for _, belt in belts do
		local part = belt.Part
		if (part.Position - eye).Magnitude <= ANIMATE_DISTANCE then
			local length = part.Size.Z
			for _, blob in belt.Blobs do
				-- blobs travel toward -Z (runners face +Z, toward the console)
				local u = ((t * BELT_SPEED / length) + blob.Offset) % 1
				local z = length / 2 - u * length
				local lift = part.Size.Y / 2 + blob.Part.Size.Y * 0.15
				blob.Part.CFrame = part.CFrame * CFrame.new(blob.X, lift, z)
			end
		end
	end
end

-- Footstep sounds of the texture under you (only you hear your own treadmill).
local stepSounds: { Sound } = {}
local nextSound = 1
local stepTexture: Config.TreadmillTexture? = nil
local lastStep = 0

local function playStep()
	local texture = stepTexture
	if not texture then
		return
	end
	local sound: Sound? = stepSounds[nextSound]
	if not sound then
		local created = Instance.new("Sound")
		created.Name = "TreadmillStep"
		created.Parent = SoundService
		stepSounds[nextSound] = created
		sound = created
	end
	assert(sound, "step sound")
	nextSound = nextSound % 3 + 1
	sound.SoundId = texture.Sound
	sound.Volume = texture.Volume
	sound.PlaybackSpeed = texture.Pitch * (0.94 + math.random() * 0.12)
	sound.TimePosition = 0
	sound:Play()
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
					.. "\n"
					.. def.Texture.Name
					.. " · x"
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
		local now = os.clock()
		animateBelts(now)
		if stepTexture and now - lastStep >= STEP_SECONDS then
			lastStep = now
			playStep()
		end
	end)
	StateController.Changed:Connect(function(state: any)
		refreshLabels(state)
		local running = (state.TreadmillMultiplier or 1) > 1
		setRunning(running)
		local on = state.TreadmillOn
		local def = if running and type(on) == "string" then Config.Treadmills[on] else nil
		stepTexture = if def then def.Texture else nil
	end)
	player.CharacterAdded:Connect(function()
		runTrack = nil
	end)
end

return TreadmillController
