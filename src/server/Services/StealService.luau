--!strict
-- Player vs player: steal eggs from other bases' incubators, lock your base, bonk thieves.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local MapLayout = require(Shared.MapLayout)
local PlayerService = require(script.Parent.PlayerService)
local PlotService = require(script.Parent.PlotService)
local BoostService = require(script.Parent.BoostService)
local HatchService = require(script.Parent.HatchService)
local EggService = require(script.Parent.EggService)
local Network = require(script.Parent.Network)

local StealService = {}

local lastBonk: { [Player]: number } = {}
local lockNotified: { [PlotService.PlotState]: boolean } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart? or nil
end

local function isProtectedNewPlayer(session: PlayerService.Session): boolean
	return session.Data.Stats.Joins <= 1 and session.Data.Stats.Playtime < Config.Steal.NewPlayerProtectionSeconds
end

function StealService.TrySteal(thief: Player, plot: PlotService.PlotState, slot: number): (boolean, string?)
	local thiefSession = PlayerService.Get(thief)
	local victim = plot.Owner
	if not thiefSession or not victim then
		return false, "Nothing to steal"
	end
	if victim == thief then
		return false, "That's your own egg!"
	end
	local victimSession = PlayerService.Get(victim)
	if not victimSession then
		return false, "Nothing to steal"
	end
	if PlotService.IsLocked(plot) then
		return false, "This base is locked!"
	end
	if isProtectedNewPlayer(victimSession) then
		return false, victim.DisplayName .. " is new - their eggs are protected for a few minutes"
	end
	if EggService.CarryOf(thief) then
		return false, "You are already carrying an egg"
	end
	local _, egg = HatchService.GetEgg(victim, slot)
	if not egg then
		return false, "No egg there"
	end
	if HatchService.IsReserved(victim, slot) then
		return false, "Someone else is stealing it!"
	end
	local root = rootOf(thief)
	local slotInfo = plot.Incubators[slot]
	if not root or not slotInfo or (root.Position - slotInfo.Part.Position).Magnitude > 14 then
		return false, "Too far away"
	end
	if not HatchService.FreeSlot(thief) then
		return false, "Your incubators are full!"
	end
	HatchService.Reserve(victim, slot, thief)
	EggService.StartCarry(thief, egg.Egg, { Kind = "Incubator", Victim = victim, Slot = slot })
	Network.Notify(
		victim,
		thief.DisplayName .. " is stealing your " .. Config.Eggs[egg.Egg].Name .. "! BONK them!",
		"error"
	)
	Network.Effect(victim, "Alarm", { Thief = thief.UserId })
	return true, nil
end

function StealService.Lock(player: Player): (boolean, string?)
	local session = PlayerService.Get(player)
	local plot = PlotService.Get(player)
	local root = rootOf(player)
	if not session or not plot or not root then
		return false, "Loading..."
	end
	if not PlotService.Contains(plot, root.Position, 2) then
		return false, "Go back to your base to lock it"
	end
	if PlotService.IsLocked(plot) then
		return false, "Already locked"
	end
	local seconds = Formulas.LockSeconds(session.Data.LockLevel, BoostService.HasPass(player, "VIP"))
	plot.LockedUntil = os.time() + seconds
	plot.Model:SetAttribute("LockedUntil", plot.LockedUntil)
	plot.Barrier.Transparency = 0.45
	lockNotified[plot] = false
	-- Anyone inside gets pushed out
	for _, other in PlayerService.All() do
		local otherRoot = rootOf(other.Player)
		if other.Player ~= player and otherRoot and PlotService.Contains(plot, otherRoot.Position) then
			PlotService.PushOut(other.Player, plot)
		end
	end
	PlayerService.MarkDirty(player, true)
	return true, "Base locked for " .. Format.Duration(seconds) .. "!"
end

local function canBonk(target: Player, attackerPlot: PlotService.PlotState?): boolean
	if EggService.CarryOf(target) then
		return true
	end
	-- Defending your base: intruders can be bonked out.
	local root = rootOf(target)
	return attackerPlot ~= nil and root ~= nil and PlotService.Contains(attackerPlot, root.Position)
end

function StealService.Bonk(attacker: Player): (boolean, string?)
	local now = os.clock()
	if lastBonk[attacker] and now - lastBonk[attacker] < Config.Steal.BonkCooldown then
		return false, nil
	end
	lastBonk[attacker] = now
	local root = rootOf(attacker)
	if not root then
		return false, nil
	end
	Network.EffectAll("BonkSwing", { UserId = attacker.UserId })
	local attackerPlot = PlotService.Get(attacker)
	local hits = 0
	for _, session in PlayerService.All() do
		local target = session.Player
		local targetRoot = rootOf(target)
		if
			target ~= attacker
			and targetRoot
			and (targetRoot.Position - root.Position).Magnitude <= Config.Steal.BonkRange
		then
			if canBonk(target, attackerPlot) then
				local away = targetRoot.Position - root.Position
				local flat = Vector3.new(away.X, 0, away.Z)
				local direction = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, 1)
				Network.Effect(target, "Knockback", {
					Direction = direction,
					Speed = Config.Steal.KnockbackSpeed,
					Stun = Config.Steal.StunSeconds,
				})
				if EggService.DropCarry(target, "Bonk") then
					Network.Notify(attacker, "You bonked " .. target.DisplayName .. " and saved the egg!", "success")
				end
				hits += 1
				if hits >= 3 then
					break
				end
			end
		end
	end
	return true, nil
