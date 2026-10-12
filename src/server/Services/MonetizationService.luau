--!strict
-- Game passes, developer products (ProcessReceipt), the gem shop and paid-random-item policy.
--  * Robux random items (Royal Egg) and luck boosts are blocked for players whose
--    PolicyService says ArePaidRandomItemsRestricted (or when the lookup fails).
--  * Receipts go through ReceiptLogic: grant + PurchaseId saved together before "Granted".
--  * Id = 0 means "not created yet": simulated in Studio, "coming soon" on live servers.

local MarketplaceService = game:GetService("MarketplaceService")
local PolicyService = game:GetService("PolicyService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local Odds = require(Shared.Odds)
local Validate = require(script.Parent.Parent.Logic.Validate)
local ReceiptLogic = require(script.Parent.Parent.Logic.ReceiptLogic)
local DataService = require(script.Parent.DataService)
local PlayerService = require(script.Parent.PlayerService)
local BoostService = require(script.Parent.BoostService)
local SlimeService = require(script.Parent.SlimeService)
local HatchService = require(script.Parent.HatchService)
local Network = require(script.Parent.Network)

local MonetizationService = {}

local rng = Random.new()
local function roll(): number
	return rng:NextNumber()
end

local productKeyById: { [number]: string } = {}
local passKeyById: { [number]: string } = {}

local function studioSimulation(): boolean
	return RunService:IsStudio() and Config.Monetization.StudioSimulatePurchases
end

-- Policy ------------------------------------------------------------------------
function MonetizationService.IsRestricted(player: Player): boolean
	local session = PlayerService.Get(player)
	if not session then
		return true
	end
	local restricted = session.Runtime.Restricted
	if restricted == nil then
		return true -- unknown yet: safest answer
	end
	return restricted == true
end

local function loadPolicy(player: Player, session: PlayerService.Session)
	local restricted = true
	for _ = 1, 3 do
		local ok, result = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		if ok and type(result) == "table" then
			restricted = result.ArePaidRandomItemsRestricted == true
			break
		end
		task.wait(1)
	end
	session.Runtime.Restricted = restricted
	PlayerService.MarkDirty(player, true)
end

local function isRandomRelated(def: any): boolean
	return def.RandomItem == true or def.RandomItemModifier == true
end

-- Grants ------------------------------------------------------------------------
local function rollRoyal(player: Player, session: PlayerService.Session)
	local luck = BoostService.GetLuck(player)
	local kind, mutation = Odds.RollRoyal(session.Data.BestZone, luck, roll)
	SlimeService.AddSlime(player, kind, mutation, "Royal", true)
end

local GRANTS: { [string]: (Player, PlayerService.Session, any) -> boolean } = {}

for key, def in Config.Products :: { [string]: any } do
	if def.Gems then
		GRANTS[key] = function(player, session)
			session.Data.Gems += def.Gems
			Network.Notify(player, "+" .. def.Gems .. " Gems! Thank you!", "success")
			return true
		end
	end
end

GRANTS.LuckPotion = function(player)
	BoostService.AddPotion(player, "Luck")
	Network.Notify(player, "Luck Potion active! Luck x" .. Config.Luck.PotionMultiplier, "success")
	return true
end

GRANTS.SpeedPotion = function(player)
	BoostService.AddPotion(player, "Speed")
	Network.Notify(player, "Speed Potion active! Speed gain x" .. Config.Boosts.SpeedPotionMultiplier, "success")
	return true
end

GRANTS.RoyalEgg = function(player, session)
	rollRoyal(player, session)
	return true
end

GRANTS.ServerLuck = function(player)
	BoostService.AddServerLuck(nil, player.DisplayName)
	return true
end

GRANTS.CashSmall = function(player, session)
	local coins = Formulas.CashPackCoins("CashSmall", SlimeService.IncomePerSecond(player))
	session.Data.Coins += coins
	Network.Notify(player, "+$" .. Format.Number(coins) .. "!", "success")
	return true
end

GRANTS.CashLarge = function(player, session)
	local coins = Formulas.CashPackCoins("CashLarge", SlimeService.IncomePerSecond(player))
	session.Data.Coins += coins
	Network.Notify(player, "+$" .. Format.Number(coins) .. "!", "success")
	return true
end

GRANTS.InstantHatch = function(player, session)
	local count = HatchService.HatchAllNow(player)
	if count == 0 then
		session.Data.Gems += 50
		Network.Notify(player, "No eggs to hatch - you got 50 Gems instead!", "success")
	end
	return true
end

-- Applies a product to a player. Restricted players get gems instead of random-item products.
function MonetizationService.GrantProduct(player: Player, key: string): boolean
	local session = PlayerService.Get(player)
	local def = (Config.Products :: any)[key]
	local grant = GRANTS[key]
	if not session or not def or not grant then
		return false
	end
	if isRandomRelated(def) and MonetizationService.IsRestricted(player) then
		local gems = def.FallbackGems or 100
		session.Data.Gems += gems
		Network.Notify(player, def.Name .. " is not available in your region. You received " .. gems .. " Gems instead.", "info")
		PlayerService.MarkDirty(player, true)
		return true
	end
	local ok = grant(player, session, def)
	PlayerService.MarkDirty(player, true)
	return ok
end

-- Receipts ----------------------------------------------------------------------
local function receiptDeps(keyOverride: string?): ReceiptLogic.Deps
	return {
		getContext = function(userId: number): ReceiptLogic.Context?
			local player = Players:GetPlayerByUserId(userId)
			if not player then
				return nil
			end
			local profile = DataService.WaitFor(player, 10)
			local waited = 0
			while profile and not PlayerService.Get(player) and waited < 10 and player.Parent do
				waited += task.wait(0.2)
			end
			if not profile or not PlayerService.Get(player) then
				return nil
			end
			return { Profile = profile :: any, Player = player }
		end,
		productKeyForId = function(productId: number): string?
			return keyOverride or productKeyById[productId]
		end,
		grant = function(ctx: ReceiptLogic.Context, productKey: string): boolean
			return MonetizationService.GrantProduct(ctx.Player, productKey)
		end,
		save = function(ctx: ReceiptLogic.Context): boolean
			return DataService.SaveProfileAsync(ctx.Profile :: any)
		end,
		now = os.time,
		maxStoredIds = Config.Monetization.MaxStoredPurchaseIds,
		log = function(message: string)
			warn("[Monetization] " .. message)
		end,
	}
end

function MonetizationService.ProcessReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local result = ReceiptLogic.Process(receiptInfo, receiptDeps(nil))
	if result == ReceiptLogic.Granted then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Passes ------------------------------------------------------------------------
local function checkPasses(player: Player)
	for key, def in Config.Passes :: { [string]: any } do
		if def.Id ~= 0 then
			local ok, owned = false, false
			for _ = 1, 3 do
				ok, owned = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.Id)
				end)
				if ok then
					break
				end
				task.wait(1)
			end
			if ok and player.Parent then
				BoostService.SetPass(player, key, owned == true)
			end
		end
	end
