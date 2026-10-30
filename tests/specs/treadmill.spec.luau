-- Treadmills: standing on an owned treadmill multiplies Speed gain; buying, VIP gate, rules.

local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local World = t.World

	local function setup()
		local world = World.new()
		world:StartServer()
		local s = {
			world = world,
			Config = world:Require("ReplicatedStorage/Shared/Config"),
			MapLayout = world:Require("ReplicatedStorage/Shared/MapLayout"),
			PlayerService = world:Require("ServerScriptService/Server/Services/PlayerService"),
			BoostService = world:Require("ServerScriptService/Server/Services/BoostService"),
			Treadmills = world:Require("ServerScriptService/Server/Services/TreadmillService"),
			EggService = world:Require("ServerScriptService/Server/Services/EggService"),
			Network = world:Require("ServerScriptService/Server/Services/Network"),
		}
		function s.join(userId)
			local player = world.AddPlayer(userId, "P" .. userId)
			world:Advance(0.5)
			return player, s.PlayerService.Get(player)
		end
		function s.standOn(player, id)
			for _, info in s.MapLayout.Treadmills do
				if info.Id == id then
					player.Character:PivotTo(CFrame.new(info.X, 3, info.Z))
				end
			end
			world:Advance(0.3)
		end
		return s
	end

	describe("Treadmills", function()
		it("lays out gym treadmills behind the spawn and zone ones just past each gate", function()
			local s = setup()
			expect(#s.MapLayout.Treadmills).toBe(#s.Config.TreadmillOrder)
			local layout = s.Config.TreadmillLayout
			for _, info in s.MapLayout.Treadmills do
				expect(math.abs(info.X) + layout.Width / 2).toBeLessThan(s.Config.Map.RoadWidth / 2)
				expect(s.MapLayout.TreadmillAt(info.X, 3, info.Z)).toBe(info.Id)
				if info.Zone == 0 then
					expect(info.Z).toBeLessThan(s.Config.Map.SpawnZ - 40)
					expect(info.Z - layout.Length / 2).toBeGreaterThan(s.MapLayout.RoadStartZ)
				else
					local zone = s.MapLayout.Zones[info.Zone]
					-- inside the zone (past its gate), before its first guard
					expect(s.MapLayout.ZoneAtZ(info.Z - layout.Length / 2)).toBe(info.Zone)
					expect(info.Z - layout.Length / 2).toBeGreaterThan(zone.GateZ + 1)
					for _, guard in zone.Guards do
						expect(guard.Z - guard.Radius - guard.Amplitude).toBeGreaterThan(info.Z + layout.Length / 2)
					end
				end
			end
			expect(s.MapLayout.TreadmillAt(0, 3, s.Config.Map.SpawnZ)).toBeNil()
			expect(s.MapLayout.TreadmillAt(s.MapLayout.Treadmills[1].X, 30, s.MapLayout.Treadmills[1].Z)).toBeNil()
		end)

		it("doubles speed gain on the free Basic treadmill", function()
			local s = setup()
			local player, session = s.join(1)
			local normal = s.BoostService.GetSpeedGain(player)
			s.standOn(player, "Basic")
			expect(s.BoostService.GetSpeedGain(player)).toBe(normal * 2)
			local before = session.Data.Speed
			s.world:Advance(10)
			expect(session.Data.Speed - before).toBeGreaterThanOrEqual(18)
			-- stepping off removes the bonus
			player.Character:PivotTo(CFrame.new(0, 3, -130))
			s.world:Advance(0.3)
			expect(s.BoostService.GetSpeedGain(player)).toBe(normal)
		end)

		it("gives nothing on a locked treadmill until it is bought", function()
			local s = setup()
			local player, session = s.join(1)
			local normal = s.BoostService.GetSpeedGain(player)
			s.standOn(player, "Bronze")
			expect(s.BoostService.GetSpeedGain(player)).toBe(normal)
			expect(s.Network.Invoke(player, "BuyTreadmill", "Bronze").ok).toBe(false) -- no coins
			session.Data.Coins = s.Config.Treadmills.Bronze.Cost + 10
			local r = s.Network.Invoke(player, "BuyTreadmill", "Bronze")
			expect(r.ok).toBe(true)
			expect(session.Data.Coins).toBe(10)
			s.world:Advance(0.3)
			expect(s.BoostService.GetSpeedGain(player)).toBe(normal * 3)
			-- cannot buy twice, bad input refused
			expect(s.Network.Invoke(player, "BuyTreadmill", "Bronze").ok).toBe(false)
			expect(s.Network.Invoke(player, "BuyTreadmill", "Mega").ok).toBe(false)
			expect(s.Network.Invoke(player, "BuyTreadmill", "Basic").ok).toBe(false)
		end)

		it("VIP treadmill (x20) needs its own pass and cannot be bought with coins", function()
			local s = setup()
			local player, session = s.join(1)
			session.Data.Coins = 1e15
			expect(s.Network.Invoke(player, "BuyTreadmill", "VIP").ok).toBe(false)
			local normal = s.BoostService.GetSpeedGain(player)
			s.standOn(player, "VIP")
			expect(s.BoostService.GetSpeedGain(player)).toBe(normal)
			-- the plain VIP pass is not enough
			s.BoostService.SetPass(player, "VIP", true)
			s.world:Advance(0.3)
			expect(s.BoostService.GetSpeedGain(player)).toBe(normal)
			s.BoostService.SetPass(player, "VIPTreadmill", true)
			s.world:Advance(0.3)
			expect(s.Config.Treadmills.VIP.Multiplier).toBe(20)
			expect(s.BoostService.GetSpeedGain(player)).toBe(normal * 20)
		end)

		it("zone treadmills need the zone (and rebirths) before they can be bought", function()
			local s = setup()
			local player, session = s.join(1)
			session.Data.Coins = 1e18
			-- Forest needs Forest unlocked
			session.Data.Speed = 0
			local r = s.Network.Invoke(player, "BuyTreadmill", "Forest")
			expect(r.ok).toBe(false)
			session.Data.Speed = s.Config.Zones[2].GateSpeed
			expect(s.Network.Invoke(player, "BuyTreadmill", "Forest").ok).toBe(true)
			expect(session.Data.Coins).toBe(1e18 - s.Config.Treadmills.Forest.Cost)
			-- Volcano Mill also needs a rebirth
			session.Data.Speed = s.Config.Zones[5].GateSpeed
			expect(s.Network.Invoke(player, "BuyTreadmill", "Volcano").ok).toBe(false)
			session.Data.Rebirths = 1
			expect(s.Network.Invoke(player, "BuyTreadmill", "Volcano").ok).toBe(true)
			-- standing on it multiplies speed gain
			local normal = s.BoostService.GetSpeedGain(player)
			s.standOn(player, "Volcano")
			expect(s.BoostService.GetSpeedGain(player)).toBe(normal * s.Config.Treadmills.Volcano.Multiplier)
		end)

		it("gives no bonus while carrying an egg", function()
			local s = setup()
			local player = s.join(1)
			s.EggService.StartCarry(player, "Meadow", { Kind = "Nest" })
			local normal = s.BoostService.GetSpeedGain(player)
			s.standOn(player, "Basic")
			expect(s.BoostService.GetSpeedGain(player)).toBe(normal)
		end)

		it("keeps bought treadmills after rebirth and after rejoining", function()
			local s = setup()
			local player, session = s.join(1)
			session.Data.Coins = s.Config.Treadmills.Silver.Cost
			expect(s.Network.Invoke(player, "BuyTreadmill", "Silver").ok).toBe(true)
			local Formulas = s.world:Require("ReplicatedStorage/Shared/Formulas")
			local speedReq, coinReq = Formulas.RebirthRequirement(0)
			session.Data.Speed, session.Data.Coins = speedReq, coinReq
			expect(s.Network.Invoke(player, "Rebirth").ok).toBe(true)
			expect(session.Data.Treadmills.Silver).toBe(true)
			s.world.RemovePlayer(player)
			s.world:Advance(1)
			local stored = s.world.dataBackend.stores[s.Config.Data.StoreName .. "/global"].Player_1
			expect(stored.Data.Treadmills.Silver).toBe(true)
		end)

		it("client shows locks and hides the buy prompt once owned", function()
			local s = setup()
			local player, session = s.join(1)
			s.world:StartClient(player)
			s.world:Advance(1)
			local folder = s.world.workspace.Map.Home.Treadmills
			local bronze = folder.Treadmill_Bronze
			expect(bronze.Console.BuyPrompt.Enabled).toBe(true)
			expect(bronze.Console.TreadmillLabel.Label.Text:find("🔒") ~= nil).toBe(true)
			session.Data.Coins = 1e6
			s.Network.Invoke(player, "BuyTreadmill", "Bronze")
			s.world:Advance(1)
			expect(bronze.Console.BuyPrompt.Enabled).toBe(false)
			expect(bronze.Console.TreadmillLabel.Label.Text:find("🔒")).toBeNil()
			-- belt stripes animate
			expect(#bronze.Belt:GetChildren()).toBeGreaterThan(0) -- texture blobs
		end)
	end)
end