end

-- Lock pad, lock expiry and pushing intruders out of locked bases.
function StealService.Tick()
	local now = os.time()
	local padInfo = MapLayout.PlotLocal.LockPad
	for _, plot in PlotService.All() do
		local owner = plot.Owner
		if owner then
			-- owner standing on the lock pad
			local ownerRoot = rootOf(owner)
			if ownerRoot and not PlotService.IsLocked(plot) then
				local lx, lz = MapLayout.WorldToPlot(plot.Layout, ownerRoot.Position.X, ownerRoot.Position.Z)
				if
					math.abs(lx - padInfo.X) <= padInfo.Size / 2 + 1
					and math.abs(lz - padInfo.Z) <= padInfo.Size / 2 + 1
				then
					local ok, message = StealService.Lock(owner)
					if ok and message then
						Network.Notify(owner, message, "success")
					end
				end
			end
		end
		if plot.LockedUntil > 0 and plot.LockedUntil <= now then
			plot.Barrier.Transparency = 1
			if owner and not lockNotified[plot] then
				lockNotified[plot] = true
				Network.Notify(owner, "Your base is UNLOCKED! Step on the red pad to lock it again.", "warning")
				PlayerService.MarkDirty(owner, true)
			end
		elseif PlotService.IsLocked(plot) then
			for _, session in PlayerService.All() do
				local intruder = session.Player
				local root = rootOf(intruder)
				if intruder ~= owner and root and PlotService.Contains(plot, root.Position) then
					PlotService.PushOut(intruder, plot)
				end
			end
		end
	end
end

local function setupIncubatorPrompts(plot: PlotService.PlotState)
	for _, slot in plot.Incubators do
		local stealPrompt = Instance.new("ProximityPrompt")
		stealPrompt.Name = "StealPrompt"
		stealPrompt.ActionText = "Steal"
		stealPrompt.ObjectText = "Egg"
		stealPrompt.HoldDuration = Config.Steal.StealHoldSeconds
		stealPrompt.MaxActivationDistance = 9
		stealPrompt.RequiresLineOfSight = false
		stealPrompt.Enabled = false
		stealPrompt.Parent = slot.Part
		stealPrompt:SetAttribute("PromptKind", "Steal")

		local hatchPrompt = Instance.new("ProximityPrompt")
		hatchPrompt.Name = "HatchPrompt"
		hatchPrompt.ActionText = "Hatch now"
		hatchPrompt.ObjectText = "Gems"
		hatchPrompt.HoldDuration = 0.3
		hatchPrompt.MaxActivationDistance = 9
		hatchPrompt.RequiresLineOfSight = false
		hatchPrompt.Enabled = false
		hatchPrompt.Parent = slot.Part
		hatchPrompt:SetAttribute("PromptKind", "Hatch")

		local function refresh()
			local hasEgg = (slot.Part:GetAttribute("Egg") or "") ~= ""
			local reservedFlag = slot.Part:GetAttribute("Reserved") == true
			stealPrompt.Enabled = hasEgg and not reservedFlag
			hatchPrompt.Enabled = hasEgg and not reservedFlag
			local eggId = slot.Part:GetAttribute("Egg")
			if hasEgg and type(eggId) == "string" and Config.Eggs[eggId] then
				stealPrompt.ObjectText = Config.Eggs[eggId].Name
			end
		end
		slot.Part:GetAttributeChangedSignal("Egg"):Connect(refresh)
		slot.Part:GetAttributeChangedSignal("Reserved"):Connect(refresh)
		refresh()

		stealPrompt.Triggered:Connect(function(player: Player)
			local ok, message = StealService.TrySteal(player, plot, slot.Index)
			if not ok and message then
				Network.Notify(player, message, "error")
			end
		end)
		hatchPrompt.Triggered:Connect(function(player: Player)
			if plot.Owner ~= player then
				return
			end
			local ok, message = HatchService.Skip(player, slot.Index)
			if message then
				Network.Notify(player, message, if ok then "success" else "error")
			end
		end)
	end
end

function StealService.Init()
	Network.Handle("LockBase", function(player)
		return StealService.Lock(player)
	end)
	Network.Handle("Bonk", function(player)
		return StealService.Bonk(player)
	end)
	for _, plot in PlotService.All() do
		setupIncubatorPrompts(plot)
	end
	PlayerService.RegisterState("Protected", function(session)
		return isProtectedNewPlayer(session)
	end)
end

function StealService.Start()
	PlayerService.PlayerLeaving:Connect(function(player: Player)
		lastBonk[player] = nil
	end)
	PlotService.PlotReleased:Connect(function(_player: Player, plot: PlotService.PlotState)
		lockNotified[plot] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			StealService.Tick()
		end
	end)
end

return StealService
