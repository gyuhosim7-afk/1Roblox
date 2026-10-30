--!strict
-- Coin upgrades (training, pedestals, incubators, lock time) and rebirth.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local Validate = require(script.Parent.Parent.Logic.Validate)
local PlayerService = require(script.Parent.PlayerService)
local PlotService = require(script.Parent.PlotService)
local SpeedService = require(script.Parent.SpeedService)
local SlimeService = require(script.Parent.SlimeService)
local HatchService = require(script.Parent.HatchService)
local EggService = require(script.Parent.EggService)
local Network = require(script.Parent.Network)

local UpgradeService = {}

local LEVEL_FIELD = {
	Training = "TrainingLevel",
	Pedestals = "PedestalLevel",
	Incubators = "IncubatorLevel",
	Lock = "LockLevel",
}

function UpgradeService.Buy(player: Player, kind: string): (boolean, string?)
	local session = PlayerService.Get(player)
	local field = LEVEL_FIELD[kind]
	if not session or not field then
		return false, "Bad request"
	end
	local data = session.Data :: any
	local level = data[field]
	local cost = Formulas.UpgradeCost(kind, level)
	if not cost then
		return false, "Already maxed!"
	end
	if session.Data.Coins < cost then
		return false, "Not enough coins (need $" .. Format.Number(cost) .. ")"
	end
	session.Data.Coins -= cost
	data[field] = level + 1

	local plot = PlotService.Get(player)
	if kind == "Pedestals" then
		if plot then
			PlotService.RefreshSlots(plot)
		end
		SlimeService.Arrange(player)
	elseif kind == "Incubators" then
		if plot then
			PlotService.RefreshSlots(plot)
		end
		HatchService.RefreshVisuals(player)
	elseif kind == "Training" then
		PlayerService.AdvanceTutorial(player, 5)
	end
	PlayerService.MarkDirty(player, true)
	local def = (Config.Upgrades :: any)[kind]
	return true, def.Name .. " upgraded to level " .. (level + 1) .. "!"
end

function UpgradeService.CanRebirth(player: Player): (boolean, string?)
	local session = PlayerService.Get(player)
	if not session then
		return false, "Loading..."
	end
	if session.Data.Rebirths >= Config.Rebirth.MaxRebirths then
		return false, "You reached MAX REBIRTH!"
	end
	local speedReq, coinReq = Formulas.RebirthRequirement(session.Data.Rebirths)
	if session.Data.Speed < speedReq then
		return false, "Need " .. Format.Number(speedReq) .. " Speed"
	end
	if session.Data.Coins < coinReq then
		return false, "Need $" .. Format.Number(coinReq)
	end
	return true, nil
end

function UpgradeService.Rebirth(player: Player): (boolean, string?)
	local ok, message = UpgradeService.CanRebirth(player)
	if not ok then
		return false, message
	end
	local session = PlayerService.Get(player)
	assert(session, "session")
	local data = session.Data
	EggService.DropCarry(player, "Rebirth")
	data.Speed = 0
	data.Coins = 0
	data.Bank = 0
	data.TrainingLevel = 0
	data.Rebirths += 1
	data.Gems += Config.Rebirth.GemReward
	local milestone = Config.Rebirth.Milestones[data.Rebirths]
	if milestone then
		data.Gems += milestone.Gems
		Network.NotifyAll(
			player.DisplayName .. " reached Rebirth " .. data.Rebirths .. " and became a " .. milestone.Title .. "!",
			"rare"
		)
	end
	player:SetAttribute("RebirthTitle", Formulas.RebirthTitle(data.Rebirths))
	SpeedService.RefreshWalkSpeed(player)
	PlotService.TeleportHome(player)
	PlayerService.MarkDirty(player, true)
	Network.NotifyAll(player.DisplayName .. " just rebirthed! (Rebirth " .. data.Rebirths .. ")", "rare")
	Network.Effect(player, "Rebirth", { Rebirths = data.Rebirths })
	return true,
		"Rebirth " .. data.Rebirths .. "! Speed gain +" .. math.floor(
			Config.Rebirth.SpeedBonusPerRebirth * 100 * data.Rebirths
		) .. "%, coins +" .. math.floor(Config.Rebirth.CoinBonusPerRebirth * 100 * data.Rebirths) .. "%"
end

function UpgradeService.Init()
	-- rebirth milestone title (shown as a chat tag)
	PlayerService.PlayerReady:Connect(function(player: Player, session: PlayerService.Session)
		player:SetAttribute("RebirthTitle", Formulas.RebirthTitle(session.Data.Rebirths))
	end)
	Network.Handle("BuyUpgrade", function(player, payload)
		local kind = Validate.Key(payload, LEVEL_FIELD)
		if not kind then
			return false, "Bad request"
		end
		return UpgradeService.Buy(player, kind)
	end)
	Network.Handle("Rebirth", function(player)
		return UpgradeService.Rebirth(player)
	end)
end

function UpgradeService.Start() end

return UpgradeService
