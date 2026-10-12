--!strict
-- Pure helpers over a player's slime list (pedestal choice, income, selling).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local ProfileSchema = require(script.Parent.ProfileSchema)

type Slime = ProfileSchema.SlimeRecord

local SlimeInventory = {}

local function idNumber(id: string): number
	return tonumber(id:match("%d+")) or 0
end

-- The `count` best-earning slimes (ties: older slime first). These sit on pedestals.
function SlimeInventory.PedestalSlimes(slimes: { Slime }, count: number): { Slime }
	local sorted = table.clone(slimes)
	table.sort(sorted, function(a, b)
		local ia, ib = Formulas.SlimeIncome(a.Kind, a.Mutation), Formulas.SlimeIncome(b.Kind, b.Mutation)
		if ia ~= ib then
			return ia > ib
		end
		return idNumber(a.Id) < idNumber(b.Id)
	end)
	local result = {}
	for i = 1, math.min(count, #sorted) do
		result[i] = sorted[i]
	end
	return result
end

-- Base income per second (before the player's coin multiplier).
function SlimeInventory.Income(slimes: { Slime }, count: number): number
	local total = 0
	for _, slime in SlimeInventory.PedestalSlimes(slimes, count) do
		total += Formulas.SlimeIncome(slime.Kind, slime.Mutation)
	end
	return total
end

function SlimeInventory.Find(slimes: { Slime }, id: string): (number?, Slime?)
	for index, slime in slimes do
		if slime.Id == id then
			return index, slime
		end
	end
	return nil, nil
end

-- Unlocked slimes in storage (not on a pedestal) whose rarity order is <= maxOrder.
function SlimeInventory.SellableBelow(slimes: { Slime }, pedestalCount: number, maxOrder: number): { Slime }
	local onPedestal: { [string]: boolean } = {}
	for _, slime in SlimeInventory.PedestalSlimes(slimes, pedestalCount) do
		onPedestal[slime.Id] = true
	end
	local result = {}
	for _, slime in slimes do
		local def = Config.Slimes[slime.Kind]
		local order = if def then Config.Rarities[def.Rarity].Order else 1
		if not slime.Locked and not onPedestal[slime.Id] and order <= maxOrder then
			table.insert(result, slime)
		end
	end
	return result
end

return SlimeInventory
