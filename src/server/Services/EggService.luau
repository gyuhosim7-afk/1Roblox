--!strict
-- Nest eggs in the zones, carrying an egg on your head, delivering it to your base,
-- and dropping it (guard hit, bonk, death, cheating) which sends it back where it came from.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local EggBuilder = require(Shared.EggBuilder)
local MapLayout = require(Shared.MapLayout)
local Signal = require(Shared.Signal)
local PlayerService = require(script.Parent.PlayerService)
local MapService = require(script.Parent.MapService)
local PlotService = require(script.Parent.PlotService)
local SpeedService = require(script.Parent.SpeedService)
local HatchService = require(script.Parent.HatchService)
local Network = require(script.Parent.Network)

export type Origin = { Kind: string, Nest: Nest?, Victim: Player?, Slot: number? }
export type Carry = {
	EggId: string,
	Origin: Origin,
	Model: Model?,
	LastPosition: Vector3?,
	LastTime: number,
}
export type Nest = {
	Zone: number,
	Index: number,
	EggId: string,
	Position: Vector3,
	HasEgg: boolean,
	Model: Model?,
	Prompt: ProximityPrompt?,
	Anchor: BasePart,
}

local EggService = {}

EggService.Delivered = Signal.new() -- (player, eggId, origin)
EggService.Dropped = Signal.new() -- (player, eggId, origin, reason)

local nests: { Nest } = {}
local carries: { [Player]: Carry } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart? or nil
end

function EggService.GetNests(): { Nest }
	return nests
end

function EggService.CarryOf(player: Player): Carry?
	return carries[player]
end

local function showNestEgg(nest: Nest, visible: boolean)
	nest.HasEgg = visible
	if nest.Model then
		for _, part in nest.Model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Transparency = if visible then 0 else 1
			end
		end
	end
	if nest.Prompt then
		nest.Prompt.Enabled = visible
	end
end

local function respawnLater(nest: Nest)
	task.delay(Config.Map.NestRespawnSeconds, function()
		if not nest.HasEgg then
			showNestEgg(nest, true)
		end
	end)
end

