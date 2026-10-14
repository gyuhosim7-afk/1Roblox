-- Guards, upgrades, rebirth, stealing from other bases, base lock and bonk.

local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

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
			GuardMotion = world:Require("ReplicatedStorage/Shared/GuardMotion"),
			Formulas = world:Require("ReplicatedStorage/Shared/Formulas"),
			PlayerService = world:Require("ServerScriptService/Server/Services/PlayerService"),
			PlotService = world:Require("ServerScriptService/Server/Services/PlotService"),
			EggService = world:Require("ServerScriptService/Server/Services/EggService"),
			HatchService = world:Require("ServerScriptService/Server/Services/HatchService"),
			StealService = world:Require("ServerScriptService/Server/Services/StealService"),
			Network = world:Require("ServerScriptService/Server/Services/Network"),
		}
		function s.join(userId)
			local player = world.AddPlayer(userId, "P" .. userId)
			world:Advance(0.3)
			local session = s.PlayerService.Get(player)
			-- not a brand-new player (skip new player protection unless a test wants it)
			session.Data.Stats.Joins = 5
			return player, session
		end
		function s.moveTo(player, position)
			player.Character:PivotTo(CFrame.new(position))
		end
		function s.walkTo(player, target)
			local session = s.PlayerService.Get(player)
			local carry = s.EggService.CarryOf(player)
			local mult = if carry then s.Config.Eggs[carry.EggId].CarryMultiplier else 1
			local speed = s.Formulas.WalkSpeed(session.Data.Speed, mult)
			local start = player.Character:FindFirstChild("HumanoidRootPart").Position
			local delta = target - start
			local steps = math.max(1, math.ceil(delta.Magnitude / (speed * 0.1)))
			for i = 1, steps do
				player.Character:PivotTo(CFrame.new(start + delta * (i / steps)))
				world:Advance(0.1)
			end
		end
		function s.root(player)
			return player.Character:FindFirstChild("HumanoidRootPart")
		end
		function s.slotPosition(plot, slot)
			return plot.Incubators[slot].Part.Position
		end
		function s.effects(player, name)
			local remote = world.game.ReplicatedStorage.Remotes.Effect
			local list = {}
			for _, call in world.InstanceLib.calls(remote, "FireClient") do
				if call[1] == player and call[2] == name then
					table.insert(list, call[3])
				end
			end
			return list
		end
		return s
	end

	describe("Guards", function()
		it("knock the egg out of a carrier's hands", function()
			local s = setup()
			local player = s.join(1)
			local zone = s.MapLayout.Zones[1]
			local guard = zone.Guards[1]
			local nest = nil
			for _, n in s.EggService.GetNests() do
				if n.Zone == 1 then
					nest = n
					break
				end
			end
			s.moveTo(player, nest.Position)
			s.EggService.TryTakeNestEgg(player, nest)
			s.world:Advance(1) -- past the grace period
			expect(s.EggService.CarryOf(player) ~= nil).toBe(true)
			-- stand exactly where the guard will be
			local now = s.world.workspace:GetServerTimeNow()
			local gx, gz = s.GuardMotion.PatrolPosition(guard, now + 0.2)
			s.moveTo(player, Vector3.new(gx, 3, gz))
			s.world:Advance(0.5)
			expect(s.EggService.CarryOf(player)).toBeNil()
			expect(nest.HasEgg).toBe(true)
			expect(#s.effects(player, "Knockback")).toBeGreaterThan(0)
		end)

		it("ignore players who are not carrying", function()
			local s = setup()
			local player = s.join(1)
			local guard = s.MapLayout.Zones[1].Guards[1]
			local now = s.world.workspace:GetServerTimeNow()
			local gx, gz = s.GuardMotion.PatrolPosition(guard, now + 0.2)
			s.moveTo(player, Vector3.new(gx, 3, gz))
			s.world:Advance(0.5)
			expect(#s.effects(player, "Knockback")).toBe(0)
		end)
	end)

	describe("Upgrades and rebirth", function()
		it("buys upgrades with coins and validates input", function()
			local s = setup()
			local player, session = s.join(1)
			expect(s.Network.Invoke(player, "BuyUpgrade", "Training").ok).toBe(false)
			session.Data.Coins = 1e6
			local r = s.Network.Invoke(player, "BuyUpgrade", "Training")
			expect(r.ok).toBe(true)
			expect(session.Data.TrainingLevel).toBe(1)
			expect(session.Data.Coins).toBe(1e6 - s.Formulas.UpgradeCost("Training", 0))
			expect(s.Network.Invoke(player, "BuyUpgrade", "Hacks").ok).toBe(false)
			expect(s.Network.Invoke(player, "BuyUpgrade", { "Training" }).ok).toBe(false)
			s.Network.Invoke(player, "BuyUpgrade", "Incubators")
			expect(session.Data.IncubatorLevel).toBe(1)
			local plot = s.PlotService.Get(player)
			expect(plot.Incubators[3].Part:GetAttribute("Unlocked")).toBe(true)
			s.Network.Invoke(player, "BuyUpgrade", "Pedestals")
			expect(plot.Pedestals[7].Part:GetAttribute("Unlocked")).toBe(true)
			-- max level
			session.Data.Coins = 1e15
			for _ = 1, 10 do
				s.Network.Invoke(player, "BuyUpgrade", "Incubators")
			end
			expect(session.Data.IncubatorLevel).toBe(s.Config.Upgrades.Incubators.MaxLevel)
		end)

		it("rebirths only when requirements are met and resets the right things", function()
			local s = setup()
			local player, session = s.join(1)
			table.insert(session.Data.Slimes, { Id = "S1", Kind = "SunnySlime", Mutation = "None", Locked = false })
			session.Data.PedestalLevel = 3
			expect(s.Network.Invoke(player, "Rebirth").ok).toBe(false)
			local speedReq, coinReq = s.Formulas.RebirthRequirement(0)
			session.Data.Speed = speedReq
			session.Data.Coins = coinReq + 5
			session.Data.TrainingLevel = 10
			local gems = session.Data.Gems
			local r = s.Network.Invoke(player, "Rebirth")
			expect(r.ok).toBe(true)
			expect(session.Data.Rebirths).toBe(1)
			expect(session.Data.Speed).toBe(0)
			expect(session.Data.Coins).toBe(0)
			expect(session.Data.TrainingLevel).toBe(0)
			expect(session.Data.PedestalLevel).toBe(3)
			expect(#session.Data.Slimes).toBe(1)
			expect(session.Data.Gems).toBe(gems + s.Config.Rebirth.GemReward)
			-- second rebirth costs more
			local speed2 = s.Formulas.RebirthRequirement(1)
			expect(speed2).toBeGreaterThan(speedReq)
		end)
	end)

	describe("Stealing from bases", function()
		it("steals an incubating egg and delivers it home", function()
			local s = setup()
			local victim, vSession = s.join(1)
			local thief, tSession = s.join(2)
			s.HatchService.AddEgg(victim, "Forest")
			local vPlot = s.PlotService.Get(victim)
			s.moveTo(thief, s.slotPosition(vPlot, 1) + Vector3.new(2, 2, 0))
			local ok, msg = s.StealService.TrySteal(thief, vPlot, 1)
			expect(ok).toBe(true)
			expect(msg).toBeNil()
			expect(s.HatchService.IsReserved(victim, 1)).toBe(true)
			expect(#s.effects(victim, "Alarm")).toBe(1)
			-- the victim's egg does not hatch while being carried away
			vSession.Data.Eggs[1].HatchAt = 0
			s.world:Advance(1)
			expect(#vSession.Data.Slimes).toBe(0)
			-- thief runs home at a legit speed (teleporting would drop the egg)
			local tPlot = s.PlotService.Get(thief)
			tSession.Data.Speed = 10000
			s.walkTo(thief, s.PlotService.SpawnCFrame(tPlot).Position)
			expect(#vSession.Data.Eggs).toBe(0)
			expect(#tSession.Data.Eggs).toBe(1)
			expect(tSession.Data.Eggs[1].Egg).toBe("Forest")
			expect(tSession.Data.Stats.PlayerSteals).toBe(1)
			expect(vSession.Data.Stats.TimesRobbed).toBe(1)
		end)

		it("returns the egg to the victim when the thief is bonked", function()
			local s = setup()
			local victim, vSession = s.join(1)
			local thief = s.join(2)
			s.HatchService.AddEgg(victim, "Forest")
			local vPlot = s.PlotService.Get(victim)
			local pos = s.slotPosition(vPlot, 1)
			s.moveTo(thief, pos + Vector3.new(2, 2, 0))
			s.StealService.TrySteal(thief, vPlot, 1)
			s.moveTo(victim, pos + Vector3.new(-3, 2, 0))
			local r = s.Network.Invoke(victim, "Bonk")
			expect(r.ok).toBe(true)
			expect(s.EggService.CarryOf(thief)).toBeNil()
			expect(s.HatchService.IsReserved(victim, 1)).toBe(false)
			expect(#vSession.Data.Eggs).toBe(1)
			expect(#s.effects(thief, "Knockback")).toBe(1)
			-- cooldown
			expect(s.Network.Invoke(victim, "Bonk").ok).toBe(false)
		end)

		it("cannot bonk innocent players outside your base", function()
			local s = setup()
			local a = s.join(1)
			local b = s.join(2)
			s.moveTo(a, Vector3.new(0, 3, 100))
			s.moveTo(b, Vector3.new(2, 3, 100))
			s.Network.Invoke(a, "Bonk")
			expect(#s.effects(b, "Knockback")).toBe(0)
		end)

		it("blocks stealing from locked bases and pushes intruders out", function()
			local s = setup()
			local victim = s.join(1)
			local thief = s.join(2)
			s.HatchService.AddEgg(victim, "Void")
			local vPlot = s.PlotService.Get(victim)
			-- lock requires being home
			s.moveTo(victim, Vector3.new(0, 3, 100))
			expect(s.Network.Invoke(victim, "LockBase").ok).toBe(false)
			victim.Character:PivotTo(s.PlotService.SpawnCFrame(vPlot))
			local r = s.Network.Invoke(victim, "LockBase")
			expect(r.ok).toBe(true)
			expect(s.PlotService.IsLocked(vPlot)).toBe(true)
			local pos = s.slotPosition(vPlot, 1)
			s.moveTo(thief, pos + Vector3.new(2, 2, 0))
			local ok, msg = s.StealService.TrySteal(thief, vPlot, 1)
			expect(ok).toBe(false)
			expect(msg).toContain("locked")
			s.world:Advance(0.5)
			expect(s.PlotService.Contains(vPlot, s.root(thief).Position)).toBe(false)
			-- lock expires
			s.world:Advance(s.Formulas.LockSeconds(0) + 1)
			expect(s.PlotService.IsLocked(vPlot)).toBe(false)
			s.moveTo(thief, pos + Vector3.new(2, 2, 0))
			ok, msg = s.StealService.TrySteal(thief, vPlot, 1)
			expect(msg).toBeNil()
			expect(ok).toBe(true)
		end)

		it("locks automatically when the owner steps on the lock pad", function()
			local s = setup()
			local owner = s.join(1)
			local plot = s.PlotService.Get(owner)
			local pad = s.MapLayout.PlotLocal.LockPad
			local x, z = s.MapLayout.PlotToWorld(plot.Layout, pad.X, pad.Z)
			s.moveTo(owner, Vector3.new(x, 3, z))
			s.world:Advance(0.5)
			expect(s.PlotService.IsLocked(plot)).toBe(true)
		end)

		it("protects brand-new players and refuses invalid steals", function()
			local s = setup()
			local victim, vSession = s.join(1)
			local thief = s.join(2)
			vSession.Data.Stats.Joins = 1
			vSession.Data.Stats.Playtime = 10
			s.HatchService.AddEgg(victim, "Meadow")
			local vPlot = s.PlotService.Get(victim)
			s.moveTo(thief, s.slotPosition(vPlot, 1) + Vector3.new(2, 2, 0))
			local ok, msg = s.StealService.TrySteal(thief, vPlot, 1)
			expect(ok).toBe(false)
			expect(msg).toContain("new")
			vSession.Data.Stats.Joins = 3
			-- own egg
			ok = s.StealService.TrySteal(victim, vPlot, 1)
			expect(ok).toBe(false)
			-- empty slot
			ok = s.StealService.TrySteal(thief, vPlot, 2)
			expect(ok).toBe(false)
			-- too far
			s.moveTo(thief, Vector3.new(0, 3, 200))
			ok = s.StealService.TrySteal(thief, vPlot, 1)
			expect(ok).toBe(false)
		end)

		it("keeps the egg with its owner if the owner leaves mid-steal", function()
			local s = setup()
			local victim = s.join(1)
			local thief, tSession = s.join(2)
			s.HatchService.AddEgg(victim, "Desert")
			local vPlot = s.PlotService.Get(victim)
			s.moveTo(thief, s.slotPosition(vPlot, 1) + Vector3.new(2, 2, 0))
			s.StealService.TrySteal(thief, vPlot, 1)
			s.world.RemovePlayer(victim)
			s.world:Advance(1)
			expect(s.EggService.CarryOf(thief)).toBeNil()
			expect(#tSession.Data.Eggs).toBe(0)
			local stored = s.world.dataBackend.stores[s.Config.Data.StoreName .. "/global"]["Player_1"]
			expect(#stored.Data.Eggs).toBe(1)
		end)
	end)
end
