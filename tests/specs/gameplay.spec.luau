-- Core loop: speed ticks, stealing nest eggs, delivering, hatching, income, collecting, selling.

local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local World = t.World

	local function setup(opts)
		local world = World.new(opts)
		world:StartServer()
		local s = {
			world = world,
			Config = world:Require("ReplicatedStorage/Shared/Config"),
			MapLayout = world:Require("ReplicatedStorage/Shared/MapLayout"),
			Formulas = world:Require("ReplicatedStorage/Shared/Formulas"),
			PlayerService = world:Require("ServerScriptService/Server/Services/PlayerService"),
			PlotService = world:Require("ServerScriptService/Server/Services/PlotService"),
			EggService = world:Require("ServerScriptService/Server/Services/EggService"),
			HatchService = world:Require("ServerScriptService/Server/Services/HatchService"),
			SlimeService = world:Require("ServerScriptService/Server/Services/SlimeService"),
			SpeedService = world:Require("ServerScriptService/Server/Services/SpeedService"),
			Network = world:Require("ServerScriptService/Server/Services/Network"),
		}
		function s.join(userId, name)
			local player = world.AddPlayer(userId, name or ("P" .. userId))
			world:Advance(0.3)
			return player, s.PlayerService.Get(player)
		end
		function s.root(player)
			return player.Character:FindFirstChild("HumanoidRootPart")
		end
		function s.moveTo(player, position)
			player.Character:PivotTo(CFrame.new(position))
		end
		function s.nestIn(zone)
			for _, nest in s.EggService.GetNests() do
				if nest.Zone == zone and nest.HasEgg then
					return nest
				end
			end
			return nil
		end
		function s.goHome(player)
			local plot = s.PlotService.Get(player)
			player.Character:PivotTo(s.PlotService.SpawnCFrame(plot))
		end
		return s
	end

	describe("Speed", function()
		it("gains +1 speed per second and converts it to walk speed", function()
			local s = setup()
			local player, session = s.join(1)
			s.world:Advance(10)
			expect(session.Data.Speed).toBeGreaterThanOrEqual(9)
			expect(session.Data.Speed).toBeLessThanOrEqual(11)
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			expect(humanoid.WalkSpeed).toBeCloseTo(s.Formulas.WalkSpeed(session.Data.Speed), 0.5)
			expect(session.Data.Stats.Playtime).toBeGreaterThanOrEqual(9)
		end)

		it("unlocks zones and notifies when passing a speed threshold", function()
			local s = setup()
			local _, session = s.join(1)
			session.Data.Speed = 99.5
			s.world:Advance(1.2)
			expect(session.Data.BestZone).toBe(2)
		end)

		it("sends players back from zones they cannot enter yet", function()
			local s = setup()
			local player, session = s.join(1)
			session.Data.Speed = 0
			local zone3 = s.MapLayout.Zones[3]
			s.moveTo(player, Vector3.new(0, 3, zone3.StartZ + 50))
			s.world:Advance(0.5)
			local z = s.root(player).Position.Z
			expect(z).toBeLessThan(s.MapLayout.Zones[2].GateZ)
		end)
	end)

	describe("Stealing nest eggs", function()
		it("carries an egg home, incubates, hatches and earns coins", function()
			local s = setup()
			local player, session = s.join(1)
			local nest = s.nestIn(1)
			s.moveTo(player, nest.Position + Vector3.new(0, 2, 2))
			local ok = s.EggService.TryTakeNestEgg(player, nest)
			expect(ok).toBe(true)
			expect(nest.HasEgg).toBe(false)
			expect(nest.Prompt.Enabled).toBe(false)
			expect(player:GetAttribute("CarryingEgg")).toBe("Meadow")
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			expect(humanoid.WalkSpeed).toBeLessThan(s.Formulas.WalkSpeed(session.Data.Speed))
			expect(session.Data.TutorialStep).toBe(2)

			-- carrying a second egg is not allowed
			local other = s.nestIn(1)
			expect((s.EggService.TryTakeNestEgg(player, other))).toBe(false)

			s.goHome(player)
			s.world:Advance(0.3)
			expect(s.EggService.CarryOf(player)).toBeNil()
			expect(#session.Data.Eggs).toBe(1)
			expect(session.Data.Eggs[1].Slot).toBe(1)
			expect(session.Data.Stats.EggsStolen).toBe(1)
			expect(session.Data.TutorialStep).toBe(3)
			local plot = s.PlotService.Get(player)
			expect(plot.Incubators[1].Part:GetAttribute("Egg")).toBe("Meadow")

			-- nest refills after a few seconds
			s.world:Advance(s.Config.Map.NestRespawnSeconds + 0.5)
			expect(nest.HasEgg).toBe(true)

			-- hatch
			s.world:Advance(s.Config.Eggs.Meadow.HatchSeconds + 1)
			expect(#session.Data.Eggs).toBe(0)
			expect(#session.Data.Slimes).toBe(1)
			local slime = session.Data.Slimes[1]
			expect(session.Data.Discovered[slime.Kind]).toBe(true)
			expect(session.Data.Gems).toBeGreaterThan(0)
			expect(session.Data.TutorialStep).toBe(4)
			-- pedestal shows it
			local found = false
			for _, child in plot.Model:GetChildren() do
				if child:GetAttribute("SlimeId") == slime.Id then
					found = true
				end
			end
			expect(found).toBe(true)

			-- income flows to the bank, then the pad collects it
			s.moveTo(player, Vector3.new(0, 3, -300)) -- away from the pad
			s.world:Advance(5)
			expect(session.Data.Bank).toBeGreaterThan(0)
			local before = session.Data.Coins
			local pad = s.MapLayout.PlotLocal.CollectPad
			local x, z = s.MapLayout.PlotToWorld(plot.Layout, pad.X, pad.Z)
			s.moveTo(player, Vector3.new(x, 3, z))
			s.world:Advance(0.5)
			expect(session.Data.Coins).toBeGreaterThan(before)
			expect(session.Data.Bank).toBeLessThan(1)
			expect(session.Data.TutorialStep).toBe(5)

			-- sell it
			local coins = session.Data.Coins
			local result = s.Network.Invoke(player, "SellSlime", slime.Id)
			expect(result.ok).toBe(true)
			expect(#session.Data.Slimes).toBe(0)
			expect(session.Data.Coins).toBe(coins + s.Formulas.SellPrice(slime.Kind, slime.Mutation))
		end)

		it("refuses eggs from locked zones and when too far", function()
			local s = setup()
			local player, session = s.join(1)
			session.Data.Speed = 0
			local nest2 = s.nestIn(2)
			s.moveTo(player, nest2.Position)
			local ok, msg = s.EggService.TryTakeNestEgg(player, nest2)
			expect(ok).toBe(false)
			expect(msg).toContain("Speed")
			local nest1 = s.nestIn(1)
			s.moveTo(player, nest1.Position + Vector3.new(0, 0, 40))
			ok = s.EggService.TryTakeNestEgg(player, nest1)
			expect(ok).toBe(false)
		end)

		it("refuses eggs when every incubator is full", function()
			local s = setup()
			local player, session = s.join(1)
			for _ = 1, 2 do
				s.HatchService.AddEgg(player, "Meadow")
			end
			local nest = s.nestIn(1)
			s.moveTo(player, nest.Position)
			local ok, msg = s.EggService.TryTakeNestEgg(player, nest)
			expect(ok).toBe(false)
			expect(msg).toBe("Incubators full")
			expect(nest.HasEgg).toBe(true)
			local _ = session
		end)

		it("returns the egg to its nest when the carrier dies", function()
			local s = setup()
			local player = s.join(1)
			local nest = s.nestIn(1)
			s.moveTo(player, nest.Position)
			s.EggService.TryTakeNestEgg(player, nest)
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			humanoid.Died:Fire()
			s.world:Advance(0.2)
			expect(s.EggService.CarryOf(player)).toBeNil()
			expect(nest.HasEgg).toBe(true)
		end)

		it("drops the egg if the carrier teleports", function()
			local s = setup()
			local player = s.join(1)
			local nest = s.nestIn(1)
			s.moveTo(player, nest.Position)
			s.EggService.TryTakeNestEgg(player, nest)
			s.world:Advance(0.6)
			s.moveTo(player, nest.Position + Vector3.new(0, 0, 400))
			s.world:Advance(0.6)
			expect(s.EggService.CarryOf(player)).toBeNil()
			expect(nest.HasEgg).toBe(true)
		end)

		it("does not drop the egg for normal running speed", function()
			local s = setup()
			local player, session = s.join(1)
			local nest = s.nestIn(1)
			local start = nest.Position + Vector3.new(0, 2, 0)
			s.moveTo(player, start)
			s.EggService.TryTakeNestEgg(player, nest)
			local walk = s.Formulas.WalkSpeed(session.Data.Speed, s.Config.Eggs.Meadow.CarryMultiplier)
			for step = 1, 20 do
				s.moveTo(player, start - Vector3.new(0, 0, walk * 0.1 * step))
				s.world:Advance(0.1)
			end
			expect(s.EggService.CarryOf(player) ~= nil).toBe(true)
		end)
	end)

	describe("Hatching", function()
		it("hatches eggs that finished while offline as soon as the player returns", function()
			local s = setup()
			local player, session = s.join(1)
			s.HatchService.AddEgg(player, "Forest")
			s.world.RemovePlayer(player)
			s.world:Advance(1)
			local world2 = World.new({ dataBackend = s.world.dataBackend, jobId = "job-2" })
			world2.scheduler.epoch = s.world.scheduler:Time() + 3600 -- an hour later
			world2:StartServer()
			local PlayerService2 = world2:Require("ServerScriptService/Server/Services/PlayerService")
			local p2 = world2.AddPlayer(1, "P1")
			world2:Advance(1)
			local session2 = PlayerService2.Get(p2)
			expect(#session2.Data.Eggs).toBe(0)
			expect(#session2.Data.Slimes).toBe(1)
			local _ = session
		end)

		it("skips hatch time with gems", function()
			local s = setup()
			local player, session = s.join(1)
			s.HatchService.AddEgg(player, "Snow")
			session.Data.Gems = 5
			local result = s.Network.Invoke(player, "SkipHatch", 1)
			expect(result.ok).toBe(false)
			session.Data.Gems = 100
			result = s.Network.Invoke(player, "SkipHatch", 1)
			expect(result.ok).toBe(true)
			expect(#session.Data.Slimes).toBe(1)
			expect(session.Data.Gems).toBe(
				100 - 12 + s.Config.Rarities[s.Config.Slimes[session.Data.Slimes[1].Kind].Rarity].DiscoveryGems
			)
		end)

		it("pauses hatching when slime storage is full", function()
			local s = setup()
			local player, session = s.join(1)
			for i = 1, s.Config.Base.MaxSlimes do
				table.insert(
					session.Data.Slimes,
					{ Id = "S" .. (1000 + i), Kind = "BlueSlime", Mutation = "None", Locked = false }
				)
			end
			s.HatchService.AddEgg(player, "Meadow")
			s.world:Advance(15)
			expect(#session.Data.Eggs).toBe(1)
			table.remove(session.Data.Slimes)
			s.world:Advance(1)
			expect(#session.Data.Eggs).toBe(0)
		end)
	end)

	describe("Slime management", function()
		it("puts the best slimes on pedestals and sells only unlocked storage slimes", function()
			local s = setup()
			local player, session = s.join(1)
			local SlimeInventory = s.world:Require("ServerScriptService/Server/Logic/SlimeInventory")
			for i = 1, 8 do
				table.insert(
					session.Data.Slimes,
					{ Id = "S" .. i, Kind = "BlueSlime", Mutation = "None", Locked = false }
				)
			end
			table.insert(session.Data.Slimes, { Id = "S9", Kind = "SunnySlime", Mutation = "None", Locked = false })
			session.Data.Slimes[1].Locked = true
			local onPedestals = SlimeInventory.PedestalSlimes(session.Data.Slimes, 6)
			expect(onPedestals[1].Id).toBe("S9")
			expect(#onPedestals).toBe(6)
			-- storage: S6, S7, S8 are unlocked commons not on pedestals (S1 locked but on pedestal anyway)
			local result = s.Network.Invoke(player, "SellAllBelow", 1)
			expect(result.ok).toBe(true)
			expect(#session.Data.Slimes).toBe(6)
			local lockResult = s.Network.Invoke(player, "LockSlime", "S9")
			expect(lockResult.ok).toBe(true)
			expect(s.Network.Invoke(player, "SellSlime", "S9").ok).toBe(false)
			expect(s.Network.Invoke(player, "SellSlime", 123).ok).toBe(false)
			expect(s.Network.Invoke(player, "SellSlime", "S404").ok).toBe(false)
		end)

		it("auto-collect pass sends income straight to coins", function()
			local s = setup()
			local player, session = s.join(1)
			local BoostService = s.world:Require("ServerScriptService/Server/Services/BoostService")
			BoostService.SetPass(player, "AutoCollect", true)
			s.SlimeService.AddSlime(player, "SunnySlime", "None")
			s.moveTo(player, Vector3.new(0, 3, -300))
			s.world:Advance(3)
			expect(session.Data.Coins).toBeGreaterThan(50)
			expect(session.Data.Bank).toBeLessThan(1)
		end)
	end)
end
