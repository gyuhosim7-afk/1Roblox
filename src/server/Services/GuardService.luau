--!strict
-- Guard slimes: server-side hit tests for players carrying eggs.
-- Positions come from GuardMotion + the shared server clock, so nothing replicates per frame.

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local MapLayout = require(Shared.MapLayout)
local GuardMotion = require(Shared.GuardMotion)
local EggService = require(script.Parent.EggService)
local PlayerService = require(script.Parent.PlayerService)
local Network = require(script.Parent.Network)

local GuardService = {}

local GRACE_SECONDS = 0.6 -- no hits right after picking up an egg
local PLAYER_RADIUS = 1.2 -- a bit forgiving: the server sees positions slightly late

local carryStarted: { [Player]: number } = {}

local function hitDirection(guard: MapLayout.Guard, t: number, position: Vector3): Vector3
	local gx, gz
	if guard.Kind == "Patrol" then
		gx, gz = GuardMotion.PatrolPosition(guard, t)
	else
		gx, gz = guard.X, guard.Z
	end
	local away = Vector3.new(position.X - gx, 0, position.Z - gz)
	if away.Magnitude < 0.01 then
		away = Vector3.new(0, 0, -1)
	end
	return away.Unit
end

function GuardService.Check()
	local now = Workspace:GetServerTimeNow()
	local clock = os.clock()
	for player, startedAt in carryStarted do
		local carry = EggService.CarryOf(player)
		if not carry then
			carryStarted[player] = nil
			continue
		end
		if clock - startedAt < GRACE_SECONDS then
			continue
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue
		end
		local position = root.Position
		local zoneIndex = MapLayout.ZoneAtZ(position.Z)
		local zone = MapLayout.Zones[zoneIndex]
		if not zone then
			continue
		end
		-- Evaluate guards where the player saw them (their position reaches us ~half a ping late).
		local ping = 0.1
		pcall(function()
			ping = player:GetNetworkPing()
		end)
		local t = now - math.clamp(ping * 0.5, 0, 0.25)
		for _, guard in zone.Guards do
			local tooHigh = position.Y > (if guard.Kind == "Patrol" then guard.Radius * 2 + 3 else 7)
			if not tooHigh and GuardMotion.Hits(guard, t, position.X, position.Z, PLAYER_RADIUS) then
				local direction = hitDirection(guard, t, position)
				EggService.DropCarry(player, "Guard")
				Network.Effect(player, "Knockback", {
					Direction = direction,
					Speed = Config.Steal.GuardKnockbackSpeed,
					Stun = Config.Steal.StunSeconds,
				})
				carryStarted[player] = nil
				break
			end
		end
	end
end

function GuardService.Init() end

function GuardService.Start()
	EggService.Dropped:Connect(function(player: Player)
		carryStarted[player] = nil
	end)
	EggService.Delivered:Connect(function(player: Player)
		carryStarted[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.05)
			-- pick up new carriers
			for _, session in PlayerService.All() do
				local player = session.Player
				if not carryStarted[player] and EggService.CarryOf(player) then
					carryStarted[player] = os.clock()
				end
			end
			GuardService.Check()
		end
	end)
end

return GuardService
