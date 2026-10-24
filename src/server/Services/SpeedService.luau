--!strict
-- The "+1 Speed every second" stat: ticks Speed up, converts it to WalkSpeed,
-- and enforces speed gates on the server (the client only removes gate collision locally).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local MapLayout = require(Shared.MapLayout)
local Signal = require(Shared.Signal)
local PlayerService = require(script.Parent.PlayerService)
local BoostService = require(script.Parent.BoostService)
local Network = require(script.Parent.Network)

local SpeedService = {}

SpeedService.GateViolation = Signal.new() -- (player) someone got past a gate they can't pass

local carryMultiplier: { [Player]: number? } = {}

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart? or nil
end

function SpeedService.RefreshWalkSpeed(player: Player)
	local session = PlayerService.Get(player)
	local humanoid = humanoidOf(player)
	if not session or not humanoid then
		return
	end
	humanoid.WalkSpeed = Formulas.WalkSpeed(session.Data.Speed, carryMultiplier[player])
end

-- EggService sets this while a player carries an egg (1 = not carrying).
function SpeedService.SetCarryMultiplier(player: Player, multiplier: number?)
	carryMultiplier[player] = multiplier
	SpeedService.RefreshWalkSpeed(player)
end

-- Highest zone this player may be in right now.
function SpeedService.AllowedZone(player: Player): number
	local session = PlayerService.Get(player)
	if not session then
		return 1
	end
	return Formulas.BestZone(session.Data.Speed, session.Data.Rebirths)
end

function SpeedService.AddSpeed(player: Player, amount: number)
	local session = PlayerService.Get(player)
	if not session then
		return
	end
	local data = session.Data
	data.Speed += amount
	local best = Formulas.BestZone(data.Speed, data.Rebirths)
	if best > data.BestZone then
		data.BestZone = best
		local zone = Config.Zones[best]
		Network.Notify(player, "New zone unlocked: " .. zone.Name .. "!", "success")
		PlayerService.MarkDirty(player, true)
	else
		PlayerService.MarkDirty(player, false)
	end
	SpeedService.RefreshWalkSpeed(player)
end

function SpeedService.Tick(dt: number)
	for _, session in PlayerService.All() do
		local player = session.Player
		session.Data.Stats.Playtime += dt
		SpeedService.AddSpeed(player, BoostService.GetSpeedGain(player) * dt)
	end
end

-- Sends players back if they got past a gate they cannot pass (exploit or speed reset).
function SpeedService.CheckGates()
	for _, session in PlayerService.All() do
		local player = session.Player
		local root = rootOf(player)
		if root then
			local position = root.Position
			local zoneIndex = MapLayout.ZoneAtZ(position.Z - 3)
			local allowed = SpeedService.AllowedZone(player)
			if zoneIndex > allowed then
				local blockedGate = MapLayout.Zones[allowed + 1]
				local backZ = blockedGate.GateZ - 12
				local character = player.Character
				if character then
					character:PivotTo(CFrame.new(math.clamp(position.X, -20, 20), 4, backZ))
				end
				SpeedService.GateViolation:Fire(player)
				Network.Notify(
					player,
					"You need more Speed to enter " .. Config.Zones[allowed + 1].Name .. "!",
					"error"
				)
			end
		end
	end
end

function SpeedService.Init() end

function SpeedService.Start()
	PlayerService.PlayerReady:Connect(function(player: Player)
		player.CharacterAdded:Connect(function()
			task.defer(SpeedService.RefreshWalkSpeed, player)
		end)
		SpeedService.RefreshWalkSpeed(player)
	end)
	PlayerService.PlayerLeaving:Connect(function(player: Player)
		carryMultiplier[player] = nil
	end)

	task.spawn(function()
		while true do
			local dt = task.wait(Config.Speed.TickSeconds)
			SpeedService.Tick(math.min(dt, Config.Speed.TickSeconds * 3))
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			SpeedService.CheckGates()
		end
	end)
end

return SpeedService