local function attachModel(player: Player, eggId: string): Model?
	local root = rootOf(player)
	local character = player.Character
	if not root or not character then
		return nil
	end
	local model = EggBuilder.Build(eggId, 0.8)
	model.Name = "CarriedEgg"
	EggBuilder.MakeCarryable(model)
	local shell = model.PrimaryPart
	if shell then
		shell.CFrame = root.CFrame * CFrame.new(0, 4.2, 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = shell
		weld.Parent = shell
	end
	model.Parent = character
	return model
end

-- Begins carrying. origin = where the egg returns if dropped.
function EggService.StartCarry(player: Player, eggId: string, origin: Origin): boolean
	if carries[player] then
		return false
	end
	local def = Config.Eggs[eggId]
	if not def then
		return false
	end
	local root = rootOf(player)
	carries[player] = {
		EggId = eggId,
		Origin = origin,
		Model = attachModel(player, eggId),
		LastPosition = root and root.Position or nil,
		LastTime = os.clock(),
	}
	SpeedService.SetCarryMultiplier(player, def.CarryMultiplier)
	player:SetAttribute("CarryingEgg", eggId)
	Network.Effect(player, "CarryStart", { Egg = eggId })
	PlayerService.MarkDirty(player, true)
	return true
end

local function endCarry(player: Player): Carry?
	local carry = carries[player]
	if not carry then
		return nil
	end
	carries[player] = nil
	if carry.Model then
		carry.Model:Destroy()
	end
	SpeedService.SetCarryMultiplier(player, nil)
	if player.Parent then
		player:SetAttribute("CarryingEgg", nil)
		Network.Effect(player, "CarryEnd", nil)
		PlayerService.MarkDirty(player, true)
	end
	return carry
end

local function returnToOrigin(origin: Origin)
	if origin.Kind == "Nest" and origin.Nest then
		showNestEgg(origin.Nest, true)
	elseif origin.Kind == "Incubator" and origin.Victim and origin.Slot then
		HatchService.Unreserve(origin.Victim, origin.Slot)
	end
end

-- Drops the carried egg; it goes back to its nest / owner's incubator.
function EggService.DropCarry(player: Player, reason: string): boolean
	local carry = endCarry(player)
	if not carry then
		return false
	end
	returnToOrigin(carry.Origin)
	EggService.Dropped:Fire(player, carry.EggId, carry.Origin, reason)
	if player.Parent then
		local messages = {
			Guard = "A guard knocked the egg out of your hands!",
			Bonk = "You got bonked and dropped the egg!",
			Died = "You dropped the egg!",
			TooFast = "You dropped the egg!",
			Gate = "You dropped the egg!",
		}
		Network.Notify(player, messages[reason] or "You dropped the egg!", "error")
	end
	return true
end

-- Cancels a carry without returning anything (used when the egg no longer exists).
function EggService.CancelCarry(player: Player)
	endCarry(player)
end

local function deliver(player: Player, carry: Carry)
	local session = PlayerService.Get(player)
	if not session then
		return
	end
	local origin = carry.Origin
	if origin.Kind == "Incubator" then
		local victim = origin.Victim
		local slot = origin.Slot
		if not victim or not slot or victim.Parent == nil then
			EggService.CancelCarry(player)
			return
		end
		local freeSlot = HatchService.FreeSlot(player)
		if not freeSlot then
			return -- keep carrying until a slot frees up
		end
		local removed = HatchService.RemoveEgg(victim, slot)
		endCarry(player)
		if not removed then
			return
		end
		HatchService.AddEgg(player, removed.Egg)
		session.Data.Stats.PlayerSteals += 1
		local victimSession = PlayerService.Get(victim)
		if victimSession then
			victimSession.Data.Stats.TimesRobbed += 1
		end
		Network.Notify(
			player,
			"You stole " .. victim.DisplayName .. "'s " .. Config.Eggs[removed.Egg].Name .. "!",
			"success"
		)
		Network.Notify(
			victim,
			player.DisplayName .. " stole your " .. Config.Eggs[removed.Egg].Name .. "! Lock your base!",
			"error"
		)
		EggService.Delivered:Fire(player, removed.Egg, origin)
		return
	end

	local slot = HatchService.AddEgg(player, carry.EggId)
	if not slot then
		return -- full: keep carrying (pickup already checks, so this is rare)
	end
	endCarry(player)
	if origin.Nest then
		respawnLater(origin.Nest)
	end
	session.Data.Stats.EggsStolen += 1
	Network.Notify(player, Config.Eggs[carry.EggId].Name .. " is incubating!", "success")
	PlayerService.AdvanceTutorial(player, 2)
	EggService.Delivered:Fire(player, carry.EggId, origin)
end

function EggService.TryTakeNestEgg(player: Player, nest: Nest): (boolean, string?)
	local session = PlayerService.Get(player)
	if not session then
		return false, "Loading..."
	end
	if not nest.HasEgg then
		return false, "Egg is gone"
	end
	if carries[player] then
		return false, "You are already carrying an egg"
	end
	local root = rootOf(player)
	if not root or (root.Position - nest.Position).Magnitude > 16 then
		return false, "Too far away"
	end
	if not Formulas.ZoneUnlocked(nest.Zone, session.Data.Speed, session.Data.Rebirths) then
		return false, "You need more Speed for this zone"
	end
	if not HatchService.FreeSlot(player) then
		Network.Notify(player, "Your incubators are full! Wait for hatching or buy more incubators.", "error")
		return false, "Incubators full"
	end
	showNestEgg(nest, false)
	EggService.StartCarry(player, nest.EggId, { Kind = "Nest", Nest = nest })
	PlayerService.AdvanceTutorial(player, 1)
	return true, nil
end

-- Delivery + anti-teleport checks for everyone carrying.
function EggService.CheckCarries()
	local now = os.clock()
	for player, carry in carries do
		local root = rootOf(player)
		if not root then
			EggService.DropCarry(player, "Died")
			continue
		end
		local position = root.Position
		local elapsed = now - carry.LastTime
		if carry.LastPosition and elapsed >= 0.5 then
			-- Measured over half a second so network jitter does not cause false positives.
			local flat = Vector3.new(position.X - carry.LastPosition.X, 0, position.Z - carry.LastPosition.Z)
			local session = PlayerService.Get(player)
			local walk = if session then Formulas.WalkSpeed(session.Data.Speed) else 16
			local allowed = walk * 1.25 + Config.Steal.TeleportSlack
			carry.LastPosition = position
			carry.LastTime = now
			if flat.Magnitude / elapsed > allowed then
				EggService.DropCarry(player, "TooFast")
				continue
			end
		elseif not carry.LastPosition then
			carry.LastPosition = position
			carry.LastTime = now
		end
		local plot = PlotService.Get(player)
		if plot and PlotService.Contains(plot, position) then
			deliver(player, carry)
		end
	end
end

local function setupNest(info: { Zone: number, Index: number, Part: BasePart, Position: Vector3 })
	local zoneDef = Config.Zones[info.Zone]
	local eggId = zoneDef.Egg
	local def = Config.Eggs[eggId]
	local model = EggBuilder.Build(eggId)
	model.Name = "NestEgg"
	model:PivotTo(CFrame.new(info.Position) * CFrame.Angles(0, (info.Index * 1.3) % (math.pi * 2), 0))
	model.Parent = info.Part.Parent
	local shell = model.PrimaryPart
	local nest: Nest = {
		Zone = info.Zone,
		Index = info.Index,
		EggId = eggId,
		Position = info.Position,
		HasEgg = true,
		Model = model,
		Prompt = nil,
		Anchor = info.Part,
	}
	if shell then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "StealPrompt"
		prompt.ActionText = "Steal"
		prompt.ObjectText = def.Name
		prompt.HoldDuration = def.HoldSeconds
		prompt.MaxActivationDistance = 11
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = shell
		prompt.Triggered:Connect(function(player: Player)
			local ok, message = EggService.TryTakeNestEgg(player, nest)
			if not ok and message and message ~= "Incubators full" then
				Network.Notify(player, message, "error")
			end
		end)
		nest.Prompt = prompt
	end
	table.insert(nests, nest)
end

function EggService.Init()
	for _, info in MapService.Nests do
		setupNest(info)
	end
	PlayerService.RegisterState("Carrying", function(session)
		local carry = carries[session.Player]
		return carry and carry.EggId or nil
	end)
end

function EggService.Start()
	PlayerService.PlayerReady:Connect(function(player: Player)
		local function hookCharacter(character: Model)
			local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
			if humanoid then
				humanoid.Died:Connect(function()
					EggService.DropCarry(player, "Died")
				end)
			end
		end
		player.CharacterAdded:Connect(hookCharacter)
		if player.Character then
			task.spawn(hookCharacter, player.Character)
		end
	end)
	PlayerService.PlayerLeaving:Connect(function(player: Player)
		-- Leaving while carrying: egg goes back.
		EggService.DropCarry(player, "Left")
		-- Someone is carrying this player's egg: it stays with its owner (their data still has it).
		for thief, carry in carries do
			if carry.Origin.Kind == "Incubator" and carry.Origin.Victim == player then
				EggService.CancelCarry(thief)
				Network.Notify(thief, "The owner left - the egg vanished!", "error")
			end
		end
	end)
	SpeedService.GateViolation:Connect(function(player: Player)
		EggService.DropCarry(player, "Gate")
	end)
	task.spawn(function()
		while true do
			task.wait(0.1)
			EggService.CheckCarries()
		end
	end)
	local _ = MapLayout
end

return EggService
