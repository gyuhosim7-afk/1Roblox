--!strict
-- Hatch odds. The same functions produce the odds shown to players and the server's roll,
-- so what players see is exactly what they get (including luck).

local Config = require(script.Parent.Config)

local Odds = {}

export type Entry = { Slime: string, Chance: number }
export type MutationEntry = { Mutation: string, Chance: number }

local function rarityOrder(slimeId: string): number
	local def = Config.Slimes[slimeId]
	return def and Config.Rarities[def.Rarity].Order or 1
end

local function normalise(weighted: { { Slime: string, Weight: number } }): { Entry }
	local total = 0
	for _, item in weighted do
		total += item.Weight
	end
	local result: { Entry } = {}
	for _, item in weighted do
		table.insert(result, { Slime = item.Slime, Chance = if total > 0 then item.Weight / total else 0 })
	end
	return result
end

-- Odds for a normal egg with the given luck multiplier.
function Odds.EggOdds(eggId: string, luck: number?): { Entry }
	local egg = Config.Eggs[eggId]
	assert(egg, "Unknown egg " .. tostring(eggId))
	local l = math.max(1, luck or 1)
	local weighted = {}
	for _, entry in egg.Pool do
		local weight = entry.Weight
		if rarityOrder(entry.Slime) >= Config.Luck.MinRarityOrder then
			weight *= l
		end
		table.insert(weighted, { Slime = entry.Slime, Weight = weight })
	end
	return normalise(weighted)
end

-- Royal Egg odds: best zone's egg, Rare+ only, extra luck.
function Odds.RoyalOdds(zoneIndex: number, luck: number?): { Entry }
	local zone = Config.Zones[math.clamp(zoneIndex, 1, #Config.Zones)]
	local egg = Config.Eggs[zone.Egg]
	local l = math.max(1, luck or 1) * Config.Luck.RoyalEggMultiplier
	local weighted = {}
	for _, entry in egg.Pool do
		local order = rarityOrder(entry.Slime)
		if order >= Config.RoyalEgg.MinRarityOrder then
			local weight = entry.Weight
			if order > Config.RoyalEgg.MinRarityOrder then
				weight *= l
			end
			table.insert(weighted, { Slime = entry.Slime, Weight = weight })
		end
	end
	return normalise(weighted)
end

function Odds.MutationOdds(luck: number?, bonus: number?): { MutationEntry }
	local l = math.max(1, luck or 1) * (bonus or 1)
	local gold = Config.Mutations.Gold.BaseChance * l
	local rainbow = Config.Mutations.Rainbow.BaseChance * l
	local special = gold + rainbow
	local cap = Config.Luck.MaxMutationTotal
	if special > cap then
		gold = gold / special * cap
		rainbow = rainbow / special * cap
	end
	return {
		{ Mutation = "None", Chance = 1 - gold - rainbow },
		{ Mutation = "Gold", Chance = gold },
		{ Mutation = "Rainbow", Chance = rainbow },
	}
end

-- Picks from a list of chances using r in [0, 1).
function Odds.Pick<T>(entries: { T }, r: number, getChance: (T) -> number): T
	local cumulative = 0
	for _, entry in entries do
		cumulative += getChance(entry)
		if r < cumulative then
			return entry
		end
	end
	return entries[#entries]
end

local function slimeChance(e: Entry): number
	return e.Chance
end

local function mutationChance(e: MutationEntry): number
	return e.Chance
end

-- rng must return a number in [0, 1)
function Odds.Roll(eggId: string, luck: number?, rng: () -> number): (string, string)
	local slime = Odds.Pick(Odds.EggOdds(eggId, luck), rng(), slimeChance)
	local mutation = Odds.Pick(Odds.MutationOdds(luck), rng(), mutationChance)
	return slime.Slime, mutation.Mutation
end

function Odds.RollRoyal(zoneIndex: number, luck: number?, rng: () -> number): (string, string)
	local slime = Odds.Pick(Odds.RoyalOdds(zoneIndex, luck), rng(), slimeChance)
	local mutation = Odds.Pick(Odds.MutationOdds(luck, Config.RoyalEgg.MutationLuckBonus), rng(), mutationChance)
	return slime.Slime, mutation.Mutation
end

return Odds
