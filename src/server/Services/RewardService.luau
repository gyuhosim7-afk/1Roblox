--!strict
-- Free rewards that keep non-paying players progressing: daily streak gems,
-- a gem gift every 10 minutes online, and offline earnings when returning.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local ProfileSchema = require(script.Parent.Parent.Logic.ProfileSchema)
local PlayerService = require(script.Parent.PlayerService)
local BoostService = require(script.Parent.BoostService)
local SlimeService = require(script.Parent.SlimeService)
local Network = require(script.Parent.Network)

local RewardService = {}

local function dailyStatus(session: PlayerService.Session): (boolean, number)
	local today = ProfileSchema.DayNumber(os.time())
	local daily = session.Data.Daily
	if daily.LastDay == today then
		return false, daily.Streak
	end
	local streak = if daily.LastDay == today - 1 then daily.Streak + 1 else 1
	return true, streak
end

function RewardService.ClaimDaily(player: Player): (boolean, string?)
	local session = PlayerService.Get(player)
	if not session then
		return false, "Loading..."
	end
	local available, streak = dailyStatus(session)
	if not available then
		return false, "Come back tomorrow!"
	end
	local gems = Formulas.DailyGems(streak)
	session.Data.Daily.LastDay = ProfileSchema.DayNumber(os.time())
	session.Data.Daily.Streak = streak
	session.Data.Gems += gems
	PlayerService.MarkDirty(player, true)
	return true, "Day " .. streak .. " reward: +" .. gems .. " Gems!"
end

function RewardService.ClaimGift(player: Player): (boolean, string?)
	local session = PlayerService.Get(player)
	if not session then
		return false, "Loading..."
	end
	local readyAt = session.Runtime.GiftReadyAt or 0
	if os.time() < readyAt then
		return false, "Gift ready in " .. Format.Duration(readyAt - os.time())
	end
	session.Runtime.GiftReadyAt = os.time() + Config.Rewards.PlaytimeGiftSeconds
	session.Data.Gems += Config.Rewards.PlaytimeGiftGems
	PlayerService.MarkDirty(player, true)
	return true, "+" .. Config.Rewards.PlaytimeGiftGems .. " Gems!"
end

local function giveOfflineEarnings(player: Player, session: PlayerService.Session)
	local lastSeen = session.Data.LastSeen
	if lastSeen <= 0 then
		return
	end
	local seconds = os.time() - lastSeen
	local income = SlimeService.IncomePerSecond(player)
	local coins = Formulas.OfflineEarnings(income, seconds, BoostService.HasPass(player, "VIP"))
	if coins <= 0 then
		return
	end
	session.Data.Coins += coins
	PlayerService.MarkDirty(player, true)
	Network.Effect(player, "OfflineEarnings", {
		Coins = coins,
		Seconds = math.min(seconds, Config.Rewards.OfflineMaxSeconds),
	})
end

function RewardService.Init()
	Network.Handle("ClaimDaily", function(player)
		return RewardService.ClaimDaily(player)
	end)
	Network.Handle("ClaimGift", function(player)
		return RewardService.ClaimGift(player)
	end)
	PlayerService.RegisterState("Daily", function(session)
		local available, streak = dailyStatus(session)
		return { Available = available, Streak = streak, Gems = Formulas.DailyGems(streak) }
	end)
	PlayerService.RegisterState("GiftReadyAt", function(session)
		return session.Runtime.GiftReadyAt or 0
	end)
end

function RewardService.Start()
	PlayerService.PlayerReady:Connect(function(player: Player, session: PlayerService.Session)
		session.Runtime.GiftReadyAt = os.time() + Config.Rewards.PlaytimeGiftSeconds
		giveOfflineEarnings(player, session)
	end)
end

return RewardService
