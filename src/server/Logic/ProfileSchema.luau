--!strict
-- Player save data: default shape, migration and repair. Pure logic (unit-tested).

local ProfileSchema = {}

ProfileSchema.Version = 1

export type SlimeRecord = { Id: string, Kind: string, Mutation: string, Locked: boolean }
export type EggRecord = { Slot: number, Egg: string, HatchAt: number, Duration: number }

export type Data = {
	SchemaVersion: number,
	Coins: number,
	Gems: number,
	Speed: number,
	Bank: number,
	TrainingLevel: number,
	PedestalLevel: number,
	IncubatorLevel: number,
	LockLevel: number,
	Rebirths: number,
	BestZone: number,
	Slimes: { SlimeRecord },
	NextSlimeId: number,
	Eggs: { EggRecord },
	Discovered: { [string]: boolean },
	Potions: { Luck: number, Speed: number },
	Daily: { LastDay: number, Streak: number },
	Stats: {
		Playtime: number,
		EggsStolen: number,
		EggsHatched: number,
		PlayerSteals: number,
		TimesRobbed: number,
		Joins: number,
		RobuxSpent: number,
	},
	TutorialStep: number,
	CreatedAt: number,
	LastSeen: number,
	Purchases: { [string]: number },
	PurchaseOrder: { string },
	PassCache: { [string]: boolean },
	Treadmills: { [string]: boolean },
}

function ProfileSchema.Default(now: number): Data
	return {
		SchemaVersion = ProfileSchema.Version,
		Coins = 0,
		Gems = 0,
		Speed = 0,
		Bank = 0,
		TrainingLevel = 0,
		PedestalLevel = 0,
		IncubatorLevel = 0,
		LockLevel = 0,
		Rebirths = 0,
		BestZone = 1,
		Slimes = {},
		NextSlimeId = 1,
		Eggs = {},
		Discovered = {},
		Potions = { Luck = 0, Speed = 0 },
		Daily = { LastDay = 0, Streak = 0 },
		Stats = {
			Playtime = 0,
			EggsStolen = 0,
			EggsHatched = 0,
			PlayerSteals = 0,
			TimesRobbed = 0,
			Joins = 0,
			RobuxSpent = 0,
		},
		TutorialStep = 1,
		CreatedAt = now,
		LastSeen = 0,
		Purchases = {},
		PurchaseOrder = {},
		PassCache = {},
		Treadmills = {},
	}
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function cleanNumber(value: any, fallback: number, min: number?): number
	if not isFiniteNumber(value) then
		return fallback
	end
	if min and value < min then
		return min
	end
	return value
end

-- Fills missing fields, repairs bad values and migrates old versions.
-- `knownSlimes` / `knownEggs` let us drop entries that no longer exist in Config.
function ProfileSchema.Reconcile(
	raw: any,
	now: number,
	knownSlimes: { [string]: any }?,
	knownEggs: { [string]: any }?
): Data
	local default = ProfileSchema.Default(now)
	if type(raw) ~= "table" then
		return default
	end
	local data = raw :: any

	-- Plain numeric fields
	for _, key in
		{
			"Coins",
			"Gems",
			"Speed",
			"Bank",
			"TrainingLevel",
			"PedestalLevel",
			"IncubatorLevel",
			"LockLevel",
			"Rebirths",
			"NextSlimeId",
			"TutorialStep",
			"CreatedAt",
			"LastSeen",
		}
	do
		data[key] = cleanNumber(data[key], (default :: any)[key], 0)
	end
	data.BestZone = math.max(1, math.floor(cleanNumber(data.BestZone, 1, 1)))
	for _, key in { "TrainingLevel", "PedestalLevel", "IncubatorLevel", "LockLevel", "Rebirths", "NextSlimeId" } do
		data[key] = math.floor(data[key])
	end
	data.NextSlimeId = math.max(1, data.NextSlimeId)

	-- Nested tables with fixed keys
	for _, key in { "Potions", "Daily", "Stats" } do
		if type(data[key]) ~= "table" then
			data[key] = (default :: any)[key]
		else
			for subKey, subDefault in (default :: any)[key] do
				data[key][subKey] = cleanNumber(data[key][subKey], subDefault, 0)
			end
		end
	end

	-- Dictionaries
	for _, key in { "Discovered", "Purchases", "PassCache", "Treadmills" } do
		if type(data[key]) ~= "table" then
			data[key] = {}
		end
	end
	if type(data.PurchaseOrder) ~= "table" then
		data.PurchaseOrder = {}
	end

	-- Slimes
	local slimes: { SlimeRecord } = {}
	local usedIds: { [string]: boolean } = {}
	local maxId = 0
	if type(data.Slimes) == "table" then
		for _, s in data.Slimes do
			if type(s) == "table" and type(s.Kind) == "string" and type(s.Id) == "string" and not usedIds[s.Id] then
				if knownSlimes == nil or knownSlimes[s.Kind] ~= nil then
					usedIds[s.Id] = true
					local numeric = tonumber(s.Id:match("^S(%d+)$"))
					if numeric and numeric > maxId then
						maxId = numeric
					end
					table.insert(slimes, {
						Id = s.Id,
						Kind = s.Kind,
						Mutation = if type(s.Mutation) == "string" then s.Mutation else "None",
						Locked = s.Locked == true,
					})
				end
			end
		end
	end
	data.Slimes = slimes
	data.NextSlimeId = math.max(data.NextSlimeId, maxId + 1)

	-- Eggs (one per slot)
	local eggs: { EggRecord } = {}
	local usedSlots: { [number]: boolean } = {}
	if type(data.Eggs) == "table" then
		for _, e in data.Eggs do
			if
				type(e) == "table"
				and type(e.Egg) == "string"
				and isFiniteNumber(e.Slot)
				and isFiniteNumber(e.HatchAt)
				and not usedSlots[e.Slot]
				and (knownEggs == nil or knownEggs[e.Egg] ~= nil)
			then
				usedSlots[e.Slot] = true
				table.insert(eggs, {
					Slot = math.floor(e.Slot),
					Egg = e.Egg,
					HatchAt = e.HatchAt,
					Duration = cleanNumber(e.Duration, 0, 0),
				})
			end
		end
	end
	data.Eggs = eggs

	-- Migrations go here: if data.SchemaVersion < 2 then ... end
	data.SchemaVersion = ProfileSchema.Version
	return data :: Data
end

-- Returns a new unique slime id and advances the counter.
function ProfileSchema.NextSlimeId(data: Data): string
	local id = "S" .. tostring(data.NextSlimeId)
	data.NextSlimeId += 1
	return id
end

-- Remember a processed purchase, keeping only the most recent `limit` ids.
function ProfileSchema.RecordPurchase(data: Data, purchaseId: string, now: number, limit: number)
	if data.Purchases[purchaseId] then
		return
	end
	data.Purchases[purchaseId] = now
	table.insert(data.PurchaseOrder, purchaseId)
	while #data.PurchaseOrder > limit do
		local oldest = table.remove(data.PurchaseOrder, 1)
		if oldest then
			data.Purchases[oldest] = nil
		end
	end
end

-- Unix day number used for daily rewards.
function ProfileSchema.DayNumber(unix: number): number
	return math.floor(unix / 86400)
end

return ProfileSchema
