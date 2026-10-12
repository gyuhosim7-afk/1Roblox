-- Data safety tests: schema repair, purchase id trimming, session locking, failures, shutdown.

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local World = t.World

	local function storeOf(world)
		local Config = world:Require("ReplicatedStorage/Shared/Config")
		return world.dataBackend.stores[Config.Data.StoreName .. "/global"]
	end

	local function keyOf(world, userId)
		local Config = world:Require("ReplicatedStorage/Shared/Config")
		return Config.Data.KeyPrefix .. userId
	end

	describe("ProfileSchema", function()
		local world = World.new()
		local Schema = world:Require("ServerScriptService/Server/Logic/ProfileSchema")
		local Config = world:Require("ReplicatedStorage/Shared/Config")

		it("creates defaults from nothing", function()
			local data = Schema.Reconcile(nil, 100, Config.Slimes, Config.Eggs)
			expect(data.Coins).toBe(0)
			expect(data.BestZone).toBe(1)
			expect(#data.Slimes).toBe(0)
			expect(data.CreatedAt).toBe(100)
		end)

		it("repairs broken values and drops unknown entries", function()
			local raw = {
				Coins = 0 / 0,
				Gems = -5,
				Speed = "fast",
				TrainingLevel = 2.7,
				Potions = "bad",
				Stats = { Playtime = 50 },
				Slimes = {
					{ Id = "S1", Kind = "BlueSlime", Mutation = "Gold" },
					{ Id = "S1", Kind = "GreenSlime" }, -- duplicate id
					{ Id = "S9", Kind = "DeletedSlime" }, -- no longer exists
					{ Id = "S5", Kind = "PinkSlime", Locked = true },
					"garbage",
				},
				Eggs = {
					{ Slot = 1, Egg = "Meadow", HatchAt = 10 },
					{ Slot = 1, Egg = "Forest", HatchAt = 10 }, -- duplicate slot
					{ Slot = 2, Egg = "Nope", HatchAt = 10 },
				},
				NextSlimeId = 2,
			}
			local data = Schema.Reconcile(raw, 100, Config.Slimes, Config.Eggs)
			expect(data.Coins).toBe(0)
			expect(data.Gems).toBe(0)
			expect(data.Speed).toBe(0)
			expect(data.TrainingLevel).toBe(2)
			expect(data.Potions.Luck).toBe(0)
			expect(data.Stats.Playtime).toBe(50)
			expect(data.Stats.Joins).toBe(0)
			expect(#data.Slimes).toBe(2)
			expect(data.Slimes[1].Mutation).toBe("Gold")
			expect(data.Slimes[2].Locked).toBe(true)
			expect(data.NextSlimeId).toBe(6) -- never reuse an id
			expect(#data.Eggs).toBe(1)
		end)

		it("generates unique slime ids", function()
			local data = Schema.Default(0)
			expect(Schema.NextSlimeId(data)).toBe("S1")
			expect(Schema.NextSlimeId(data)).toBe("S2")
		end)

		it("keeps only the newest purchase ids", function()
			local data = Schema.Default(0)
			for i = 1, 5 do
				Schema.RecordPurchase(data, "p" .. i, i, 3)
			end
			expect(data.Purchases.p1).toBeNil()
			expect(data.Purchases.p2).toBeNil()
			expect(data.Purchases.p5).toBe(5)
			expect(#data.PurchaseOrder).toBe(3)
			Schema.RecordPurchase(data, "p5", 99, 3)
			expect(data.Purchases.p5).toBe(5)
		end)
	end)

	describe("RateLimiter", function()
		local world = World.new()
		local RateLimiter = world:Require("ServerScriptService/Server/Logic/RateLimiter")
		it("allows bursts then refills", function()
			local limiter = RateLimiter.new(3, 1)
			expect(limiter:Allow("a", 0)).toBe(true)
			expect(limiter:Allow("a", 0)).toBe(true)
			expect(limiter:Allow("a", 0)).toBe(true)
			expect(limiter:Allow("a", 0)).toBe(false)
			expect(limiter:Allow("a", 1)).toBe(true)
			expect(limiter:Allow("b", 1)).toBe(true)
		end)
	end)

	describe("DataService", function()
		it("saves on leave and restores on rejoin in another server", function()
			local backend = nil
			local worldA = World.new()
			backend = worldA.dataBackend
			worldA:StartServer()
			local DataService = worldA:Require("ServerScriptService/Server/Services/DataService")
			local player = worldA.AddPlayer(101, "Alice")
			worldA:Advance(0.5)
			local profile = DataService.Get(player)
			expect(profile ~= nil).toBe(true)
			profile.Data.Coins = 1234
			worldA.RemovePlayer(player)
			worldA:Advance(1)
			local stored = storeOf(worldA)[keyOf(worldA, 101)]
			expect(stored.Data.Coins).toBe(1234)
			expect(stored.Session).toBeNil()

			local worldB = World.new({ dataBackend = backend, jobId = "job-B" })
			worldB:StartServer()
			local DataServiceB = worldB:Require("ServerScriptService/Server/Services/DataService")
			local playerB = worldB.AddPlayer(101, "Alice")
			worldB:Advance(0.5)
			expect(DataServiceB.Get(playerB).Data.Coins).toBe(1234)
		end)

		it("waits for another server's lock, then takes over; the old server stops saving", function()
			local worldA = World.new({ jobId = "job-A" })
			worldA:StartServer()
			local DataServiceA = worldA:Require("ServerScriptService/Server/Services/DataService")
			local playerA = worldA.AddPlayer(202, "Bob")
			worldA:Advance(0.5)
			DataServiceA.Get(playerA).Data.Coins = 50
			expect(DataServiceA.SaveAsync(playerA)).toBe(true)

			local worldB = World.new({ dataBackend = worldA.dataBackend, jobId = "job-B" })
			worldB:StartServer()
			local DataServiceB = worldB:Require("ServerScriptService/Server/Services/DataService")
			local playerB = worldB.AddPlayer(202, "Bob")
			worldB:Advance(5)
			expect(DataServiceB.Get(playerB)).toBeNil() -- still waiting on lock
			worldB:Advance(40)
			local profileB = DataServiceB.Get(playerB)
			expect(profileB ~= nil).toBe(true)
			expect(profileB.Data.Coins).toBe(50)

			-- Server A tries to save stale data: must refuse and kick.
			DataServiceA.Get(playerA).Data.Coins = 999999
			local okA = worldA:Run(function()
				return DataServiceA.SaveAsync(playerA)
			end)
			expect(okA).toBe(false)
			expect(playerA:GetAttribute("__Kicked") ~= nil).toBe(true)
			local stored = storeOf(worldA)[keyOf(worldA, 202)]
			expect(stored.Data.Coins).toBe(50)
			expect(stored.Session.JobId).toBe("job-B")
		end)

		it("kicks instead of loading blank data when the DataStore is down (live server)", function()
			local world = World.new()
			world.dataBackend.stores["StealASlime_PlayerData_v1/global"] = {
				Player_303 = { Data = { Coins = 777 } },
			}
			world.dataBackend.failAll = true
			world:StartServer()
			local DataService = world:Require("ServerScriptService/Server/Services/DataService")
			local player = world.AddPlayer(303, "Cara")
			world:Advance(120)
			expect(DataService.Get(player)).toBeNil()
			expect(player:GetAttribute("__Kicked") ~= nil).toBe(true)
			world.dataBackend.failAll = false
			expect(storeOf(world).Player_303.Data.Coins).toBe(777)
		end)

		it("uses temporary unsaved data in Studio when the DataStore is unavailable", function()
			local world = World.new({ isStudio = true })
			world.dataBackend.failAll = true
			world:StartServer()
			local DataService = world:Require("ServerScriptService/Server/Services/DataService")
			local player = world.AddPlayer(404, "Dev")
			world:Advance(120)
			local profile = DataService.Get(player)
			expect(profile ~= nil).toBe(true)
			expect(profile.NoSave).toBe(true)
		end)

		it("retries failed saves with backoff", function()
			local world = World.new()
			world:StartServer()
			local DataService = world:Require("ServerScriptService/Server/Services/DataService")
			local player = world.AddPlayer(505, "Dan")
			world:Advance(0.5)
			DataService.Get(player).Data.Gems = 42
			world.dataBackend.failNext = 3
			local ok = world:Run(function()
				return DataService.SaveAsync(player)
			end)
			expect(ok).toBe(true)
			expect(storeOf(world).Player_505.Data.Gems).toBe(42)
		end)

		it("autosaves periodically", function()
			local world = World.new()
			world:StartServer()
			local DataService = world:Require("ServerScriptService/Server/Services/DataService")
			local player = world.AddPlayer(606, "Eve")
			world:Advance(0.5)
			DataService.Get(player).Data.Coins = 314
			world:Advance(65)
			expect(storeOf(world).Player_606.Data.Coins).toBe(314)
			expect(storeOf(world).Player_606.Session.JobId).toBe("job-test")
		end)

		it("saves everyone and releases locks on shutdown", function()
			local world = World.new()
			world:StartServer()
			local DataService = world:Require("ServerScriptService/Server/Services/DataService")
			local p1 = world.AddPlayer(701, "F")
			local p2 = world.AddPlayer(702, "G")
			world:Advance(0.5)
			DataService.Get(p1).Data.Coins = 1
			DataService.Get(p2).Data.Coins = 2
			world:Close()
			expect(storeOf(world).Player_701.Data.Coins).toBe(1)
			expect(storeOf(world).Player_702.Data.Coins).toBe(2)
			expect(storeOf(world).Player_701.Session).toBeNil()
		end)

		it("keeps retrying a failed leave-save until it succeeds", function()
			local world = World.new()
			world:StartServer()
			local DataService = world:Require("ServerScriptService/Server/Services/DataService")
			local player = world.AddPlayer(808, "H")
			world:Advance(0.5)
			DataService.Get(player).Data.Coins = 88
			world.dataBackend.failNext = 8 -- more than one retry round
			world.RemovePlayer(player)
			world:Advance(200)
			expect(storeOf(world).Player_808.Data.Coins).toBe(88)
			expect(storeOf(world).Player_808.Session).toBeNil()
		end)

		it("serializes concurrent saves so the latest data wins", function()
			local world = World.new()
			world:StartServer()
			local DataService = world:Require("ServerScriptService/Server/Services/DataService")
			local player = world.AddPlayer(909, "I")
			world:Advance(0.5)
			local profile = DataService.Get(player)
			profile.Data.Coins = 1
			world.dataBackend.failNext = 1 -- first save needs a retry (yields)
			local results = {}
			world.task.spawn(function()
				results[1] = DataService.SaveAsync(player)
			end)
			profile.Data.Coins = 2
			world.task.spawn(function()
				results[2] = DataService.SaveAsync(player)
			end)
			world:Advance(10)
			expect(results[1]).toBe(true)
			expect(results[2]).toBe(true)
			expect(storeOf(world).Player_909.Data.Coins).toBe(2)
		end)
	end)
end
