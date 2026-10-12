--!strict
-- Multipliers from game passes, potions (timed, saved as unix expiry) and server-wide luck.
-- Everything else asks this service for a player's current luck / coin / speed multipliers.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Signal = require(Shared.Signal)
local PlayerService = require(script.Parent.PlayerService)
local Network = require(script.Parent.Network)

local BoostService = {}

BoostService.PassesChanged = Signal.new() -- (player)

local serverLuckEndsAt = 0

local function passesOf(session: PlayerService.Session): { [string]: boolean }
	local passes = session.Runtime.Passes
	if not passes then
		passes = {}
		session.Runtime.Passes = passes
	end
	return passes
end

function BoostService.HasPass(player: Player, key: string): boolean
	local session = PlayerService.Get(player)
	return session ~= nil and passesOf(session)[key] == true
end

-- Called by MonetizationService after an ownership check or purchase.
function BoostService.SetPass(player: Player, key: string, owned: boolean)
	local session = PlayerService.Get(player)
	if not session then
		return
	end
	local passes = passesOf(session)
	if passes[key] == owned then
		return
	end
	passes[key] = owned
	if owned then
		session.Data.PassCache[key] = true
	end
	if key == "VIP" then
		player:SetAttribute("VIP", owned) -- everyone's client shows the VIP chat tag
	end
	PlayerService.MarkDirty(player, true)
	BoostService.PassesChanged:Fire(player)
end

function BoostService.GetModifiers(player: Player): Formulas.Modifiers
	local session = PlayerService.Get(player)
	if not session then
		return {}
	end
	local now = os.time()
	local passes = passesOf(session)
	return {
		DoubleCoins = passes.DoubleCoins == true,
		DoubleSpeed = passes.DoubleSpeed == true,
		VIP = passes.VIP == true,
		Lucky = passes.Lucky == true,
		ExtraIncubators = passes.ExtraIncubators == true,
		LuckPotion = session.Data.Potions.Luck > now,
		SpeedPotion = session.Data.Potions.Speed > now,
		ServerLuck = serverLuckEndsAt > now,
	}
end

function BoostService.GetLuck(player: Player): number
	return Formulas.Luck(BoostService.GetModifiers(player))
end

function BoostService.GetCoinMultiplier(player: Player): number
	local session = PlayerService.Get(player)
	if not session then
		return 1
	end
	return Formulas.CoinMultiplier(session.Data.Rebirths, BoostService.GetModifiers(player))
end

function BoostService.GetSpeedGain(player: Player): number
	local session = PlayerService.Get(player)
	if not session then
		return 0
	end
	return Formulas.SpeedGainPerSecond(session.Data.TrainingLevel, session.Data.Rebirths, BoostService.GetModifiers(player))
end

-- kind: "Luck" | "Speed"
function BoostService.AddPotion(player: Player, kind: string, seconds: number?)
	local session = PlayerService.Get(player)
	if not session then
		return
	end
	local now = os.time()
	local potions = session.Data.Potions :: any
	local current = math.max(now, potions[kind] or 0)
	potions[kind] = math.min(current + (seconds or Config.Boosts.PotionSeconds), now + Config.Boosts.MaxPotionSeconds)
	PlayerService.MarkDirty(player, true)
end

function BoostService.AddServerLuck(seconds: number?, buyerName: string?)
	local now = os.time()
	serverLuckEndsAt = math.min(
		math.max(now, serverLuckEndsAt) + (seconds or Config.Boosts.ServerLuckSeconds),
		now + Config.Boosts.MaxServerLuckSeconds
	)
	for _, session in PlayerService.All() do
		PlayerService.MarkDirty(session.Player, true)
	end
	if buyerName then
		Network.NotifyAll(buyerName .. " activated SERVER LUCK x" .. Config.Luck.ServerMultiplier .. " for everyone!", "rare")
	end
end

function BoostService.ServerLuckEndsAt(): number
	return serverLuckEndsAt
end

function BoostService.Init()
	PlayerService.RegisterState("Passes", function(session)
		return table.clone(passesOf(session))
	end)
	PlayerService.RegisterState("Luck", function(session)
		return BoostService.GetLuck(session.Player)
	end)
	PlayerService.RegisterState("CoinMultiplier", function(session)
		return BoostService.GetCoinMultiplier(session.Player)
	end)
	PlayerService.RegisterState("SpeedPerSecond", function(session)
		return BoostService.GetSpeedGain(session.Player)
	end)
	PlayerService.RegisterState("ServerLuckEndsAt", function()
		return serverLuckEndsAt
	end)
end

function BoostService.Start()
	PlayerService.PlayerReady:Connect(function(player: Player, session: PlayerService.Session)
		-- Trust previously confirmed passes immediately; MonetizationService re-verifies.
		local passes = passesOf(session)
		for key in session.Data.PassCache do
			if (Config.Passes :: any)[key] then
				passes[key] = true
			end
		end
		if passes.VIP then
			player:SetAttribute("VIP", true)
		end
		PlayerService.MarkDirty(player, true)
		BoostService.PassesChanged:Fire(player)
	end)

	-- Resync when a timed boost runs out so the client's odds/multipliers update.
	task.spawn(function()
		local lastActive: { [Player]: string } = {}
		while true do
			task.wait(1)
			for _, session in PlayerService.All() do
				local mods = BoostService.GetModifiers(session.Player)
				local signature = tostring(mods.LuckPotion) .. tostring(mods.SpeedPotion) .. tostring(mods.ServerLuck)
				if lastActive[session.Player] ~= signature then
					lastActive[session.Player] = signature
					PlayerService.MarkDirty(session.Player, true)
				end
			end
			for player in lastActive do
				if player.Parent == nil then
					lastActive[player] = nil
				end
			end
		end
	end)
end

return BoostService
