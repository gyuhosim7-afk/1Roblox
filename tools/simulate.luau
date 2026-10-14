-- Progression simulation using the real Config / Formulas / Odds.
-- A simple "typical player" makes trips to the best unlocked zone, hatches eggs, buys upgrades
-- greedily and rebirths as soon as possible. Prints when each milestone is reached.
-- Usage: lune run tools/simulate [hours] [paid]   (paid = 1 → owns 2x Coins + 2x Speed + Extra Incubators)

local process = require("@lune/process")
local World = require("../tests/harness/World")

local HOURS = tonumber(process.args[1]) or 30
local PAID = process.args[2] == "1"
local SEED = tonumber(process.args[3]) or 7

local world = World.new()
local Config = world:Require("ReplicatedStorage/Shared/Config")
local Formulas = world:Require("ReplicatedStorage/Shared/Formulas")
local Odds = world:Require("ReplicatedStorage/Shared/Odds")
local MapLayout = world:Require("ReplicatedStorage/Shared/MapLayout")
local Format = world:Require("ReplicatedStorage/Shared/Format")

local rng = world.Random.new(SEED)
local function roll()
	return rng:NextNumber()
end

local mods = { DoubleCoins = PAID, DoubleSpeed = PAID, ExtraIncubators = PAID }

local p = {
	t = 0,
	speed = 0,
	coins = 0,
	training = 0,
	pedestals = 0,
	incubators = 0,
	lock = 0,
	rebirths = 0,
	slimes = {}, -- { kind, mutation, income }
	eggs = {}, -- { egg, hatchAt }
	bestZone = 1,
}

local HOME_Z = -130
local milestones = {}
local function mark(name)
	if not milestones[name] then
		milestones[name] = p.t
		print(string.format("%8s  %-28s speed %-8s coins %-8s income %-8s/s slimes %d training %d R%d", Format.Duration(p.t), name, Format.Number(p.speed), Format.Number(p.coins), Format.Number(0), #p.slimes, p.training, p.rebirths))
	end
end

local function income()
	table.sort(p.slimes, function(a, b)
		return a.income > b.income
	end)
	local total = 0
	for i = 1, math.min(#p.slimes, Formulas.PedestalCount(p.pedestals)) do
		total += p.slimes[i].income
	end
	return total * Formulas.CoinMultiplier(p.rebirths, mods)
end

local function advance(seconds)
	-- speed, income and hatching over `seconds`
	local step = 1
	local elapsed = 0
	while elapsed < seconds do
		local dt = math.min(step, seconds - elapsed)
		p.speed += Formulas.SpeedGainPerSecond(p.training, p.rebirths, mods) * dt
		p.coins += income() * dt
		p.t += dt
		elapsed += dt
		for i = #p.eggs, 1, -1 do
			if p.eggs[i].hatchAt <= p.t then
				local kind, mutation = Odds.Roll(p.eggs[i].egg, 1, roll)
				table.insert(p.slimes, { kind = kind, mutation = mutation, income = Formulas.SlimeIncome(kind, mutation) })
				table.remove(p.eggs, i)
			end
		end
		local best = Formulas.BestZone(p.speed, p.rebirths)
		if best > p.bestZone then
			p.bestZone = best
		end
		local zoneNow = Formulas.BestZone(p.speed, p.rebirths)
		mark("Zone " .. zoneNow .. " " .. Config.Zones[zoneNow].Name)
	end
end

local function sellSurplus()
	if #p.slimes < Config.Base.MaxSlimes - 5 then
		return
	end
	table.sort(p.slimes, function(a, b)
		return a.income > b.income
	end)
	local keep = Formulas.PedestalCount(p.pedestals) + 5
	while #p.slimes > keep do
		local s = table.remove(p.slimes)
		p.coins += Formulas.SellPrice(s.kind, s.mutation)
	end
end

local function buyUpgrades()
	local bought = true
	while bought do
		bought = false
		local options = {}
		local incCost = Formulas.UpgradeCost("Incubators", p.incubators)
		if incCost then
			table.insert(options, { kind = "Incubators", cost = incCost, weight = 0.6 })
		end
		local pedCost = Formulas.UpgradeCost("Pedestals", p.pedestals)
		if pedCost and #p.slimes >= Formulas.PedestalCount(p.pedestals) then
			table.insert(options, { kind = "Pedestals", cost = pedCost, weight = 0.8 })
		end
		local trainCost = Formulas.UpgradeCost("Training", p.training)
		if trainCost then
			table.insert(options, { kind = "Training", cost = trainCost, weight = 1 })
		end
		table.sort(options, function(a, b)
			return a.cost * a.weight < b.cost * b.weight
		end)
		for _, option in options do
			if p.coins >= option.cost then
				p.coins -= option.cost
				if option.kind == "Incubators" then
					p.incubators += 1
				elseif option.kind == "Pedestals" then
					p.pedestals += 1
				else
					p.training += 1
				end
				bought = true
				break
			end
		end
	end
end

local function tryRebirth()
	local speedReq, coinReq = Formulas.RebirthRequirement(p.rebirths)
	if p.speed >= speedReq and p.coins >= coinReq then
		p.rebirths += 1
		p.speed = 0
		p.coins = 0
		p.training = 0
		mark("Rebirth " .. p.rebirths)
	end
end

local function trip()
	local zoneIndex = Formulas.BestZone(p.speed, p.rebirths)
	local zone = MapLayout.Zones[zoneIndex]
	local def = Config.Zones[zoneIndex]
	local egg = Config.Eggs[def.Egg]
	local nestZ = zone.StartZ + (zone.EndZ - zone.StartZ) * 0.71
	local distance = nestZ - HOME_Z + 50
	local walk = Formulas.WalkSpeed(p.speed)
	local out = distance / walk
	local back = distance / (walk * egg.CarryMultiplier)
	local dropChance = 0.1 + 0.03 * zoneIndex
	local tripTime = out + egg.HoldSeconds + 1.5 + back
	-- expected retries from guard hits (each failed attempt costs about half a trip)
	tripTime += tripTime * 0.5 * dropChance / (1 - dropChance)
	advance(tripTime + 3) -- +3s: collect coins / steer at home
	table.insert(p.eggs, { egg = def.Egg, hatchAt = p.t + egg.HatchSeconds })
end

local capacity = function()
	return Formulas.IncubatorCount(p.incubators, mods.ExtraIncubators)
end

print(string.format("Simulating %d hours (%s)", HOURS, if PAID then "PAID: 2x coins, 2x speed, +2 incubators" else "free player"))
while p.t < HOURS * 3600 do
	if #p.eggs < capacity() then
		trip()
	else
		-- wait for the next hatch
		local nextHatch = math.huge
		for _, e in p.eggs do
			nextHatch = math.min(nextHatch, e.hatchAt)
		end
		advance(math.max(1, math.min(nextHatch - p.t, 60)))
	end
	sellSurplus()
	buyUpgrades()
	tryRebirth()
end

print(string.format("\nAfter %s: speed %s, coins %s, income %s/s, rebirths %d, training %d, pedestals %d, incubators %d, slimes %d",
	Format.Duration(p.t), Format.Number(p.speed), Format.Number(p.coins), Format.Number(income()), p.rebirths, p.training,
	Formulas.PedestalCount(p.pedestals), capacity(), #p.slimes))
