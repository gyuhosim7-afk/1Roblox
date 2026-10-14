--!strict
-- Game math shared by server (authoritative) and client (display only).
-- Pure functions over Config; no Roblox services.

local Config = require(script.Parent.Config)

local Formulas = {}

export type Modifiers = {
	DoubleCoins: boolean?,
	DoubleSpeed: boolean?,
	VIP: boolean?,
	Lucky: boolean?,
	LuckPotion: boolean?,
	SpeedPotion: boolean?,
	ServerLuck: boolean?,
	ExtraIncubators: boolean?,
}

-- Cost to go from `level` to `level + 1`. Returns nil when already at max level.
function Formulas.UpgradeCost(kind: string, level: number): number?
	local def = (Config.Upgrades :: any)[kind]
	if not def then
		return nil
	end
	if level >= def.MaxLevel then
		return nil
	end
	return math.floor(def.Base * def.Growth ^ level)
end

function Formulas.PedestalCount(level: number): number
	return Config.Upgrades.Pedestals.Start + level
end

function Formulas.IncubatorCount(level: number, hasPass: boolean?): number
	return Config.Upgrades.Incubators.Start + level + (if hasPass then Config.ExtraIncubatorsFromPass else 0)
end

function Formulas.LockSeconds(level: number, vip: boolean?): number
	return Config.Base.LockBaseSeconds
		+ Config.Base.LockPerLevelSeconds * level
		+ (if vip then Config.Base.VipLockBonusSeconds else 0)
end

-- Real Humanoid.WalkSpeed for a Speed stat value.
function Formulas.WalkSpeed(speed: number, carryMultiplier: number?): number
	local s = Config.Speed
	local walk = math.min(s.WalkMax, s.WalkBase + s.WalkFactor * math.max(0, speed) ^ s.WalkExponent)
	return walk * (carryMultiplier or 1)
end

function Formulas.SpeedGainPerSecond(trainingLevel: number, rebirths: number, mods: Modifiers): number
	local s = Config.Speed
	local base = s.BaseGainPerSecond + s.TrainingGainPerLevel * trainingLevel
	local mult = 1 + Config.Rebirth.SpeedBonusPerRebirth * rebirths
	if mods.DoubleSpeed then
		mult *= Config.Boosts.SpeedPassMultiplier
	end
	if mods.SpeedPotion then
		mult *= Config.Boosts.SpeedPotionMultiplier
	end
	return base * mult
end

function Formulas.CoinMultiplier(rebirths: number, mods: Modifiers): number
	local mult = 1 + Config.Rebirth.CoinBonusPerRebirth * rebirths
	if mods.DoubleCoins then
		mult *= Config.Boosts.CoinPassMultiplier
	end
	if mods.VIP then
		mult *= Config.Boosts.VipCoinMultiplier
	end
	return mult
end

function Formulas.Luck(mods: Modifiers): number
	local luck = 1
	if mods.Lucky then
		luck *= Config.Luck.PassMultiplier
	end
	if mods.LuckPotion then
		luck *= Config.Luck.PotionMultiplier
	end
	if mods.ServerLuck then
		luck *= Config.Luck.ServerMultiplier
	end
	return luck
end

-- Base income of one slime (before the player's coin multiplier).
function Formulas.SlimeIncome(slimeId: string, mutation: string?): number
	local def = Config.Slimes[slimeId]
	if not def then
		return 0
	end
	local mutationDef = (Config.Mutations :: any)[mutation or "None"] or Config.Mutations.None
	return def.Income * mutationDef.Multiplier
end

function Formulas.SellPrice(slimeId: string, mutation: string?): number
	return math.floor(Formulas.SlimeIncome(slimeId, mutation) * Config.Base.SellSeconds)
end

function Formulas.RebirthRequirement(rebirths: number): (number, number)
	local r = Config.Rebirth
	local speed = math.floor(r.SpeedBase * r.SpeedGrowth ^ rebirths)
	local coins = math.floor(r.CoinBase * r.CoinGrowth ^ rebirths)
	return speed, coins
end

function Formulas.SkipCost(remainingSeconds: number): number
	if remainingSeconds <= 0 then
		return 0
	end
	return math.max(1, math.ceil(remainingSeconds / Config.GemShop.SkipSecondsPerGem))
end

function Formulas.OfflineEarnings(incomePerSecond: number, offlineSeconds: number, vip: boolean?): number
	local r = Config.Rewards
	if offlineSeconds < r.OfflineMinSeconds then
		return 0
	end
	local seconds = math.min(offlineSeconds, r.OfflineMaxSeconds)
	local rate = if vip then r.VipOfflineRate else r.OfflineRate
	return math.floor(incomePerSecond * seconds * rate)
end

function Formulas.CashPackCoins(productKey: string, incomePerSecond: number): number
	local def = (Config.Products :: any)[productKey]
	if not def or not def.CashSeconds then
		return 0
	end
	return math.max(def.MinCoins, math.floor(incomePerSecond * def.CashSeconds))
end

-- streak is 1-based (1 = first day)
function Formulas.DailyGems(streak: number): number
	local list = Config.Rewards.DailyGems
	local index = ((math.max(1, streak) - 1) % #list) + 1
	return list[index]
end

function Formulas.ZoneUnlocked(zoneIndex: number, speed: number, rebirths: number): boolean
	local zone = Config.Zones[zoneIndex]
	if not zone then
		return false
	end
	return speed >= zone.GateSpeed and rebirths >= zone.RebirthsRequired
end

-- Highest zone index the player can currently enter.
function Formulas.BestZone(speed: number, rebirths: number): number
	local best = 1
	for index = 1, #Config.Zones do
		if Formulas.ZoneUnlocked(index, speed, rebirths) then
			best = index
		else
			break
		end
	end
	return best
end

return Formulas
