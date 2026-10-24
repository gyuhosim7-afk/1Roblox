-- Receipts (no double grants, no lost purchases), passes, policy restrictions, gem shop, rewards.

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local World = t.World

	describe("ReceiptLogic", function()
		local world = World.new()
		local ReceiptLogic = world:Require("ServerScriptService/Server/Logic/ReceiptLogic")
		local Schema = world:Require("ServerScriptService/Server/Logic/ProfileSchema")

		local function makeDeps(state)
			return {
				getContext = function(userId)
					if state.missing then
						return nil
					end
					return { Profile = state.profile, Player = userId }
				end,
				productKeyForId = function(id)
					return if id == 1 then "Gems100" else nil
				end,
				grant = function(ctx, key)
					if state.grantError then
						error("boom")
					end
					state.grants += 1
					ctx.Profile.Data.Gems += 100
					return true
				end,
				save = function()
					state.saves += 1
					return not state.saveFails
				end,
				now = function()
					return 1000
				end,
				maxStoredIds = 50,
			}
		end

		local function newState()
			return { profile = { Data = Schema.Default(0) }, grants = 0, saves = 0 }
		end

		it("grants once even if the same receipt arrives again", function()
			local state = newState()
			local deps = makeDeps(state)
			local receipt = { PlayerId = 1, ProductId = 1, PurchaseId = "abc", CurrencySpent = 49 }
			expect(ReceiptLogic.Process(receipt, deps)).toBe("Granted")
			expect(ReceiptLogic.Process(receipt, deps)).toBe("Granted")
			expect(state.grants).toBe(1)
			expect(state.profile.Data.Gems).toBe(100)
			expect(state.profile.Data.Stats.RobuxSpent).toBe(49)
		end)

		it("does not confirm until the save succeeds, and still grants only once", function()
			local state = newState()
			local deps = makeDeps(state)
			local receipt = { PlayerId = 1, ProductId = 1, PurchaseId = "x1" }
			state.saveFails = true
			expect(ReceiptLogic.Process(receipt, deps)).toBe("NotProcessedYet")
			expect(ReceiptLogic.Process(receipt, deps)).toBe("NotProcessedYet")
			state.saveFails = false
			expect(ReceiptLogic.Process(receipt, deps)).toBe("Granted")
			expect(state.grants).toBe(1)
		end)

		it("waits when the player is not in the server or the product is unknown", function()
			local state = newState()
			local deps = makeDeps(state)
			state.missing = true
			expect(ReceiptLogic.Process({ PlayerId = 1, ProductId = 1, PurchaseId = "a" }, deps)).toBe(
				"NotProcessedYet"
			)
			state.missing = false
			expect(ReceiptLogic.Process({ PlayerId = 1, ProductId = 999, PurchaseId = "b" }, deps)).toBe(
				"NotProcessedYet"
			)
			expect(state.grants).toBe(0)
		end)

		it("does not record a purchase whose grant failed", function()
			local state = newState()
			local deps = makeDeps(state)
			state.grantError = true
			expect(ReceiptLogic.Process({ PlayerId = 1, ProductId = 1, PurchaseId = "c" }, deps)).toBe(
				"NotProcessedYet"
			)
			expect(state.profile.Data.Purchases.c).toBeNil()
		end)
	end)

	local function setup(opts)
		opts = opts or {}
		local world = World.new(opts)
		local Config = world:Require("ReplicatedStorage/Shared/Config")
		if opts.ids ~= false then
			local id = 1000
			for _, key in Config.ProductOrder do
				id += 1
				Config.Products[key].Id = id
			end
			for _, key in Config.PassOrder do
				id += 1
				Config.Passes[key].Id = id
			end
		end
		world:StartServer()
		local s = {
			world = world,
			Config = Config,
			PlayerService = world:Require("ServerScriptService/Server/Services/PlayerService"),
			Monetization = world:Require("ServerScriptService/Server/Services/MonetizationService"),
			BoostService = world:Require("ServerScriptService/Server/Services/BoostService"),
			HatchService = world:Require("ServerScriptService/Server/Services/HatchService"),
			Network = world:Require("ServerScriptService/Server/Services/Network"),
			MPS = world.services.MarketplaceService,
		}
		function s.join(userId)
			local player = world.AddPlayer(userId, "P" .. userId)
			world:Advance(0.5)
			return player, s.PlayerService.Get(player)
		end
		function s.receipt(player, key, purchaseId)
			return world:Run(function()
				return s.MPS.ProcessReceipt({
					PlayerId = player.UserId,
					ProductId = Config.Products[key].Id,
					PurchaseId = purchaseId,
					CurrencySpent = Config.Products[key].Price,
				})
			end)
		end
		function s.stored(userId)
			return world.dataBackend.stores[Config.Data.StoreName .. "/global"]["Player_" .. userId]
		end
		return s
	end

	describe("Developer products", function()
		it("grants gems through ProcessReceipt and saves the purchase id", function()
			local s = setup()
			local player, session = s.join(1)
			local Enum = require("@lune/roblox").Enum
			local result = s.receipt(player, "Gems100", "P-1")
			expect(result).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
			expect(session.Data.Gems).toBe(100)
			expect(s.stored(1).Data.Purchases["P-1"] ~= nil).toBe(true)
			expect(s.stored(1).Data.Gems).toBe(100)
			-- duplicate delivery
			s.receipt(player, "Gems100", "P-1")
			expect(session.Data.Gems).toBe(100)
		end)

		it("retries safely through a DataStore outage", function()
			local s = setup()
			local player, session = s.join(1)
			local Enum = require("@lune/roblox").Enum
			s.world.dataBackend.failAll = true
			local result = s.receipt(player, "Gems350", "P-2")
			expect(result).toBe(Enum.ProductPurchaseDecision.NotProcessedYet)
			s.world.dataBackend.failAll = false
			result = s.receipt(player, "Gems350", "P-2")
			expect(result).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
			expect(session.Data.Gems).toBe(350)
			expect(s.stored(1).Data.Gems).toBe(350)
		end)

		it("gives a Rare-or-better slime from the Royal Egg", function()
			local s = setup()
			local player, session = s.join(1)
			for i = 1, 20 do
				s.receipt(player, "RoyalEgg", "R-" .. i)
			end
			expect(#session.Data.Slimes).toBe(20)
			for _, slime in session.Data.Slimes do
				local rarity = s.Config.Slimes[slime.Kind].Rarity
				expect(s.Config.Rarities[rarity].Order).toBeGreaterThanOrEqual(3)
				expect(s.Config.Eggs.Meadow.Pool[1].Slime ~= slime.Kind).toBe(true)
			end
		end)

		it("scales cash packs with income and activates potions and server luck", function()
			local s = setup()
			local player, session = s.join(1)
			local SlimeService = s.world:Require("ServerScriptService/Server/Services/SlimeService")
			SlimeService.AddSlime(player, "SunnySlime", "None")
			local coins = session.Data.Coins
			s.receipt(player, "CashSmall", "C-1")
			expect(session.Data.Coins - coins).toBe(math.max(1000, 40 * 900))
			s.receipt(player, "LuckPotion", "L-1")
			expect(s.BoostService.GetLuck(player)).toBe(2)
			local other = s.join(2)
			s.receipt(player, "ServerLuck", "S-1")
			expect(s.BoostService.GetLuck(other)).toBe(2)
			expect(s.BoostService.GetLuck(player)).toBe(4)
		end)

		it("prompts the real purchase for configured products", function()
			local s = setup()
			local player = s.join(1)
			local r = s.Network.Invoke(player, "BuyProduct", "Gems100")
			expect(r.ok).toBe(true)
			expect(#s.world.prompts).toBe(1)
			expect(s.world.prompts[1].id).toBe(s.Config.Products.Gems100.Id)
			expect(s.Network.Invoke(player, "BuyProduct", "FreeRobux").ok).toBe(false)
		end)
	end)

	describe("Paid random item policy", function()
		it("blocks Royal Egg and luck items for restricted players", function()
			local s = setup({
				policies = { [5] = { ArePaidRandomItemsRestricted = true, IsPaidItemTradingAllowed = false } },
			})
			local player, session = s.join(5)
			s.world:Advance(1)
			expect(s.Monetization.IsRestricted(player)).toBe(true)
			expect(s.Network.Invoke(player, "BuyProduct", "RoyalEgg").ok).toBe(false)
			expect(s.Network.Invoke(player, "BuyProduct", "LuckPotion").ok).toBe(false)
			expect(s.Network.Invoke(player, "BuyProduct", "ServerLuck").ok).toBe(false)
			expect(s.Network.Invoke(player, "BuyPass", "Lucky").ok).toBe(false)
			session.Data.Gems = 1000
			expect(s.Network.Invoke(player, "BuyWithGems", "RoyalEgg").ok).toBe(false)
			expect(s.Network.Invoke(player, "BuyWithGems", "LuckPotion").ok).toBe(false)
			expect(session.Data.Gems).toBe(1000)
			-- non-random items still work
			expect(s.Network.Invoke(player, "BuyProduct", "Gems100").ok).toBe(true)
			expect(s.Network.Invoke(player, "BuyWithGems", "SpeedPotion").ok).toBe(true)
			-- a receipt that slips through gives gems instead of a random item
			s.receipt(player, "RoyalEgg", "X-1")
			expect(#session.Data.Slimes).toBe(0)
			expect(session.Data.Gems).toBe(1000 - 40 + s.Config.Products.RoyalEgg.FallbackGems)
		end)

		it("treats a failed policy lookup as restricted", function()
			local s = setup({ policies = { [6] = "error" } })
			local player = s.join(6)
			s.world:Advance(5)
			expect(s.Monetization.IsRestricted(player)).toBe(true)
		end)

		it("allows random items for eligible players", function()
			local s = setup()
			local player, session = s.join(7)
			s.world:Advance(1)
			expect(s.Monetization.IsRestricted(player)).toBe(false)
			session.Data.Gems = 200
			expect(s.Network.Invoke(player, "BuyWithGems", "RoyalEgg").ok).toBe(true)
			expect(#session.Data.Slimes).toBe(1)
			expect(session.Data.Gems).toBe(
				200
					- s.Config.GemShop.RoyalEgg
					+ s.Config.Rarities[s.Config.Slimes[session.Data.Slimes[1].Kind].Rarity].DiscoveryGems
			)
		end)
	end)

	describe("Game passes", function()
		it("detects owned passes on join and applies purchases", function()
			local world = World.new({ ownedPasses = {} })
			local Config = world:Require("ReplicatedStorage/Shared/Config")
			Config.Passes.DoubleCoins.Id = 501
			Config.Passes.ExtraIncubators.Id = 502
			world.ownedPasses[9] = { [501] = true }
			world:StartServer()
			local PlayerService = world:Require("ServerScriptService/Server/Services/PlayerService")
			local BoostService = world:Require("ServerScriptService/Server/Services/BoostService")
			local HatchService = world:Require("ServerScriptService/Server/Services/HatchService")
			local player = world.AddPlayer(9, "Nine")
			world:Advance(1)
			expect(BoostService.HasPass(player, "DoubleCoins")).toBe(true)
			expect(BoostService.GetCoinMultiplier(player)).toBe(2)
			expect(HatchService.Capacity(player)).toBe(2)
			world.services.MarketplaceService.PromptGamePassPurchaseFinished:Fire(player, 502, true)
			world:Advance(0.1)
			expect(HatchService.Capacity(player)).toBe(4)
			expect(PlayerService.Get(player).Data.PassCache.ExtraIncubators).toBe(true)
		end)

		it("simulates purchases in Studio when ids are not set, and says coming soon live", function()
			local s = setup({ isStudio = true, ids = false })
			local player, session = s.join(1)
			local r = s.Network.Invoke(player, "BuyProduct", "Gems1000")
			expect(r.ok).toBe(true)
			expect(session.Data.Gems).toBe(1000)
			r = s.Network.Invoke(player, "BuyPass", "AutoCollect")
			expect(r.ok).toBe(true)
			expect(s.BoostService.HasPass(player, "AutoCollect")).toBe(true)

			local live = setup({ ids = false })
			local p2 = live.join(2)
			local r2 = live.Network.Invoke(p2, "BuyProduct", "Gems1000")
			expect(r2.ok).toBe(false)
			expect(r2.msg).toBe("Coming soon!")
		end)
	end)

	describe("Free rewards", function()
		it("gives daily gems once per day with a streak", function()
			local s = setup()
			local player, session = s.join(1)
			local r = s.Network.Invoke(player, "ClaimDaily")
			expect(r.ok).toBe(true)
			expect(session.Data.Gems).toBe(10)
			expect(s.Network.Invoke(player, "ClaimDaily").ok).toBe(false)
			s.world:Advance(86400, 60)
			expect(s.Network.Invoke(player, "ClaimDaily").ok).toBe(true)
			expect(session.Data.Daily.Streak).toBe(2)
			s.world:Advance(86400 * 2, 60)
			s.Network.Invoke(player, "ClaimDaily")
			expect(session.Data.Daily.Streak).toBe(1)
		end)

		it("gives a playtime gift every 10 minutes", function()
			local s = setup()
			local player, session = s.join(1)
			expect(s.Network.Invoke(player, "ClaimGift").ok).toBe(false)
			s.world:Advance(s.Config.Rewards.PlaytimeGiftSeconds + 1, 1)
			expect(s.Network.Invoke(player, "ClaimGift").ok).toBe(true)
			expect(session.Data.Gems).toBe(s.Config.Rewards.PlaytimeGiftGems)
			expect(s.Network.Invoke(player, "ClaimGift").ok).toBe(false)
		end)

		it("pays offline earnings when returning", function()
			local s = setup()
			local player, session = s.join(1)
			local SlimeService = s.world:Require("ServerScriptService/Server/Services/SlimeService")
			SlimeService.AddSlime(player, "SunnySlime", "None")
			s.world.RemovePlayer(player)
			s.world:Advance(1)
			local world2 = World.new({ dataBackend = s.world.dataBackend, jobId = "job-2" })
			world2.scheduler.epoch = s.world.scheduler:Time() + 7200
			world2:StartServer()
			local PlayerService2 = world2:Require("ServerScriptService/Server/Services/PlayerService")
			local p2 = world2.AddPlayer(1, "P1")
			world2:Advance(1)
			local data = PlayerService2.Get(p2).Data
			-- 40 coins/s * ~7200 s * 25%
			expect(data.Coins).toBeGreaterThan(40 * 7000 * 0.25)
			expect(data.Coins).toBeLessThan(40 * 7300 * 0.25 + 1000)
			local _ = session
		end)
	end)
end