end

local function onPassPurchased(player: Player, key: string)
	BoostService.SetPass(player, key, true)
	local def = (Config.Passes :: any)[key]
	Network.Notify(player, "You got " .. def.Name .. "! Thank you!", "success")
	Network.Effect(player, "Purchase", { Kind = "Pass", Key = key })
end

-- Requests ----------------------------------------------------------------------
function MonetizationService.BuyPass(player: Player, payload: any): (boolean, string?)
	local key = Validate.Key(payload, Config.Passes :: any)
	if not key then
		return false, "Bad request"
	end
	local def = (Config.Passes :: any)[key]
	if BoostService.HasPass(player, key) then
		return false, "You already own this!"
	end
	if isRandomRelated(def) and MonetizationService.IsRestricted(player) then
		return false, "Not available in your region"
	end
	if def.Id == 0 then
		if studioSimulation() then
			onPassPurchased(player, key)
			return true, "[Studio] Simulated purchase"
		end
		return false, "Coming soon!"
	end
	MarketplaceService:PromptGamePassPurchase(player, def.Id)
	return true, nil
end

function MonetizationService.BuyProduct(player: Player, payload: any): (boolean, string?)
	local key = Validate.Key(payload, Config.Products :: any)
	if not key then
		return false, "Bad request"
	end
	local def = (Config.Products :: any)[key]
	if isRandomRelated(def) and MonetizationService.IsRestricted(player) then
		return false, "Not available in your region"
	end
	if def.Id == 0 then
		if studioSimulation() then
			local receipt = {
				PlayerId = player.UserId,
				ProductId = 0,
				PurchaseId = "studio-" .. HttpService:GenerateGUID(false),
				CurrencySpent = 0,
			}
			local result = ReceiptLogic.Process(receipt, receiptDeps(key))
			return result == ReceiptLogic.Granted, "[Studio] Simulated purchase"
		end
		return false, "Coming soon!"
	end
	MarketplaceService:PromptProductPurchase(player, def.Id)
	return true, nil
end

function MonetizationService.BuyWithGems(player: Player, payload: any): (boolean, string?)
	local session = PlayerService.Get(player)
	local item = Validate.Key(payload, Config.GemShop :: any)
	if not session or not item or item == "SkipSecondsPerGem" then
		return false, "Bad request"
	end
	local cost = (Config.GemShop :: any)[item] :: number
	-- Gems can be bought with Robux, so gem-bought random items follow the same policy.
	if (item == "RoyalEgg" or item == "LuckPotion") and MonetizationService.IsRestricted(player) then
		return false, "Not available in your region"
	end
	if session.Data.Gems < cost then
		return false, "You need " .. cost .. " gems"
	end
	session.Data.Gems -= cost
	if item == "LuckPotion" then
		BoostService.AddPotion(player, "Luck")
	elseif item == "SpeedPotion" then
		BoostService.AddPotion(player, "Speed")
	elseif item == "RoyalEgg" then
		rollRoyal(player, session)
	end
	PlayerService.MarkDirty(player, true)
	return true, nil
end

function MonetizationService.Init()
	for key, def in Config.Products :: { [string]: any } do
		if def.Id ~= 0 then
			productKeyById[def.Id] = key
		end
	end
	for key, def in Config.Passes :: { [string]: any } do
		if def.Id ~= 0 then
			passKeyById[def.Id] = key
		end
	end
	Network.Handle("BuyPass", MonetizationService.BuyPass)
	Network.Handle("BuyProduct", MonetizationService.BuyProduct)
	Network.Handle("BuyWithGems", MonetizationService.BuyWithGems)
	PlayerService.RegisterState("Restricted", function(session)
		return session.Runtime.Restricted ~= false
	end)
end

function MonetizationService.Start()
	MarketplaceService.ProcessReceipt = MonetizationService.ProcessReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		local key = passKeyById[passId]
		if purchased and key then
			onPassPurchased(player, key)
		end
	end)
	PlayerService.PlayerReady:Connect(function(player: Player, session: PlayerService.Session)
		task.spawn(loadPolicy, player, session)
		task.spawn(checkPasses, player)
	end)
end

return MonetizationService
