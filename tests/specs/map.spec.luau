-- Map layout, guard motion and plot assignment.

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local World = t.World

	describe("MapLayout", function()
		local world = World.new()
		local Config = world:Require("ReplicatedStorage/Shared/Config")
		local MapLayout = world:Require("ReplicatedStorage/Shared/MapLayout")

		it("lays zones end to end with gates between them", function()
			for index, zone in MapLayout.Zones do
				expect(zone.EndZ - zone.StartZ).toBe(Config.Zones[index].Length)
				if index > 1 then
					local prev = MapLayout.Zones[index - 1]
					expect(zone.StartZ - prev.EndZ).toBe(Config.Map.GateGap)
					expect(zone.GateZ).toBe(zone.StartZ - Config.Map.GateGap / 2)
				end
			end
			expect(MapLayout.RoadEndZ).toBeGreaterThan(MapLayout.Zones[#MapLayout.Zones].EndZ)
		end)

		it("puts nests and guards inside their zone and on the road", function()
			for index, zone in MapLayout.Zones do
				expect(#zone.Nests).toBe(Config.Zones[index].Nests)
				for _, nest in zone.Nests do
					expect(nest.Z > zone.StartZ and nest.Z < zone.EndZ).toBe(true)
					expect(math.abs(nest.X) < MapLayout.HalfRoad - 3).toBe(true)
				end
				local patrol, sweeper = 0, 0
				for _, guard in zone.Guards do
					expect(guard.Z >= zone.StartZ and guard.Z <= zone.EndZ).toBe(true)
					if guard.Kind == "Patrol" then
						patrol += 1
						expect(guard.Amplitude + guard.Radius <= MapLayout.HalfRoad).toBe(true)
					else
						sweeper += 1
					end
				end
				expect(patrol).toBe(Config.Zones[index].PatrolGuards)
				expect(sweeper).toBe(Config.Zones[index].SweeperGuards)
			end
		end)

		it("sweepers never sweep over a nest", function()
			for _, zone in MapLayout.Zones do
				for _, guard in zone.Guards do
					if guard.Kind == "Sweeper" then
						for _, nest in zone.Nests do
							local dist = math.sqrt((nest.X - guard.X) ^ 2 + (nest.Z - guard.Z) ^ 2)
							expect(dist).toBeGreaterThan(guard.Amplitude + 1)
						end
					end
				end
			end
		end)

		it("converts plot coordinates both ways and faces the road", function()
			for _, plot in MapLayout.Plots do
				local x, z = MapLayout.PlotToWorld(plot, 5, -12)
				local lx, lz = MapLayout.WorldToPlot(plot, x, z)
				expect(lx).toBeCloseTo(5)
				expect(lz).toBeCloseTo(-12)
				-- the entrance (local -Z) is closer to the road than the back
				local ex = MapLayout.PlotToWorld(plot, 0, -20)
				local bx = MapLayout.PlotToWorld(plot, 0, 20)
				expect(math.abs(ex) < math.abs(bx)).toBe(true)
				expect(MapLayout.IsInPlot(plot, plot.X, plot.Z)).toBe(true)
			end
			expect(#MapLayout.Plots).toBe(Config.MaxPlayers)
		end)

		it("plots do not overlap the road or each other", function()
			for _, plot in MapLayout.Plots do
				expect(math.abs(plot.X) - Config.Map.PlotSize / 2).toBeGreaterThan(MapLayout.HalfRoad)
				for _, other in MapLayout.Plots do
					if other ~= plot and other.Side == plot.Side then
						expect(math.abs(other.Z - plot.Z)).toBeGreaterThanOrEqual(Config.Map.PlotSize)
					end
				end
			end
		end)

		it("finds the zone for a z position", function()
			expect(MapLayout.ZoneAtZ(-100)).toBe(0)
			expect(MapLayout.ZoneAtZ(MapLayout.Zones[1].StartZ + 5)).toBe(1)
			expect(MapLayout.ZoneAtZ(MapLayout.Zones[3].GateZ + 1)).toBe(3)
			expect(MapLayout.ZoneAtZ(MapLayout.Zones[3].GateZ - 1)).toBe(2)
		end)

		it("keeps plot props inside the plot", function()
			local half = MapLayout.PlotLocal.Half
			for _, p in MapLayout.PlotLocal.Pedestals do
				expect(math.abs(p.X) < half - 2 and math.abs(p.Z) < half - 2).toBe(true)
			end
			for _, p in MapLayout.PlotLocal.Incubators do
				expect(math.abs(p.X) < half - 2 and math.abs(p.Z) < half - 2).toBe(true)
			end
			expect(#MapLayout.PlotLocal.Pedestals).toBe(
				Config.Upgrades.Pedestals.Start + Config.Upgrades.Pedestals.MaxLevel
			)
			expect(#MapLayout.PlotLocal.Incubators).toBe(
				Config.Upgrades.Incubators.Start + Config.Upgrades.Incubators.MaxLevel + Config.ExtraIncubatorsFromPass
			)
		end)
	end)

	describe("GuardMotion", function()
		local world = World.new()
		local GuardMotion = world:Require("ReplicatedStorage/Shared/GuardMotion")
		local patrol = {
			Id = "p",
			Kind = "Patrol",
			Zone = 1,
			X = 0,
			Z = 100,
			Amplitude = 20,
			Period = 4,
			Phase = 0,
			Radius = 4,
			Direction = 1,
		}
		local sweeper = {
			Id = "s",
			Kind = "Sweeper",
			Zone = 1,
			X = 0,
			Z = 200,
			Amplitude = 28,
			Period = 8,
			Phase = 0,
			Radius = 1.6,
			Direction = 1,
		}
		it("patrols left and right within its amplitude", function()
			local x0 = GuardMotion.PatrolPosition(patrol, 0)
			local x1 = GuardMotion.PatrolPosition(patrol, 1)
			local x3 = GuardMotion.PatrolPosition(patrol, 3)
			expect(x0).toBeCloseTo(0)
			expect(x1).toBeCloseTo(20)
			expect(x3).toBeCloseTo(-20)
		end)
		it("hits players touching the ball only", function()
			expect(GuardMotion.Hits(patrol, 1, 20, 100)).toBe(true)
			expect(GuardMotion.Hits(patrol, 1, 15, 100)).toBe(true)
			expect(GuardMotion.Hits(patrol, 1, 14, 100)).toBe(false)
			expect(GuardMotion.Hits(patrol, 1, 0, 100)).toBe(false)
			expect(GuardMotion.Hits(patrol, 1, 20, 110)).toBe(false)
		end)
		it("sweeper arm hits along its length", function()
			-- angle 0 at t=0: arm along X axis
			expect(GuardMotion.Hits(sweeper, 0, 25, 200)).toBe(true)
			expect(GuardMotion.Hits(sweeper, 0, -10, 200.5)).toBe(true)
			expect(GuardMotion.Hits(sweeper, 0, 0, 210)).toBe(false)
			-- a quarter turn later the arm points along Z
			expect(GuardMotion.Hits(sweeper, 2, 0, 210)).toBe(true)
		end)
	end)

	describe("World build and plots", function()
		it("builds the map and assigns each player a plot", function()
			local world = World.new()
			world:StartServer()
			local PlotService = world:Require("ServerScriptService/Server/Services/PlotService")
			local MapService = world:Require("ServerScriptService/Server/Services/MapService")
			local Config = world:Require("ReplicatedStorage/Shared/Config")
			expect(world.workspace:FindFirstChild("Map") ~= nil).toBe(true)
			expect(#MapService.Gates).toBe(#Config.Zones - 1)
			local nestCount = 0
			for _, zone in Config.Zones do
				nestCount += zone.Nests
			end
			expect(#MapService.Nests).toBe(nestCount)

			local a = world.AddPlayer(1, "A")
			local b = world.AddPlayer(2, "B")
			world:Advance(0.5)
			local plotA = PlotService.Get(a)
			local plotB = PlotService.Get(b)
			expect(plotA ~= nil and plotB ~= nil).toBe(true)
			expect(plotA.Index ~= plotB.Index).toBe(true)
			expect(plotA.Model:GetAttribute("OwnerUserId")).toBe(1)
			expect(plotA.SignLabel.Text).toBe("A's Base")
			-- spawned inside own plot
			local root = a.Character:FindFirstChild("HumanoidRootPart")
			expect(PlotService.Contains(plotA, root.Position)).toBe(true)
			-- default slots unlocked
			expect(plotA.Incubators[2].Part:GetAttribute("Unlocked")).toBe(true)
			expect(plotA.Incubators[3].Part:GetAttribute("Unlocked")).toBe(false)
			expect(plotA.Pedestals[6].Part:GetAttribute("Unlocked")).toBe(true)
			expect(plotA.Pedestals[7].Part:GetAttribute("Unlocked")).toBe(false)

			world.RemovePlayer(a)
			world:Advance(0.5)
			expect(plotA.Owner).toBeNil()
			expect(plotA.Model:GetAttribute("OwnerUserId")).toBe(0)
			local c = world.AddPlayer(3, "C")
			world:Advance(0.5)
			expect(PlotService.Get(c).Index).toBe(plotA.Index)
		end)

		it("kicks the 9th player when every plot is taken", function()
			local world = World.new()
			world:StartServer()
			local players = {}
			for i = 1, 9 do
				players[i] = world.AddPlayer(100 + i, "P" .. i)
			end
			world:Advance(0.5)
			expect(players[8]:GetAttribute("__Kicked")).toBeNil()
			expect(players[9]:GetAttribute("__Kicked") ~= nil).toBe(true)
		end)
	end)
end
