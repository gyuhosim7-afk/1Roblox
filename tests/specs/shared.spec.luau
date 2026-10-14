-- Tests for pure shared modules: Config sanity, Format, Formulas, Odds.

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local world = t.World.new()
	local Config = world:Require("ReplicatedStorage/Shared/Config")
	local Format = world:Require("ReplicatedStorage/Shared/Format")
	local Formulas = world:Require("ReplicatedStorage/Shared/Formulas")
	local Odds = world:Require("ReplicatedStorage/Shared/Odds")

	describe("Config", function()
		it("every egg pool references real slimes", function()
			for eggId, egg in Config.Eggs do
				for _, entry in egg.Pool do
					expect(Config.Slimes[entry.Slime] ~= nil).toBe(true)
				end
				expect(Config.Zones[egg.Zone].Egg).toBe(eggId)
			end
		end)

		it("every slime belongs to exactly one egg", function()
			local seen = {}
			for _, egg in Config.Eggs do
				for _, entry in egg.Pool do
					expect(seen[entry.Slime]).toBeNil()
					seen[entry.Slime] = true
				end
			end
			for slimeId in Config.Slimes do
				expect(seen[slimeId]).toBe(true)
			end
		end)

		it("every slime has a valid rarity and positive income", function()
			for _, slime in Config.Slimes do
				expect(Config.Rarities[slime.Rarity] ~= nil).toBe(true)
				expect(slime.Income).toBeGreaterThan(0)
				expect(slime.Color:match("^#%x%x%x%x%x%x$") ~= nil).toBe(true)
			end
		end)

		it("zones get strictly harder", function()
			for index = 2, #Config.Zones do
				local prev, zone = Config.Zones[index - 1], Config.Zones[index]
				expect(zone.GateSpeed).toBeGreaterThan(prev.GateSpeed)
				expect(zone.GuardPeriod).toBeLessThanOrEqual(prev.GuardPeriod)
			end
		end)

		it("pass and product orders list every entry", function()
			local count = 0
			for _ in Config.Passes do
				count += 1
			end
			expect(#Config.PassOrder).toBe(count)
			count = 0
			for _ in Config.Products do
				count += 1
			end
			expect(#Config.ProductOrder).toBe(count)
		end)

		it("random items have fallbacks or modifiers declared", function()
			expect(Config.Products.RoyalEgg.RandomItem).toBe(true)
			expect(Config.Products.RoyalEgg.FallbackGems).toBeGreaterThan(0)
			expect(Config.Products.LuckPotion.RandomItemModifier).toBe(true)
			expect(Config.Passes.Lucky.RandomItemModifier).toBe(true)
		end)
	end)

	describe("Format", function()
		it("abbreviates numbers", function()
			expect(Format.Number(0)).toBe("0")
			expect(Format.Number(15)).toBe("15")
			expect(Format.Number(999)).toBe("999")
			expect(Format.Number(1000)).toBe("1K")
			expect(Format.Number(1234)).toBe("1.23K")
			expect(Format.Number(15500)).toBe("15.5K")
			expect(Format.Number(250000)).toBe("250K")
			expect(Format.Number(1.5e9)).toBe("1.5B")
			expect(Format.Number(-2500)).toBe("-2.5K")
			expect(Format.Number(2.5)).toBe("2.5")
		end)
		it("formats commas and time", function()
			expect(Format.Commas(1234567)).toBe("1,234,567")
			expect(Format.Commas(100)).toBe("100")
			expect(Format.Clock(65)).toBe("1:05")
			expect(Format.Clock(3725)).toBe("1:02:05")
			expect(Format.Duration(20)).toBe("20s")
			expect(Format.Duration(65)).toBe("1m 5s")
			expect(Format.Duration(3725)).toBe("1h 2m")
		end)
		it("formats percentages", function()
			expect(Format.Percent(0.6)).toBe("60%")
			expect(Format.Percent(0.018)).toBe("1.8%")
			expect(Format.Percent(0.0005)).toBe("0.05%")
			expect(Format.Percent(0.000123456)).toBe("0.01235%")
			expect(Format.Percent(1)).toBe("100%")
		end)
	end)

	describe("Formulas", function()
		it("walk speed grows with speed and respects carry and cap", function()
			expect(Formulas.WalkSpeed(0)).toBe(16)
			expect(Formulas.WalkSpeed(100)).toBeCloseTo(16 + 6 * 100 ^ 0.3)
			expect(Formulas.WalkSpeed(100, 0.5)).toBeCloseTo(Formulas.WalkSpeed(100) / 2)
			expect(Formulas.WalkSpeed(1000)).toBeGreaterThan(Formulas.WalkSpeed(100))
			expect(Formulas.WalkSpeed(1e12)).toBe(Config.Speed.WalkMax)
		end)
		it("speed gain stacks training, rebirth and boosts", function()
			expect(Formulas.SpeedGainPerSecond(0, 0, {})).toBe(1)
			expect(Formulas.SpeedGainPerSecond(4, 0, {})).toBe(5)
			expect(Formulas.SpeedGainPerSecond(4, 2, {})).toBe(10)
			expect(Formulas.SpeedGainPerSecond(4, 2, { DoubleSpeed = true, SpeedPotion = true })).toBe(40)
		end)
		it("upgrade costs grow and stop at max level", function()
			local a = Formulas.UpgradeCost("Training", 0)
			local b = Formulas.UpgradeCost("Training", 1)
			expect(a).toBe(Config.Upgrades.Training.Base)
			expect(b).toBeGreaterThan(a)
			expect(Formulas.UpgradeCost("Incubators", Config.Upgrades.Incubators.MaxLevel)).toBeNil()
			expect(Formulas.UpgradeCost("Nope", 0)).toBeNil()
		end)
		it("counts pedestals, incubators and lock time", function()
			expect(Formulas.PedestalCount(0)).toBe(6)
			expect(Formulas.IncubatorCount(1, true)).toBe(5)
			expect(Formulas.LockSeconds(2, true)).toBe(45 + 30 + 60)
		end)
		it("computes slime income with mutations", function()
			expect(Formulas.SlimeIncome("BlueSlime", "None")).toBe(2)
			expect(Formulas.SlimeIncome("BlueSlime", "Gold")).toBe(4)
			expect(Formulas.SlimeIncome("BlueSlime", "Rainbow")).toBe(10)
			expect(Formulas.SlimeIncome("Nope", "None")).toBe(0)
			expect(Formulas.SellPrice("BlueSlime", "None")).toBe(40)
		end)
		it("zone unlocking follows speed and rebirth requirements", function()
			expect(Formulas.BestZone(0, 0)).toBe(1)
			expect(Formulas.BestZone(100, 0)).toBe(2)
			expect(Formulas.BestZone(1e9, 0)).toBe(6) -- Void needs 2 rebirths
			expect(Formulas.BestZone(1e9, 2)).toBe(7)
		end)
		it("offline earnings respect cap, rate and minimum", function()
			expect(Formulas.OfflineEarnings(100, 30)).toBe(0)
			expect(Formulas.OfflineEarnings(100, 1000)).toBe(25000)
			expect(Formulas.OfflineEarnings(100, 1e9)).toBe(100 * 10800 * 0.25)
			expect(Formulas.OfflineEarnings(100, 1000, true)).toBe(50000)
		end)
		it("daily rewards cycle every 7 days", function()
			expect(Formulas.DailyGems(1)).toBe(10)
			expect(Formulas.DailyGems(7)).toBe(100)
			expect(Formulas.DailyGems(8)).toBe(10)
		end)
		it("skip cost is at least one gem", function()
			expect(Formulas.SkipCost(0)).toBe(0)
			expect(Formulas.SkipCost(1)).toBe(1)
			expect(Formulas.SkipCost(95)).toBe(10)
		end)
		it("cash packs scale with income but have a minimum", function()
			expect(Formulas.CashPackCoins("CashSmall", 0)).toBe(1000)
			expect(Formulas.CashPackCoins("CashSmall", 100)).toBe(90000)
			expect(Formulas.CashPackCoins("Gems100", 100)).toBe(0)
		end)
	end)

	describe("Odds", function()
		local function sum(list)
			local total = 0
			for _, e in list do
				total += e.Chance
			end
			return total
		end

		it("every egg's odds sum to 100% with and without luck", function()
			for eggId in Config.Eggs do
				expect(sum(Odds.EggOdds(eggId, 1))).toBeCloseTo(1, 1e-9)
				expect(sum(Odds.EggOdds(eggId, 6))).toBeCloseTo(1, 1e-9)
			end
			for zone = 1, #Config.Zones do
				expect(sum(Odds.RoyalOdds(zone, 1))).toBeCloseTo(1, 1e-9)
			end
			expect(sum(Odds.MutationOdds(1))).toBeCloseTo(1, 1e-9)
			expect(sum(Odds.MutationOdds(100))).toBeCloseTo(1, 1e-9)
		end)

		it("matches the configured weights at luck 1", function()
			local odds = Odds.EggOdds("Meadow", 1)
			expect(odds[1].Slime).toBe("BlueSlime")
			expect(odds[1].Chance).toBeCloseTo(0.6)
			expect(odds[5].Chance).toBeCloseTo(0.01)
		end)

		it("luck raises rare chances and lowers common chances", function()
			local base = Odds.EggOdds("Forest", 1)
			local lucky = Odds.EggOdds("Forest", 2)
			expect(lucky[1].Chance).toBeLessThan(base[1].Chance)
			expect(lucky[6].Chance).toBeGreaterThan(base[6].Chance)
		end)

		it("mutation chances are capped", function()
			local m = Odds.MutationOdds(1000)
			expect(m[2].Chance + m[3].Chance).toBeCloseTo(Config.Luck.MaxMutationTotal)
		end)

		it("royal egg only contains Rare or better", function()
			for zone = 1, #Config.Zones do
				for _, e in Odds.RoyalOdds(zone, 1) do
					local rarity = Config.Slimes[e.Slime].Rarity
					expect(Config.Rarities[rarity].Order).toBeGreaterThanOrEqual(3)
				end
			end
		end)

		it("rolls follow the displayed odds statistically", function()
			local rng = world.Random.new(42)
			local counts = {}
			local n = 20000
			for _ = 1, n do
				local slime = Odds.Roll("Meadow", 1, function()
					return rng:NextNumber()
				end)
				counts[slime] = (counts[slime] or 0) + 1
			end
			for _, e in Odds.EggOdds("Meadow", 1) do
				local observed = (counts[e.Slime] or 0) / n
				expect(math.abs(observed - e.Chance)).toBeLessThan(0.02)
			end
		end)

		it("pick handles edge values", function()
			local entries = { { Chance = 0.5, Id = "a" }, { Chance = 0.5, Id = "b" } }
			local get = function(e)
				return e.Chance
			end
			expect(Odds.Pick(entries, 0, get).Id).toBe("a")
			expect(Odds.Pick(entries, 0.4999, get).Id).toBe("a")
			expect(Odds.Pick(entries, 0.5, get).Id).toBe("b")
			expect(Odds.Pick(entries, 0.99999999, get).Id).toBe("b")
		end)
	end)
end
