-- End-to-end scenario: a new player plays a full session, rebirths, buys things, leaves,
-- and comes back on another server with everything intact. Also runs the Studio SelfTest.

local roblox = require("@lune/roblox")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local World = t.World

	describe("Full session", function()
		it("new player -> steal -> hatch -> upgrade -> rebirth -> buy -> rejoin", function()
			local world = World.new({ isStudio = true })
			world:StartServer()
			local Config = world:Require("ReplicatedStorage/Shared/Config")
			local Formulas = world:Require("ReplicatedStorage/Shared/Formulas")
			local PlayerService = world:Require("ServerScriptService/Server/Services/PlayerService")
			local EggService = world:Require("ServerScriptService/Server/Services/EggService")
			local PlotService = world:Require("ServerScriptService/Server/Services/PlotService")
			local Network = world:Require("ServerScriptService/Server/Services/Network")
			local player = world.AddPlayer(77, "Scenario")
			world:Advance(1)
			local session = PlayerService.Get(player)
			local data = session.Data

			-- 1) steal two Meadow eggs and bring them home
			for _ = 1, 2 do
				local nest
				for _, n in EggService.GetNests() do
					if n.Zone == 1 and n.HasEgg then
						nest = n
						break
					end
				end
				player.Character:PivotTo(CFrame.new(nest.Position + Vector3.new(0, 2, 2)))
				expect((EggService.TryTakeNestEgg(player, nest))).toBe(true)
				player.Character:PivotTo(PlotService.SpawnCFrame(PlotService.Get(player)))
				world:Advance(0.3)
			end
			expect(#data.Eggs).toBe(2)

			-- 2) hatch, earn, collect
			world:Advance(Config.Eggs.Meadow.HatchSeconds + 2)
			expect(#data.Slimes).toBe(2)
			player.Character:PivotTo(CFrame.new(0, 3, -300))
			world:Advance(20)
			local plot = PlotService.Get(player)
			local MapLayout = world:Require("ReplicatedStorage/Shared/MapLayout")
			local pad = MapLayout.PlotLocal.CollectPad
			local x, z = MapLayout.PlotToWorld(plot.Layout, pad.X, pad.Z)
			player.Character:PivotTo(CFrame.new(x, 3, z))
			world:Advance(0.5)
			expect(data.Coins).toBeGreaterThan(0)

			-- 3) buy an upgrade, claim free rewards
			data.Coins += 100
			expect(Network.Invoke(player, "BuyUpgrade", "Training").ok).toBe(true)
			expect(Network.Invoke(player, "ClaimDaily").ok).toBe(true)
			expect(data.TutorialStep).toBe(6) -- tutorial finished

			-- 4) rebirth
			local speedReq, coinReq = Formulas.RebirthRequirement(0)
			data.Speed = speedReq
			data.Coins = coinReq
			expect(Network.Invoke(player, "Rebirth").ok).toBe(true)
			expect(data.Rebirths).toBe(1)

			-- 5) buy gems and a Royal Egg (Studio simulation path goes through ProcessReceipt logic)
			world:Advance(2) -- policy lookup
			expect(Network.Invoke(player, "BuyProduct", "Gems350").ok).toBe(true)
			local gems = data.Gems
			expect(Network.Invoke(player, "BuyWithGems", "RoyalEgg").ok).toBe(true)
			expect(data.Gems).toBeLessThan(gems)
			local slimeCount = #data.Slimes
			expect(slimeCount).toBe(3)

			-- 6) leave and rejoin on another server: everything is still there
			world.RemovePlayer(player)
			world:Advance(2)
			local world2 = World.new({ dataBackend = world.dataBackend, jobId = "job-2" })
			world2:StartServer()
			local PlayerService2 = world2:Require("ServerScriptService/Server/Services/PlayerService")
			local player2 = world2.AddPlayer(77, "Scenario")
			world2:Advance(1)
			local data2 = PlayerService2.Get(player2).Data
			expect(data2.Rebirths).toBe(1)
			expect(#data2.Slimes).toBe(slimeCount)
			expect(data2.Daily.Streak).toBe(1)
			expect(data2.TrainingLevel).toBe(0) -- reset by rebirth
		end)
	end)

	describe("Studio SelfTest", function()
		it("passes every check on a fresh server", function()
			local world = World.new({ isStudio = true })
			world:StartServer()
			local SelfTest = world:Require("ServerScriptService/Server/Services/SelfTest")
			for _, result in SelfTest.Run() do
				expect(result.Ok).toBe(true)
			end
			world:Advance(0.5)
			local allPass = false
			for _, line in world.logs do
				if line:find("ALL PASS") then
					allPass = true
				end
			end
			expect(allPass).toBe(true)
		end)
	end)
end
