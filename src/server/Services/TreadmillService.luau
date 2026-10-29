--!strict
-- Treadmills in the gym behind the spawn. Standing on an owned treadmill multiplies Speed gain
-- (server checks the position; the client only animates). Treadmills are bought with coins.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local MapLayout = require(Shared.MapLayout)
local Build = require(Shared.Build)
local Validate = require(script.Parent.Parent.Logic.Validate)
local PlayerService = require(script.Parent.PlayerService)
local MapService = require(script.Parent.MapService)
local EggService = require(script.Parent.EggService)
local Network = require(script.Parent.Network)

local TreadmillService = {}

local GROUND_Y = 0

local function passesOf(session: PlayerService.Session): { [string]: boolean }
	return session.Runtime.Passes or {}
end

function TreadmillService.Owns(player: Player, id: string): boolean
	local session = PlayerService.Get(player)
	if not session then
		return false
	end
	return Formulas.OwnsTreadmill(id, session.Data.Treadmills, passesOf(session))
end

-- Multiplier the player gets right now (nil when not on an owned treadmill).
function TreadmillService.CurrentMultiplier(player: Player): number?
	local session = PlayerService.Get(player)
	return session and session.Runtime.TreadmillMultiplier or nil
end

function TreadmillService.Buy(player: Player, payload: any): (boolean, string?)
	local session = PlayerService.Get(player)
	local id = Validate.Key(payload, Config.Treadmills :: any)
	if not session or not id then
		return false, "Bad request"
	end
	local def = Config.Treadmills[id]
	if TreadmillService.Owns(player, id) then
		return false, "You already own this treadmill!"
	end
	local lock = Formulas.TreadmillLock(id, session.Data.Speed, session.Data.Rebirths)
	if lock then
		return false, lock
	end
	if session.Data.Coins < def.Cost then
		return false, "Not enough coins (need $" .. Format.Number(def.Cost) .. ")"
	end
	session.Data.Coins -= def.Cost
	session.Data.Treadmills[id] = true
	PlayerService.MarkDirty(player, true)
	return true, def.Name .. " unlocked! Stand on it for x" .. def.Multiplier .. " Speed"
end

-- Which treadmill each player stands on; updates the speed multiplier.
function TreadmillService.Tick()
	for _, session in PlayerService.All() do
		local player = session.Player
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local id: string? = nil
		if root and not EggService.CarryOf(player) then
			local pos = root.Position
			id = MapLayout.TreadmillAt(pos.X, pos.Y - GROUND_Y, pos.Z)
		end
		local multiplier: number? = nil
		if id and Formulas.OwnsTreadmill(id, session.Data.Treadmills, passesOf(session)) then
			multiplier = Config.Treadmills[id].Multiplier
		end
		if session.Runtime.TreadmillMultiplier ~= multiplier or session.Runtime.TreadmillOn ~= id then
			local wasOn = session.Runtime.TreadmillMultiplier
			session.Runtime.TreadmillMultiplier = multiplier
			session.Runtime.TreadmillOn = id
			PlayerService.MarkDirty(player, true)
			if id and not multiplier and session.Runtime.TreadmillHint ~= id then
				session.Runtime.TreadmillHint = id
				local def = Config.Treadmills[id]
				local how = Formulas.TreadmillLock(id, session.Data.Speed, session.Data.Rebirths)
					or ("Buy it for $" .. Format.Number(def.Cost))
				Network.Notify(player, def.Name .. " is locked. " .. how .. ".", "info")
			elseif multiplier and not wasOn then
				session.Runtime.TreadmillHint = nil
			end
		end
	end
end

local function buildTreadmill(parent: Instance, info: MapLayout.TreadmillLayout)
	local def = Config.Treadmills[info.Id]
	local layout = Config.TreadmillLayout
	local model = Build.Model("Treadmill_" .. info.Id, parent)
	local base = Build.Part({
		Name = "Base",
		Size = Vector3.new(layout.Width + 2, 1, layout.Length + 2),
		Position = Vector3.new(info.X, GROUND_Y + 0.5, info.Z),
		Color = "#37474F",
		Material = Enum.Material.Metal,
		Parent = model,
	})
	model.PrimaryPart = base
	local belt = Build.Part({
		Name = "Belt",
		Size = Vector3.new(layout.Width, 0.3, layout.Length),
		Position = Vector3.new(info.X, GROUND_Y + 1.15, info.Z),
		Color = "#212121",
		Material = Enum.Material.Rubber,
		Parent = model,
	})
	belt:SetAttribute("TreadmillId", info.Id)
	belt:AddTag("TreadmillBelt")
	for _, side in { -1, 1 } do
		Build.Part({
			Name = "Rail",
			Size = Vector3.new(0.6, 0.8, layout.Length + 2),
			Position = Vector3.new(info.X + side * (layout.Width / 2 + 0.6), GROUND_Y + 1.4, info.Z),
			Color = def.Color,
			Material = Enum.Material.Neon,
			Parent = model,
		})
		Build.Part({
			Name = "Post",
			Size = Vector3.new(0.6, 4, 0.6),
			Position = Vector3.new(
				info.X + side * (layout.Width / 2 + 0.6),
				GROUND_Y + 3,
				info.Z + layout.Length / 2 + 0.5
			),
			Color = "#B0BEC5",
			Material = Enum.Material.Metal,
			Parent = model,
		})
	end
	local console = Build.Part({
		Name = "Console",
		Size = Vector3.new(layout.Width + 1.8, 1.4, 1),
		Position = Vector3.new(info.X, GROUND_Y + 5, info.Z + layout.Length / 2 + 0.5),
		Color = def.Color,
		Parent = model,
	})
	local billboard = Build.Billboard(
		console,
		def.Name .. "\nx" .. def.Multiplier .. " Speed",
		UDim2.fromScale(9, 2.6),
		Vector3.new(0, 3.6, 0),
		90
	)
	billboard.Name = "TreadmillLabel"
	local label = billboard:FindFirstChild("Label") :: TextLabel
	label.TextColor3 = Build.Hex(def.Color)

	if def.Cost > 0 then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "BuyPrompt"
		prompt.ActionText = "Buy $" .. Format.Number(def.Cost)
		prompt.ObjectText = def.Name .. " (x" .. def.Multiplier .. ")"
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("TreadmillId", info.Id)
		prompt.Parent = console
		prompt.Triggered:Connect(function(player: Player)
			local ok, message = TreadmillService.Buy(player, info.Id)
			if message then
				Network.Notify(player, message, if ok then "success" else "error")
			end
		end)
	end
	model:SetAttribute("TreadmillId", info.Id)
end

function TreadmillService.Init()
	local root = MapService.Root
	assert(root, "MapService must build the map first")
	local home = root:FindFirstChild("Home") or root
	local folder = Build.Folder("Treadmills", home)
	for _, info in MapLayout.Treadmills do
		buildTreadmill(folder, info)
	end
	-- a sign for the gym
	local sign = Build.Part({
		Name = "GymSign",
		Size = Vector3.new(30, 6, 1),
		Position = Vector3.new(0, 9, MapLayout.Treadmills[1].Z - Config.TreadmillLayout.Length / 2 - 6),
		Color = "#FF4FA3",
		Parent = folder,
	})
	Build.SurfaceText(sign, Enum.NormalId.Back, "SPEED GYM", Color3.new(1, 1, 1))

	Network.Handle("BuyTreadmill", TreadmillService.Buy)
	PlayerService.RegisterState("TreadmillOn", function(session)
		return session.Runtime.TreadmillOn
	end)
	PlayerService.RegisterState("TreadmillMultiplier", function(session)
		return session.Runtime.TreadmillMultiplier or 1
	end)
end

function TreadmillService.Start()
	task.spawn(function()
		while true do
			task.wait(0.2)
			TreadmillService.Tick()
		end
	end)
end

return TreadmillService
